import 'dart:convert';
import '../../../../core/services/startup_policy.dart';
import '../../../../core/services/service_health.dart';
import '../../../../core/utils/app_constants.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/subscription_model.dart';
import '../../data/services/subscription_service.dart';
import '../../../../core/services/offline_grace_manager.dart';
import '../../../../core/services/notification_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  SubscriptionModel? _subscription;
  bool _loading = true;
  bool _isOnline = true;
  int _offlineTrxCount = 0;
  double _offlineDebt = 0;
  StreamSubscription? _stream;
  Future<void>? _initializing;
  bool _verified = false;
  String _owner = '';
  bool get verificationReady => _verified;
  String get verificationMessage => _verified ? 'Menggunakan data subscription terverifikasi.'
      : 'Subscription belum dapat diverifikasi. Periksa koneksi lalu coba lagi.';

  SubscriptionModel? get subscription => _subscription;
  bool get loading => _loading;
  bool get isOnline => _isOnline;
  int get offlineTrxCount => _offlineTrxCount;
  double get offlineDebt => _offlineDebt;

  bool get canTransactBasic => _verified && (_subscription?.isActive ?? false);
  bool get isWarning => _subscription?.isWarning ?? false;
  bool get isLocked =>
      _subscription?.isEmpty == true || _subscription?.isLocked == true;

  static const double minimumBalance = 5000;

  bool get isBelowMinimum {
    if (!_isOnline || _loading) return false;
    final sub = _subscription;
    if (sub == null) return false;
    // Kalau plan aktif (monthly/yearly) → tidak locked meski saldo rendah
    if (sub.isPlanActive) return false;
    return sub.balance < minimumBalance;
  }

  double get balance => _subscription?.balance ?? 0;
  int get remainingTrx => _subscription?.remainingTransactions ?? 0;

  /// Cost per trx dari DB (bukan hardcode)
  double get costPerTrx => _subscription?.costPerTransaction ?? 300;

  Future<void> init() => _initializing ??= _initialize().whenComplete(() => _initializing = null);
  Future<void> _initialize() async {
    _loading = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(AppConstants.keyUid) ?? '';
    final owner = prefs.getString(AppConstants.keyOwnerId) ?? '';
    if (_owner != owner) { _subscription = null; _verified = false; }
    _owner = owner;
    final key = 'startup_subscription_' + owner;
    try {
      final sub = await SubscriptionService.instance.getMySubscription().timeout(const Duration(seconds: 12));
      if (prefs.getString(AppConstants.keyUid) != uid || prefs.getString(AppConstants.keyOwnerId) != owner) return;
      _subscription = sub;
      _verified = sub != null && sub.branchId == owner;
      _isOnline = true;
      if (_verified) {
        await prefs.setString(key, jsonEncode({'verified_at': DateTime.now().toUtc().toIso8601String(), 'data': sub!.toMap()}));
        await OfflineGraceManager.instance.rememberVerifiedSubscription(owner, sub.toMap());
        ServiceHealth.instance.record('subscription', null);
      } else {
        await prefs.remove(key);
        ServiceHealth.instance.record('subscription', FailureKind.denied);
      }
    } catch (e) {
      _isOnline = false;
      _verified = false;
      final kind = failureKind(e);
      final raw = (kind == FailureKind.denied || kind == FailureKind.invalidSession) ? null : prefs.getString(key);
      if (raw != null && prefs.getString(AppConstants.keyOwnerId) == owner && prefs.getString(AppConstants.keyUid) == uid) {
        try {
          final saved = jsonDecode(raw) as Map;
          final sub = SubscriptionModel.fromMap(Map<String, dynamic>.from(saved['data'] as Map));
          if (sub.branchId == owner && validCacheAge(DateTime.tryParse(saved['verified_at'].toString()), DateTime.now().toUtc())) {
            _subscription = sub; _verified = true;
          }
        } catch (_) {}
      }
      ServiceHealth.instance.record('subscription', failureKind(e));
    } finally {
      await _loadOfflineInfo();
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadOfflineInfo() async {
    final info = await OfflineGraceManager.instance.getOfflineInfo();
    _offlineTrxCount = info["offline_trx"] as int? ?? 0;
    _offlineDebt = info["offline_debt"] as double? ?? 0;
  }

  Future<TransactionPermission> checkAndDeduct() async {
    final prefs = await SharedPreferences.getInstance();
    final ownerId = prefs.getString("sb_owner_id") ?? "";

    debugPrint('💰 [SubProvider] checkAndDeduct: ownerId=$ownerId');

    final permission = await OfflineGraceManager.instance.canTransact();
    if (!permission.allowed) return permission;

    final deducted = await OfflineGraceManager.instance.recordTransaction(ownerId);
    debugPrint('💰 [SubProvider] deducted=$deducted');

    final offlineInfo = await OfflineGraceManager.instance.getOfflineInfo();
    final newBalance = (offlineInfo['cached_balance'] as double?) ?? 0.0;
    debugPrint('💰 [SubProvider] newBalance from OfflineGraceManager=$newBalance');

    if (_subscription != null) {
      // Kalau plan aktif, saldo tidak berkurang
      final isPlanActive = _subscription!.isPlanActive;
      final cost = _subscription!.costPerTransaction;

      final updatedBalance = isPlanActive
          ? _subscription!.balance  // plan aktif → saldo tetap
          : newBalance > 0
          ? newBalance
          : (_subscription!.balance - cost).clamp(0.0, double.infinity);

      _subscription = _subscription!.copyWith(
        balance: updatedBalance.toDouble(),
        totalTransactions: _subscription!.totalTransactions + 1,
      );
      debugPrint('💰 [SubProvider] ✅ balance updated: ${_subscription!.balance} (planActive=$isPlanActive)');
    }

    await _loadOfflineInfo();
    notifyListeners();

    return permission;
  }

  Future<void> refreshBalance() async {
    debugPrint('💰 [SubProvider] refreshBalance called');
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      await OfflineGraceManager.instance.syncBalanceFromFirebase(ownerId);
      final info = await OfflineGraceManager.instance.getOfflineInfo();
      final newBalance = (info['cached_balance'] as double?) ?? 0.0;
      if (_subscription != null) {
        _subscription = _subscription!.copyWith(balance: newBalance);
      }
      notifyListeners();
      debugPrint('💰 [SubProvider] refreshBalance done: $newBalance');
    } catch (e) {
      debugPrint('💰 [SubProvider] refreshBalance error: $e');
    }
  }

  Future<bool> checkBalanceOnline() async {
    await init();
    if (!_verified || _subscription == null || _subscription!.isLocked) return false;
    if (!_isOnline) return (await OfflineGraceManager.instance.canTransactOffline()).allowed;
    return _subscription!.isPlanActive || _subscription!.balance >= minimumBalance;
  }

  Future<SyncResult> syncOfflineDebt() async {
    final result = await OfflineGraceManager.instance.syncOfflineDebt();
    if (result.success) {
      await init();
      if (result.hasDebt == true && result.trxSynced != null) {
        NotificationService.instance.notifyOfflineSynced(
            result.trxSynced!, result.debtPaid ?? 0,
            result.isLocked ?? false);
      }
    }
    return result;
  }

  Future<void> _trySyncOfflineDebt() async {
    final info = await OfflineGraceManager.instance.getOfflineInfo();
    final debt = info["offline_debt"] as double? ?? 0;
    if (debt > 0) {
      debugPrint("Auto-syncing offline debt: Rp$debt");
      await OfflineGraceManager.instance.syncOfflineDebt();
    }
  }

  Future<String?> requestTopUp({
    required double amount,
    required String method,
    String? notes,
  }) async {
    return SubscriptionService.instance.requestTopUp(
        amount: amount, method: method, notes: notes);
  }

  @override
  void dispose() {
    _stream?.cancel();
    super.dispose();
  }
}