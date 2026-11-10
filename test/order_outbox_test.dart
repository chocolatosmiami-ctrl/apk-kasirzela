// Run without Flutter: dart test/order_outbox_test.dart
import 'dart:async';
import '../lib/core/services/order_outbox.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class MemoryStore implements OrderOutboxStore {
  final List<OutboxReceipt> rows = [];
  final Map<int, String> errors = {};
  @override
  Future<List<OutboxReceipt>> pending(String account) async => List.of(rows);
  @override
  Future<void> acknowledge(OutboxReceipt receipt) async {
    rows.remove(receipt);
    errors.remove(receipt.localId);
  }

  @override
  Future<void> recordFailure(OutboxReceipt receipt, String message) async {
    errors[receipt.localId] = message;
  }
}

Future<void> main() async {
  final store = MemoryStore();
  const a = OutboxReceipt(1, 'cashier-a', {'order_number': 'a', 'quantity': 3});
  const b = OutboxReceipt(2, 'cashier-b', {'order_number': 'b', 'quantity': 4});
  store.rows.addAll([a, b]);

  final offline = OrderOutbox(
    store,
    (_) async => throw StateError('network down'),
  );
  final result = await offline.flush('cashier-a');
  check(
    result.failed == 1 && store.rows.length == 2,
    'Offline receipt must remain queued',
  );
  check(
    store.errors.containsKey(1) && !store.errors.containsKey(2),
    'Only original account can send',
  );

  // A new worker after an app restart must read the same durable store.
  var deductions = 0;
  final serverReceipts = <String>{};
  var loseResponse = true;
  Future<Map<String, dynamic>> server(Map<String, dynamic> p) async {
    if (serverReceipts.add(p['order_number'] as String)) deductions++;
    if (loseResponse) {
      loseResponse = false;
      throw StateError('response lost after commit');
    }
    return {'success': true, 'stock_applied': true};
  }

  await OrderOutbox(store, server).flush('cashier-a');
  check(
    store.rows.contains(a) && deductions == 1,
    'Lost response must keep receipt',
  );
  await OrderOutbox(store, server).flush('cashier-a');
  check(
    !store.rows.contains(a) && deductions == 1,
    'Retry must acknowledge same receipt once',
  );
  check(store.rows.single == b, 'Other account receipt must be untouched');

  final conflict = OrderOutbox(
    store,
    (_) async => {
      'success': true,
      'stock_applied': false,
      'error': 'ingredient stock missing',
    },
  );
  await conflict.flush('cashier-b');
  check(
    store.rows.single == b && store.errors[2]!.contains('stock missing'),
    'Saved order with unresolved stock must not be acknowledged',
  );

  final entered = Completer<void>();
  final release = Completer<void>();
  var calls = 0;
  final coalesced = OrderOutbox(store, (_) async {
    calls++;
    entered.complete();
    await release.future;
    return {'success': true, 'stock_applied': true};
  });
  final first = coalesced.flush('cashier-b');
  await entered.future;
  final second = coalesced.flush('cashier-b');
  release.complete();
  await Future.wait([first, second]);
  check(calls == 1 && store.rows.isEmpty, 'Reconnect and timer must not race');

  store.rows.add(a);
  await OrderOutbox(store, (_) async => {}).flush('');
  check(store.rows.length == 1, 'Signed-out devices must not send');
  store.rows.add(const OutboxReceipt(3, 'cashier-a', {'order_number': 'c'}));
  var attempts = 0;
  await OrderOutbox(store, (_) async {
    attempts++;
    throw StateError('connection unavailable');
  }).flush('cashier-a');
  check(
    attempts == 1 && store.rows.length == 2,
    'Offline backlog must stop on a broken connection without deleting rows',
  );
  await OrderOutbox(
    store,
    (p) async => p['order_number'] == 'a'
        ? {'success': true, 'stock_applied': false, 'error': 'stock conflict'}
        : {'success': true, 'stock_applied': true},
  ).flush('cashier-a');
  check(
    store.rows.single == a,
    'One stock conflict must not block later receipts',
  );
  print(
    'PASS: offline retention, restart, lost response/retry, account isolation, stock conflict, coalescing, sign-out',
  );
}
