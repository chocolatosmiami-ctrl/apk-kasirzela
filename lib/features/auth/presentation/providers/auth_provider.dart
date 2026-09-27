import '../../../../core/utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/supabase_auth_service.dart';
import '../../data/models/user_model.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/database/database_helper.dart';

class AuthProvider extends ChangeNotifier {
  AppUserProfile? _currentUser;
  bool _loading = true;

  AppUserProfile? get currentUser => _currentUser;
  bool get loading => _loading;
  bool get isLoggedIn => _currentUser != null;

  bool get isSuperAdmin => _currentUser?.isSuperAdmin ?? false;
  bool get isOwner => _currentUser?.isOwner ?? false;
  bool get isOwnerLevel => _currentUser?.isOwnerLevel ?? false;
  bool get isManajer => _currentUser?.isManajer ?? false;
  bool get isKasir => _currentUser?.isKasir ?? false;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  String get userName => _currentUser?.name ?? '';
  String get userRole => _currentUser?.role ?? '';
  String get branchName => _currentUser?.branchName ?? '';
  String get branchMode => _currentUser?.branchMode ?? 'food';
  bool get isRetailMode => branchMode == 'retail';

  Future<void> checkSession() async {
    _loading = true;
    notifyListeners();
    debugPrint('🔑 [AuthProvider] checkSession START');
    _currentUser = await SupabaseAuthService.instance.getSession();
    debugPrint('🔑 [AuthProvider] checkSession result: ${_currentUser?.name ?? "NULL"} / role: ${_currentUser?.role ?? "NULL"}');
    _loading = false;
    notifyListeners();
  }

  // login called
  Future<AuthResult> login({
    required String email, required String password}) async {
    final result = await SupabaseAuthService.instance.login(
        email: email, password: password);
    if (result.success) {
      _currentUser = await SupabaseAuthService.instance.getSession();
      notifyListeners();
    }
    return result;
  }

  Future<AuthResult> register({
    required String name, required String email,
    required String password, required String businessName}) async {
    final result = await SupabaseAuthService.instance.registerOwner(
      name: name, email: email,
      password: password, businessName: businessName,
    );
    if (result.success) {
      _currentUser = await SupabaseAuthService.instance.getSession();
      notifyListeners();
    }
    return result;
  }

  Future<void> logout() async {
    await SupabaseAuthService.instance.logout();
    _currentUser = null;
    notifyListeners();
  }

  Future<void> savePin(String pin) async {
    // Simpan HASH bukan plaintext
    final pinHash = DatabaseHelper.hashPin(pin);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sb_pin_hash', pinHash);
    // Kirim hash ke Supabase via RPC
    try {
      final email = _currentUser?.email ?? '';
      if (email.isNotEmpty) {
        await SupabaseConfig.client.rpc('set_user_pin', params: {
          'p_email': email,
          'p_pin_hash': pinHash,
        });
      }
    } catch (e) {
      debugPrint('savePin error: $e');
    }
  }

  Future<bool> verifyPin(String pin) async {
    if (pin.isEmpty) return false;

    String uid = _currentUser?.authId ?? '';
    String email = _currentUser?.email ?? '';
    debugPrint('🔐 [verifyPin] START uid=$uid email=$email pin_len=${pin.length}');

    // If _currentUser is null OR uid empty, get fresh session
    if (_currentUser == null || uid.isEmpty) {
      try {
        final session = await SupabaseAuthService.instance.getSession();
        uid = session?.authId ?? '';
        email = session?.email ?? '';
        // Also set _currentUser so next calls work
        if (session != null) {
          _currentUser = session;
          notifyListeners();
        }
      } catch (_) {}
    }

    // 1. Check Supabase via RPC SECURITY DEFINER (tidak butuh service key)
    try {
      if (uid.isNotEmpty || email.isNotEmpty) {
        // RPC get_user_pin_hash dipanggil dengan anon key;
        // function di Supabase harus dibuat sebagai SECURITY DEFINER.
        final rpcRes = await SupabaseConfig.client.rpc(
          'get_user_pin_hash',
          params: {
            'p_auth_id': uid.isNotEmpty ? uid : null,
            'p_email': email.isNotEmpty ? email : null,
          },
        );

        if (rpcRes != null && rpcRes is Map) {
          // RPC hanya mengembalikan pin_hash (tidak pernah PIN plaintext)
          final storedHash = rpcRes['pin_hash']?.toString() ?? '';
          if (storedHash.isNotEmpty &&
              storedHash == DatabaseHelper.hashPin(pin)) {
            debugPrint('🔐 [verifyPin] ✅ matched RPC hash');
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('verifyPin Supabase error: $e');
    }

    // 2. Check SQLite local (offline fallback)
    try {
      final where = email.isNotEmpty ? 'email = ?' : 'auth_id = ?';
      final args = [email.isNotEmpty ? email : uid];
      final users = await DatabaseHelper.instance.query(
          'users', where: where, whereArgs: args);

      if (users.isNotEmpty) {
        // Hanya cek pin_hash — tidak pernah compare plaintext
        final localHash = users.first['pin_hash']?.toString() ?? '';
        debugPrint('🔐 [verifyPin] SQLite hash: ${localHash.isEmpty ? "EMPTY" : "SET"}');
        if (localHash.isNotEmpty && localHash == DatabaseHelper.hashPin(pin)) {
          debugPrint('🔐 [verifyPin] ✅ matched SQLite hash');
          return true;
        }
      }
    } catch (e) {
      debugPrint('verifyPin SQLite error: $e');
    }

    // 3. Check SharedPrefs backup — nilai yang tersimpan adalah HASH
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHash = prefs.getString('sb_pin_hash') ?? '';
      debugPrint('🔐 [verifyPin] SharedPrefs hash: ${savedHash.isEmpty ? "EMPTY" : "SET"}');
      // Bandingkan hash(input) dengan hash tersimpan
      if (savedHash.isNotEmpty && savedHash == DatabaseHelper.hashPin(pin)) {
        debugPrint('🔐 [verifyPin] ✅ matched SharedPrefs hash');
        return true;
      }
    } catch (e) {
      debugPrint('verifyPin SharedPrefs error: $e');
    }

    debugPrint('verifyPin: ❌ all checks failed');
    return false;
  }

  // BUG 8 FIX: Cek apakah PIN hash benar-benar tersimpan, bukan hanya cek login.
  bool get hasPinSetup {
    // Pengecekan sync dari _currentUser — pin di-load saat getSession()
    if (_currentUser == null) return false;
    final pin = _currentUser!.pin;
    return pin != null && pin.isNotEmpty;
  }

  // ── User management ──────────────────────────────────
  Future<List<UserModel>> getUsers() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final role    = prefs.getString(AppConstants.keyRole) ?? '';

      if (ownerId.isEmpty) return [];

      // Coba direct query dulu (owner punya Auth session)
      try {
        final res = await SupabaseConfig.client
            .from('users')
            .select()
            .eq('owner_id', ownerId)
            .neq('role', 'superadmin')
            .order('name');
        if ((res as List).isNotEmpty) {
          debugPrint('✅ [getUsers] ${res.length} users via direct query');
          return res.map((r) => UserModel.fromMap(r)).toList();
        }
      } catch (_) {}

      // Fallback: pakai RPC SECURITY DEFINER
      final rpcRes = await SupabaseConfig.client.rpc(
        'get_owner_users', params: {'p_owner_id': ownerId});
      if (rpcRes is List) {
        debugPrint('✅ [getUsers] ${rpcRes.length} users via RPC');
        return rpcRes.map((r) => UserModel.fromMap(r as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('getUsers error: $e');
      return [];
    }
  }

  Future<bool> addUser(String name, String pin, String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      // FIX: simpan pin_hash bukan plaintext
      final pinHash = pin.isNotEmpty ? DatabaseHelper.hashPin(pin) : null;
      await SupabaseConfig.client.from('users').insert({
        'owner_id': ownerId,
        'branch_id': branchId.isEmpty ? null : branchId,
        'name': name,
        'email': name.toLowerCase().replaceAll(' ', '.') + '@staff.local',
        'role': role,
        if (pinHash != null) 'pin_hash': pinHash,
        'is_active': true,
      });
      return true;
    } catch (e) {
      debugPrint('addUser error: $e');
      return false;
    }
  }

  Future<bool> updateUser(String id, String name, String pin,
      String role) async {
    try {
      // FIX: simpan pin_hash bukan plaintext
      final pinHash = pin.isNotEmpty ? DatabaseHelper.hashPin(pin) : null;
      await SupabaseConfig.client.from('users').update({
        'name': name,
        'role': role,
        if (pinHash != null) 'pin_hash': pinHash,
      }).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('updateUser error: $e');
      return false;
    }
  }

  Future<bool> deleteUser(String id) async {
    try {
      await SupabaseConfig.client.from('users')
          .update({'is_active': false}).eq('id', id);
      return true;
    } catch (e) {
      return false;
    }
  }

  
}
