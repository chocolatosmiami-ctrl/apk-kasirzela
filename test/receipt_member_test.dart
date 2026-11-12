import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/receipt_member.dart';
import '../lib/features/orders/data/models/order_models.dart';

void main() {
  const identity = {'member_name': 'Member uji', 'member_number': '001234'};
  const base = {
    'id': 7,
    'order_number': 'TEST-7',
    'cashier_id': 'dummy-account',
    'branch_id': 'dummy-branch',
    'total': 2000,
    'service_charge_amount': 100,
    'created_at': '2026-01-01T10:00:00+07:00',
    'updated_at': '2026-01-01T10:00:00+07:00'
  };
  const payload = {
    'version': 1,
    'order_number': 'TEST-7',
    'account_id': 'dummy-account',
    'branch_id': 'dummy-branch',
    ...identity
  };
  List<String> lines(ReceiptMemberData data) =>
      data.rows.map((e) => '${e.key}: ${e.value}').toList();
  test(
      'member receipt keeps name and leading zeros; ordinary receipt omits both',
      () {
    expect(lines(ReceiptMemberData.fromRecord({...base, ...identity})),
        ['Nama member: Member uji', 'No. member: 001234']);
    expect(ReceiptMemberData.fromRecord(base).rows, isEmpty);
  });
  test(
      'durable pending or acknowledged payload is usable only for same receipt',
      () {
    expect(
        lines(ReceiptMemberData.fromRecord(
            {...base, 'receipt_member_payload': jsonEncode(payload)})).last,
        'No. member: 001234');
    for (final change in [
      {'order_number': 'OTHER'},
      {'account_id': 'other-account'},
      {'branch_id': 'other-branch'},
      {'version': 2},
      {'member_number': '1234'},
    ]) {
      expect(
          ReceiptMemberData.fromRecord({
            ...base,
            'receipt_member_payload': jsonEncode({...payload, ...change})
          }).rows,
          isEmpty);
    }
    expect(
        ReceiptMemberData.fromRecord(
            {...base, 'receipt_member_payload': '{broken'}).rows,
        isEmpty);
  });
  test(
      'control characters cannot insert printer commands or extra receipt lines',
      () {
    expect(
        lines(ReceiptMemberData.fromRecord(
            {...identity, 'member_name': 'Uji\n\x1b@Member'})).first,
        'Nama member: Uji  @Member');
  });
  test('reprint enrichment preserves local financial data and identifiers', () {
    final local = OrderModel.fromMap(base);
    final server =
        OrderModel.fromMap({...base, ...identity, 'id': 999, 'total': 1});
    final receipt = local.withReceiptMemberFrom(server);
    expect(receipt.memberName, 'Member uji');
    expect(receipt.memberNumber, '001234');
    expect(receipt.id, 7);
    expect(receipt.total, 2000);
    expect(receipt.serviceChargeAmount, 100);
    expect(identical(receipt.items, local.items), isTrue);
    expect(receipt.toMap().containsKey('member_number'), isFalse);
    expect(
        identical(
            local.withReceiptMemberFrom(OrderModel.fromMap(
                {...base, ...identity, 'cashier_id': 'other-account'})),
            local),
        isTrue);
    expect(
        identical(
            local.withReceiptMemberFrom(OrderModel.fromMap(
                {...base, ...identity, 'order_number': 'OTHER'})),
            local),
        isTrue);
  });
}
