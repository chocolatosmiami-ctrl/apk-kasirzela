import 'package:flutter/foundation.dart';
import '../../../../core/utils/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/config/supabase_config.dart';
import '../models/subscription_model.dart';

class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  SupabaseClient get _db => SupabaseConfig.client;

  Future<String?> _getOwnerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.keyOwnerId);
  }

  Future<SubscriptionModel?> getMySubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String ownerId = (await _getOwnerId()) ?? '';
      final role = prefs.getString(AppConstants.keyRole) ?? '';
      final authId = prefs.getString(AppConstants.keyUid) ?? '';
      final branchId = prefs.getString(AppConstants.keyBranchId) ?? '';

      debugPrint('💰 [SubService] getMySubscription: ownerId=$ownerId role=$role authId=$authId branchId=$branchId');

      // ── 1. Coba lookup langsung pakai owner_id dari SharedPreferences ──
      var res = ownerId.isNotEmpty
          ? await _db
              .from('subscriptions')
              .select()
              .eq('owner_id', ownerId)
              .maybeSingle()
          : null;

      debugPrint('💰 [SubService] lookup #1 (ownerId=$ownerId): ${res != null ? 'FOUND' : 'NULL'}');

      // ── 2. Fallback: cari lewat owners table (hanya owner/superadmin) ──
      if (res == null && authId.isNotEmpty &&
          (role == 'owner' || role == 'superadmin')) {
        final ownerRow = await _db.from('owners')
            .select('id').eq('auth_id', authId).maybeSingle();
        final realOwnerId = ownerRow?['id']?.toString() ?? '';
        if (realOwnerId.isNotEmpty && realOwnerId != ownerId) {
          res = await _db.from('subscriptions')
              .select().eq('owner_id', realOwnerId).maybeSingle();
          if (res != null) {
            ownerId = realOwnerId;
            await prefs.setString(AppConstants.keyOwnerId, realOwnerId);
            debugPrint('💰 [SubService] lookup #2 (owners): FOUND, saved ownerId=$realOwnerId');
          }
        }
      }

      // ── 3. Fallback: cari lewat branch_id → branches.owner_id ──
      if (res == null && branchId.isNotEmpty) {
        final branch = await _db.from('branches')
            .select('owner_id').eq('id', branchId).maybeSingle();
        final realOwnerId = branch?['owner_id'] as String? ?? '';
        debugPrint('💰 [SubService] lookup #3 (branchId=$branchId): branch owner=$realOwnerId');
        if (realOwnerId.isNotEmpty) {
          res = await _db.from('subscriptions')
              .select().eq('owner_id', realOwnerId).maybeSingle();
          if (res != null) {
            ownerId = realOwnerId;
            await prefs.setString(AppConstants.keyOwnerId, realOwnerId);
            debugPrint('💰 [SubService] lookup #3: FOUND, saved ownerId=$realOwnerId');
          }
        }
      }

      if (res == null) {
        debugPrint('💰 [SubService] ❌ subscription NOT FOUND after all lookups');
        return null;
      }

      debugPrint('💰 [SubService] ✅ subscription FOUND: balance=${res['balance']} plan=${res['plan_type']} expires=${res['plan_expires_at']}');

      // Map semua field termasuk plan & cost_per_trx dari DB
      return SubscriptionModel.fromMap({
        'branch_id': ownerId,
        'branch_name': '',
        'balance': res['balance'],
        'total_transactions': res['total_transactions'],
        'cost_per_trx': res['cost_per_trx'],       // ambil dari DB
        'is_locked': res['is_locked'],
        'last_top_up': res['last_top_up'],
        'locked_at': res['locked_at'],
        'plan_type': res['plan_type'] ?? 'per_trx',
        'plan_started_at': res['plan_started_at'],
        'plan_expires_at': res['plan_expires_at'],
        'plan_price': res['plan_price'],
      });
    } catch (e) {
      debugPrint('💰 [SubService] ❌ getMySubscription ERROR: $e');
      return null;
    }
  }

  Future<bool> deductTransaction() async {
    try {
      String? ownerId = await _getOwnerId();
      if (ownerId == null) return true;

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
      final kasirName = prefs2.getString(AppConstants.keyName) ?? '';
      final branchName = prefs2.getString(AppConstants.keyBranchName) ?? '';

      final result = await _db.rpc('deduct_subscription_balance', params: {
        'p_owner_id': ownerId,
        'p_kasir_email': kasirEmail,
        'p_kasir_name': kasirName,
        'p_branch_id': branchId.isNotEmpty ? branchId : null,
        'p_branch_name': branchName,
      });

      if (result == null) return true;

      final success = result['success'] as bool? ?? false;
      final isLocked = result['is_locked'] as bool? ?? false;
      final error = result['error'] as String? ?? '';

      if (!success) {
        if (error == 'subscription_not_found') return true;
        return isLocked ? false : true;
      }

      return !isLocked;
    } catch (_) {
      return true;
    }
  }

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
      return null;
    } catch (e) {
      return 'Gagal membuat request: $e';
    }
  }

  Future<List<Map<String, dynamic>>> getAllSubscriptions() async {
    try {
      final users = await _db
          .from('users')
          .select()
          .inFilter('role', ['owner', 'superadmin']);

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
          'plan_type': sub['plan_type'] as String? ?? 'per_trx',
          'cost_per_trx': (sub['cost_per_trx'] as num?)?.toDouble() ?? 300,
        };
      }).toList()
        ..sort((a, b) => (a['owner_name'] as String)
            .compareTo(b['owner_name'] as String));
    } catch (_) {
      return [];
    }
  }

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
    } catch (_) {
      return false;
    }
  }

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
        // Gunakan cost_per_trx dari DB masing-masing owner
        final cost = (s['cost_per_trx'] as num?)?.toDouble() ?? 300;
        totalTrx += trx;
        totalRevenue += trx * cost;
        if (!locked) activeOwners++;
      }

      return {
        'total_revenue': totalRevenue,
        'total_transactions': totalTrx,
        'total_owners': users.length,
        'active_owners': activeOwners,
      };
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getPendingTopUps() async {
    try {
      return List<Map<String, dynamic>>.from(
        await _db.from('topup_requests')
            .select()
            .eq('status', 'pending')
            .order('created_at', ascending: false),
      );
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
      return false;
    }
  }

  Stream<List<TopUpRequest>> pendingTopUpsStream() {
    return _db.from('topup_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .map((data) => data
        .map((d) => TopUpRequest.fromMap(d['id']?.toString() ?? '', d))
        .toList());
  }

  Future<bool> blockOwner(String ownerId, bool block) async {
    try {
      await _db.from('subscriptions').update({
        'is_locked': block,
      }).eq('owner_id', ownerId);
      await _db.from('users').update({
        'is_active': !block,
      }).eq('owner_id', ownerId);
      return true;
    } catch (_) {
      return false;
    }
  }
}