import '../lib/core/services/receipt_sync_state.dart';
void check(bool ok, String message) { if (!ok) throw StateError(message); }
void main() {
  const base = {'local_saved': true, 'state': 'pending', 'session_present': true, 'same_account': true};
  check(!const ReceiptSyncState(base).confirmed, 'Local payment is not server confirmation');
  check(const ReceiptSyncState(base).message.contains('Jangan bayar ulang'), 'No duplicate payment');
  check(ReceiptSyncState({...base, 'state': 'done'}).confirmed, 'Only acknowledgment confirms');
  check(ReceiptSyncState({...base, 'session_present': false}).message.contains('Login online'), 'Signed-out queue is actionable');
  check(ReceiptSyncState({...base, 'same_account': false}).message.contains('akun lain'), 'Account isolation remains visible');
  check(ReceiptSyncState({...base, 'state': null}).message.contains('antrean'), 'Missing outbox is distinct');
  final report = const ReceiptSyncState({...base, 'account_id': 'PRIVATE', 'last_error': 'stock missing'}).report;
  check(!report.contains('PRIVATE') && report.contains('stock missing'), 'Report only includes approved diagnostic fields');
  print('PASS: local versus server confirmation, auth missing, account mismatch, missing outbox, diagnostic fields');
}
