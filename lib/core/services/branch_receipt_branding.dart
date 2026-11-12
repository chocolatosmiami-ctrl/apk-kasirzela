import 'dart:convert';

class ReceiptBrandingScope {
  final String accountId, ownerId, branchId;
  const ReceiptBrandingScope(this.accountId, this.ownerId, this.branchId);
  bool get hasIdentity => accountId.isNotEmpty && ownerId.isNotEmpty;
  String get cacheKey =>
      'branch_receipt_v1:${jsonEncode([accountId, ownerId, branchId])}';
  @override
  bool operator ==(Object other) =>
      other is ReceiptBrandingScope &&
      accountId == other.accountId &&
      ownerId == other.ownerId &&
      branchId == other.branchId;
  @override
  int get hashCode => Object.hash(accountId, ownerId, branchId);
}

/// Branding only: this cache never supplies stock, permissions or payment rules.
class BranchReceiptSnapshot {
  final ReceiptBrandingScope scope;
  final Map<String, String> fields;
  static const keys = [
    'struk_nama',
    'struk_alamat',
    'struk_telp',
    'struk_footer',
    'logo_url'
  ];
  BranchReceiptSnapshot(this.scope, Map<dynamic, dynamic> source)
      : fields =
            Map.unmodifiable({for (final key in keys) key: _text(source[key])});
  static String _text(dynamic value) => value is String ? value.trim() : '';
  String encode() => jsonEncode({
        'version': 1,
        'account_id': scope.accountId,
        'owner_id': scope.ownerId,
        'branch_id': scope.branchId,
        'fields': fields
      });
  static BranchReceiptSnapshot? decode(
      String? raw, ReceiptBrandingScope scope) {
    if (raw == null || !scope.hasIdentity || scope.branchId.isEmpty)
      return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['version'] != 1 ||
          data['account_id'] != scope.accountId ||
          data['owner_id'] != scope.ownerId ||
          data['branch_id'] != scope.branchId ||
          data['fields'] is! Map) return null;
      final fields = data['fields'] as Map;
      if (keys.any((key) => fields[key] is! String)) return null;
      return BranchReceiptSnapshot(scope, fields);
    } catch (_) {
      return null;
    }
  }
}

/// A late reply from an earlier account/branch must not replace current branding.
class BranchReceiptBranding {
  ReceiptBrandingScope? _scope;
  BranchReceiptSnapshot? _snapshot;
  int _revision = 0;
  ReceiptBrandingScope? get scope => _scope;
  int get ticket => _revision;
  BranchReceiptSnapshot? get snapshot => _snapshot;
  bool bind(ReceiptBrandingScope scope) {
    if (_scope == scope) return false;
    _scope = scope;
    _snapshot = null;
    _revision++;
    return true;
  }

  void clear() {
    _scope = null;
    _snapshot = null;
    _revision++;
  }

  bool accept(int ticket, BranchReceiptSnapshot snapshot) {
    if (ticket != _revision || snapshot.scope != _scope) return false;
    _snapshot = snapshot;
    return true;
  }

  String effectiveLogo(String ownerLogo) {
    final scope = _scope;
    if (scope == null || !scope.hasIdentity) return '';
    if (scope.branchId.isEmpty) return ownerLogo;
    // Unknown branch settings are not proof that this branch has no logo.
    // Keep the logo blank until its own cache/server snapshot is available.
    final snapshot = _snapshot;
    if (snapshot == null) return '';
    final logo = snapshot.fields['logo_url'] ?? '';
    return logo.isNotEmpty ? logo : ownerLogo;
  }
}
