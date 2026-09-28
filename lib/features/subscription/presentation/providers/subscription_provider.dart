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

  SubscriptionModel? get subscription => _subscription;
  bool get loading => _loading;
  bool get isOnline => _isOnline;
  int get offlineTrxCount => _offlineTrxCount;
  double get offlineDebt => _offlineDebt;

  bool get canTransactBasic => _subscription?.isActive ?? true;
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

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    try {
      _isOnline = await OfflineGraceManager.instance.isOnline();
      _subscription = await SubscriptionService.instance.getMySubscription();

      if (_isOnline) {
        final actualOwnerId = _subscription?.branchId ?? '';
        final prefs = await SharedPreferences.getInstance();
        final savedOwnerId = prefs.getString("sb_owner_id") ?? "";
        final ownerIdToSync = actualOwnerId.isNotEmpty ? actualOwnerId : savedOwnerId;
        if (ownerIdToSync.isNotEmpty) {
          await OfflineGraceManager.instance.syncBalanceFromFirebase(ownerIdToSync);
          await _trySyncOfflineDebt();
        }
      }

      await _loadOfflineInfo();

      if (_subscription != null) {
        if (_subscription!.isEmpty) {
          NotificationService.instance.notifyBalanceEmpty();
        } else if (_subscription!.isWarning) {
          NotificationService.instance.notifyBalanceLow(
              _subscription!.balance, _subscription!.remainingTransactions);
        }
      }

      _loading = false;
      notifyListeners();
    } catch (e) {
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
    try {
      final isOnline = await OfflineGraceManager.instance.isOnline();
      _isOnline = isOnline;
      if (!isOnline) {
        notifyListeners();
        return true;
      }
      _subscription = await SubscriptionService.instance.getMySubscription();
      notifyListeners();

      // Kalau plan aktif → selalu boleh transaksi
      if (_subscription?.isPlanActive == true) return true;

      final bal = _subscription?.balance ?? 0;
      debugPrint('💰 [checkBalanceOnline] bal=$bal minimum=$minimumBalance');
      return bal >= minimumBalance;
    } catch (e) {
      debugPrint('💰 [checkBalanceOnline] error=$e → allow (fail-open)');
      return true;
    }
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