import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constants.dart';

/// Identity of the draft cart, independent of any pending receipt/outbox.
class CartScope {
  final String accountId;
  final String ownerId;
  final String branchId;
  const CartScope(this.accountId, this.ownerId, this.branchId);

  factory CartScope.fromPreferences(SharedPreferences prefs) => CartScope(
        prefs.getString(AppConstants.keyUid) ?? '',
        prefs.getString(AppConstants.keyOwnerId) ?? '',
        prefs.getString(AppConstants.keyBranchId) ?? '',
      );

  bool get hasIdentity => accountId.isNotEmpty && ownerId.isNotEmpty;
  @override
  bool operator ==(Object other) =>
      other is CartScope &&
      accountId == other.accountId &&
      ownerId == other.ownerId &&
      branchId == other.branchId;
  @override
  int get hashCode => Object.hash(accountId, ownerId, branchId);
}

/// Drafts are invalidated immediately by Auth changes, and again at async sinks.
mixin SessionBoundCart on ChangeNotifier {
  String _accountId = '';
  String _ownerId = '';
  String _profileBranch = '';
  String _profileRole = '';
  CartScope? _cartScope;
  int _cartEpoch = 0;
  CartScope? get cartScope => _cartScope;
  int get cartSessionEpoch => _cartEpoch;

  void clearSessionState();

  void bindAccount(String accountId, String ownerId,
      {String branchId = '', String role = ''}) {
    if (_accountId == accountId &&
        _ownerId == ownerId &&
        _profileBranch == branchId &&
        _profileRole == role) return;
    _accountId = accountId;
    _ownerId = ownerId;
    _profileBranch = branchId;
    _profileRole = role;
    invalidateSession();
  }

  void invalidateSession() {
    _cartEpoch++;
    _cartScope = null;
    clearSessionState();
  }

  Future<CartScope?> prepareSession() async {
    final epoch = _cartEpoch;
    final prefs = await SharedPreferences.getInstance();
    if (epoch != _cartEpoch) return null;
    final next = CartScope.fromPreferences(prefs);
    if (!next.hasIdentity ||
        next.accountId != _accountId ||
        next.ownerId != _ownerId) {
      if (_cartScope != null) invalidateSession();
      return null;
    }
    if (_cartScope != next) {
      _cartEpoch++;
      _cartScope = next;
      clearSessionState();
    }
    return _cartScope;
  }

  bool isActiveCartScope(CartScope scope) =>
      identical(scope, _cartScope) &&
      scope.accountId == _accountId &&
      scope.ownerId == _ownerId;

  bool isCurrentSession(CartScope scope, int epoch, SharedPreferences prefs) =>
      epoch == _cartEpoch &&
      isActiveCartScope(scope) &&
      scope == CartScope.fromPreferences(prefs) &&
      scope.accountId == _accountId &&
      scope.ownerId == _ownerId;

  void requireCurrentSession(
      CartScope scope, int epoch, SharedPreferences prefs) {
    if (!isCurrentSession(scope, epoch, prefs)) {
      throw StateError('Akun atau cabang berubah. Buka kembali keranjang.');
    }
  }
}
