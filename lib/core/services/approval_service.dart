import '../utils/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class PendingApproval {
  final String id;
  final String name;
  final String email;
  final String role;
  final String branchId;
  final String createdAt;

  const PendingApproval({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.branchId,
    required this.createdAt,
  });

  factory PendingApproval.fromMap(Map<String, dynamic> map) => PendingApproval(
    id: map['id']?.toString() ?? '',
    name: map['name'] as String? ?? '',
    email: map['email'] as String? ?? '',
    role: map['role'] as String? ?? 'kasir',
    branchId: map['branch_id']?.toString() ?? '',
    createdAt: map['created_at']?.toString() ?? '',
  );
}

class ApprovalService {
  static final ApprovalService instance = ApprovalService._();
  ApprovalService._();

  SupabaseClient get _db => SupabaseConfig.client;

  Future<bool> approveUser(String id) async {
    try {
      await _db.from('users').update({
        'is_active': true, 'is_approved': true,
      }).eq('id', id);
      return true;
    } catch (e) { return false; }
  }

  Future<bool> rejectUser(String id) async {
    try {
      await _db.from('users').update({
        'is_active': false, 'is_approved': false,
      }).eq('id', id);
      return true;
    } catch (e) { return false; }
  }

  Future<List<PendingApproval>> getPendingApprovals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerId = prefs.getString(AppConstants.keyOwnerId) ?? '';
      final res = await _db.from('users')
          .select()
          .eq('owner_id', ownerId)
          .eq('is_approved', false)
          .order('created_at', ascending: false);
      return res.map((r) => PendingApproval.fromMap(r)).toList();
    } catch (e) { return []; }
  }

  // Cached broadcast stream - safe for multiple listeners
  Stream<List<PendingApproval>>? _stream;
  
  Stream<List<PendingApproval>> pendingApprovalsStream() {
    _stream ??= _createStream().asBroadcastStream();
    return _stream!;
  }

  Stream<List<PendingApproval>> _createStream() async* {
    yield await getPendingApprovals();
    await for (final _ in Stream.periodic(const Duration(seconds: 60))) {
      yield await getPendingApprovals();
    }
  }
}
