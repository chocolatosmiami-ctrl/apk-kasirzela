import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constants.dart';
import 'checkout_diagnostic.dart';
import 'login_route.dart';
import '../config/supabase_config.dart';
import '../database/database_helper.dart';
import 'order_outbox.dart';
import 'checkout_member.dart';

class OfflineOrderSyncService extends ChangeNotifier {
  static final instance = OfflineOrderSyncService._();
  OfflineOrderSyncService._() {
    _outbox = OrderOutbox(_SqliteOrderOutbox(), (payload) async {
      final result = await SupabaseConfig.client
          .rpc(checkoutSyncRpc(payload), params: {'p_payload': payload})
          .timeout(const Duration(seconds: 15));
      if (result is! Map) throw StateError('Respons sinkronisasi tidak valid');
      return Map<String, dynamic>.from(result);
    });
  }
  late final OrderOutbox _outbox;
  Timer? _retryTimer;
  Future<OutboxRun>? _active;
  bool syncing = false;
  int stockRevision = 0; // Changes only after server acknowledgement, never for an idle scan.
  int pendingCount = 0;
  String? lastError;
  bool needsLogin = false;
  String _statusAccountId = '';
  bool get statusMatchesAccount => _statusAccountId ==
      (SupabaseConfig.client.auth.currentUser?.id ?? '');

  void start() {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => kick());
    kick();
  }

  void stop() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void kick() {
    unawaited(
      flush().catchError((Object e) {
        lastError = e.toString();
        notifyListeners();
        return const OutboxRun(0, 1);
      }),
    );
  }

  Future<OutboxRun> flush() =>
      _active ??= _flush().whenComplete(() => _active = null);

  Future<OutboxRun> _flush() async {
    // Never relabel receipts with whoever happens to be logged in now.
    final accountId = SupabaseConfig.client.auth.currentUser?.id ?? '';
    syncing = true;
    notifyListeners();
    try {
      await _refreshStatus(accountId);
      notifyListeners();
      final result = await _outbox.flush(accountId);
      if (result.sent > 0) stockRevision++;
      await _refreshStatus(accountId);
      return result;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _refreshStatus(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final rows = await DatabaseHelper.instance.rawQuery(
      '''
        SELECT last_error FROM order_sync_outbox
        WHERE state = 'pending' AND account_id = ? ORDER BY id
      ''',
      [accountId],
    );
    _statusAccountId = accountId;
    pendingCount = rows.length;
    lastError = rows.isEmpty ? null : rows.first['last_error']?.toString();
    needsLogin = needsServerLogin(accountId.isNotEmpty,
        prefs.getString(AppConstants.keyEmail)?.isNotEmpty ?? false, lastError);
    if (accountId.isEmpty)
      lastError = 'Login kembali untuk menyinkronkan transaksi';
  }

  /// Read the exact receipt, not a global success flag or aggregate queue count.
  Future<Map<String, Object?>> receiptStatus(int orderId, String number) async {
    final rows = await DatabaseHelper.instance.rawQuery('''
      SELECT o.order_number, o.branch_id, o.synced,
             q.state, q.account_id, q.attempts, q.last_error, q.acknowledged_at
      FROM orders o LEFT JOIN order_sync_outbox q ON q.order_id = o.id
      WHERE o.id = ? AND o.order_number = ?
    ''', [orderId, number]);
    final uid = SupabaseConfig.client.auth.currentUser?.id ?? '';
    return {
      if (rows.isNotEmpty) ...rows.single,
      'local_saved': rows.isNotEmpty,
      'session_present': uid.isNotEmpty,
      'same_account': rows.isNotEmpty && uid.isNotEmpty && rows.single['account_id'] == uid,
      'project': Uri.parse(SupabaseConfig.supabaseUrl).host,
      'last_error': CheckoutDiagnostic.sanitize(
        rows.isEmpty ? '' : rows.single['last_error']?.toString() ?? ''),
    };
  }

  /// Must be called INSIDE the same SQLite transaction as orders/order_items.
  static Future<void> enqueue(
    Transaction txn, {
    required int orderId,
    required String accountId,
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    CheckoutMember? member,
  }) async {
    if (accountId.isEmpty || (order['branch_id']?.toString() ?? '').isEmpty) {
      throw StateError(
        'Identitas akun/cabang kosong. Login dan pilih cabang dahulu.',
      );
    }
    if (member != null && (member.scope.accountId != accountId ||
        member.scope.branchId != order['branch_id'])) {
      throw StateError('Sesi member tidak sesuai receipt.');
    }
    final payload = <String, dynamic>{
      'version': 1,
      'account_id': accountId,
      'branch_id': order['branch_id'],
      'order_number': order['order_number'],
      'created_at': order['created_at'],
      'cashier_name': order['cashier_name'],
      'subtotal': order['subtotal'],
      'discount': order['discount_amount'],
      'tax': order['tax_amount'],
      'service_charge_amount': order['service_charge_amount'],
      'total': order['total'],
      'payment_method': order['payment_method'],
      'paid_amount': order['paid_amount'],
      'change_amount': order['change_amount'],
      'notes': order['note'],
      'items': items,
      if (member != null) ...{
        'order_type': order['order_type'], ...member.toPayload(),
      },
    };
    await txn.insert('order_sync_outbox', {
      'order_id': orderId,
      'account_id': accountId,
      'branch_id': order['branch_id'],
      'payload': jsonEncode(payload),
      'state': 'pending',
      'attempts': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> pendingItems(
    String branchId,
    String capturedAt,
  ) async {
    final rows = await DatabaseHelper.instance.rawQuery(
      '''
      SELECT payload FROM order_sync_outbox
      WHERE branch_id = ? AND (state = 'pending' OR acknowledged_at >= ?)
    ''',
      [branchId, capturedAt],
    );
    return rows.expand((row) {
      final payload = jsonDecode(row['payload'] as String) as Map;
      if (payload['order_type'] == 'retail') return <Map<String, dynamic>>[];
      final date = DateTime.parse(payload['created_at'] as String)
          .toUtc()
          .add(const Duration(hours: 7))
          .toIso8601String()
          .substring(0, 10);
      final today = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 7))
          .toIso8601String()
          .substring(0, 10);
      if (date != today) return <Map<String, dynamic>>[];
      return (payload['items'] as List).map(
        (i) => Map<String, dynamic>.from(i as Map),
      );
    }).toList();
  }

  /// Explicit recovery. Never assign old receipts to a new account/branch.
  Future<void> importLegacyFoodOrders() async {
    final accountId = SupabaseConfig.client.auth.currentUser?.id ?? '';
    if (accountId.isEmpty) throw StateError('Login kembali dahulu');
    await DatabaseHelper.instance.runTransaction((txn) async {
      final orders = await txn.rawQuery(
        '''
        SELECT o.* FROM orders o
        LEFT JOIN order_sync_outbox q ON q.order_id = o.id
        WHERE o.status IN ('paid', 'completed') AND o.order_type != 'retail'
          AND o.cashier_id = ? AND COALESCE(o.branch_id, '') != ''
          AND q.id IS NULL AND o.synced = 0
        ORDER BY o.created_at
      ''',
        [accountId],
      );
      for (final order in orders) {
        final items = await txn.query(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [order['id']],
        );
        await enqueue(
          txn,
          orderId: order['id'] as int,
          accountId: accountId,
          order: order,
          items: items
              .map(
                (i) => <String, dynamic>{
                  'item_name': i['name'],
                  'quantity': i['qty'],
                  'price': i['price'],
                  'subtotal': i['subtotal'],
                  'unit': i['unit'],
                },
              )
              .toList(),
        );
      }
    });
  }
}

class _SqliteOrderOutbox implements OrderOutboxStore {
  @override
  Future<List<OutboxReceipt>> pending(String accountId) async {
    final rows = await DatabaseHelper.instance.rawQuery(
      '''
      SELECT id, account_id, payload FROM order_sync_outbox
      WHERE state = 'pending' AND account_id = ? ORDER BY id
    ''',
      [accountId],
    );
    return rows
        .map(
          (r) => OutboxReceipt(
            r['id'] as int,
            r['account_id'] as String,
            Map<String, dynamic>.from(jsonDecode(r['payload'] as String)),
          ),
        )
        .toList();
  }

  @override
  Future<void> acknowledge(OutboxReceipt receipt) async {
    await DatabaseHelper.instance.runTransaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE orders SET synced = 1 WHERE id =
        (SELECT order_id FROM order_sync_outbox WHERE id = ?)
      ''',
        [receipt.localId],
      );
      await txn.update(
        'order_sync_outbox',
        {
          'state': 'done',
          'last_error': null,
          'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [receipt.localId],
      );
    });
  }

  @override
  Future<void> recordFailure(OutboxReceipt receipt, String message) async {
    await DatabaseHelper.instance.rawUpdate(
      '''
      UPDATE order_sync_outbox SET attempts = attempts + 1, last_error = ?
      WHERE id = ? AND state = 'pending'
    ''',
      [message, receipt.localId],
    );
  }
}
