import 'dart:async';
import 'package:flutter/foundation.dart';
import 'startup_policy.dart';

class ServiceHealth extends ChangeNotifier {
  static final instance = ServiceHealth();
  final Map<String, FailureKind> failures = {};
  bool cachedProfile = false;
  bool get connectionFailure =>
      cachedProfile ||
      failures.values.any(
        (kind) => const {
          FailureKind.timeout,
          FailureKind.network,
          FailureKind.server,
        }.contains(kind),
      );
  bool get degraded => cachedProfile || failures.isNotEmpty;
  final _recovery = SingleFlight();
  bool get retrying => _recovery.running;
  void record(String stage, FailureKind? failure) {
    if (failure == null) {
      failures.remove(stage);
    } else {
      failures[stage] = failure;
    }
    // HTTP callbacks can arrive during build; batch notifications after this turn.
    scheduleMicrotask(notifyListeners);
  }

  void profileCache(bool value) {
    cachedProfile = value;
    scheduleMicrotask(notifyListeners);
  }

  Future<void> Function()? pageRefresh;
  Future<void> retry(Future<void> Function() operation) {
    final future = _recovery.run(() async {
      try {
        await operation();
        failures.remove('recovery');
      } catch (e) {
        log('recovery', 1, 0, failureKind(e));
      } finally {
        scheduleMicrotask(notifyListeners);
      }
    });
    scheduleMicrotask(notifyListeners);
    return future.whenComplete(() => scheduleMicrotask(notifyListeners));
  }

  static void log(
    String stage,
    int attempt,
    int milliseconds,
    FailureKind? failure,
  ) {
    trace(stage, attempt, milliseconds, failure);
    instance.record(stage, failure);
  }
  static void trace(String stage, int attempt, int milliseconds, FailureKind? failure) {
    debugPrint('startup stage=$stage attempt=$attempt ms=$milliseconds result=${failure?.name ?? 'ok'}');
  }
}
