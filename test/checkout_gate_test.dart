import '../lib/core/services/checkout_gate.dart';
void check(bool ok, String reason) { if (!ok) throw StateError(reason); }

Future<void> main() async {
  final gate = CheckoutGate();
  for (final scenario in ['stock rejection', 'identity failure', 'database failure']) {
    final lease = gate.tryAcquire()!;
    check(gate.isBusy && gate.tryAcquire() == null, 'Concurrent payment must be blocked');
    try { throw StateError(scenario); } catch (_) {} finally { lease.release(); }
    check(!gate.isBusy, 'Failure must not leave checkout locked: ' + scenario);
    final retry = gate.tryAcquire()!;
    lease.release();
    check(gate.isBusy, 'An old lease must not unlock a new payment');
    retry.release();
  }
  final success = gate.tryAcquire()!;
  try { await Future<void>.value(); } finally { success.release(); }
  check(!gate.isBusy, 'Successful payment must release checkout');
  print('PASS: failures/retry, successful payment, overlap protection, stale lease isolation');
}
