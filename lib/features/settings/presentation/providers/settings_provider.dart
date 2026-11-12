import 'dart:async';
import '../../../../core/services/branch_receipt_branding.dart';
import '../../../../core/services/read_work.dart';
import 'dart:convert';
import '../../../../core/services/service_health.dart';
import '../../../../core/services/startup_policy.dart';
import '../../../../core/utils/app_constants.dart';
import '../../../../core/config/supabase_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/database/database_helper.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SettingsProvider extends ChangeNotifier {
  Map<String, String> _settings = {};
  bool _loaded = false;
  String _currentEmail = '';
  int _loadEpoch = 0;
  int _identityRevision = 0;
  String _identityKey = '';
  String _authAccount = '', _authOwner = '', _activeBranchName = '';
  bool _authBound = false, _disposed = false;
  final _branding = BranchReceiptBranding();
  final Future<dynamic> Function(String)? _branchReader;
  SettingsProvider({Future<dynamic> Function(String)? branchReader})
      : _branchReader = branchReader;

  /// Auth notifications invalidate branding immediately, including logout.
  /// Selected branch still comes from preferences (owners can switch branches).
  void bindAccount(String accountId, String ownerId) {
    if (_authBound && _authAccount == accountId && _authOwner == ownerId) return;
    _authBound = true; _authAccount = accountId; _authOwner = ownerId;
    _identityKey = '';
    _identityRevision++; _loadEpoch++;
    _settings = {}; _loaded = false; _currentEmail = '';
    _branding.clear(); _resetBranch();
    scheduleMicrotask(() { if (!_disposed) notifyListeners(); });
  }

  String _keyFor(SharedPreferences prefs) => jsonEncode([
    prefs.getString(AppConstants.keyUid) ?? '',
    prefs.getString(AppConstants.keyOwnerId) ?? '',
    prefs.getString(AppConstants.keyBranchId) ?? '',
    prefs.getString(AppConstants.keyEmail) ?? '',
  ]);
  bool _authMatches(SharedPreferences prefs) => !_authBound ||
      (_authAccount == (prefs.getString(AppConstants.keyUid) ?? '') &&
       _authOwner == (prefs.getString(AppConstants.keyOwnerId) ?? ''));
  bool _prepareScope(SharedPreferences prefs) {
    if (!_authMatches(prefs) || _disposed) return false;
    final key = _keyFor(prefs);
    if (key != _identityKey) {
      _identityKey = key; _identityRevision++; _loadEpoch++;
      _settings = {}; _loaded = false;
      _currentEmail = prefs.getString(AppConstants.keyEmail) ?? '';
      _resetBranch();
      _activeBranchName = prefs.getString(AppConstants.keyBranchName) ?? '';
      _branding.clear();
      _branding.bind(ReceiptBrandingScope(
        prefs.getString(AppConstants.keyUid) ?? '',
        prefs.getString(AppConstants.keyOwnerId) ?? '',
        prefs.getString(AppConstants.keyBranchId) ?? ''));
    }
    return true;
  }
  bool _current(int ticket, String identity, SharedPreferences prefs) =>
      !_disposed && ticket == _loadEpoch && identity == _identityKey &&
      identity == _keyFor(prefs) && _authMatches(prefs);
  void _resetBranch() {
    _branchStrukNama = null; _branchStrukAlamat = null;
    _branchStrukTelp = null; _branchStrukFooter = null;
    _branchDiskonEnabled = false; _branchDiskonLabel = 'Diskon';
    _branchDiskonTipe = 'persen'; _branchDiskonNilai = 0;
    _branchDiskonDari = null; _branchDiskonSampai = null; _branchRounding = 0;
    _activeBranchName = '';
  }
  void _applyBranding(BranchReceiptSnapshot snapshot) {
    _branchStrukNama = snapshot.fields['struk_nama'];
    _branchStrukAlamat = snapshot.fields['struk_alamat'];
    _branchStrukTelp = snapshot.fields['struk_telp'];
    _branchStrukFooter = snapshot.fields['struk_footer'];
  }
  void _restoreBranchBranding(SharedPreferences prefs) {
    final scope = _branding.scope;
    if (scope == null || _branding.snapshot != null) return;
    final saved = BranchReceiptSnapshot.decode(prefs.getString(scope.cacheKey), scope);
    if (saved != null && _branding.accept(_branding.ticket, saved)) _applyBranding(saved);
  }
  @override
  void dispose() { _disposed = true; _loadEpoch++; _branding.clear(); super.dispose(); }


  // ── Branch-level overrides (dari kolom branches di Supabase) ──────────────
  String? _branchStrukNama;
  String? _branchStrukAlamat;
  String? _branchStrukTelp;
  String? _branchStrukFooter;
  bool _branchDiskonEnabled = false;
  String _branchDiskonLabel = 'Diskon';
  String _branchDiskonTipe = 'persen';   // 'persen' | 'nominal'
  double _branchDiskonNilai = 0;
  DateTime? _branchDiskonDari;
  DateTime? _branchDiskonSampai;
  int _branchRounding = 0;              // 0=off, 100, 500, 1000

  bool get loaded => _loaded;
  bool get isLoaded => _loaded;

  // ── Global getters (dari owners) ──────────────────────────────────────────
  String get storeName => _settings['store_name'] ?? 'Warung Makan';
  String get storeAddress => _settings['store_address'] ?? '';
  String get storePhone => _settings['store_phone'] ?? '';
  String get receiptHeader => _settings['receipt_header'] ?? '';
  String get receiptFooter => _settings['receipt_footer'] ?? '';
  String get logoUrl => _settings['logo_url'] ?? '';
  bool get taxEnabled =>
      _settings['tax_enabled'] == 'true' || _settings['tax_enabled'] == true;
  double get taxPercent =>
      double.tryParse(_settings['tax_percent']?.toString() ?? '10') ?? 10.0;
  bool get serviceChargeEnabled =>
      _settings['service_charge_enabled'] == 'true' ||
          _settings['service_charge_enabled'] == true;
  double get serviceChargeAmount =>
      double.tryParse(
          _settings['service_charge_amount']?.toString() ?? '1000') ??
          1000.0;
  bool get isDarkMode => _settings['dark_mode'] == '1';
  String get receiptWidth => _settings['receipt_width'] ?? '58';
  String get currencySymbol => _settings['currency_symbol'] ?? 'Rp';
  String? get logoPath => _settings['logo_path'];

  // ── Effective getters: branch override global jika ada ───────────────────
  /// Nama yang tampil di header struk (per cabang)
  String get effectiveStoreName => _branchStrukNama?.isNotEmpty == true
      ? _branchStrukNama!
      : (_branding.scope?.branchId.isNotEmpty == true &&
          _branding.snapshot == null && _activeBranchName.isNotEmpty)
          ? _activeBranchName : storeName;

  /// Alamat di struk (per cabang)
  String get effectiveStoreAddress => _branchStrukAlamat?.isNotEmpty == true
      ? _branchStrukAlamat!
      : storeAddress;

  /// Telepon di struk (per cabang)
  String get effectiveStorePhone => _branchStrukTelp?.isNotEmpty == true
      ? _branchStrukTelp!
      : storePhone;

  /// Footer struk (per cabang)
  String get effectiveReceiptFooter => _branchStrukFooter?.isNotEmpty == true
      ? _branchStrukFooter!
      : receiptFooter;

  /// Logo URL (per cabang override logo global)
  String get effectiveLogoUrl => _branding.effectiveLogo(logoUrl);

  // ── Branch discount getters ───────────────────────────────────────────────
  bool get branchDiskonEnabled => _branchDiskonEnabled && _isBranchDiskonValid;
  String get branchDiskonLabel => _branchDiskonLabel;
  String get branchDiskonTipe => _branchDiskonTipe;
  double get branchDiskonNilai => _branchDiskonNilai;
  int get branchRounding => _branchRounding;

  bool get _isBranchDiskonValid {
    if (!_branchDiskonEnabled) return false;
    final now = DateTime.now();
    if (_branchDiskonDari != null && now.isBefore(_branchDiskonDari!))
      return false;
    if (_branchDiskonSampai != null &&
        now.isAfter(_branchDiskonSampai!.add(const Duration(days: 1))))
      return false;
    return true;
  }

  // ── Load settings per email ───────────────────────────────────────────────
  final _settingsReads = ReadFlights<void>();
  final _branchReads = ReadFlights<void>();
  Future<void> loadSettings({bool localOnly = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_prepareScope(prefs)) return;
    final key = '$_identityKey:$_identityRevision:$localOnly';
    return _settingsReads.run(key, () => _loadForEmail(_currentEmail, localOnly: localOnly));
  }
  Future<void> reloadForCurrentUser() => loadSettings();

  Future<void> _loadForEmail(String email, {bool localOnly = false}) async {
    final ticket = ++_loadEpoch;
    final identity = _identityKey;
    final scopePrefs = await SharedPreferences.getInstance();
    if (!_current(ticket, identity, scopePrefs)) return;
    final db = await DatabaseHelper.instance.database;
    List<Map<String, dynamic>> rows;

    if (email.isNotEmpty) {
      rows = await db.rawQuery(
        'SELECT key, value, email FROM settings WHERE email = ? OR email IS NULL OR email = ""',
        [email],
      );
      if (!_current(ticket, identity, scopePrefs)) return;
      final globalMap = <String, String>{};
      final userMap = <String, String>{};
      for (final r in rows) {
        final key = r['key'] as String;
        final val = r['value'] as String? ?? '';
        final rowEmail = r['email'] as String? ?? '';
        if (rowEmail == email) {
          userMap[key] = val;
        } else {
          globalMap[key] = val;
        }
      }
      _settings = {...globalMap, ...userMap};
    } else {
      rows = await db.rawQuery(
        'SELECT key, value, email FROM settings WHERE email IS NULL OR email = ""',
      );
      if (!_current(ticket, identity, scopePrefs)) return;
      _settings = {
        for (var r in rows) r['key'] as String: r['value'] as String? ?? ''
      };
    }

    if (!_current(ticket, identity, scopePrefs)) return;
    final cachePrefs = await SharedPreferences.getInstance();
    if (!_current(ticket, identity, scopePrefs)) return;
    // Legacy unscoped logos cannot establish an owner/branch identity.
    _settings.remove('logo_url');
    final cacheKey = 'startup_settings_v2:$identity';
    if (!_current(ticket, identity, scopePrefs)) return;
    final saved = cachePrefs.getString(cacheKey);
    if (saved != null) {
      try { _settings.addAll(Map<String, String>.from(jsonDecode(saved) as Map)); } catch (_) {}
    }
    _restoreBranchBranding(cachePrefs);
    _loaded = true;
    notifyListeners();
    if (localOnly) return;

    // Fetch global settings dari Supabase owners
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_current(ticket, identity, scopePrefs)) return;
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      // The verified profile already supplies owner_id; do not resolve another
      // owner by email or reuse another account's owner settings.
      final resolvedOwnerId = ownerId;
      if (resolvedOwnerId.isNotEmpty) {
        final res = await SupabaseConfig.client
            .rpc('get_owner_settings', params: {'p_owner_id': resolvedOwnerId});
        if (!_current(ticket, identity, scopePrefs)) return;
        if (res != null && res is Map) {
          if ((res['business_name'] as String?)?.isNotEmpty == true)
            _settings['store_name'] = res['business_name'] as String;
          if ((res['address'] as String?)?.isNotEmpty == true)
            _settings['store_address'] = res['address'] as String;
          if ((res['phone'] as String?)?.isNotEmpty == true)
            _settings['store_phone'] = res['phone'] as String;
          _settings['logo_url'] = res['logo_url'] is String ? (res['logo_url'] as String).trim() : '';
          _settings['tax_enabled'] =
          (res['tax_enabled'] == true || res['tax_enabled'] == 'true')
              ? 'true'
              : 'false';
          _settings['tax_percent'] = (res['tax_percent'] ?? 10).toString();
          _settings['service_charge_enabled'] = (res['service_charge_enabled'] ==
              true ||
              res['service_charge_enabled'] == 'true')
              ? 'true'
              : 'false';
          _settings['service_charge_amount'] =
              (res['service_charge_amount'] ?? 1000).toString();
        }
      }
      ServiceHealth.instance.record('settings', null);
    } catch (e) { ServiceHealth.log('settings',1,0,failureKind(e));
    }

    if (!_current(ticket, identity, scopePrefs)) return;
    // ── Load branch-specific settings (override global) ───────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      if (!_current(ticket, identity, scopePrefs)) return;
      if (branchId.isNotEmpty) {
        await _loadBranchSettings(branchId);
      }
    } catch (e) {
    }

    if (!_current(ticket, identity, scopePrefs)) return;
    await cachePrefs.setString(cacheKey, jsonEncode(_settings));
    if (!_current(ticket, identity, scopePrefs)) return;
    _loaded = true;
    notifyListeners();
  }

  /// Load/reload setting cabang tertentu (dipanggil saat ganti cabang)
  Future<void> loadBranchSettings(String branchId) async {
    await _loadBranchSettings(branchId);
    if (!_disposed) notifyListeners();
  }

  Future<void> _loadBranchSettings(String branchId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_prepareScope(prefs) || branchId != prefs.getString(AppConstants.keyBranchId)) return;
    _restoreBranchBranding(prefs);
    final scope = _branding.scope;
    if (scope == null || !scope.hasIdentity || branchId.isEmpty) return;
    final ticket = _branding.ticket;
    final identity = _identityKey;
    return _branchReads.run('$identity:$_identityRevision',
      () => _readBranchSettings(branchId, scope, ticket, identity));
  }
  Future<void> _readBranchSettings(String branchId, ReceiptBrandingScope scope,
      int ticket, String identity) async {
    try {
      final branchReader = _branchReader;
      final res = branchReader != null ? await branchReader(branchId) :
          await SupabaseConfig.client.rpc('get_branch_print_settings_by_id',
            params: {'p_branch_id': branchId});
      if (res is! Map || _disposed || !res.containsKey('logo_url') ||
          BranchReceiptSnapshot.keys.any((key) => res[key] != null && res[key] is! String)) return;
      final latestPrefs = await SharedPreferences.getInstance();
      if (identity != _identityKey || identity != _keyFor(latestPrefs) ||
          !_authMatches(latestPrefs)) return;
      final snapshot = BranchReceiptSnapshot(scope, res);
      if (!_branding.accept(ticket, snapshot)) return;
      _applyBranding(snapshot);
      await latestPrefs.setString(scope.cacheKey, snapshot.encode());
      if (identity != _identityKey || identity != _keyFor(latestPrefs) ||
          ticket != _branding.ticket || !_authMatches(latestPrefs)) return;

      // PPN & SC per cabang override global (kalau beda)
      final ppnEnabled = res['ppn_enabled'] as bool? ?? false;
      final ppnPersen = (res['ppn_persen'] as num?)?.toDouble() ?? 0;
      final scEnabled = res['sc_enabled'] as bool? ?? false;
      final scAmount = (res['sc_amount'] as num?)?.toDouble() ?? 0;
      if (ppnPersen > 0 || ppnEnabled) {
        _settings['tax_enabled'] = ppnEnabled ? 'true' : 'false';
        _settings['tax_percent'] = ppnPersen.toString();
      }
      if (scAmount > 0 || scEnabled) {
        _settings['service_charge_enabled'] = scEnabled ? 'true' : 'false';
        _settings['service_charge_amount'] = scAmount.toString();
      }

      // Rounding
      _branchRounding = (res['rounding'] as num?)?.toInt() ?? 0;

      // Diskon spesial
      _branchDiskonEnabled = res['diskon_enabled'] as bool? ?? false;
      _branchDiskonLabel = res['diskon_label'] as String? ?? 'Diskon';
      _branchDiskonTipe = res['diskon_tipe'] as String? ?? 'persen';
      _branchDiskonNilai = (res['diskon_nilai'] as num?)?.toDouble() ?? 0;
      _branchDiskonDari = _parseDate(res['diskon_berlaku_dari'] as String?);
      _branchDiskonSampai = _parseDate(res['diskon_berlaku_sampai'] as String?);
    } catch (e) {
    }
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
    final db = await DatabaseHelper.instance.database;
    if (_currentEmail.isNotEmpty) {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (key, value, email) VALUES (?, ?, ?)',
        [key, value, _currentEmail],
      );
    } else {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
        [key, value],
      );
    }
    notifyListeners();
  }

  Future<void> saveAll(Map<String, String> values) async {
    for (final entry in values.entries) {
      await setSetting(entry.key, entry.value);
    }
  }

  Future<void> toggleDarkMode() async =>
      setSetting('dark_mode', isDarkMode ? '0' : '1');
  Future<void> toggleTax() async =>
      setSetting('tax_enabled', taxEnabled ? '0' : '1');
  Future<void> toggleServiceCharge() async =>
      setSetting('service_charge_enabled', serviceChargeEnabled ? '0' : '1');

  Future<String?> backupDatabase() async {
    try {
      final dbPath = await DatabaseHelper.instance.getDatabasePath();
      final extDir = await getExternalStorageDirectory();
      if (extDir == null) return null;
      final backupDir = Directory(p.join(extDir.path, 'POSBackup'));
      if (!await backupDir.exists()) await backupDir.create(recursive: true);
      final now = DateTime.now();
      final fileName =
          'pos_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.db';
      final destPath = p.join(backupDir.path, fileName);
      await File(dbPath).copy(destPath);
      return destPath;
    } catch (e) {
      return null;
    }
  }

  Future<bool> restoreDatabase(String filePath) async {
    try {
      final dbPath = await DatabaseHelper.instance.getDatabasePath();
      await File(filePath).copy(dbPath);
      await loadSettings();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> saveSettings(Map<String, String> values) => saveAll(values);
  Future<void> saveSetting(String key, String value) => setSetting(key, value);
}
