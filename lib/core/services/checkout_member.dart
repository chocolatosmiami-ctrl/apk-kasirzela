import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'cart_session.dart';

class CheckoutMember {
  final CartScope scope;
  final int epoch;
  final String customerId, number, name;
  final num? points;
  const CheckoutMember(
      {required this.scope,
      required this.epoch,
      required this.customerId,
      required this.number,
      required this.name,
      this.points});

  bool matches(CartScope current, int currentEpoch) =>
      identical(scope, current) && epoch == currentEpoch;
  Map<String, dynamic> toPayload() => {
        'customer_id': customerId,
        'member_number': number,
        'member_name': name,
      };
}

typedef MemberLookup = Future<Map<String, dynamic>> Function(
    CartScope scope, String number);

/// Selection belongs to one account/branch/session and never grants a discount.
class CheckoutMemberController extends ChangeNotifier {
  final SessionBoundCart cart;
  final MemberLookup lookup;
  final input = TextEditingController();
  CheckoutMember? _member;
  CartScope? _scope;
  int _ticket = 0;
  bool _disposed = false;
  String _lastText = '';
  bool busy = false;
  String? error;

  CheckoutMemberController({required this.cart, MemberLookup? lookup})
      : lookup = lookup ?? _lookup {
    _scope = cart.cartScope;
    (cart as ChangeNotifier).addListener(_sessionChanged);
    input.addListener(_inputChanged);
  }

  CheckoutMember? get selected {
    final scope = cart.cartScope;
    return scope != null &&
            _member?.matches(scope, cart.cartSessionEpoch) == true
        ? _member
        : null;
  }

  bool get ready => !busy && (input.text.trim().isEmpty || selected != null);

  void _inputChanged() {
    if (input.text == _lastText) return;
    _lastText = input.text;
    _ticket++;
    _member = null;
    error = null;
    busy = false;
    notifyListeners();
  }

  void _sessionChanged() {
    if (identical(_scope, cart.cartScope)) return;
    _scope = cart.cartScope;
    clear();
  }

  void clear() {
    _ticket++;
    _member = null;
    error = null;
    busy = false;
    if (input.text.isNotEmpty) {
      input.clear();
    } else {
      notifyListeners();
    }
  }

  Future<void> verify() async {
    if (busy) return;
    final number = input.text.trim();
    final scope = cart.cartScope;
    if (!RegExp(r'^\d{6}$').hasMatch(number)) {
      error = 'Kode member harus 6 digit.';
      notifyListeners();
      return;
    }
    if (scope == null || scope.branchId.isEmpty) {
      error = 'Buka ulang pembayaran pada cabang aktif.';
      notifyListeners();
      return;
    }
    final epoch = cart.cartSessionEpoch;
    final ticket = ++_ticket;
    bool current() =>
        !_disposed &&
        ticket == _ticket &&
        identical(scope, cart.cartScope) &&
        epoch == cart.cartSessionEpoch;
    busy = true;
    error = null;
    _member = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      cart.requireCurrentSession(scope, epoch, prefs);
      final row = await lookup(scope, number);
      if (!current()) return;
      cart.requireCurrentSession(scope, epoch, prefs);
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty ||
          row['member_number']?.toString() != number ||
          row['nama'] is! String ||
          (row['nama'] as String).trim().isEmpty) {
        throw StateError('Invalid member response');
      }
      final points = row['poin'];
      _member = CheckoutMember(
          scope: scope,
          epoch: epoch,
          customerId: id,
          number: number,
          name: row['nama'] as String,
          points: points is num && points.isFinite ? points : null);
    } catch (e) {
      if (!current()) return;
      error = e is PostgrestException && e.code == '22023'
          ? 'Kode member tidak ditemukan pada usaha ini.'
          : e is PostgrestException && e.code == '42501'
              ? 'Akun belum diizinkan memeriksa member di cabang ini.'
              : 'Member belum dapat diverifikasi. Coba lagi atau hapus kode untuk melanjutkan.';
    } finally {
      if (current()) {
        busy = false;
        notifyListeners();
      }
    }
  }

  static Future<Map<String, dynamic>> _lookup(
      CartScope scope, String number) async {
    final client = SupabaseConfig.client;
    if (client.auth.currentUser?.id != scope.accountId)
      throw StateError('Session changed');
    final result = await client.rpc('zela_member_lookup', params: {
      'p_branch_id': scope.branchId,
      'p_member_number': number,
    }).timeout(const Duration(seconds: 12));
    if (client.auth.currentUser?.id != scope.accountId || result is! Map) {
      throw StateError('Session or member response changed');
    }
    return Map<String, dynamic>.from(result);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticket++;
    (cart as ChangeNotifier).removeListener(_sessionChanged);
    input.removeListener(_inputChanged);
    input.dispose();
    super.dispose();
  }
}
