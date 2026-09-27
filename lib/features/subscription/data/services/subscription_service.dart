import '../../../../core/utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../models/subscription_model.dart'; // TopUpRequest
import '../models/subscription_model.dart'; // TopUpRequest

class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  SupabaseClient get _db => SupabaseConfig.client;
  static const double _costPerTrx = 150;

  Future<String?> _getOwnerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyOwnerId);
  }

  // ── Ambil subscription owner ──────────────────────────
  Future<SubscriptionModel?> getMySubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String ownerId = (await _getOwnerId()) ?? '';
      final role = prefs.getString(AppConstants.keyRole) ?? '';
      final authId = prefs.getString(AppConstants.keyUid) ?? '';
      debugPrint('💰 [Subscription] getMySubscription: ownerId=$ownerId role=$role');

      // Step 1: Direct query by owner_id (dari tabel owners)
      var res = await _db
          .from('subscriptions')
          .select()
          .eq('owner_id', ownerId)
          .maybeSingle();
      debugPrint('💰 [Subscription] Direct by owner_id: ${res != null ? 'FOUND' : 'NULL'}');

      // Step 2: Untuk owner/superadmin — cari owner_id dari tabel owners via auth_id
      if (res == null && authId.isNotEmpty &&
          (role == 'owner' || role == 'superadmin')) {
        debugPrint('💰 [Subscription] Trying owners table via auth_id=$authId');
        final ownerRow = await _db.from('owners')
            .select('id').eq('auth_id', authId).maybeSingle();
        final realOwnerId = ownerRow?['id']?.toString() ?? '';
        if (realOwnerId.isNotEmpty && realOwnerId != ownerId) {
          debugPrint('💰 [Subscription] Found real owner_id=$realOwnerId from owners table');
          res = await _db.from('subscriptions')
              .select().eq('owner_id', realOwnerId).maybeSingle();
          if (res != null) {
            ownerId = realOwnerId;
            await prefs.setString(AppConstants.keyOwnerId, realOwnerId);
            debugPrint('💰 [Subscription] ✅ Fixed owner_id=$realOwnerId via owners table');
          }
        }
      }

      // Step 3: Try via branch_id → get real owner_id (untuk kasir)
      if (res == null) {
        final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';
        debugPrint('💰 [Subscription] Trying branch_id=$branchId');

        if (branchId.isNotEmpty) {
          final branch = await _db.from('branches')
              .select('owner_id').eq('id', branchId).maybeSingle();
          final realOwnerId = branch?['owner_id'] as String? ?? '';
          debugPrint('💰 [Subscription] Branch owner_id=$realOwnerId');

          if (realOwnerId.isNotEmpty) {
            res = await _db.from('subscriptions')
                .select().eq('owner_id', realOwnerId).maybeSingle();
            if (res != null) {
              ownerId = realOwnerId;
              await prefs.setString(AppConstants.keyOwnerId, realOwnerId);
              debugPrint('💰 [Subscription] ✅ Fixed owner_id=$realOwnerId via branch');
            }
          }
        }
      }

      if (res == null) {
        debugPrint('💰 [Subscription] ❌ No subscription found anywhere');
        return null;
      }

      final balance = (res['balance'] as num?)?.toDouble() ?? 0;
      debugPrint('💰 [Subscription] ✅ Found! balance=$balance, locked=${res['is_locked']}');
      return SubscriptionModel.fromMap({
        'branch_id': ownerId,
        'branch_name': '',
        'balance': res['balance'],
        'total_transactions': res['total_transactions'],
        'is_locked': res['is_locked'],
        'last_top_up': res['last_top_up'],
        'locked_at': res['locked_at'],
      });
    } catch (e) {
      debugPrint('💰 [Subscription] ❌ Error: $e');
      return null;
    }
  }

  // ── Potong saldo per transaksi ─────────────────────────
  // BUG 7 FIX: Deduction sekarang dilakukan via RPC SECURITY DEFINER di server.
  // Sebelumnya: client baca balance → hitung → UPDATE langsung (tidak aman, tidak atomic).
  // Sekarang: server yang baca, kunci row (FOR UPDATE), hitung, dan update.
  // p_amount DIHAPUS dari RPC — nilai Rp150 hardcoded di server (lihat BUG 47 fix di SQL).
  Future<bool> deductTransaction() async {
    try {
      String? ownerId = await _getOwnerId();
      if (ownerId == null) return true;

      // Resolusi ownerId via branch jika perlu
      final prefs2 = await SharedPreferences.getInstance();
      final branchId = prefs2.getString(AppConstants.keyBranchId) ?? '';
      if (branchId.isNotEmpty) {
        try {
          final branch = await _db.from('branches')
              .select('owner_id').eq('id', branchId).maybeSingle();
          final realOwner = branch?['owner_id'] as String? ?? '';
          if (realOwner.isNotEmpty && realOwner != ownerId) {
            ownerId = realOwner;
            await prefs2.setString(AppConstants.keyOwnerId, realOwner);
          }
        } catch (_) {}
      }

      final kasirEmail = prefs2.getString(AppConstants.keyEmail) ?? '';
      final kasirName  = prefs2.getString(AppConstants.keyName)  ?? '';
      final branchName = prefs2.getString(AppConstants.keyBranchName) ?? '';

      // Panggil RPC server-side yang sudah fixed (FOR UPDATE + amount hardcoded)
      final result = await _db.rpc('deduct_subscription_balance', params: {
        'p_owner_id':    ownerId,
        'p_kasir_email': kasirEmail,
        'p_kasir_name':  kasirName,
        'p_branch_id':   branchId.isNotEmpty ? branchId : null,
        'p_branch_name': branchName,
        // p_amount sengaja TIDAK dikirim — hardcoded 150 di server
      });

      if (result == null) {
        debugPrint('💰 [deduct] RPC returned null, izinkan transaksi');
        return true;
      }

      final success  = result['success'] as bool? ?? false;
      final isLocked = result['is_locked'] as bool? ?? false;
      final error    = result['error'] as String? ?? '';

      if (!success) {
        debugPrint('💰 [deduct] RPC error: $error');
        if (error == 'subscription_not_found') return true; // izinkan jika belum ada data
        return isLocked ? false : true;
      }

      debugPrint('💰 [deduct] RPC success: balance=${result['balance']}, locked=$isLocked');
      return !isLocked;
    } catch (e) {
      debugPrint('deductTransaction error: $e');
      return true; // allow if error
    }
  }

  // ── Top up request ─────────────────────────────────────
  Future<String?> requestTopUp({
    required double amount,
    required String method,
    String? notes,
  }) async {
    try {
      final ownerId = await _getOwnerId();
      if (ownerId == null) return 'Session tidak valid';

      final prefs = await SharedPreferences.getInstance();
      final ownerName = prefs.getString(AppConstants.keyName) ?? '';
      final ownerEmail = prefs.getString(AppConstants.keyEmail) ?? '';

      await _db.from('topup_requests').insert({
        'owner_id': ownerId,
        'owner_name': ownerName,
        'owner_email': ownerEmail,
        'amount': amount,
        'method': method,
        'status': 'pending',
        'notes': notes,
      });
      return null; // null = success
    } catch (e) {
      return 'Gagal membuat request: $e';
    }
  }

  // ── Super Admin: semua subscriptions ──────────────────
  Future<List<Map<String, dynamic>>> getAllSubscriptions() async {
    try {
      // Ambil semua owner dari users
      final users = await _db
          .from('users')
          .select()
          .inFilter('role', ['owner', 'superadmin']);

      // Ambil semua subscriptions
      final subs = await _db.from('subscriptions').select();
      final subsMap = {
        for (final s in subs) s['owner_id'] as String: s
      };

      return users.map((u) {
        final ownerId = u['owner_id'] as String? ?? '';
        final sub = subsMap[ownerId] ?? {};
        return {
          'id': ownerId,
          'owner_id': ownerId,
          'owner_name': u['name'] as String? ?? '-',
          'owner_email': u['email'] as String? ?? '-',
          'balance': (sub['balance'] as num?)?.toDouble() ?? 0.0,
          'total_transactions': sub['total_transactions'] as int? ?? 0,
          'is_locked': sub['is_locked'] as bool? ?? false,
          'is_trial': sub['is_trial'] as bool? ?? true,
        };
      }).toList()
        ..sort((a, b) => (a['owner_name'] as String)
            .compareTo(b['owner_name'] as String));
    } catch (e) {
      debugPrint('getAllSubscriptions error: $e');
      return [];
    }
  }

  // ── Super Admin: top up manual ─────────────────────────
  Future<bool> superAdminTopUp(
      String ownerId, double amount, String note) async {
    try {
      final sub = await _db.from('subscriptions')
          .select('balance')
          .eq('owner_id', ownerId)
          .single();

      final newBalance = (sub['balance'] as num).toDouble() + amount;

      await _db.from('subscriptions').update({
        'balance': newBalance,
        'is_locked': false,
        'last_top_up': DateTime.now().toUtc().toIso8601String(),
      }).eq('owner_id', ownerId);

      return true;
    } catch (e) {
      debugPrint('superAdminTopUp error: $e');
      return false;
    }
  }

  // ── Super Admin: total revenue ─────────────────────────
  Future<Map<String, dynamic>> getTotalRevenue() async {
    try {
      final users = await _db
          .from('users')
          .select('id')
          .inFilter('role', ['owner', 'superadmin']);

      final subs = await _db.from('subscriptions').select();

      double totalRevenue = 0;
      int totalTrx = 0, activeOwners = 0;

      for (final s in subs) {
        final trx = s['total_transactions'] as int? ?? 0;
        final locked = s['is_locked'] as bool? ?? false;
        totalTrx += trx;
        totalRevenue += trx * _costPerTrx;
        if (!locked) activeOwners++;
      }

      return {
        'total_revenue': totalRevenue,
        'total_transactions': totalTrx,
        'total_owners': users.length,
        'active_owners': activeOwners,
      };
    } catch (e) {
      return {};
    }
  }

  // ── Top up requests untuk super admin ─────────────────
  Future<List<Map<String, dynamic>>> getPendingTopUps() async {
    try {
      return List<Map<String, dynamic>>.from(
        await _db.from('topup_requests')
            .select()
            .eq('status', 'pending')
            .order('created_at', ascending: false),
      );
    } catch (e) {
      return [];
    }
  }

  Future<bool> approveTopUp(String requestId, String ownerId,
      double amount) async {
    try {
      await superAdminTopUp(ownerId, amount, 'Approved');
      await _db.from('topup_requests').update({
        'status': 'approved',
        'processed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', requestId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> rejectTopUp(String requestId, String reason) async {
    try {
      await _db.from('topup_requests').update({
        'status': 'rejected',
        'reject_reason': reason,
        'processed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', requestId);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Stream pending top ups untuk super admin
  Stream<List<TopUpRequest>> pendingTopUpsStream() {
    return _db.from('topup_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .map((data) => data
            .map((d) => TopUpRequest.fromMap(d['id']?.toString() ?? '', d))
            .toList());
  }

  // Block/unblock owner
  Future<bool> blockOwner(String ownerId, bool block) async {
    try {
      await _db.from('subscriptions').update({
        'is_locked': block,
      }).eq('owner_id', ownerId);
      await _db.from('users').update({
        'is_active': !block,
      }).eq('owner_id', ownerId);
      return true;
    } catch (e) {
      return false;
    }
  }
}
