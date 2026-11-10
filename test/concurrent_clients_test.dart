// In-process simulation only: no Supabase traffic and no device benchmark.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/services/read_work.dart';
import '../lib/core/services/order_outbox.dart';
import '../lib/core/services/resilient_http_client.dart';
import 'order_outbox_test.dart' show MemoryStore;

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Future<void> main() => run().timeout(const Duration(seconds: 30));
Future<void> run() async {
  for (final clients in [10, 25, 50, 100]) {
    final watch = Stopwatch()..start();
    final flights = ReadFlights<int>();
    var reads = 0;
    final gate = Completer<void>();
    final requests = <Future<int>>[];
    for (var client = 0; client < clients; client++) {
      for (var tap = 0; tap < 20; tap++) {
        requests.add(flights.run('account-$client:branch', () async {
          reads++;
          await gate.future;
          return client;
        }));
      }
    }
    check(reads == clients, 'read storms must coalesce per identity');
    gate.complete();
    final values = await Future.wait(requests);
    for (var i = 0; i < values.length; i++) {
      check(values[i] == i ~/ 20, 'cross-account read result');
    }

    var online = false, sends = 0, deductions = 0;
    final committed = <String>{}, lostAck = <String>{};
    final stores = List.generate(clients, (client) {
      final store = MemoryStore();
      for (var i = 0; i < 10; i++) {
        store.rows.add(OutboxReceipt(i, 'account-$client', {
          'order_number': 'account-$client-receipt-$i',
        }));
      }
      return store;
    });
    final workers = List.generate(clients, (client) => OrderOutbox(
      stores[client], (payload) async {
        sends++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (!online) throw StateError('simulated offline');
        final key = payload['order_number'] as String;
        // Idempotent FAKE SERVER: this does not verify production SQL.
        if (committed.add(key)) deductions++;
        if (key.endsWith('-0') && lostAck.add(key)) {
          throw StateError('simulated lost response after commit');
        }
        return {'success': true, 'stock_applied': true};
      },
    ));
    Future<void> wave() async {
      final pending = <Future<OutboxRun>>[];
      for (var client = 0; client < clients; client++) {
        for (var tap = 0; tap < 10; tap++) {
          pending.add(workers[client].flush('account-$client'));
        }
      }
      await Future.wait(pending);
    }
    await wave();
    check(sends == clients, 'repeated reconnect must share one flush');
    check(stores.every((s) => s.rows.length == 10), 'offline receipt lost');
    online = true;
    await wave(); // First receipt commits but acknowledgement is lost.
    check(deductions == clients, 'fake-server first commits mismatch');
    await wave(); // Same stable receipt key, then remaining receipts.
    check(stores.every((s) => s.rows.isEmpty), 'pending receipt after recovery');
    check(committed.length == clients * 10 && deductions == clients * 10,
        'lost/duplicate fake-server receipt or deduction');
    check(sends == clients * 12, 'unexpected automatic write amplification');
    print(jsonEncode({'clients': clients, 'result': 'PASS',
      'readTriggers': clients * 20, 'underlyingReads': reads,
      'receipts': committed.length, 'fakeStockDeductions': deductions,
      'sendAttemptsIncludingOfflineAndLostAck': sends,
      'simulationElapsedMs': watch.elapsedMilliseconds}));
  }
  for (final status in [504, 521, 525]) {
    var reads = 0, writes = 0;
    final client = ResilientHttpClient(
      sharedClient: MockClient((request) async {
        if (request.method == 'GET') { reads++; } else { writes++; }
        return http.Response('{}', status);
      }), sleep: (_) async {}, random: () => 0.5,
    );
    try {
      await Future.wait(List.generate(100, (_) => client.get(
        Uri.parse('https://simulated.invalid/rest/v1/menu_items'))));
      await Future.wait(List.generate(100, (_) => client.post(
        Uri.parse('https://simulated.invalid/rest/v1/rpc/insert_order'))));
      check(reads == 200, 'safe read retry limit exceeded');
      check(writes == 100, 'write automatically retried by transport');
      print(jsonEncode({'status': status, 'clients': 100, 'result': 'PASS',
        'readAttempts': reads, 'writeAttempts': writes}));
    } finally { client.close(); }
  }
}
