/// Pure Dart retry loop. Persistence and HTTP are supplied by the app.
String checkoutSyncRpc(Map<String, dynamic> payload) {
  if (payload.containsKey('member_number') || payload.containsKey('customer_id')) {
    if (payload['member_number'] is! String ||
        !RegExp(r'^\d{6}$').hasMatch(payload['member_number'] as String) ||
        (payload['customer_id']?.toString() ?? '').isEmpty) {
      throw StateError('Identitas member pada receipt tidak lengkap.');
    }
    return payload['order_type'] == 'retail'
        ? 'zela_member_sync_retail_order' : 'zela_member_sync_food_order';
  }
  return 'sync_paid_food_order';
}

class OutboxReceipt {
  final int localId;
  final String accountId;
  final Map<String, dynamic> payload;
  const OutboxReceipt(this.localId, this.accountId, this.payload);
}

abstract class OrderOutboxStore {
  Future<List<OutboxReceipt>> pending(String accountId);
  Future<void> acknowledge(OutboxReceipt receipt);
  Future<void> recordFailure(OutboxReceipt receipt, String message);
}

class OutboxRun {
  final int sent, failed;
  const OutboxRun(this.sent, this.failed);
}

class OrderOutbox {
  final OrderOutboxStore store;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) send;
  Future<OutboxRun>? _running;
  OrderOutbox(this.store, this.send);

  // Coalesce reconnect, timer, checkout and manual requests in this isolate.
  Future<OutboxRun> flush(String accountId) {
    if (accountId.isEmpty) return Future.value(const OutboxRun(0, 0));
    return _running ??= _flush(accountId).whenComplete(() => _running = null);
  }

  Future<OutboxRun> _flush(String accountId) async {
    var sent = 0, failed = 0;
    for (final receipt in await store.pending(accountId)) {
      if (receipt.accountId != accountId) continue;
      try {
        // Transport may time out after a server commit. The payload and its
        // stable receipt key must survive unchanged for the next retry.
        final result = await send(receipt.payload);
        if (result['success'] != true || result['stock_applied'] != true ||
            (receipt.payload.containsKey('member_number') && result['member_linked'] != true)) {
          await store.recordFailure(
            receipt,
            result['error']?.toString() ??
                (receipt.payload.containsKey('member_number') && result['member_linked'] != true
                    ? 'Member belum dikonfirmasi server'
                    : 'Order/stok belum dikonfirmasi server'),
          );
          failed++;
          continue;
        }
        await store.acknowledge(receipt);
        sent++;
      } catch (error) {
        await store.recordFailure(receipt, error.toString());
        failed++;
        // A broken connection should not wait on every remaining receipt.
        // Unsent rows remain durable for the next reconnect/timer attempt.
        break;
      }
    }
    return OutboxRun(sent, failed);
  }
}
