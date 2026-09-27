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
  String _currentEmail = ''; // email user yang sedang login

  bool get loaded => _loaded;
  bool get isLoaded => _loaded;
  String get storeName => _settings['store_name'] ?? 'Warung Makan';
  String get storeAddress => _settings['store_address'] ?? '';
  String get storePhone => _settings['store_phone'] ?? '';
  String get receiptHeader => _settings['receipt_header'] ?? '';
  String get receiptFooter => _settings['receipt_footer'] ?? '';
  String get logoUrl => _settings['logo_url'] ?? '';
  bool get taxEnabled => _settings['tax_enabled'] == 'true' || _settings['tax_enabled'] == true;
  double get taxPercent => double.tryParse(_settings['tax_percent']?.toString() ?? '10') ?? 10.0;
  bool get serviceChargeEnabled => _settings['service_charge_enabled'] == 'true' || _settings['service_charge_enabled'] == true;
  double get serviceChargeAmount => double.tryParse(_settings['service_charge_amount']?.toString() ?? '1000') ?? 1000.0;

  bool get isDarkMode => _settings['dark_mode'] == '1';
  String get receiptWidth => _settings['receipt_width'] ?? '58';
  String get currencySymbol => _settings['currency_symbol'] ?? 'Rp';
  String? get logoPath => _settings['logo_path'];

  // ── Load settings per email user yang login ──────────
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _currentEmail = prefs.getString(AppConstants.keyEmail) ?? '';
    await _loadForEmail(_currentEmail);
  }

  // Dipanggil setelah login berhasil dengan email baru
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
      // Load settings milik email ini
      rows = await db.rawQuery(
        'SELECT key, value, email FROM settings WHERE email = ? OR email IS NULL OR email = ""',
        [email],
      );
      // Prioritaskan: jika ada key yang sama, pakai yang punya email
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
      _settings = {...globalMap, ...userMap}; // user settings override global
    } else {
      // Belum login — load global settings saja
      rows = await db.rawQuery(
        'SELECT key, value, email FROM settings WHERE email IS NULL OR email = ""',
      );
      _settings = {for (var r in rows) r['key'] as String: r['value'] as String? ?? ''};
    }

    // Fetch dari Supabase owners - override store info
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId  = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final authId   = prefs.getString(AppConstants.keyUid) ?? '';
      final email    = prefs.getString(AppConstants.keyEmail) ?? '';
      final role     = prefs.getString(AppConstants.keyRole) ?? '';
      debugPrint('🔧 [Settings] fetchSupabase ownerId=' + ownerId + ' authId=' + authId + ' email=' + email + ' role=' + role);

      // Kalau ownerId kosong atau tidak ketemu, coba lookup dari users table by email
      String resolvedOwnerId = ownerId;
      // Kalau ownerId tidak ketemu di owners, lookup via users table
      if (resolvedOwnerId.isNotEmpty) {
        final checkOwner = await SupabaseConfig.client
            .from('owners').select('id').eq('id', resolvedOwnerId).maybeSingle();
        if (checkOwner == null && email.isNotEmpty) {
          debugPrint('🔧 [Settings] ownerId not in owners table, lookup via users email=' + email);
          final userRow = await SupabaseConfig.client
              .from('users').select('owner_id').eq('email', email).maybeSingle();
          resolvedOwnerId = userRow?['owner_id']?.toString() ?? resolvedOwnerId;
          debugPrint('🔧 [Settings] resolved ownerId=' + resolvedOwnerId);
        }
      }

      if (resolvedOwnerId.isNotEmpty) {
        // Pakai RPC SECURITY DEFINER agar anon key bisa akses tabel owners
        final res = await SupabaseConfig.client
            .rpc('get_owner_settings', params: {'p_owner_id': resolvedOwnerId});
        debugPrint('🔧 [Settings] owners RPC result: ' + (res?.toString() ?? 'NULL'));
        if (res != null && res is Map) {
          if ((res['business_name'] as String?)?.isNotEmpty == true) {
            _settings['store_name'] = res['business_name'] as String;
          }
          if ((res['address'] as String?)?.isNotEmpty == true) {
            _settings['store_address'] = res['address'] as String;
          }
          if ((res['phone'] as String?)?.isNotEmpty == true) {
            _settings['store_phone'] = res['phone'] as String;
          }
          if ((res['logo_url'] as String?)?.isNotEmpty == true) {
            _settings['logo_url'] = res['logo_url'] as String;
          }
          _settings['tax_enabled'] = (res['tax_enabled'] == true || res['tax_enabled'] == 'true') ? 'true' : 'false';
          _settings['tax_percent'] = (res['tax_percent'] ?? 10).toString();
          _settings['service_charge_enabled'] = (res['service_charge_enabled'] == true || res['service_charge_enabled'] == 'true') ? 'true' : 'false';
          _settings['service_charge_amount'] = (res['service_charge_amount'] ?? 1000).toString();
          debugPrint('✅ [Settings] store_name=' + (_settings['store_name'] ?? ''));
          debugPrint('✅ [Settings] tax=' + taxEnabled.toString() + ' taxPct=' + taxPercent.toString());
          debugPrint('✅ [Settings] sc=' + serviceChargeEnabled.toString() + ' scAmt=' + serviceChargeAmount.toString());
          debugPrint('✅ [Settings] raw sc_enabled=' + (res['service_charge_enabled']?.toString() ?? 'null') + ' sc_amount=' + (res['service_charge_amount']?.toString() ?? 'null'));
        } else {
          debugPrint('⚠️ [Settings] RPC returned NULL');
        }
      } else {
        debugPrint('⚠️ [Settings] ownerId kosong - skip Supabase fetch');
      }
    } catch (e) {
      debugPrint('⚠️ [Settings] Supabase owners fetch error: ' + e.toString());
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
    final db = await DatabaseHelper.instance.database;
    // Simpan per email jika ada user login
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

  Future<void> toggleDarkMode() async {
    await setSetting('dark_mode', isDarkMode ? '0' : '1');
  }

  Future<void> toggleTax() async {
    await setSetting('tax_enabled', taxEnabled ? '0' : '1');
  }

  Future<void> toggleServiceCharge() async {
    await setSetting('service_charge_enabled', serviceChargeEnabled ? '0' : '1');
  }

  // Backup database to external storage
  Future<String?> backupDatabase() async {
    try {
      final dbPath = await DatabaseHelper.instance.getDatabasePath();
      final extDir = await getExternalStorageDirectory();
      if (extDir == null) return null;

      final backupDir = Directory(p.join(extDir.path, 'POSBackup'));
      if (!await backupDir.exists()) await backupDir.create(recursive: true);

      final now = DateTime.now();
      final fileName = 'pos_backup_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}.db';
      final destPath = p.join(backupDir.path, fileName);

      await File(dbPath).copy(destPath);
      return destPath;
    } catch (e) {
      return null;
    }
  }

  // Restore database from file
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

  // Aliases for convenience
  Future<void> saveSettings(Map<String, String> values) => saveAll(values);
  Future<void> saveSetting(String key, String value) => setSetting(key, value);
}