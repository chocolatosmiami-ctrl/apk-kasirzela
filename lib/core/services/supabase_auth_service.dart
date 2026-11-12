import 'dart:async';
import 'dart:convert';
import 'startup_policy.dart';
import 'service_health.dart';
import '../utils/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../database/database_helper.dart';
import 'login_route.dart';

/// User-visible errors are fixed text; never echo SDK exceptions or credentials.
String authenticationErrorMessage(Object error) {
  final kind = failureKind(error);
  if (kind == FailureKind.server) {
    return 'Layanan login sedang bermasalah. Coba lagi nanti. Kode: LOGIN_SERVICE';
  }
  if (kind == FailureKind.timeout || kind == FailureKind.network ||
      error is AuthRetryableFetchException) {
    return 'Server login belum merespons. Coba lagi nanti. '
        'Jika tetap gagal di beberapa jaringan, '
        'pengelola perlu memeriksa status layanan Auth. Kode: LOGIN_CONNECTION';
  }
  if (error is AuthException) {
    final code = error.code;
    if (code == 'invalid_credentials' ||
        error.message.contains('Invalid login credentials')) {
      return 'Email atau password salah';
    }
    if (code == 'email_not_confirmed' || error.message.contains('Email not confirmed')) {
      return 'Email belum dikonfirmasi. Cek inbox email Anda';
    }
    if (code == 'over_request_rate_limit' || error.statusCode == '429' ||
        error.message.contains('Too many requests')) {
      return 'Terlalu banyak percobaan. Tunggu beberapa saat';
    }
    if (code == 'user_already_exists' || error.message.contains('User already registered')) {
      return 'Email sudah terdaftar';
    }
    if (code == 'weak_password' || error.message.contains('weak password')) {
      return 'Password terlalu lemah';
    }
    if (code == 'staff_session_not_ready') {
      return 'Akun kasir belum dapat dihubungkan ke Auth. Hubungi owner. Kode: STAFF_AUTH_NOT_READY';
    }
  }
  if (kind == FailureKind.invalidSession) {
    return 'Sesi tidak berlaku. Login kembali dengan email dan password. Kode: LOGIN_SESSION';
  }
  if (kind == FailureKind.denied) {
    return 'Akun belum diizinkan mengakses layanan. Hubungi owner. Kode: LOGIN_ACCESS';
  }
  return 'Login belum berhasil. Coba lagi atau hubungi pengelola. Kode: LOGIN_UNKNOWN';
}

class SupabaseAuthService {
  static final SupabaseAuthService instance = SupabaseAuthService._();
  SupabaseAuthService._();

  SupabaseClient get _client => SupabaseConfig.client;
  SupabaseClient get client => SupabaseConfig.client;

  bool get hasActiveSession => _client.auth.currentSession != null;

  AppUserProfile? get currentUser => null;

  Future<AppUserProfile?>? _sessionRead;
  String _sessionReadUid = '';
  int _profileGeneration = 0;

  /// Supersede in-flight profile reads without deleting Auth or local receipts.
  void invalidateSessionRead() {
    _profileGeneration++;
    _sessionRead = null;
    _sessionReadUid = '';
  }

  /// Only call after the server accepted a PIN change. Preserve the original
  /// verification time and access fields; an offline fallback must not revive
  /// the previous PIN or extend cached authorization.
  Future<void> recordAcceptedPin(String uid, String pinHash) async {
    if (uid.isEmpty || _client.auth.currentUser?.id != uid) return;
    _profileGeneration++;
    _sessionRead = null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('verified_profile_$uid');
    if (raw == null) return;
    try {
      final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final row = Map<String, dynamic>.from(saved['row'] as Map);
      if (row['auth_id'] != uid || _client.auth.currentUser?.id != uid) return;
      row['pin_hash'] = pinHash;
      saved['row'] = row;
      await prefs.setString('verified_profile_$uid', jsonEncode(saved));
    } catch (_) {
      await prefs.remove('verified_profile_$uid');
    }
  }

  Future<AppUserProfile?> getSession() {
    final uid = _client.auth.currentUser?.id ?? '';
    if (_sessionRead != null && _sessionReadUid == uid) return _sessionRead!;
    _sessionReadUid = uid;
    final generation = ++_profileGeneration;
    final future = _readSession(uid, generation);
    _sessionRead = future;
    return future.whenComplete(() { if (generation == _profileGeneration) _sessionRead = null; });
  }

  AppUserProfile _profile(Map<String, dynamic> row, String uid) {
    final branch = row['branches'] as Map<String, dynamic>?;
    return AppUserProfile(authId: uid, email: row['email']?.toString() ?? '',
      name: row['name']?.toString() ?? '', role: row['role']?.toString() ?? 'kasir',
      ownerId: row['owner_id']?.toString() ?? '', branchId: row['branch_id']?.toString() ?? '',
      branchName: branch?['name']?.toString() ?? '', branchMode: branch?['mode']?.toString() ?? 'food',
      pin: row['pin_hash']?.toString());
  }

  Future<void> _storeProfileContext(AppUserProfile profile, bool Function() current) async {
    final prefs = await SharedPreferences.getInstance();
    final sameOwner = prefs.getString(AppConstants.keyUid) == profile.authId &&
        prefs.getString(AppConstants.keyOwnerId) == profile.ownerId;
    final selectedBranch = sameOwner && profile.branchId.isEmpty &&
        const {'owner', 'superadmin', 'manajer'}.contains(profile.role);
    final values = <String, String>{
      AppConstants.keyUid: profile.authId, AppConstants.keyEmail: profile.email,
      AppConstants.keyName: profile.name, AppConstants.keyRole: profile.role,
      AppConstants.keyOwnerId: profile.ownerId,
      if (!selectedBranch) ...{
        AppConstants.keyBranchId: profile.branchId, AppConstants.keyBranchName: profile.branchName,
        AppConstants.keyBranchMode: profile.branchMode,
      },
    };
    for (final entry in values.entries) {
      if (!current()) return;
      if (prefs.getString(entry.key) != entry.value) await prefs.setString(entry.key, entry.value);
    }
  }

  Future<AppUserProfile?> _readSession(String uid, int generation) async {
    if (uid.isEmpty) return null; // PIN/preferences cannot manufacture an Auth session.
    final watch = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    bool current() => generation == _profileGeneration && _client.auth.currentUser?.id == uid;
    try {
      // Initialization can restore an expired session before its background
      // refresh completes. Do not send that access token to the profile API.
      if (_client.auth.currentSession?.isExpired == true) {
        final response = await _client.auth.refreshSession()
            .timeout(LoginTimeouts.refresh);
        if (!current()) throw StateError('Superseded profile attempt');
        if (response.session == null) {
          throw const AuthException('Sign in required', code: 'session_not_found');
        }
      }
      final row = await _client.from('users')
        .select('auth_id,email,name,role,owner_id,branch_id,is_active,is_approved,pin_hash,branches(name,mode)')
        .eq('auth_id', uid).maybeSingle().timeout(LoginTimeouts.profileRead);
      if (!current()) throw StateError('Superseded profile attempt');
      if (row == null || row['is_active'] != true || row['is_approved'] != true) {
        await prefs.remove('verified_profile_$uid');
        ServiceHealth.instance.record('profile', FailureKind.denied);
        return null;
      }
      await prefs.setString('verified_profile_$uid', jsonEncode({
        'verified_at': DateTime.now().toUtc().toIso8601String(), 'row': row}));
      if (!current()) return null;
      ServiceHealth.instance.profileCache(false);
      ServiceHealth.log('profile', 1, watch.elapsedMilliseconds, null);
      final profile = _profile(row, uid);
      await _storeProfileContext(profile, current);
      return current() ? profile : null;
    } catch (e) {
      if (!current()) rethrow;
      final kind = failureKind(e);
      ServiceHealth.log('profile', 1, watch.elapsedMilliseconds, kind);
      if (kind == FailureKind.invalidSession || kind == FailureKind.denied) rethrow;
      // Only a previously server-approved, account-scoped, fresh profile qualifies.
      final raw = prefs.getString('verified_profile_$uid');
      if (raw != null) {
        try {
          final saved = jsonDecode(raw) as Map;
          final row = Map<String, dynamic>.from(saved['row'] as Map);
          if (canUseProfileCache(row, uid, DateTime.tryParse(saved['verified_at'].toString()), DateTime.now().toUtc())) {
            ServiceHealth.instance.profileCache(true);
            final profile = _profile(row, uid);
            await _storeProfileContext(profile, current);
            return current() ? profile : null;
          }
        } catch (_) {}
      }
      rethrow; // Show recovery, not an erroneous logout/login due to a 5xx.
    }
  }

  Future<AuthResult> registerOwner({
    required String name,
    required String email,
    required String password,
    required String businessName,
  }) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      final isSuperAdmin = cleanEmail == SupabaseConfig.superAdminEmail;
      final role = isSuperAdmin ? 'superadmin' : 'owner';

      final res = await _client.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'name': name, 'role': role},
      );

      if (res.user == null) {
        return AuthResult.error('Gagal membuat akun');
      }

      final uid = res.user!.id;

      if (_client.auth.currentSession == null) {
        try {
          await _client.auth.signInWithPassword(
              email: cleanEmail, password: password);
        } catch (_) {}
      }

      final rpcRes = await _client.rpc('register_owner', params: {
        'p_auth_id': uid,
        'p_name': name,
        'p_email': cleanEmail,
        'p_business_name': businessName,
      });

      if (rpcRes == null || rpcRes['success'] != true) {
        final errMsg = rpcRes?['error']?.toString() ?? 'Gagal menyimpan data';
        return AuthResult.error(errMsg);
      }

      final ownerId = rpcRes['owner_id'] as String;

      await _saveSession(
          uid: uid,
          name: name,
          email: cleanEmail,
          role: role,
          ownerId: ownerId);

      return AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.error(authenticationErrorMessage(e));
    } catch (e) {
      return AuthResult.error(authenticationErrorMessage(e));
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final cleanEmail = email.trim().toLowerCase();

      if (cleanEmail == SupabaseConfig.superAdminEmail) {
        return await _loginSuperAdmin(cleanEmail, password);
      }

      final res = await _client.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );

      if (res.user == null) return AuthResult.error('Login gagal');

      final uid = res.user!.id;

      final userRes = await _client
          .from('users')
          .select()
          .eq('auth_id', uid)
          .maybeSingle();

      if (userRes == null) {
        await _client.auth.signOut();
        return AuthResult.error('Profil tidak ditemukan. Hubungi admin.');
      }

      if (userRes['is_active'] == false) {
        await _client.auth.signOut();
        return AuthResult.error('Akun dinonaktifkan');
      }

      final role = userRes['role'] as String? ?? 'kasir';
      final ownerId = userRes['owner_id'] as String? ?? uid;
      final branchId = userRes['branch_id'] as String? ?? '';

      await _saveSession(
        uid: uid,
        name: userRes['name'] as String? ?? '',
        email: cleanEmail,
        role: role,
        ownerId: ownerId,
        branchId: branchId,
      );

      return AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.error(authenticationErrorMessage(e));
    } catch (e) {
      return AuthResult.error(authenticationErrorMessage(e));
    }
  }

  Future<AuthResult> _loginSuperAdmin(String email, String password) async {
    try {
      AuthResponse res;
      try {
        res = await _client.auth.signInWithPassword(
            email: email, password: password);
      } catch (authErr) {
        return AuthResult.error(authenticationErrorMessage(authErr));
      }

      if (res.user == null) return AuthResult.error('Login super admin gagal');
      final uid = res.user!.id;

      // Login verifies existing server authority; it never provisions privilege.
      final row = await _client.from('users')
          .select('owner_id,name,email,role,is_active,is_approved')
          .eq('auth_id', uid).maybeSingle().timeout(LoginTimeouts.profileRead);
      if (row == null || row['role'] != 'superadmin' ||
          row['is_active'] != true || row['is_approved'] != true) {
        return AuthResult.error('Akun ini tidak memiliki hak superadmin.');
      }
      await _saveSession(uid: uid, name: row['name']?.toString() ?? 'Super Admin',
        email: row['email']?.toString() ?? email, role: 'superadmin',
        ownerId: row['owner_id']?.toString() ?? '');

      return AuthResult.success();
    } catch (e) {
      return AuthResult.error(authenticationErrorMessage(e));
    }
  }

  Future<BranchResult> addBranch({
    required String name,
    required String address,
    String mode = 'food',
    String? phone,
  }) async {
    try {
      final session = await getSession();
      if (session == null) return BranchResult.error('Sesi tidak valid');
      if (!session.isOwnerLevel) {
        return BranchResult.error('Hanya owner yang bisa menambah cabang');
      }

      final res = await _client.from('branches').insert({
        'owner_id': session.ownerId,
        'name': name,
        'address': address,
        'phone': phone,
        'mode': mode,
        'is_active': true,
      }).select().single();

      final branchId = res['id'] as String;

      return BranchResult.success(branchId, name);
    } catch (e) {
      return BranchResult.error('Gagal membuat cabang: $e');
    }
  }

  Future<List<BranchOption>> getOwnerBranches() async {
    try {
      final session = await getSession();
      if (session == null) return [];

      final res = await _client
          .from('branches')
          .select()
          .eq('owner_id', session.ownerId)
          .eq('is_active', true)
          .order('created_at');

      return res
          .map((d) => BranchOption(
        id: d['id'] as String,
        name: d['name'] as String,
        address: d['address'] as String? ?? '',
        mode: d['mode'] as String? ?? 'food',
        ownerId: d['owner_id'] as String? ?? '',
      ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<AuthResult> createStaffAccount({
    required String name,
    required String email,
    required String password,
    required String role,
    required String branchId,
    required String branchName,
  }) async {
    try {
      final ownerSession = await getSession();
      if (ownerSession == null) return AuthResult.error('Sesi tidak valid');
      if (!ownerSession.isOwnerLevel) {
        return AuthResult.error('Hanya owner yang bisa membuat akun staff');
      }

      final cleanEmail = email.trim().toLowerCase();
      final ownerId = ownerSession.ownerId;

      final passwordHash = DatabaseHelper.hashPin(password);
      final rpcRes = await _client.rpc('create_staff_account', params: {
        'p_owner_id': ownerId,
        'p_branch_id': branchId.isEmpty ? null : branchId,
        'p_name': name.trim(),
        'p_email': cleanEmail,
        'p_role': role,
        'p_auth_id': null,
        'p_password': passwordHash,
      });

      if (rpcRes == null || rpcRes['success'] != true) {
        final errMsg = rpcRes?['error']?.toString() ?? 'Gagal simpan data';
        if (errMsg.contains('duplicate') || errMsg.contains('unique')) {
          return AuthResult.error('Email $cleanEmail sudah terdaftar');
        }
        return AuthResult.error(errMsg);
      }

      return AuthResult.staffCreated(
        message: 'Akun ${name.trim()} berhasil dibuat!\n'
            'Email : $cleanEmail\n'
            'Role  : $role\n\n'
            'Berikan password kepada staff secara langsung.\n'
            'Staff login via tab "Login Staff".',
      );
    } catch (e) {
      if (e.toString().contains('duplicate') ||
          e.toString().contains('unique') ||
          e.toString().contains('already')) {
        return AuthResult.error('Email sudah terdaftar');
      }
      return AuthResult.error('Gagal membuat akun: $e');
    }
  }

  Future<void> logout() async {
    await _client.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyUid);
    await prefs.remove(AppConstants.keyName);
    await prefs.remove(AppConstants.keyEmail);
    await prefs.remove(AppConstants.keyRole);
    await prefs.remove(AppConstants.keyOwnerId);
    await prefs.remove(AppConstants.keyBranchId);
    await prefs.remove(AppConstants.keyBranchName);
    await prefs.remove(AppConstants.keyKasirName);
  }

  Future<AuthResult> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
      return AuthResult.success();
    } catch (_) {
      return AuthResult.error('Gagal kirim email reset');
    }
  }

  Future<void> _saveSession({
    required String uid,
    required String name,
    required String email,
    required String role,
    required String ownerId,
    String branchId = '',
    String branchName = '',
    String branchMode = 'food',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyUid, uid);
    await prefs.setString(AppConstants.keyName, name);
    await prefs.setString(AppConstants.keyEmail, email);
    await prefs.setString(AppConstants.keyRole, role);
    await prefs.setString(AppConstants.keyOwnerId, ownerId);
    await prefs.setString(AppConstants.keyBranchId, branchId);
    await prefs.setString(AppConstants.keyBranchName, branchName);
    await prefs.setString(AppConstants.keyBranchMode, branchMode);
    await prefs.setString(AppConstants.keyKasirName, name);
  }

  Future<bool> deleteBranch(String branchId) async {
    try {
      final session = await getSession();
      if (session == null) return false;

      final role = session.role.toLowerCase();
      if (role != 'owner' && role != 'superadmin') return false;

      var query = SupabaseConfig.client
          .from('branches')
          .update({'is_active': false})
          .eq('id', branchId);

      if (role == 'owner') {
        query = query.eq('owner_id', session.ownerId);
      }

      final result = await query.select('id');
      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

// ── Models ──────────────────────────────────────────────────
class AppUserProfile {
  final String authId, email, name, role;
  final String ownerId, branchId, branchName, branchMode;
  final String? pin;

  const AppUserProfile({
    required this.authId,
    required this.email,
    required this.name,
    required this.role,
    required this.ownerId,
    required this.branchId,
    required this.branchName,
    required this.branchMode,
    this.pin,
  });

  String get id => authId;

  bool get isSuperAdmin => role == 'superadmin';
  bool get isOwner => role == 'owner';
  bool get isOwnerLevel => role == 'owner' || role == 'superadmin';
  bool get isAdmin => role == 'admin' || isOwnerLevel;
  bool get isManajer => role == 'manajer' || isSuperAdmin;
  bool get isKasir => role == 'kasir';
}

class AuthResult {
  final bool success;
  final bool isStaffCreated;
  final String? error;
  final String? message;

  const AuthResult._(
      {required this.success,
        this.isStaffCreated = false,
        this.error,
        this.message});

  factory AuthResult.success() => const AuthResult._(success: true);
  factory AuthResult.error(String msg) =>
      AuthResult._(success: false, error: msg);
  factory AuthResult.staffCreated({required String message}) =>
      AuthResult._(success: true, isStaffCreated: true, message: message);
}

class BranchResult {
  final bool success;
  final String? branchId, branchName, error;
  const BranchResult._(
      {required this.success, this.branchId, this.branchName, this.error});
  factory BranchResult.success(String id, String name) =>
      BranchResult._(success: true, branchId: id, branchName: name);
  factory BranchResult.error(String msg) =>
      BranchResult._(success: false, error: msg);
}

class BranchOption {
  final String id, name, address, mode, ownerId;
  const BranchOption(
      {required this.id,
        required this.name,
        required this.address,
        this.mode = 'food',
        this.ownerId = ''});
  bool get isRetail => mode == 'retail';
}
