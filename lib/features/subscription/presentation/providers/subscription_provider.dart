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

  // Saldo aktif (online dari Firebase atau cache lokal)
  bool get canTransactBasic => _subscription?.isActive ?? true;
  bool get isWarning => _subscription?.isWarning ?? false;
  bool get isLocked =>
      _subscription?.isEmpty == true || _subscription?.isLocked == true;

  // Threshold minimum saldo agar kasir bisa digunakan (online)
  static const double minimumBalance = 5000;

  // true = online DAN saldo < 5000 → kasir harus diblokir
  bool get isBelowMinimum =>
      _isOnline && !_loading && (_subscription?.balance ?? 0) < minimumBalance;
  double get balance => _subscription?.balance ?? 0;
  int get remainingTrx => _subscription?.remainingTransactions ?? 0;

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    try {
      // Cek online/offline
      _isOnline = await OfflineGraceManager.instance.isOnline();

      // Load dari Firebase kalau online
      _subscription = await SubscriptionService.instance.getMySubscription();

      // Kalau online, sync balance ke cache lokal
      if (_isOnline) {
        // Sync balance - use subscription's actual owner_id (may differ from SharedPrefs)
        final actualOwnerId = _subscription?.branchId ?? '';
        final prefs = await SharedPreferences.getInstance();
        final savedOwnerId = prefs.getString("sb_owner_id") ?? "";
        final ownerIdToSync = actualOwnerId.isNotEmpty ? actualOwnerId : savedOwnerId;
        if (ownerIdToSync.isNotEmpty) {
          await OfflineGraceManager.instance.syncBalanceFromFirebase(ownerIdToSync);
          await _trySyncOfflineDebt();
        }
      }

      // Load info offline
      await _loadOfflineInfo();

      // Check balance and notify if needed
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

      // Reload subscription setiap 30 detik saat online
      // Supabase realtime tersedia tapi tidak digunakan untuk simplicity
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

  // Dipanggil setelah checkout berhasil
  Future<TransactionPermission> checkAndDeduct() async {
    final prefs = await SharedPreferences.getInstance();
    final ownerId = prefs.getString("sb_owner_id") ?? "";

    debugPrint('💰 [SubProvider] checkAndDeduct: ownerId=$ownerId');

    // Cek permission dulu
    final permission = await OfflineGraceManager.instance.canTransact();
    if (!permission.allowed) return permission;

    // Potong saldo
    final deducted = await OfflineGraceManager.instance.recordTransaction(ownerId);
    debugPrint('💰 [SubProvider] deducted=$deducted');

    // ── Update UI balance IMMEDIATELY ─────────────────────
    // FIX: baca balance via OfflineGraceManager agar konsisten dengan
    // signed storage — jangan pakai prefs.getDouble langsung
    final offlineInfo = await OfflineGraceManager.instance.getOfflineInfo();
    final newBalance = (offlineInfo['cached_balance'] as double?) ?? 0.0;
    debugPrint('💰 [SubProvider] newBalance from OfflineGraceManager=$newBalance');

    if (_subscription != null) {
      final updatedBalance = newBalance > 0
          ? newBalance
          : (_subscription!.balance - 150).clamp(0.0, double.infinity);
      _subscription = _subscription!.copyWith(
        balance: updatedBalance.toDouble(),
        totalTransactions: _subscription!.totalTransactions + 1,
      );
      debugPrint('💰 [SubProvider] ✅ _subscription.balance updated: ${_subscription!.balance}');
    }

    await _loadOfflineInfo();
    notifyListeners();

    return permission;
  }

  // Refresh balance dari Supabase (dipanggil manual atau setelah login)
  Future<void> refreshBalance() async {
    debugPrint('💰 [SubProvider] refreshBalance called');
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      await OfflineGraceManager.instance.syncBalanceFromFirebase(ownerId);
      // FIX: baca via getOfflineInfo agar konsisten dengan signed storage
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

  // Cek balance terbaru dari Supabase — dipanggil saat buka CashierScreen
  // Return true = boleh transaksi, false = saldo di bawah minimum (online)
  Future<bool> checkBalanceOnline() async {
    try {
      final isOnline = await OfflineGraceManager.instance.isOnline();
      _isOnline = isOnline;
      if (!isOnline) {
        notifyListeners();
        return true; // offline → grace period, boleh transaksi
      }
      // Online → fetch saldo terbaru dari Supabase
      _subscription = await SubscriptionService.instance.getMySubscription();
      notifyListeners();
      final bal = _subscription?.balance ?? 0;
      debugPrint('💰 [checkBalanceOnline] bal=$bal minimum=$minimumBalance');
      return bal >= minimumBalance;
    } catch (e) {
      debugPrint('💰 [checkBalanceOnline] error=$e → allow (fail-open)');
      return true; // error = treat as offline, boleh transaksi
    }
  }

  // Sync hutang offline - dipanggil saat internet nyala
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
