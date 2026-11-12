import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/core/services/resilient_http_client.dart';
import '../lib/core/services/startup_policy.dart';
import '../lib/core/services/supabase_auth_service.dart';

class _Transport extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) action;
  _Transport(this.action);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      action(request);
}

void main() {
  final authUrl = Uri.parse('https://dummy.invalid/auth/v1/token');
  test(
      'login and legacy login use 30s while ordinary reads keep their 5s bound',
      () {
    final client = ResilientHttpClient();
    addTearDown(client.close);
    expect(client.deadlineFor(authUrl), const Duration(seconds: 30));
    expect(
        client.deadlineFor(
            Uri.parse('https://dummy.invalid/functions/v1/legacy-staff-login')),
        const Duration(seconds: 30));
    expect(
        client
            .deadlineFor(Uri.parse('https://dummy.invalid/rest/v1/menu_items')),
        const Duration(seconds: 5));
    expect(LoginTimeouts.refresh, greaterThan(LoginTimeouts.request));
    expect(LoginTimeouts.startup,
        greaterThan(LoginTimeouts.refresh + LoginTimeouts.profileRead));
  });

  test('an 8s Auth response is accepted rather than aborted at 5s', () {
    fakeAsync((clock) {
      var calls = 0;
      var completed = false;
      Object? error;
      final client = ResilientHttpClient(sharedClient: _Transport((_) async {
        calls++;
        await Future<void>.delayed(const Duration(seconds: 8));
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      }));
      client.post(authUrl, body: '{}').then((_) => completed = true,
          onError: (Object e) {
        error = e;
      });
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 6));
      expect(completed, false);
      expect(error, isNull);
      clock.elapse(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(completed, true);
      expect(error, isNull);
      expect(calls, 1);
      client.close();
    });
  });

  test(
      'a hung Auth POST aborts at the bounded deadline and is never transport-retried',
      () {
    fakeAsync((clock) {
      var calls = 0;
      var aborted = false;
      Object? error;
      final client = ResilientHttpClient(
          authenticationDeadline: const Duration(milliseconds: 100),
          sharedClient: _Transport((request) {
            calls++;
            (request as http.AbortableRequest)
                .abortTrigger!
                .then((_) => aborted = true);
            return Completer<http.StreamedResponse>().future;
          }));
      client.post(authUrl, body: '{}').then((_) {}, onError: (Object e) {
        error = e;
      });
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 101));
      clock.flushMicrotasks();
      expect(error, isA<TimeoutException>());
      expect(aborted, true);
      expect(calls, 1);
      client.close();
    });
  });

  test(
      'explicit fixture deadlines still bound Auth tests as well as ordinary requests',
      () {
    final client =
        ResilientHttpClient(deadline: const Duration(milliseconds: 15));
    addTearDown(client.close);
    expect(client.deadlineFor(authUrl), const Duration(milliseconds: 15));
  });

  test(
      'SDK-wrapped transport failure shows a fixed message without leaking its body',
      () {
    final message = authenticationErrorMessage(AuthRetryableFetchException(
        message: 'DUMMY_PRIVATE_VALUE TimeoutException'));
    expect(message, contains('LOGIN_CONNECTION'));
    expect(message, isNot(contains('DUMMY_PRIVATE_VALUE')));
    expect(message, isNot(contains('AuthRetryableFetchException')));
    expect(message, isNot(contains('password salah')));
  });

  test('credential and service failures remain distinct', () {
    expect(
        authenticationErrorMessage(
            const AuthException('dummy', code: 'invalid_credentials')),
        'Email atau password salah');
    expect(
        authenticationErrorMessage(
            AuthRetryableFetchException(statusCode: '503')),
        contains('LOGIN_SERVICE'));
    expect(
        authenticationErrorMessage(
            const AuthException('dummy', statusCode: '429')),
        contains('Terlalu banyak percobaan'));
  });
}
