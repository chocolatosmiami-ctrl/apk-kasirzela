/// One checkout owns the gate until its own finally block releases the lease.
class CheckoutGate {
  CheckoutLease? _active;
  bool get isBusy => _active != null;
  CheckoutLease? tryAcquire() {
    if (isBusy) return null;
    return _active = CheckoutLease._(this);
  }
}

class CheckoutLease {
  final CheckoutGate _gate;
  CheckoutLease._(this._gate);
  void release() {
    // Releasing an old lease cannot unlock a newer payment.
    if (identical(_gate._active, this)) _gate._active = null;
  }
}
