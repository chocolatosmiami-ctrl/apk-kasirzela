import '../utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../database/database_helper.dart';

/// Service untuk sync data lama dari SQLite lokal ke Supabase
class SqliteSyncService {
  static final SqliteSyncService instance = SqliteSyncService._();
  SqliteSyncService._();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  // Key untuk track order yang sudah di-sync
  static const String _keySyncedOrders = 'sqlite_synced_order_numbers';

  Future<Set<String>> _getSyncedOrderNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = prefs.getStringList(_keySyncedOrders) ?? [];
    return list.toSet();
  }

  Future<void> _markAsSynced(String orderNumber) async {
    final prefs  = await SharedPreferences.getInstance();
    final synced = prefs.getStringList(_keySyncedOrders) ?? [];
    if (!synced.contains(orderNumber)) {
      synced.add(orderNumber);
      // BUG 6 FIX: Batasi ukuran list maksimum 1000 entry untuk mencegah bloat.
      // Hapus entry terlama jika melebihi batas.
      const maxSynced = 1000;
      final trimmed = synced.length > maxSynced
          ? synced.sublist(synced.length - maxSynced)
          : synced;
      await prefs.setStringList(_keySyncedOrders, trimmed);
    }
  }

  /// Sync semua orders dari SQLite yang belum ada di Supabase
  /// [onProgress] dipanggil setiap order selesai di-sync
  Future<SyncSummary> syncAllOrders({
    void Function(int done, int total, String status)? onProgress,
  }) async {
    if (_isSyncing) {
      return SyncSummary(success: 0, failed: 0, skipped: 0,
          error: 'Sync sedang berjalan');
    }
    _isSyncing = true;

    int success = 0, failed = 0, skipped = 0;

    try {
      final prefs      = await SharedPreferences.getInstance();
      final branchId   = prefs.getString(AppConstants.keyBranchId) ?? '';
      final kasirName  = prefs.getString(AppConstants.keyKasirName) ??
          prefs.getString(AppConstants.keyName) ?? '';
      final cashierId  = prefs.getString(AppConstants.keyUid) ?? '';

      if (branchId.isEmpty) {
        return SyncSummary(success: 0, failed: 0, skipped: 0,
            error: 'Branch ID tidak ditemukan. Login ulang dulu.');
      }

      // Ambil semua orders paid dari SQLite
      final orders = await DatabaseHelper.instance.rawQuery('''
        SELECT o.*, 
               GROUP_CONCAT(
                 oi.name || '|' || oi.qty || '|' || oi.price || '|' || oi.subtotal,
                 ';;'
               ) as items_raw
        FROM orders o
        LEFT JOIN order_items oi ON oi.order_id = o.id
        WHERE o.status = 'paid'
        GROUP BY o.id
        ORDER BY o.created_at ASC
      ''');

      final total   = orders.length;
      final synced  = await _getSyncedOrderNumbers();

      debugPrint('📦 [SQLITE-SYNC] Total orders: $total, sudah sync: ${synced.length}');
      onProgress?.call(0, total, 'Memulai sync $total orders...');

      for (int i = 0; i < orders.length; i++) {
        final order       = orders[i];
        final orderNumber = order['order_number']?.toString() ?? '';

        // Skip kalau sudah di-sync sebelumnya
        if (synced.contains(orderNumber)) {
          skipped++;
          onProgress?.call(i + 1, total,
              'Skip $orderNumber (sudah ada)');
          continue;
        }

        // Cek apakah sudah ada di Supabase berdasarkan order_number
        try {
          final existing = await SupabaseConfig.client
              .from('orders')
              .select('id')
              .eq('order_number', orderNumber)
              .maybeSingle();

          if (existing != null) {
            skipped++;
            await _markAsSynced(orderNumber);
            onProgress?.call(i + 1, total,
                'Skip $orderNumber (sudah ada di server)');
            continue;
          }
        } catch (_) {}

        // Parse items
        final itemsRaw = order['items_raw']?.toString() ?? '';
        final items = itemsRaw.isEmpty ? <Map<String, dynamic>>[] :
            itemsRaw.split(';;').where((s) => s.isNotEmpty).map((s) {
              final parts = s.split('|');
              return {
                'item_name': parts.length > 0 ? parts[0] : '',
                'quantity':  parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1,
                'price':     parts.length > 2 ? double.tryParse(parts[2]) ?? 0.0 : 0.0,
                'subtotal':  parts.length > 3 ? double.tryParse(parts[3]) ?? 0.0 : 0.0,
                'unit':      'porsi',
              };
            }).toList();

        // Normalize order_type
        final rawType   = order['order_type']?.toString() ?? 'food';
        final orderType = rawType == 'retail' ? 'retail' : 'food';

        // Kirim ke Supabase via RPC
        try {
          final result = await SupabaseConfig.client.rpc('insert_order',
              params: {
            'p_branch_id':      branchId,
            'p_cashier_id':     cashierId,
            'p_cashier_name':   kasirName,
            'p_order_number':   orderNumber,
            'p_order_type':     orderType,
            'p_status':         'paid',
            'p_subtotal':       (order['subtotal'] as num?)?.toDouble() ?? 0,
            'p_discount':       (order['discount_amount'] as num?)?.toDouble() ?? 0,
            'p_tax':            (order['tax_amount'] as num?)?.toDouble() ?? 0,
            'p_total':          (order['total'] as num?)?.toDouble() ?? 0,
            'p_payment_method': order['payment_method']?.toString() ?? 'cash',
            'p_paid_amount':    (order['paid_amount'] as num?)?.toDouble() ?? 0,
            'p_change_amount':  (order['change_amount'] as num?)?.toDouble() ?? 0,
            'p_notes':          order['note']?.toString(),
            'p_created_at':     order['created_at']?.toString(),
            'p_items':          items,
          });

          final ok = result?['success'] as bool? ?? false;
          if (ok) {
            success++;
            await _markAsSynced(orderNumber);
            debugPrint('📦 [SQLITE-SYNC] ✅ $orderNumber synced');
            onProgress?.call(i + 1, total,
                '✅ $orderNumber (Rp${(order['total'] as num?)?.toInt()})');
          } else {
            failed++;
            final err = result?['error']?.toString() ?? 'unknown';
            debugPrint('📦 [SQLITE-SYNC] ❌ $orderNumber: $err');
            onProgress?.call(i + 1, total, '❌ $orderNumber: $err');
          }
        } catch (e) {
          failed++;
          debugPrint('📦 [SQLITE-SYNC] ❌ $orderNumber error: $e');
          onProgress?.call(i + 1, total, '❌ $orderNumber error');
        }

        // Delay kecil agar tidak flood API
        await Future.delayed(const Duration(milliseconds: 100));
      }

      return SyncSummary(
        success: success, failed: failed, skipped: skipped);
    } catch (e) {
      debugPrint('📦 [SQLITE-SYNC] Fatal error: $e');
      return SyncSummary(
        success: success, failed: failed, skipped: skipped,
        error: e.toString());
    } finally {
      _isSyncing = false;
    }
  }
}

class SyncSummary {
  final int success, failed, skipped;
  final String? error;
  const SyncSummary({
    required this.success,
    required this.failed,
    required this.skipped,
    this.error,
  });

  int get total => success + failed + skipped;
  bool get hasError => error != null;
}
