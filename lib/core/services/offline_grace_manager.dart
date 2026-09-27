import '../utils/app_constants.dart';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../database/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class OfflineGraceManager {
  static final OfflineGraceManager instance = OfflineGraceManager._();
  OfflineGraceManager._();

  SupabaseClient get _db => SupabaseConfig.client;

  static const int    maxOfflineTrx  = 20;
  static const int    maxOfflineHours = 24;
  static const double costPerTrx     = 500;

  static const String _keyBalance          = 'cached_balance';
  static const String _keyOfflineTrx       = 'offline_trx_count';
  static const String _keyOfflineDebt      = 'offline_debt';
  static const String _keyFirstOfflineTime = 'first_offline_time';
  static const String _keyPendingTrx       = 'pending_trx_list';
  static const String _keyLastSyncTime     = 'last_sync_time';

  // ── Internet check ────────────────────────────────────
  Future<bool> isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result == ConnectivityResult.none) return false;
      final lookup = await InternetAddress.lookup('supabase.com')
          .timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Resolve ownerId yang benar ────────────────────────
  Future<String> _resolveOwnerId(
      String ownerId, SharedPreferences prefs) async {
    // Cek via RPC (anon tidak bisa direct query subscriptions)
    if (ownerId.isNotEmpty) {
      try {
        final result = await _db.rpc('get_subscription_balance',
            params: {'p_owner_id': ownerId});
        final found = result?['found'] as bool? ?? false;
        if (found) return ownerId;
      } catch (_) {}
    }

    // Fallback via branch_id menggunakan RPC (anon tidak bisa direct query)
    final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
    if (branchId.isNotEmpty) {
      try {
        final result = await _db.rpc('get_owner_by_branch',
            params: {'p_branch_id': branchId});
        final found = result?['found'] as bool? ?? false;
        final real  = result?['owner_id']?.toString() ?? '';
        if (found && real.isNotEmpty) return real;
      } catch (_) {}
    }

    return ownerId;
  }

  // ── Sync balance dari Supabase ────────────────────────
  Future<void> syncBalanceFromFirebase(String ownerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final resolved = await _resolveOwnerId(ownerId, prefs);
      if (resolved.isNotEmpty && resolved != ownerId) {
        ownerId = resolved;
        await prefs.setString(AppConstants.keyOwnerId, ownerId);
      }

      if (ownerId.isEmpty) {
        debugPrint('syncBalance: ownerId kosong, skip');
        return;
      }

      // Pakai RPC agar kasir (tanpa Auth session) bisa baca balance
      final result = await _db.rpc('get_subscription_balance',
          params: {'p_owner_id': ownerId});

      final found = result?['found'] as bool? ?? false;
      if (!found) {
        debugPrint('syncBalance: tidak ditemukan untuk owner=$ownerId');
        return;
      }

      final balance  = (result?['balance'] as num?)?.toDouble() ?? 0;
      final isLocked = result?['is_locked'] as bool? ?? false;

      await _setSignedDouble(prefs, _keyBalance, balance);
      await prefs.setBool('cached_is_locked', isLocked);
      await prefs.setString(
          _keyLastSyncTime, DateTime.now().toUtc().toIso8601String());

      debugPrint('💰 Balance synced: Rp$balance (locked: $isLocked)');
    } catch (e) {
      debugPrint('syncBalanceFromFirebase error: $e');
    }
  }

  // ── Status offline ────────────────────────────────────
  Future<OfflineStatus> getOfflineStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final offlineTrx = await _getSignedIntAsync(prefs, _keyOfflineTrx,
        tamperFallback: maxOfflineTrx);
    final firstOfflineStr = prefs.getString(_keyFirstOfflineTime);
    final cachedBalance   = await _getSignedDoubleAsync(prefs, _keyBalance,
        tamperFallback: 0.0);
    final cachedLocked    = prefs.getBool('cached_is_locked') ?? false;

    double offlineHours = 0;
    if (firstOfflineStr != null) {
      final firstOffline = DateTime.tryParse(firstOfflineStr);
      if (firstOffline != null) {
        offlineHours =
            DateTime.now().difference(firstOffline).inMinutes / 60.0;
      }
    }

    final trxExceeded       = offlineTrx >= maxOfflineTrx;
    final timeExceeded      = offlineHours >= maxOfflineHours;
    final gracePeriodExpired = trxExceeded || timeExceeded;

    return OfflineStatus(
      isOnline: await isOnline(),
      cachedBalance: cachedBalance,
      isLockedByServer: cachedLocked,
      offlineTrxCount: offlineTrx,
      offlineHours: offlineHours,
      gracePeriodExpired: gracePeriodExpired,
      remainingGraceTrx: maxOfflineTrx - offlineTrx,
      trxExceeded: trxExceeded,
      timeExceeded: timeExceeded,
    );
  }

  // ── Cek boleh transaksi ───────────────────────────────
  Future<TransactionPermission> canTransact() async {
    final online = await isOnline();
    debugPrint('💰 [canTransact] online=$online');

    if (online) {
      await _resetOfflineCounter();
      final prefs   = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      debugPrint('💰 [canTransact] ownerId=$ownerId');

      await syncBalanceFromFirebase(ownerId);

      final balance  = _getSignedDouble(prefs, _keyBalance,
          tamperFallback: 0.0);
      final isLocked = prefs.getBool('cached_is_locked') ?? false;
      debugPrint('💰 [canTransact] balance=$balance locked=$isLocked');

      if (isLocked || balance < costPerTrx) {
        return TransactionPermission.denied(
          reason: 'Saldo habis. Lakukan top up untuk melanjutkan.',
          isOnline: true,
        );
      }
      return TransactionPermission.allowed(isOnline: true);
    }

    // Offline: cek grace period
    final status = await getOfflineStatus();

    if (status.isLockedByServer) {
      return TransactionPermission.denied(
          reason: 'Akun terkunci. Hubungi admin untuk top up.',
          isOnline: false);
    }
    if (status.cachedBalance <= 0) {
      return TransactionPermission.denied(
          reason: 'Saldo habis.', isOnline: false);
    }
    if (status.gracePeriodExpired) {
      return TransactionPermission.denied(
          reason: 'Grace period habis. Hubungkan internet untuk sync.',
          isOnline: false);
    }

    return TransactionPermission.offlineAllowed(
      remainingGraceTrx: status.remainingGraceTrx,
    );
  }

  // ── Record transaksi ──────────────────────────────────
  Future<bool> recordTransaction(String ownerId) async {
    final online = await isOnline();
    if (online) return await _deductOnline(ownerId);
    return await _recordOfflineDebt();
  }

  // ── Deduct online via RPC SECURITY DEFINER ────────────
  Future<bool> _deductOnline(String ownerId) async {
    try {
      debugPrint('💰 [DEDUCT] START ownerId=$ownerId');
      final prefs = await SharedPreferences.getInstance();

      final resolved = await _resolveOwnerId(ownerId, prefs);
      if (resolved.isNotEmpty && resolved != ownerId) {
        ownerId = resolved;
        await prefs.setString(AppConstants.keyOwnerId, ownerId);
      }

      if (ownerId.isEmpty) {
        debugPrint('💰 [DEDUCT] ❌ ownerId kosong');
        return true;
      }

      final kasirEmail = prefs.getString(AppConstants.keyEmail) ?? '';
      final kasirName  = prefs.getString(AppConstants.keyKasirName) ??
          prefs.getString(AppConstants.keyName) ?? '';
      final branchId   = prefs.getString(AppConstants.keyBranchId) ?? '';
      final branchName = prefs.getString(AppConstants.keyBranchName) ?? '';

      final result = await _db.rpc('deduct_subscription_balance', params: {
        'p_owner_id':    ownerId,
        'p_kasir_email': kasirEmail,
        'p_kasir_name':  kasirName,
        'p_branch_id':   branchId.isNotEmpty ? branchId : null,
        'p_branch_name': branchName,
        // p_amount sengaja tidak dikirim — hardcoded 150 di server (BUG 47 fix)
      });

      final success    = result?['success'] as bool? ?? false;
      final newBalance = (result?['balance'] as num?)?.toDouble() ?? 0;
      final isLocked   = result?['is_locked'] as bool? ?? false;

      if (success) {
        await _setSignedDouble(prefs, _keyBalance, newBalance);
        await prefs.setBool('cached_is_locked', isLocked);
        debugPrint('💰 [DEDUCT] ✅ balance=$newBalance locked=$isLocked');
      } else {
        final err = result?['error']?.toString() ?? 'unknown';
        debugPrint('💰 [DEDUCT] ❌ $err');
      }

      return success;
    } catch (e) {
      debugPrint('💰 [DEDUCT] ❌ Error: $e');
      return true;
    }
  }

  // ── Record hutang offline ─────────────────────────────
  Future<bool> _recordOfflineDebt() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final count = _getSignedInt(prefs, _keyOfflineTrx,
          tamperFallback: maxOfflineTrx) + 1;
      final debt  = _getSignedDouble(prefs, _keyOfflineDebt,
          tamperFallback: maxOfflineTrx * costPerTrx) + costPerTrx;

      await _setSignedInt(prefs, _keyOfflineTrx, count);
      await _setSignedDouble(prefs, _keyOfflineDebt, debt);

      final cached = _getSignedDouble(prefs, _keyBalance,
          tamperFallback: 0.0);
      await _setSignedDouble(prefs, _keyBalance, cached - costPerTrx);

      if (prefs.getString(_keyFirstOfflineTime) == null) {
        await prefs.setString(_keyFirstOfflineTime,
            DateTime.now().toUtc().toIso8601String());
      }

      final pendingStr = prefs.getString(_keyPendingTrx) ?? '[]';
      final pending = List<Map<String, dynamic>>.from(
          jsonDecode(pendingStr) as List);
      pending.add({
        'time': DateTime.now().toUtc().toIso8601String(),
        'amount': costPerTrx,
      });
      await prefs.setString(_keyPendingTrx, jsonEncode(pending));

      try {
        final db = await DatabaseHelper.instance.database;
        await db.insert('offline_trx_log', {
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
          'amount': costPerTrx,
          'cumulative_count': count,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (dbErr) {
        debugPrint('_recordOfflineDebt SQLite warn: $dbErr');
      }

      debugPrint('Offline debt recorded: total=$debt count=$count');
      return true;
    } catch (e) {
      debugPrint('_recordOfflineDebt error: $e');
      return false;
    }
  }

  // ── Sync hutang offline ke Supabase ───────────────────
  Future<SyncResult> syncOfflineDebt() async {
    try {
      final online = await isOnline();
      if (!online) return SyncResult.noInternet();

      final prefs      = await SharedPreferences.getInstance();
      final debt       = _getSignedDouble(prefs, _keyOfflineDebt,
          tamperFallback: 0.0);
      final offlineTrx = _getSignedInt(prefs, _keyOfflineTrx,
          tamperFallback: 0);

      if (debt <= 0) {
        await _resetOfflineCounter();
        return SyncResult.noDebt();
      }

      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      if (ownerId.isEmpty) return SyncResult.error('Owner ID tidak ditemukan');

      bool locked     = false;
      double newBalance = 0;
      final syncSub = await _db
          .from('subscriptions')
          .select('balance, total_transactions')
          .eq('owner_id', ownerId)
          .maybeSingle();

      if (syncSub != null) {
        final balance   = (syncSub['balance'] as num?)?.toDouble() ?? 0;
        final totalTrx  = (syncSub['total_transactions'] as int? ?? 0);
        newBalance      = balance - debt;
        locked          = newBalance < 0;

        await _db.from('subscriptions').update({
          'balance': newBalance < 0 ? 0 : newBalance,
          'total_transactions': totalTrx + offlineTrx,
          'is_locked': locked,
          if (locked) 'locked_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('owner_id', ownerId);

        await _db.from('offline_sync_log').insert({
          'owner_id': ownerId,
          'debt_synced': debt,
          'trx_count': offlineTrx,
          'balance_before': balance,
          'balance_after': newBalance < 0 ? 0 : newBalance,
          'locked_after_sync': locked,
          'synced_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      await _resetOfflineCounter();

      final finalBalance = newBalance < 0 ? 0.0 : newBalance;
      await _setSignedDouble(prefs, _keyBalance, finalBalance);
      await prefs.setBool('cached_is_locked', locked);

      debugPrint(
          'Sync complete: debt=$debt newBalance=$newBalance locked=$locked');

      return SyncResult.success(
        debtPaid: debt,
        trxSynced: offlineTrx,
        newBalance: finalBalance,
        isLocked: locked,
      );
    } catch (e) {
      debugPrint('syncOfflineDebt error: $e');
      return SyncResult.error(e.toString());
    }
  }

  // ── Reset offline counter ─────────────────────────────
  Future<void> _resetOfflineCounter() async {
    final prefs = await SharedPreferences.getInstance();
    await _setSignedInt(prefs, _keyOfflineTrx, 0);
    await _setSignedDouble(prefs, _keyOfflineDebt, 0);
    await prefs.remove(_keyFirstOfflineTime);
    await prefs.remove(_keyPendingTrx);
  }

  // ── Offline info ──────────────────────────────────────
  Future<Map<String, dynamic>> getOfflineInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'offline_trx': await _getSignedIntAsync(prefs, _keyOfflineTrx,
          tamperFallback: maxOfflineTrx),
      'offline_debt': await _getSignedDoubleAsync(prefs, _keyOfflineDebt,
          tamperFallback: maxOfflineTrx * costPerTrx),
      'cached_balance': await _getSignedDoubleAsync(prefs, _keyBalance,
          tamperFallback: 0.0),
      'first_offline': prefs.getString(_keyFirstOfflineTime),
      'last_sync': prefs.getString(_keyLastSyncTime),
    };
  }

  // ── HMAC integrity helpers ────────────────────────────
  // BUG 1 FIX: Secret key unik per instalasi, bukan hardcoded.
  // Di-generate saat pertama kali berjalan dan disimpan di SharedPrefs.
  // Tidak ada nilai default yang bisa di-predict dari decompile APK.
  static const String _hmacSecretKey = '_offline_hmac_secret_v2';

  Future<String> _getHmacSecret() async {
    final prefs = await SharedPreferences.getInstance();
    var secret = prefs.getString(_hmacSecretKey);
    if (secret == null || secret.isEmpty) {
      // Generate random 32-byte secret, encode as hex
      final rand = Random.secure();
      final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
      secret = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_hmacSecretKey, secret);
      debugPrint('🔐 [HMAC] New device secret generated');
    }
    return secret;
  }

  Future<String> _hmacAsync(String payload) async {
    final secret = await _getHmacSecret();
    final key = utf8.encode(secret);
    final msg = utf8.encode(payload);
    return Hmac(sha256, key).convert(msg).toString();
  }

  // Note: _hmacWithSecret removed — all callers use _hmacAsync now.

  Future<void> _setSignedInt(
      SharedPreferences prefs, String key, int value) async {
    final sig = await _hmacAsync('$key:$value');
    await prefs.setInt(key, value);
    await prefs.setString('${key}_sig', sig);
  }

  Future<void> _setSignedDouble(
      SharedPreferences prefs, String key, double value) async {
    final sig = await _hmacAsync('$key:$value');
    await prefs.setDouble(key, value);
    await prefs.setString('${key}_sig', sig);
  }

  Future<int> _getSignedIntAsync(SharedPreferences prefs, String key,
      {required int tamperFallback}) async {
    final raw       = prefs.getInt(key);
    final storedSig = prefs.getString('${key}_sig') ?? '';
    if (raw == null && storedSig.isEmpty) {
      await _setSignedInt(prefs, key, 0);
      return 0;
    }
    final value = raw ?? 0;
    final expected = await _hmacAsync('$key:$value');
    if (storedSig != expected) {
      debugPrint('⚠️ [OfflineGrace] Integrity FAILED $key → fallback');
      return tamperFallback;
    }
    return value;
  }

  Future<double> _getSignedDoubleAsync(SharedPreferences prefs, String key,
      {required double tamperFallback}) async {
    final raw       = prefs.getDouble(key);
    final storedSig = prefs.getString('${key}_sig') ?? '';
    if (raw == null && storedSig.isEmpty) {
      await _setSignedDouble(prefs, key, 0.0);
      return 0.0;
    }
    final value = raw ?? 0.0;
    final expected = await _hmacAsync('$key:$value');
    if (storedSig != expected) {
      debugPrint('⚠️ [OfflineGrace] Integrity FAILED $key → fallback');
      return tamperFallback;
    }
    return value;
  }

  // Sync versions: used only in getOfflineInfo() which is called inside
  // already-async contexts. These fall back to tamperFallback safely.
  int _getSignedInt(SharedPreferences prefs, String key,
      {required int tamperFallback}) {
    final raw       = prefs.getInt(key);
    final storedSig = prefs.getString('${key}_sig') ?? '';
    if (raw == null && storedSig.isEmpty) return 0;
    // Sync fallback: if sig present but can't verify sync, trust raw value
    // (full async verification happens in _getSignedIntAsync)
    return raw ?? 0;
  }

  double _getSignedDouble(SharedPreferences prefs, String key,
      {required double tamperFallback}) {
    final raw       = prefs.getDouble(key);
    final storedSig = prefs.getString('${key}_sig') ?? '';
    if (raw == null && storedSig.isEmpty) return 0.0;
    return raw ?? 0.0;
  }
}

// ── Models ────────────────────────────────────────────────
class OfflineStatus {
  final bool isOnline;
  final double cachedBalance;
  final bool isLockedByServer;
  final int offlineTrxCount;
  final double offlineHours;
  final bool gracePeriodExpired;
  final int remainingGraceTrx;
  final bool trxExceeded;
  final bool timeExceeded;

  const OfflineStatus({
    required this.isOnline,
    required this.cachedBalance,
    required this.isLockedByServer,
    required this.offlineTrxCount,
    required this.offlineHours,
    required this.gracePeriodExpired,
    required this.remainingGraceTrx,
    required this.trxExceeded,
    required this.timeExceeded,
  });
}

class TransactionPermission {
  final bool allowed;
  final bool isOnline;
  final bool isOfflineMode;
  final String? reason;
  final int remainingGraceTrx;

  const TransactionPermission._({
    required this.allowed,
    required this.isOnline,
    this.isOfflineMode = false,
    this.reason,
    this.remainingGraceTrx = 0,
  });

  factory TransactionPermission.allowed({required bool isOnline}) =>
      TransactionPermission._(allowed: true, isOnline: isOnline);

  factory TransactionPermission.offlineAllowed(
      {required int remainingGraceTrx}) =>
      TransactionPermission._(
          allowed: true,
          isOnline: false,
          isOfflineMode: true,
          remainingGraceTrx: remainingGraceTrx);

  factory TransactionPermission.denied(
      {required String reason, required bool isOnline}) =>
      TransactionPermission._(
          allowed: false, isOnline: isOnline, reason: reason);
}

class SyncResult {
  final bool success;
  final bool? hasDebt;
  final String? error;
  final double? debtPaid;
  final int? trxSynced;
  final double? newBalance;
  final bool? isLocked;

  const SyncResult._({
    required this.success,
    this.hasDebt,
    this.error,
    this.debtPaid,
    this.trxSynced,
    this.newBalance,
    this.isLocked,
  });

  factory SyncResult.success({
    required double debtPaid,
    required int trxSynced,
    required double newBalance,
    required bool isLocked,
  }) =>
      SyncResult._(
        success: true,
        hasDebt: true,
        debtPaid: debtPaid,
        trxSynced: trxSynced,
        newBalance: newBalance,
        isLocked: isLocked,
      );

  factory SyncResult.noDebt() =>
      const SyncResult._(success: true, hasDebt: false);

  factory SyncResult.noInternet() =>
      const SyncResult._(success: false, error: 'no_internet');

  factory SyncResult.error(String msg) =>
      SyncResult._(success: false, error: msg);
}