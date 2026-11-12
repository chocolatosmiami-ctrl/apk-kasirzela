import 'dart:convert';

/// Member identity recorded on this receipt, never the currently selected cart.
class ReceiptMemberData {
  final String? name, number;
  const ReceiptMemberData({this.name, this.number});

  static String? _text(dynamic value) {
    if (value is! String) return null;
    final text = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    return text.isEmpty ? null : text;
  }

  static ReceiptMemberData _fields(Map<dynamic, dynamic> row) {
    final number = _text(row['member_number']);
    if (number == null || !RegExp(r'^\d{6}$').hasMatch(number)) {
      return const ReceiptMemberData();
    }
    return ReceiptMemberData(name: _text(row['member_name']), number: number);
  }

  factory ReceiptMemberData.fromRecord(Map<String, dynamic> row) {
    final direct = _fields(row);
    if (direct.number != null) return direct;
    final raw = row['receipt_member_payload'];
    if (raw is! String || raw.isEmpty) return direct;
    try {
      final payload = jsonDecode(raw);
      if (payload is! Map ||
          payload['version'] != 1 ||
          (row['order_number']?.toString() ?? '').isEmpty ||
          (row['cashier_id']?.toString() ?? '').isEmpty ||
          (row['branch_id']?.toString() ?? '').isEmpty ||
          payload['order_number'] != row['order_number'] ||
          payload['account_id'] != row['cashier_id']?.toString() ||
          payload['branch_id'] != row['branch_id']?.toString()) return direct;
      return _fields(payload);
    } catch (_) {
      return direct;
    }
  }

  List<MapEntry<String, String>> get rows {
    final checked = _fields({'member_name': name, 'member_number': number});
    return [
      if (checked.number != null) ...[
        if (checked.name != null) MapEntry('Nama member', checked.name!),
        MapEntry('No. member', checked.number!),
      ],
    ];
  }
}
