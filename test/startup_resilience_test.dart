// Standalone Dart simulation: no device, database or production calls.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:gotrue/gotrue.dart';
import '../lib/core/services/resilient_http_client.dart';
import '../lib/core/services/startup_policy.dart';
import '../lib/features/subscription/data/models/subscription_model.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

class FakeTransport extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) action;
  bool closed = false;
  FakeTransport(this.action);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      action(request);
  @override
  void close() {
    closed = true;
  }
}

http.StreamedResponse response(int status, [String body = '{}']) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );
Future<void> expectFailure(Future<dynamic> operation, Type type) async {
  try {
    await operation;
  } catch (e) {
    check(e.runtimeType == type, 'expected $type, got ${e.runtimeType}');
    return;
  }
  throw StateError('expected failure $type');
}

Future<void> main() async {
  var count = 0;
  Future<void> scenario(String label, Future<void> Function() run) async {
    await run();
    count++;
    print('PASS $label');
  }

  final url = Uri.parse(
    'https://unit.invalid/rest/v1/menu_items?email=PRIVATE',
  );
  for (final status in [200, 504, 521, 525]) {
    await scenario('HTTP $status bounded safe read / diagnostics', () async {
      final clients = <FakeTransport>[];
      final delays = <Duration>[];
      final logs = <String>[];
      final c = ResilientHttpClient(
        createClient: () {
          final fake = FakeTransport((_) async => response(status));
          clients.add(fake);
          return fake;
        },
        sleep: (d) async {
          delays.add(d);
        },
        random: () => 0.5,
        diagnostic: (s, a, ms, k) => logs.add('$s $a $ms $k'),
      );
      check((await c.get(url)).statusCode == status, 'status preserved');
      check(clients.length == (status == 200 ? 1 : 2), 'read retry limit');
      check(clients.every((f) => f.closed), 'each transport closed');
      check(delays.isEmpty || delays.single.inMilliseconds == 250, 'backoff');
      check(!logs.join().contains('PRIVATE'), 'query is never logged');
      c.close();
    });
  }
  for (final path in [
    '/rest/v1/orders',
    '/rest/v1/rpc/insert_order',
    '/rest/v1/rpc/get_next_daily_seq',
    '/rest/v1/rpc/app_restaurant_tables',
    '/auth/v1/token',
  ]) {
    await scenario('no transport retry for write/auth $path', () async {
      var calls = 0;
      final c = ResilientHttpClient(
        createClient: () => FakeTransport((_) async {
          calls++;
          return response(504);
        }),
        sleep: (_) async {},
      );
      await c.post(
        Uri.parse('https://unit.invalid$path'),
        body: '{"private":"value"}',
      );
      check(calls == 1, 'must not duplicate ambiguous write');
      c.close();
    });
  }
  await scenario('whitelisted read RPC retries then recovers', () async {
    var calls = 0;
    final c = ResilientHttpClient(
      createClient: () =>
          FakeTransport((_) async => response(++calls == 1 ? 525 : 200)),
      sleep: (_) async {},
    );
    check(
      (await c.post(
            Uri.parse('https://unit.invalid/rest/v1/rpc/get_menu_stock_today'),
          )).statusCode ==
          200,
      'read RPC recovers',
    );
    check(calls == 2, 'limited retry');
    c.close();
  });
  for (final kind in [
    'offline',
    'headers never complete',
    'body never completes',
  ]) {
    await scenario(kind, () async {
      final clients = <FakeTransport>[];
      final c = ResilientHttpClient(
        deadline: const Duration(milliseconds: 15),
        sleep: (_) async {},
        createClient: () {
          final f = FakeTransport((_) async {
            if (kind == 'offline') throw const SocketException('PRIVATE');
            if (kind == 'headers never complete')
              return Completer<http.StreamedResponse>().future;
            return http.StreamedResponse(
              StreamController<List<int>>().stream,
              200,
            );
          });
          clients.add(f);
          return f;
        },
      );
      await expectFailure(
        c.get(url),
        kind == 'offline' ? SocketException : TimeoutException,
      );
      check(
        clients.length == 2 && clients.every((f) => f.closed),
        'timeout closes transport',
      );
      c.close();
    });
  }
  await scenario('late result cannot replace recovered response', () async {
    final late = Completer<http.StreamedResponse>();
    var calls = 0;
    final c = ResilientHttpClient(
      deadline: const Duration(milliseconds: 15),
      sleep: (_) async {},
      createClient: () => FakeTransport(
        (_) =>
            ++calls == 1 ? late.future : Future.value(response(200, 'fresh')),
      ),
    );
    final received = await c.get(url);
    late.complete(response(200, 'obsolete'));
    await Future<void>.delayed(Duration.zero);
    check(received.body == 'fresh' && calls == 2, 'late result ignored');
    c.close();
  });
  await scenario(
    'auxiliary failure does not fail siblings; UI ticket invalidation',
    () async {
      var siblingDone = false;
      await Future.wait([
        supplemental('broken', () async {
          throw TimeoutException('');
        }),
        supplemental('healthy', () async {
          siblingDone = true;
        }),
      ]);
      check(siblingDone, 'healthy auxiliary data remains usable');
      final epoch = AttemptEpoch();
      final old = epoch.begin();
      final current = epoch.begin();
      check(
        !epoch.current(old) && epoch.current(current),
        'superseded navigation ignored',
      );
      epoch.dispose();
      check(!epoch.current(current), 'no navigation after disposal');
      final now = DateTime.utc(2026, 11, 3);
      check(
        validCacheAge(now.subtract(const Duration(hours: 23)), now),
        'fresh cache',
      );
      check(
        !validCacheAge(now.subtract(const Duration(hours: 25)), now),
        'expired cache denied',
      );
      check(
        !validCacheAge(now.add(const Duration(seconds: 1)), now),
        'clock rollback denied',
      );
      check(!validCacheAge(null, now), 'unverified cache denied');
    },
  );
  await scenario(
    'repeated retry taps share one operation; retry works after failure/recovery',
    () async {
      final gate = SingleFlight();
      final waiting = Completer<void>();
      var calls = 0;
      Future<void> action() async {
        calls++;
        await waiting.future;
      }

      final first = gate.run(action);
      final taps = List.generate(20, (_) => gate.run(action));
      check(
        gate.running && calls == 1 && taps.every((f) => identical(f, first)),
        'one in-flight operation',
      );
      waiting.complete();
      await Future.wait(taps);
      check(!gate.running, 'button released');
      await expectFailure(
        gate.run(() async {
          throw TimeoutException('');
        }),
        TimeoutException,
      );
      await gate.run(() async {
        calls++;
      });
      check(!gate.running && calls == 2, 'network recovery after failed retry');
    },
  );
  await scenario(
    'cache cannot grant another user, inactive/unapproved access or expired plan',
    () async {
      final now = DateTime.now().toUtc();
      final row = <String, dynamic>{
        'auth_id': 'a',
        'is_active': true,
        'is_approved': true,
      };
      check(
        canUseProfileCache(row, 'a', now, now),
        'verified same-account cache',
      );
      check(!canUseProfileCache(row, 'b', now, now), 'other account denied');
      check(
        !canUseProfileCache({...row, 'is_active': false}, 'a', now, now),
        'disabled denied',
      );
      check(
        !canUseProfileCache({...row, 'is_approved': false}, 'a', now, now),
        'unapproved denied',
      );
      check(
        !canUseProfileCache(
          row,
          'a',
          now.subtract(const Duration(days: 2)),
          now,
        ),
        'stale role denied',
      );
      SubscriptionModel plan({bool locked = false, bool expired = false}) =>
          SubscriptionModel(
            branchId: 'owner',
            branchName: '',
            balance: 0,
            totalTransactions: 0,
            isLocked: locked,
            planType: 'monthly',
            planExpiresAt: now.add(Duration(days: expired ? -1 : 1)),
          );
      check(plan().isActive, 'valid plan');
      check(!plan(locked: true).isActive, 'locked plan cannot transact');
      check(
        !plan(expired: true).isActive,
        'expired plan cannot transact with empty balance',
      );
    },
  );
  // Exercise the actual installed GoTrue refresh implementation, not a replica.
  for (final status in [504, 521, 525]) {
    await scenario(
      'GoTrue temporary refresh $status preserves session and recovers',
      () async {
        var calls = 0;
        var signedOut = false;
        late GoTrueClient auth;
        final client = ResilientHttpClient(
          createClient: () => FakeTransport((_) async {
            calls++;
            if (calls == 1)
              return response(status, '{"message":"temporarily unavailable"}');
            check(
              auth.currentSession != null && !signedOut,
              'session retained during failure',
            );
            return response(200, jsonEncode(sessionData()));
          }),
        );
        auth = GoTrueClient(
          url: 'https://unit.invalid/auth/v1',
          httpClient: client,
          autoRefreshToken: false,
        );
        final sub = auth.onAuthStateChange.listen((e) {
          if (e.event == AuthChangeEvent.signedOut) signedOut = true;
        }, onError: (_) {});
        await auth.setInitialSession(jsonEncode(sessionData()));
        await auth.refreshSession();
        check(
          calls == 2 && auth.currentSession != null && !signedOut,
          'healthy retry restores active session',
        );
        await sub.cancel();
        auth.dispose();
        client.close();
      },
    );
  }
  await scenario(
    'GoTrue definitive revoked refresh token differs from outage',
    () async {
      final client = ResilientHttpClient(
        createClient: () => FakeTransport(
          (_) async => response(
            400,
            '{"error_code":"refresh_token_not_found","message":"invalid refresh token"}',
          ),
        ),
      );
      final auth = GoTrueClient(
        url: 'https://unit.invalid/auth/v1',
        httpClient: client,
        autoRefreshToken: false,
      );
      final sub = auth.onAuthStateChange.listen((_) {}, onError: (_) {});
      await auth.setInitialSession(jsonEncode(sessionData()));
      try {
        await auth.refreshSession();
        throw StateError('expected Auth failure');
      } on AuthException catch (e) {
        check(
          failureKind(e) == FailureKind.invalidSession,
          'classified invalid session',
        );
      }
      check(
        auth.currentSession == null,
        'SDK clears definitively revoked session',
      );
      await sub.cancel();
      auth.dispose();
      client.close();
    },
  );
  print('PASS $count startup resilience scenarios (no production calls)');
}

Map<String, dynamic> sessionData() {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  String part(Map<String, dynamic> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return {
    'access_token': '${part({'alg': 'none'})}.${part({'exp': exp})}.fixture',
    'refresh_token': 'fixture-only',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': 'test-user',
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
}
