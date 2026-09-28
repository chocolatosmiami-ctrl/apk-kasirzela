import '../utils/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../database/database_helper.dart';

class SupabaseAuthService {
  static final SupabaseAuthService instance = SupabaseAuthService._();
  SupabaseAuthService._();

  SupabaseClient get _client => SupabaseConfig.client;
  SupabaseClient get client => SupabaseConfig.client;

  bool get hasActiveSession => _client.auth.currentSession != null;

  AppUserProfile? get currentUser => null;

  Future<AppUserProfile?> getSession() async {
    try {
      final session = _client.auth.currentSession;

      if (session != null) {
        final uid = session.user.id;
        final res = await _client
            .from('users')
            .select('*, branches(name, mode)')
            .eq('auth_id', uid)
            .maybeSingle();

        if (res != null) {
          final role = res['role'] as String? ?? 'kasir';
          final branchData = res['branches'] as Map<String, dynamic>?;
          return AppUserProfile(
            authId: uid,
            email: session.user.email ?? '',
            name: res['name'] as String? ?? '',
            role: role,
            ownerId: res['owner_id'] as String? ?? uid,
            branchId: res['branch_id'] as String? ?? '',
            branchName: branchData?['name'] as String? ?? '',
            branchMode: branchData?['mode'] as String? ?? 'food',
            pin: res['pin_hash'] as String?,
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(AppConstants.keyEmail) ?? '';
      final name = prefs.getString(AppConstants.keyName) ?? '';
      final role = prefs.getString(AppConstants.keyRole) ?? '';
      final uid = prefs.getString(AppConstants.keyUid) ?? '';
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';

      if (email.isNotEmpty && role.isNotEmpty &&
          role != 'owner' && role != 'superadmin') {
        try {
          final staffData = await _client.rpc(
              'get_staff_by_email', params: {'p_email': email});

          Map<String, dynamic>? profile;
          if (staffData is Map<String, dynamic>) {
            profile = staffData;
          } else if (staffData is List && staffData.isNotEmpty) {
            profile = staffData.first as Map<String, dynamic>;
          } else {
            profile = null;
          }

          if (profile != null) {
            final profileBranchId =
                profile['branch_id']?.toString() ?? branchId;
            String profileBranchMode = 'food';
            String profileBranchName = '';
            if (profileBranchId.isNotEmpty) {
              try {
                final branchRow = await _client
                    .from('branches')
                    .select('mode, name')
                    .eq('id', profileBranchId)
                    .maybeSingle();
                profileBranchMode =
                    branchRow?['mode'] as String? ?? 'food';
                profileBranchName =
                    branchRow?['name'] as String? ?? '';
              } catch (_) {}
            }

            final sp2 = await SharedPreferences.getInstance();
            await sp2.setString(
                AppConstants.keyBranchMode, profileBranchMode);
            await sp2.setString(
                AppConstants.keyBranchName, profileBranchName);

            return AppUserProfile(
              authId: uid,
              email: email,
              name: profile['name'] as String? ?? name,
              role: profile['role'] as String? ?? role,
              ownerId: profile['owner_id']?.toString() ?? ownerId,
              branchId: profileBranchId,
              branchName: profileBranchName,
              branchMode: profileBranchMode,
              pin: profile['pin_hash'] as String?,
            );
          }
        } catch (_) {}

        if (name.isNotEmpty) {
          return AppUserProfile(
            authId: uid,
            email: email,
            name: name,
            role: role,
            ownerId: ownerId,
            branchId: branchId,
            branchName: prefs.getString(AppConstants.keyBranchName) ?? '',
            branchMode: prefs.getString(AppConstants.keyBranchMode) ?? 'food',
            pin: null,
          );
        }
      }

      return null;
    } catch (_) {
      return null;
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
      return AuthResult.error(_mapError(e.message));
    } catch (e) {
      return AuthResult.error('Terjadi kesalahan: $e');
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
      return AuthResult.error(_mapError(e.message));
    } catch (e) {
      return AuthResult.error('Terjadi kesalahan: $e');
    }
  }

  Future<AuthResult> _loginSuperAdmin(String email, String password) async {
    try {
      AuthResponse res;
      try {
        res = await _client.auth.signInWithPassword(
            email: email, password: password);
      } catch (authErr) {
        return AuthResult.error(_mapError(authErr.toString()));
      }

      if (res.user == null) return AuthResult.error('Login super admin gagal');
      final uid = res.user!.id;

      String ownerId = uid;
      try {
        final rpcRes = await _client.rpc('setup_superadmin', params: {
          'p_auth_id': uid,
          'p_email': email,
        });
        ownerId = rpcRes?['owner_id'] as String? ?? uid;
      } catch (_) {
        try {
          final userRow = await _client
              .from('users')
              .select('owner_id')
              .eq('auth_id', uid)
              .maybeSingle();
          if (userRow != null) {
            ownerId = userRow['owner_id']?.toString() ?? uid;
          } else {
            await _client.from('users').upsert({
              'auth_id': uid,
              'owner_id': uid,
              'name': 'Super Admin',
              'email': email,
              'role': 'superadmin',
              'is_active': true,
              'is_approved': true,
            }, onConflict: 'auth_id');
          }
        } catch (_) {}
      }

      await _saveSession(
        uid: uid,
        name: 'Super Admin',
        email: email,
        role: 'superadmin',
        ownerId: ownerId,
      );

      return AuthResult.success();
    } catch (e) {
      return AuthResult.error('Error super admin: $e');
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

  String _mapError(String msg) {
    if (msg.contains('Invalid login')) return 'Email atau password salah';
    if (msg.contains('already registered')) return 'Email sudah terdaftar';
    if (msg.contains('weak password')) return 'Password terlalu lemah';
    if (msg.contains('Email not confirmed')) return 'Email belum dikonfirmasi';
    if (msg.contains('network')) return 'Tidak ada koneksi internet';
    return msg;
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
