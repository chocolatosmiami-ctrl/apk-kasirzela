import '../utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  SupabaseClient get _db => SupabaseConfig.client;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('NotificationService initialized (Supabase)');
  }

  Future<void> _save(String title, String body, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      if (ownerId.isEmpty) return;
      await _db.from('notifications').insert({
        'owner_id': ownerId,
        'title': title,
        'body': body,
        'type': type,
        'is_read': false,
      });
    } catch (e) {
      debugPrint('NotificationService._save error: $e');
    }
  }

  Future<void> notifyBalanceLow(double balance, int remaining) async {
    await _save('⚠️ Saldo Hampir Habis',
        'Sisa $remaining trx (${_fmt(balance)}). Segera top up!',
        'balance_low');
  }

  Future<void> notifyBalanceEmpty() async {
    await _save('🔒 Saldo Habis',
        'Lakukan top up untuk melanjutkan transaksi.', 'balance_empty');
  }

  Future<void> notifyTopUpSuccess(double amount) async {
    await _save('✅ Top Up Berhasil',
        '${_fmt(amount)} ditambahkan ke saldo.', 'topup_success');
  }

  Future<void> notifyStockLow(String name, double stock, String unit) async {
    await _save('⚠️ Stok Menipis',
        '$name tersisa $stock $unit.', 'stock_low');
  }

  Future<void> notifyOfflineSynced(int trxCount, double debt,
      bool locked) async {
    await _save(
      locked ? '⚠️ Saldo Habis Setelah Sync' : '✅ Sync Berhasil',
      '$trxCount trx sync. ${locked ? "Top up!" : "OK"}',
      'offline_sync',
    );
  }

  Future<void> notifyShiftReport(double revenue, double expense,
      double profit) async {
    await _save('📊 Laporan Shift',
        'Omzet: ${_fmt(revenue)} | Laba: ${_fmt(profit)}',
        'shift_report');
  }

  Future<void> markAllRead(String ownerId) async {
    await _db.from('notifications')
        .update({'is_read': true})
        .eq('owner_id', ownerId)
        .eq('is_read', false);
  }

  String _fmt(double v) => v >= 1000000
      ? 'Rp${(v/1000000).toStringAsFixed(1)}jt'
      : 'Rp${(v/1000).toStringAsFixed(0)}rb';
}
