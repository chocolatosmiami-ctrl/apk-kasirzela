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

  // ── Branch-level overrides (dari kolom branches di Supabase) ──────────────
  String? _branchStrukNama;
  String? _branchStrukAlamat;
  String? _branchStrukTelp;
  String? _branchStrukFooter;
  String? _branchLogoUrl;
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
      : storeName;

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
  String get effectiveLogoUrl =>
      _branchLogoUrl?.isNotEmpty == true ? _branchLogoUrl! : logoUrl;

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
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _currentEmail = prefs.getString(AppConstants.keyEmail) ?? '';
    await _loadForEmail(_currentEmail);
  }

  Future<void> reloadForCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(AppConstants.keyEmail) ?? '';
    if (email != _currentEmail) {
      _currentEmail = email;
      await _loadForEmail(_currentEmail);
    }
  }

  Future<void> _loadForEmail(String email) async {
    final db = await DatabaseHelper.instance.database;
    List<Map<String, dynamic>> rows;

    if (email.isNotEmpty) {
      rows = await db.rawQuery(
        'SELECT key, value, email FROM settings WHERE email = ? OR email IS NULL OR email = ""',
        [email],
      );
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
      _settings = {
        for (var r in rows) r['key'] as String: r['value'] as String? ?? ''
      };
    }

    // Fetch global settings dari Supabase owners
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final authId = prefs.getString(AppConstants.keyUid) ?? '';
      final emailPref = prefs.getString(AppConstants.keyEmail) ?? '';
      final role = prefs.getString(AppConstants.keyRole) ?? '';
      debugPrint(
          '🔧 [Settings] fetchSupabase ownerId=$ownerId authId=$authId email=$emailPref role=$role');

      String resolvedOwnerId = ownerId;
      if (resolvedOwnerId.isNotEmpty) {
        final checkOwner = await SupabaseConfig.client
            .from('owners')
            .select('id')
            .eq('id', resolvedOwnerId)
            .maybeSingle();
        if (checkOwner == null && emailPref.isNotEmpty) {
          debugPrint(
              '🔧 [Settings] ownerId not in owners table, lookup via users email=$emailPref');
          final userRow = await SupabaseConfig.client
              .from('users')
              .select('owner_id')
              .eq('email', emailPref)
              .maybeSingle();
          resolvedOwnerId =
              userRow?['owner_id']?.toString() ?? resolvedOwnerId;
          debugPrint('🔧 [Settings] resolved ownerId=$resolvedOwnerId');
        }
      }

      if (resolvedOwnerId.isNotEmpty) {
        final res = await SupabaseConfig.client
            .rpc('get_owner_settings', params: {'p_owner_id': resolvedOwnerId});
        debugPrint(
            '🔧 [Settings] owners RPC result: ${res?.toString() ?? 'NULL'}');
        if (res != null && res is Map) {
          if ((res['business_name'] as String?)?.isNotEmpty == true)
            _settings['store_name'] = res['business_name'] as String;
          if ((res['address'] as String?)?.isNotEmpty == true)
            _settings['store_address'] = res['address'] as String;
          if ((res['phone'] as String?)?.isNotEmpty == true)
            _settings['store_phone'] = res['phone'] as String;
          if ((res['logo_url'] as String?)?.isNotEmpty == true)
            _settings['logo_url'] = res['logo_url'] as String;
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
          debugPrint('✅ [Settings] store_name=${_settings['store_name']}');
          debugPrint(
              '✅ [Settings] tax=$taxEnabled taxPct=$taxPercent sc=$serviceChargeEnabled scAmt=$serviceChargeAmount');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Settings] Supabase owners fetch error: $e');
    }

    // ── Load branch-specific settings (override global) ───────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      if (branchId.isNotEmpty) {
        await _loadBranchSettings(branchId);
      }
    } catch (e) {
      debugPrint('⚠️ [Settings] branch settings load error: $e');
    }

    _loaded = true;
    notifyListeners();
  }

  /// Load/reload setting cabang tertentu (dipanggil saat ganti cabang)
  Future<void> loadBranchSettings(String branchId) async {
    await _loadBranchSettings(branchId);
    notifyListeners();
  }

  Future<void> _loadBranchSettings(String branchId) async {
    try {
      debugPrint('🏪 [Settings] load branch settings branchId=$branchId');
      final res = await SupabaseConfig.client.rpc(
        'get_branch_print_settings_by_id',
        params: {'p_branch_id': branchId},
      );
      debugPrint('🏪 [Settings] branch RPC result: ${res?.toString() ?? 'NULL'}');
      if (res == null || res is! Map) return;

      _branchStrukNama = res['struk_nama'] as String?;
      _branchStrukAlamat = res['struk_alamat'] as String?;
      _branchStrukTelp = res['struk_telp'] as String?;
      _branchStrukFooter = res['struk_footer'] as String?;
      _branchLogoUrl = res['logo_url'] as String?;

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

      debugPrint(
          '✅ [Settings] branch override: nama=$_branchStrukNama rounding=$_branchRounding diskon=$_branchDiskonEnabled(${_branchDiskonNilai}${_branchDiskonTipe == 'persen' ? '%' : 'Rp'})');
    } catch (e) {
      debugPrint('⚠️ [Settings] _loadBranchSettings error: $e');
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