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

  static const int maxOfflineTrx   = 20;
  static const int maxOfflineHours  = 24;
  // costPerTrx tidak lagi hardcode — diambil dari DB saat sync
  static const double _defaultCostPerTrx = 300;

  static const String _keyBalance          = 'cached_balance';
  static const String _keyOfflineTrx       = 'offline_trx_count';
  static const String _keyOfflineDebt      = 'offline_debt';
  static const String _keyFirstOfflineTime = 'first_offline_time';
  static const String _keyPendingTrx       = 'pending_trx_list';
  static const String _keyLastSyncTime     = 'last_sync_time';
  static const String _keyCostPerTrx       = 'cached_cost_per_trx';

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

  // ── Ambil cost per trx dari cache lokal ──────────────
  Future<double> _getCachedCostPerTrx() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyCostPerTrx) ?? _defaultCostPerTrx;
  }

  // ── Resolve ownerId yang benar ────────────────────────
  Future<String> _resolveOwnerId(
      String ownerId, SharedPreferences prefs) async {
    if (ownerId.isNotEmpty) {
      try {
        final result = await _db.rpc('get_subscription_balance',
            params: {'p_owner_id': ownerId});
        final found = result?['found'] as bool? ?? false;
        if (found) return ownerId;
      } catch (_) {}
    }

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

      // Ambil balance + cost_per_trx + plan_type sekaligus dari tabel langsung
      // (RPC get_subscription_balance hanya return balance & is_locked)
      try {
        final subData = await _db
            .from('subscriptions')
            .select('balance, is_locked, cost_per_trx, plan_type, plan_expires_at')
            .eq('owner_id', ownerId)
            .maybeSingle();

        if (subData != null) {
          final balance    = (subData['balance'] as num?)?.toDouble() ?? 0;
          final isLocked   = subData['is_locked'] as bool? ?? false;
          final costPerTrx = (subData['cost_per_trx'] as num?)?.toDouble() ?? _defaultCostPerTrx;
          final planType   = subData['plan_type'] as String? ?? 'per_trx';
          final planExpiry = subData['plan_expires_at'] as String?;

          // Cek plan aktif
          bool planActive = false;
          if (planType != 'per_trx' && planExpiry != null) {
            final expiry = DateTime.tryParse(planExpiry);
            planActive = expiry != null && expiry.isAfter(DateTime.now());
          }

          await _setSignedDouble(prefs, _keyBalance, balance);
          await prefs.setBool('cached_is_locked', isLocked);
          await prefs.setDouble(_keyCostPerTrx, costPerTrx);
          await prefs.setString('cached_plan_type', planType);
          await prefs.setBool('cached_plan_active', planActive);
          await prefs.setString(
              _keyLastSyncTime, DateTime.now().toUtc().toIso8601String());

          debugPrint('💰 Balance synced: Rp$balance cost=$costPerTrx plan=$planType active=$planActive locked=$isLocked');
          return;
        }
      } catch (_) {}

      // Fallback ke RPC kalau direct query gagal (kasir tanpa auth)
      final result = await _db.rpc('get_subscription_balance',
          params: {'p_owner_id': ownerId});

      final found    = result?['found'] as bool? ?? false;
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

      debugPrint('💰 Balance synced (fallback RPC): Rp$balance locked=$isLocked');
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

    final trxExceeded        = offlineTrx >= maxOfflineTrx;
    final timeExceeded       = offlineHours >= maxOfflineHours;
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
      final prefs    = await SharedPreferences.getInstance();
      final ownerId  = prefs.getString(AppConstants.keyOwnerId) ?? '';
      debugPrint('💰 [canTransact] ownerId=$ownerId');

      await syncBalanceFromFirebase(ownerId);

      final balance     = _getSignedDouble(prefs, _keyBalance, tamperFallback: 0.0);
      final isLocked    = prefs.getBool('cached_is_locked') ?? false;
      final planActive  = prefs.getBool('cached_plan_active') ?? false;
      final costPerTrx  = prefs.getDouble(_keyCostPerTrx) ?? _defaultCostPerTrx;

      debugPrint('💰 [canTransact] balance=$balance locked=$isLocked planActive=$planActive cost=$costPerTrx');

      // Kalau plan aktif (monthly/yearly) → selalu boleh transaksi
      if (planActive) {
        return TransactionPermission.allowed(isOnline: true);
      }

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
      // Cek plan aktif dari cache
      final prefs      = await SharedPreferences.getInstance();
      final planActive = prefs.getBool('cached_plan_active') ?? false;
      if (!planActive) {
        return TransactionPermission.denied(
            reason: 'Saldo habis.', isOnline: false);
      }
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

  // ── Deduct online via RPC ─────────────────────────────
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

      // RPC deduct_subscription_balance sudah handle:
      // - cost_per_trx dari DB (bukan hardcode)
      // - skip deduct kalau plan monthly/yearly aktif
      // - insert ke subscription_logs otomatis
      final result = await _db.rpc('deduct_subscription_balance', params: {
        'p_owner_id':    ownerId,
        'p_kasir_email': kasirEmail,
        'p_kasir_name':  kasirName,
        'p_branch_id':   branchId.isNotEmpty ? branchId : null,
        'p_branch_name': branchName,
      });

      final success    = result?['success'] as bool? ?? false;
      final newBalance = (result?['balance'] as num?)?.toDouble() ?? 0;
      final isLocked   = result?['is_locked'] as bool? ?? false;
      final skipped    = result?['skipped_deduct'] as bool? ?? false;

      if (success) {
        await _setSignedDouble(prefs, _keyBalance, newBalance);
        await prefs.setBool('cached_is_locked', isLocked);
        debugPrint('💰 [DEDUCT] ✅ balance=$newBalance locked=$isLocked skipped=$skipped');
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
      final prefs      = await SharedPreferences.getInstance();
      final costPerTrx = prefs.getDouble(_keyCostPerTrx) ?? _defaultCostPerTrx;

      final count = _getSignedInt(prefs, _keyOfflineTrx,
          tamperFallback: maxOfflineTrx) + 1;
      final debt  = _getSignedDouble(prefs, _keyOfflineDebt,
          tamperFallback: maxOfflineTrx * costPerTrx) + costPerTrx;

      await _setSignedInt(prefs, _keyOfflineTrx, count);
      await _setSignedDouble(prefs, _keyOfflineDebt, debt);

      final cached = _getSignedDouble(prefs, _keyBalance, tamperFallback: 0.0);
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

      debugPrint('Offline debt recorded: total=$debt count=$count cost=$costPerTrx');
      return true;
    } catch (e) {
      debugPrint('_recordOfflineDebt error: $e');
      return false;
    }
  }

  // ── Sync hutang offline ke Supabase via RPC ───────────
  // FIX: dulu pakai direct UPDATE → tidak masuk subscription_logs
  // Sekarang pakai RPC deduct_subscription_balance per transaksi
  Future<SyncResult> syncOfflineDebt() async {
    try {
      final online = await isOnline();
      if (!online) return SyncResult.noInternet();

      final prefs      = await SharedPreferences.getInstance();
      final debt       = _getSignedDouble(prefs, _keyOfflineDebt, tamperFallback: 0.0);
      final offlineTrx = _getSignedInt(prefs, _keyOfflineTrx, tamperFallback: 0);

      if (debt <= 0 || offlineTrx <= 0) {
        await _resetOfflineCounter();
        return SyncResult.noDebt();
      }

      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      if (ownerId.isEmpty) return SyncResult.error('Owner ID tidak ditemukan');

      final kasirEmail = prefs.getString(AppConstants.keyEmail) ?? '';
      final kasirName  = prefs.getString(AppConstants.keyKasirName) ??
          prefs.getString(AppConstants.keyName) ?? '';
      final branchId   = prefs.getString(AppConstants.keyBranchId) ?? '';
      final branchName = prefs.getString(AppConstants.keyBranchName) ?? '';

      bool locked       = false;
      double newBalance = 0;
      int syncedCount   = 0;

      // Panggil RPC per transaksi offline — agar masuk subscription_logs satu per satu
      for (int i = 0; i < offlineTrx; i++) {
        try {
          final result = await _db.rpc('deduct_subscription_balance', params: {
            'p_owner_id':    ownerId,
            'p_kasir_email': kasirEmail,
            'p_kasir_name':  kasirName,
            'p_branch_id':   branchId.isNotEmpty ? branchId : null,
            'p_branch_name': branchName,
            'p_order_number': 'OFFLINE-SYNC-${i + 1}',
            'p_order_items':  'Transaksi offline (sync)',
          });

          final success = result?['success'] as bool? ?? false;
          newBalance    = (result?['balance'] as num?)?.toDouble() ?? newBalance;
          locked        = result?['is_locked'] as bool? ?? false;

          if (success) {
            syncedCount++;
          }

          // Kalau locked, stop sync
          if (locked) break;
        } catch (e) {
          debugPrint('syncOfflineDebt RPC[$i] error: $e');
        }
      }

      await _resetOfflineCounter();
      await _setSignedDouble(prefs, _keyBalance, newBalance);
      await prefs.setBool('cached_is_locked', locked);

      debugPrint('Sync complete: synced=$syncedCount/$offlineTrx newBalance=$newBalance locked=$locked');

      return SyncResult.success(
        debtPaid: debt,
        trxSynced: syncedCount,
        newBalance: newBalance,
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
    final prefs      = await SharedPreferences.getInstance();
    final costPerTrx = prefs.getDouble(_keyCostPerTrx) ?? _defaultCostPerTrx;
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
  static const String _hmacSecretKey = '_offline_hmac_secret_v2';

  Future<String> _getHmacSecret() async {
    final prefs = await SharedPreferences.getInstance();
    var secret = prefs.getString(_hmacSecretKey);
    if (secret == null || secret.isEmpty) {
      final rand  = Random.secure();
      final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
      secret = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_hmacSecretKey, secret);
      debugPrint('🔐 [HMAC] New device secret generated');
    }
    return secret;
  }

  Future<String> _hmacAsync(String payload) async {
    final secret = await _getHmacSecret();
    final key    = utf8.encode(secret);
    final msg    = utf8.encode(payload);
    return Hmac(sha256, key).convert(msg).toString();
  }

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
    final value    = raw ?? 0;
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
    final value    = raw ?? 0.0;
    final expected = await _hmacAsync('$key:$value');
    if (storedSig != expected) {
      debugPrint('⚠️ [OfflineGrace] Integrity FAILED $key → fallback');
      return tamperFallback;
    }
    return value;
  }

  int _getSignedInt(SharedPreferences prefs, String key,
      {required int tamperFallback}) {
    final raw = prefs.getInt(key);
    if (raw == null) return 0;
    return raw;
  }

  double _getSignedDouble(SharedPreferences prefs, String key,
      {required double tamperFallback}) {
    final raw = prefs.getDouble(key);
    if (raw == null) return 0.0;
    return raw;
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