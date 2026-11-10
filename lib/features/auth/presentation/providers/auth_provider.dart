import '../../../../core/services/pin_secret.dart';
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

  Future<void>? _sessionCheck;
  int _sessionEpoch = 0;
  Future<void> checkSession() => _sessionCheck ??= _checkSession().whenComplete(() => _sessionCheck = null);
  Future<void> _checkSession() async {
    final ticket = ++_sessionEpoch;
    _loading = true;
    notifyListeners();
    try {
      final profile = await SupabaseAuthService.instance.getSession();
      if (ticket == _sessionEpoch) _currentUser = profile;
    } finally {
      if (ticket == _sessionEpoch) { _loading = false; notifyListeners(); }
    }
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
    _sessionEpoch++;
    await SupabaseAuthService.instance.logout();
    _currentUser = null;
    notifyListeners();
  }

  Future<void> savePin(String pin) async {
    final user = _currentUser;
    if (user == null || user.email.isEmpty) throw StateError('Login diperlukan');
    final pinHash = await PinSecret.create(pin);
    final result = await SupabaseConfig.client.rpc('set_user_pin', params: {
      'p_email': user.email, 'p_pin_hash': pinHash,
    }).timeout(const Duration(seconds: 8));
    if (result is! Map || result['success'] != true) throw StateError('PIN belum tersimpan di server');
    if (SupabaseConfig.client.auth.currentUser?.id != user.authId) throw StateError('Akun telah berubah');
    await SupabaseAuthService.instance.recordAcceptedPin(user.authId, pinHash);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sb_pin_hash', pinHash);
    await prefs.setString('sb_pin_email', user.email);
    await DatabaseHelper.instance.update('users', {'pin_hash': pinHash}, 'email = ?', [user.email]);
    _currentUser = AppUserProfile(authId: user.authId, email: user.email, name: user.name,
      role: user.role, ownerId: user.ownerId, branchId: user.branchId,
      branchName: user.branchName, branchMode: user.branchMode, pin: pinHash);
    notifyListeners();
  }

  Future<bool> verifyPin(String pin) async {
    if (pin.isEmpty) return false;
    final verifiedHash = _currentUser?.pin;
    if (verifiedHash != null && verifiedHash.isNotEmpty) {
      return PinSecret.verify(pin, verifiedHash);
    }

    String uid = _currentUser?.authId ?? '';
    String email = _currentUser?.email ?? '';

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
        ).timeout(const Duration(seconds: 6));

        if (rpcRes != null && rpcRes is Map) {
          // RPC hanya mengembalikan pin_hash (tidak pernah PIN plaintext)
          final storedHash = rpcRes['pin_hash']?.toString() ?? '';
          if (storedHash.isNotEmpty &&
              await PinSecret.verify(pin, storedHash)) {
            return true;
          }
        }
      }
    } catch (e) {}

    // 2. Check SQLite local (offline fallback)
    try {
      final where = email.isNotEmpty ? 'email = ?' : 'auth_id = ?';
      final args = [email.isNotEmpty ? email : uid];
      final users = await DatabaseHelper.instance.query(
          'users', where: where, whereArgs: args);

      if (users.isNotEmpty) {
        // Hanya cek pin_hash — tidak pernah compare plaintext
        final localHash = users.first['pin_hash']?.toString() ?? '';
        if (localHash.isNotEmpty && await PinSecret.verify(pin, localHash)) {
          return true;
        }
      }
    } catch (e) {}

    // 3. Check SharedPrefs backup — nilai yang tersimpan adalah HASH
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHash = prefs.getString('sb_pin_hash') ?? '';
      // Bandingkan hash(input) dengan hash tersimpan
      if (prefs.getString('sb_pin_email') == email && savedHash.isNotEmpty && await PinSecret.verify(pin, savedHash)) {
        return true;
      }
    } catch (e) {}

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
          return res.map((r) => UserModel.fromMap(r)).toList();
        }
      } catch (_) {}

      // Fallback: pakai RPC SECURITY DEFINER
      final rpcRes = await SupabaseConfig.client.rpc(
          'get_owner_users', params: {'p_owner_id': ownerId});
      if (rpcRes is List) {
        return rpcRes.map((r) => UserModel.fromMap(r as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> addUser(String name, String pin, String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
      // FIX: simpan pin_hash bukan plaintext
      final pinHash = pin.isNotEmpty ? await PinSecret.create(pin) : null;
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
      return false;
    }
  }

  Future<bool> updateUser(String id, String name, String pin,
      String role) async {
    try {
      // FIX: simpan pin_hash bukan plaintext
      final pinHash = pin.isNotEmpty ? await PinSecret.create(pin) : null;
      await SupabaseConfig.client.from('users').update({
        'name': name,
        'role': role,
        if (pinHash != null) 'pin_hash': pinHash,
      }).eq('id', id);
      return true;
    } catch (e) {
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
