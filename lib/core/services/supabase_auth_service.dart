import '../utils/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../database/database_helper.dart';

class SupabaseAuthService {
  static final SupabaseAuthService instance = SupabaseAuthService._();
  SupabaseAuthService._();

  SupabaseClient get _client => SupabaseConfig.client;
  // Public accessor
  SupabaseClient get client => SupabaseConfig.client;

  // ── Cek apakah sudah login ────────────────────────────
  // Sync getter: cek apakah ada session Supabase aktif.
  // Untuk profil lengkap (nama, role, dll) tetap pakai getSession().
  // Getter ini berguna untuk quick-check tanpa async.
  bool get hasActiveSession => _client.auth.currentSession != null;

  // Deprecated getter — dulu selalu return null, sekarang diganti hasActiveSession.
  // Biarkan ada untuk backward compatibility tapi arahkan ke getSession().
  AppUserProfile? get currentUser => null; // gunakan getSession() untuk profil lengkap

  Future<AppUserProfile?> getSession() async {
    try {
      debugPrint('🔍 [getSession] START');
      // Try Supabase Auth session first (owner/superadmin)
      final session = _client.auth.currentSession;
      debugPrint('🔍 [getSession] Supabase session: ${session?.user.email ?? "NULL"}');
      
      if (session != null) {
        final uid = session.user.id;
        final res = await _client
            .from('users')
            .select('*, branches(name, mode)')
            .eq('auth_id', uid)
            .maybeSingle();

        debugPrint('🔍 [getSession] users row found');
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
            pin: res['pin_hash'] as String?, // kolom 'pin' tidak exist, pakai pin_hash
          );
        }
      }

      // Fallback: Staff login via password (no Supabase Auth session)
      // Baca dari SharedPreferences yang disimpan saat login
      final prefs = await SharedPreferences.getInstance();
      final email   = prefs.getString(AppConstants.keyEmail) ?? '';
      final name    = prefs.getString(AppConstants.keyName) ?? '';
      final role    = prefs.getString(AppConstants.keyRole) ?? '';
      final uid     = prefs.getString(AppConstants.keyUid) ?? '';
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final branchId= prefs.getString(AppConstants.keyBranchId) ?? '';

      // Jika ada data di SharedPreferences → user sedang login sebagai staff
      debugPrint('🔍 [getSession] SharedPrefs → email=$email, role=$role, uid=$uid, branchId=$branchId');
      if (email.isNotEmpty && role.isNotEmpty && 
          role != 'owner' && role != 'superadmin') {
        // Ambil data lengkap via RPC (bypass RLS)
        try {
          final staffData = await _client.rpc(
            'get_staff_by_email', params: {'p_email': email});
          // RPC bisa return json (Map) atau List tergantung versi fungsi di Supabase
          Map<String, dynamic>? profile;
          if (staffData is Map<String, dynamic>) {
            profile = staffData;
          } else if (staffData is List && staffData.isNotEmpty) {
            profile = staffData.first as Map<String, dynamic>;
          } else {
            profile = null;
          }
          
          if (profile != null) {
            // Ambil branchMode dari data branch user, bukan hardcode 'food'
            final profileBranchId = profile['branch_id']?.toString() ?? branchId;
            String profileBranchMode = 'food';
            String profileBranchName = '';
            if (profileBranchId.isNotEmpty) {
              try {
                final branchRow = await _client
                    .from('branches')
                    .select('mode, name')
                    .eq('id', profileBranchId)
                    .maybeSingle();
                profileBranchMode = branchRow?['mode'] as String? ?? 'food';
                profileBranchName = branchRow?['name'] as String? ?? '';
              } catch (_) {}
            }
            // Simpan ke SharedPrefs agar persist saat offline
            final sp2 = await SharedPreferences.getInstance();
            await sp2.setString(AppConstants.keyBranchMode, profileBranchMode);
            await sp2.setString(AppConstants.keyBranchName, profileBranchName);

            return AppUserProfile(
              authId: uid,
              email: email,
              name: profile['name'] as String? ?? name,
              role: profile['role'] as String? ?? role,
              ownerId: profile['owner_id']?.toString() ?? ownerId,
              branchId: profileBranchId,
              branchName: profileBranchName,
              branchMode: profileBranchMode,
              pin: profile['pin_hash'] as String?, // kolom 'pin' tidak exist, pakai pin_hash
            );
          }
        } catch (_) {}

        // Fallback minimal dari SharedPreferences saja
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
    } catch (e) {
      debugPrint('getSession error: $e');
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
      debugPrint('🔑 [Login] email=$cleanEmail');
      final role = isSuperAdmin ? 'superadmin' : 'owner';

      // Daftar ke Supabase Auth
      final res = await _client.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'name': name, 'role': role},
      );

      if (res.user == null) {
        return AuthResult.error('Gagal membuat akun');
      }

      final uid = res.user!.id;

      // Ensure session is active after signUp
      // signUp auto-signs in if email confirmation is disabled
      if (_client.auth.currentSession == null) {
        try {
          await _client.auth.signInWithPassword(
            email: cleanEmail, password: password);
        } catch (e) {
          debugPrint('Auto sign-in after signUp failed: $e');
        }
      }

      // Use RPC function to bypass RLS (SECURITY DEFINER)
      // This handles: owners + users + subscriptions insert atomically
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

      await _saveSession(uid: uid, name: name, email: cleanEmail,
          role: role, ownerId: ownerId);

      return AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.error(_mapError(e.message));
    } catch (e) {
      return AuthResult.error('Terjadi kesalahan: $e');
    }
  }

  // ── Login ─────────────────────────────────────────────
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final cleanEmail = email.trim().toLowerCase();

      // Super admin: login via Supabase Auth biasa (tidak ada bypass password).
      // Jika email cocok dengan superAdminEmail, tetap lanjut flow normal.
      // _loginSuperAdmin tetap dipanggil untuk upsert data owner/user jika perlu.
      if (cleanEmail == SupabaseConfig.superAdminEmail) {
        return await _loginSuperAdmin(cleanEmail, password);
      }

      final res = await _client.auth.signInWithPassword(
        email: cleanEmail, password: password,
      );

      if (res.user == null) return AuthResult.error('Login gagal');

      final uid = res.user!.id;

      // Ambil profil user
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
      // Step 1: Login via Supabase Auth
      AuthResponse res;
      try {
        res = await _client.auth.signInWithPassword(
            email: email, password: password);
      } catch (authErr) {
        return AuthResult.error(_mapError(authErr.toString()));
      }

      if (res.user == null) return AuthResult.error('Login super admin gagal');
      final uid = res.user!.id;

      // Step 2: Coba RPC setup_superadmin
      // Jika RPC belum dibuat di Supabase, fallback ke query langsung
      String ownerId = uid;
      try {
        final rpcRes = await _client.rpc('setup_superadmin', params: {
          'p_auth_id': uid,
          'p_email': email,
        });
        ownerId = rpcRes?['owner_id'] as String? ?? uid;
        debugPrint('✅ [SuperAdmin] setup via RPC, ownerId=$ownerId');
      } catch (rpcErr) {
        debugPrint('⚠️ [SuperAdmin] RPC setup_superadmin gagal: $rpcErr');
        debugPrint('   → Fallback: cek tabel users langsung');
        // Fallback: ambil ownerId dari tabel users jika sudah ada
        try {
          final userRow = await _client
              .from('users')
              .select('owner_id')
              .eq('auth_id', uid)
              .maybeSingle();
          if (userRow != null) {
            ownerId = userRow['owner_id']?.toString() ?? uid;
            debugPrint('✅ [SuperAdmin] Found existing user, ownerId=$ownerId');
          } else {
            // Belum ada row user → buat via upsert langsung
            // (hanya berfungsi jika RLS mengizinkan insert oleh authenticated)
            await _client.from('users').upsert({
              'auth_id': uid,
              'owner_id': uid,
              'name': 'Super Admin',
              'email': email,
              'role': 'superadmin',
              'is_active': true,
              'is_approved': true,
            }, onConflict: 'auth_id');
            debugPrint('✅ [SuperAdmin] Created user row directly');
          }
        } catch (fbErr) {
          debugPrint('⚠️ [SuperAdmin] Fallback juga gagal: $fbErr');
          // Tetap lanjut login dengan uid sebagai ownerId
        }
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

  // ── Tambah cabang ─────────────────────────────────────
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

      // Trial subscription untuk cabang baru (pakai owner subscription)
      // Tidak perlu buat subscription per cabang, sudah per owner

      return BranchResult.success(branchId, name);
    } catch (e) {
      return BranchResult.error('Gagal membuat cabang: $e');
    }
  }

  // ── Ambil cabang milik owner ──────────────────────────
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

      return res.map((d) => BranchOption(
        id: d['id'] as String,
        name: d['name'] as String,
        address: d['address'] as String? ?? '',
        mode: d['mode'] as String? ?? 'food',
        ownerId: d['owner_id'] as String? ?? '',
      )).toList();
    } catch (e) {
      return [];
    }
  }

  // ── Buat akun staff ───────────────────────────────────
  Future<AuthResult> createStaffAccount({
    required String name,
    required String email,
    required String password,
    required String role,
    required String branchId,
    required String branchName,

  }) async {
    try {
      // Pastikan yang login adalah owner/superadmin
      final ownerSession = await getSession();
      if (ownerSession == null) return AuthResult.error('Sesi tidak valid');
      if (!ownerSession.isOwnerLevel) {
        return AuthResult.error('Hanya owner yang bisa membuat akun staff');
      }

      final cleanEmail = email.trim().toLowerCase();
      // Selalu gunakan ownerId dari session yang sedang login
      // Siapapun yang login dan membuat staff = itulah owner staff tersebut
      final ownerId = ownerSession.ownerId;

      // PENTING: JANGAN gunakan signUp() - itu akan LOGOUT owner!
      // Simpan langsung ke tabel users via RPC SECURITY DEFINER
      // FIX: hash password sebelum disimpan — jangan kirim plaintext ke DB
      final passwordHash = DatabaseHelper.hashPin(password);
      final rpcRes = await _client.rpc('create_staff_account', params: {
        'p_owner_id':  ownerId,
        'p_branch_id': branchId.isEmpty ? null : branchId,
        'p_name':      name.trim(),
        'p_email':     cleanEmail,
        'p_role':      role,
        'p_auth_id':   null,
        'p_password':  passwordHash, // kirim hash, bukan plaintext
      });

      if (rpcRes == null || rpcRes['success'] != true) {
        final errMsg = rpcRes?['error']?.toString() ?? 'Gagal simpan data';
        // Cek apakah duplicate email
        if (errMsg.contains('duplicate') || errMsg.contains('unique')) {
          return AuthResult.error('Email $cleanEmail sudah terdaftar');
        }
        return AuthResult.error(errMsg);
      }

      debugPrint('✅ [createStaff] RPC success, ownerId=$ownerId, email=$cleanEmail');
      // BUG 3 FIX: Password tidak ditampilkan di UI — sampaikan ke staff secara langsung.
      return AuthResult.staffCreated(
        message: 'Akun ${name.trim()} berhasil dibuat!\n'
            'Email : $cleanEmail\n'
            'Role  : $role\n\n'
            'Berikan password kepada staff secara langsung.\n'
            'Staff login via tab "Login Staff".',
      );
    } catch (e) {
      debugPrint('createStaffAccount error: $e');
      if (e.toString().contains('duplicate') ||
          e.toString().contains('unique') ||
          e.toString().contains('already')) {
        return AuthResult.error('Email sudah terdaftar');
      }
      return AuthResult.error('Gagal membuat akun: $e');
    }
  }


  // ── Logout ────────────────────────────────────────────
  Future<void> logout() async {
    await _client.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    // Hapus HANYA data sesi — jangan clear() semua karena
    // akan menghapus settings (dark mode, side menu, branch_mode, dll)
    await prefs.remove(AppConstants.keyUid);
    await prefs.remove(AppConstants.keyName);
    await prefs.remove(AppConstants.keyEmail);
    await prefs.remove(AppConstants.keyRole);
    await prefs.remove(AppConstants.keyOwnerId);
    await prefs.remove(AppConstants.keyBranchId);
    await prefs.remove(AppConstants.keyBranchName);
    await prefs.remove(AppConstants.keyKasirName);
    // sb_pin_hash sengaja TIDAK dihapus agar PIN tidak perlu dibuat ulang
    // setiap kali login. Hash aman disimpan karena bukan plaintext.
    // branch_mode & use_side_menu sengaja TIDAK dihapus agar tetap persisten
  }

  // ── Reset password ────────────────────────────────────
  Future<AuthResult> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
      return AuthResult.success();
    } catch (e) {
      return AuthResult.error('Gagal kirim email reset');
    }
  }

  // ── Save session to SharedPreferences ────────────────
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

  // Hapus/nonaktifkan cabang — hanya owner & superadmin
  Future<bool> deleteBranch(String branchId) async {
    try {
      final session = await getSession();
      if (session == null) return false;

      final role = session.role.toLowerCase();
      if (role != 'owner' && role != 'superadmin') {
        debugPrint('❌ deleteBranch: role=$role tidak diizinkan');
        return false;
      }

      var query = SupabaseConfig.client
          .from('branches')
          .update({'is_active': false})
          .eq('id', branchId);

      if (role == 'owner') {
        // Fix: gunakan session.ownerId bukan session.authId
        // authId = UUID dari Supabase Auth, ownerId = UUID dari tabel owners
        query = query.eq('owner_id', session.ownerId);
      }

      final result = await query.select('id');
      if (result.isEmpty) {
        debugPrint('❌ deleteBranch: not found or not authorized');
        return false;
      }

      debugPrint('✅ Branch $branchId deactivated by ${session.email}');
      return true;
    } catch (e) {
      debugPrint('❌ deleteBranch error: $e');
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
    required this.authId, required this.email,
    required this.name, required this.role,
    required this.ownerId, required this.branchId,
    required this.branchName, required this.branchMode,
    this.pin,
  });

  // Alias for backward compatibility
  String get id => authId;

  bool get isSuperAdmin => role == 'superadmin';
  bool get isOwner => role == 'owner';
  bool get isOwnerLevel => role == 'owner' || role == 'superadmin';
  bool get isAdmin => role == 'admin' || isOwnerLevel;
  // superadmin memiliki semua akses termasuk fitur manajer
  bool get isManajer => role == 'manajer' || isSuperAdmin;
  bool get isKasir => role == 'kasir';
}

class AuthResult {
  final bool success;
  final bool isStaffCreated;
  final String? error;
  final String? message;

  const AuthResult._({required this.success,
      this.isStaffCreated = false, this.error, this.message});

  factory AuthResult.success() => const AuthResult._(success: true);
  factory AuthResult.error(String msg) =>
      AuthResult._(success: false, error: msg);
  factory AuthResult.staffCreated({required String message}) =>
      AuthResult._(success: true, isStaffCreated: true, message: message);
}

class BranchResult {
  final bool success;
  final String? branchId, branchName, error;
  const BranchResult._({required this.success,
      this.branchId, this.branchName, this.error});
  factory BranchResult.success(String id, String name) =>
      BranchResult._(success: true, branchId: id, branchName: name);
  factory BranchResult.error(String msg) =>
      BranchResult._(success: false, error: msg);
}

class BranchOption {
  final String id, name, address, mode, ownerId;
  const BranchOption({required this.id, required this.name,
      required this.address, this.mode = 'food', this.ownerId = ''});
  bool get isRetail => mode == 'retail';
}

