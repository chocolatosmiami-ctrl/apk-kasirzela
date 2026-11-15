import '../lib/core/services/order_outbox.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class Store implements OrderOutboxStore {
  final rows = <OutboxReceipt>[];
  int acknowledgements = 0;
  @override
  Future<List<OutboxReceipt>> pending(String account) async => List.of(rows);
  @override
  Future<void> acknowledge(OutboxReceipt receipt) async {
    acknowledgements++;
    rows.remove(receipt);
  }

  @override
  Future<void> recordFailure(OutboxReceipt receipt, String message) async {}
}

Future<void> main() async {
  final payload = <String, dynamic>{
    'qr_visit_id': '10000000-0000-4000-8000-000000000001',
    'qr_bill_token': '20000000-0000-4000-8000-000000000001',
    'order_number': 'QR-10000000000040008000000000000001'
  };
  check(checkoutSyncRpc(payload) == 'sync_qr_food_order_v1',
      'QR must use atomic QR settlement');
  check(checkoutSyncRpc({'order_number': 'normal'}) == 'sync_paid_food_order',
      'ordinary POS route unchanged');
  var denied = false;
  try {
    checkoutSyncRpc({...payload, 'order_number': 'changed'});
  } catch (_) {
    denied = true;
  }
  check(denied, 'changed receipt identity accepted');
  final store = Store();
  store.rows.add(OutboxReceipt(1, 'account-a', payload));
  var attempt = 0;
  final outbox = OrderOutbox(store, (sent) async {
    check(identical(sent, payload), 'retry replaced saved receipt');
    attempt++;
    if (attempt == 1) throw StateError('Lost response after server commit');
    if (attempt == 2) return {'success': true, 'stock_applied': true};
    return {'success': true, 'stock_applied': true, 'qr_billed': true};
  });
  await outbox.flush('account-a');
  check(store.rows.length == 1 && store.acknowledgements == 0,
      'uncertain payment discarded');
  await outbox.flush('account-a');
  check(store.rows.length == 1 && store.acknowledgements == 0,
      'non-QR acknowledgement accepted');
  await outbox.flush('account-a');
  check(store.rows.isEmpty && store.acknowledgements == 1,
      'confirmed QR receipt not acknowledged once');
  print(
      'PASS: QR receipt identity, durable retries, explicit settlement acknowledgement, ordinary POS route');
}
