import '../lib/core/services/checkout_diagnostic.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final missing = CheckoutDiagnostic.fromError(
    Exception("no such table: order_sync_outbox (code 1) sql 'INSERT SECRET_NOTE' args [PRIVATE_PHONE]"),
    stage: 'local_outbox');
  check(missing.code == 'LOCAL_TABLE_MISSING', 'Missing queue must be classified');
  check(!missing.report.contains('SECRET_NOTE') && !missing.report.contains('PRIVATE_PHONE'),
    'Receipt SQL/arguments must not be copied');
  check(missing.report.contains('order_sync_outbox'), 'Keep the useful missing table name');
  check(missing.report.contains('local_outbox'), 'Keep the failing stage');
  final column = CheckoutDiagnostic.fromError(
    Exception('table orders has no column named cashier_name'), stage: 'local_order');
  check(column.code == 'LOCAL_COLUMN_MISSING', 'Legacy schema must be distinguishable');
  final id = CheckoutDiagnostic.fromError(
    StateError('Identitas akun/cabang kosong. Login dan pilih cabang dahulu.'), stage: 'local_outbox');
  check(id.code == 'IDENTITY_MISSING', 'Legacy staff identity failure must be explicit');
  final token = CheckoutDiagnostic.fromError(
    Exception('Bearer private-access-token eyJhbGciOiJIUzI1NiJ9.abc123.signature'),
    stage: 'session');
  check(!token.report.contains('private-access-token') && !token.report.contains('eyJhbGci'),
    'Do not expose access tokens');
  final saved = CheckoutDiagnostic.fromError(Exception('model parse failed'),
    stage: 'receipt_model', receiptSaved: true, orderNumber: 'TEST-RECEIPT');
  check(saved.userMessage.contains('Jangan lakukan pembayaran ulang'),
    'Post-commit failure must not prompt a duplicate payment');
  check(saved.report.contains('Receipt lokal tersimpan: YA'), 'Record successful local commit');
  final foreignKey = CheckoutDiagnostic.fromError(
    Exception('FOREIGN KEY constraint failed'), stage: 'local_items');
  check(foreignKey.code == 'LOCAL_FOREIGN_KEY', 'Missing related data must be explicit');
  final number = CheckoutDiagnostic.fromError(
    Exception("type 'double' is not a subtype of type 'int'"), stage: 'local_menu_stock');
  check(number.code == 'LOCAL_DATA_TYPE', 'Numeric conversion issue must be explicit');
  print('PASS: table/column/identity/FK/type errors, failing stage, SQL argument redaction, token redaction, post-commit duplicate prevention message');
}
