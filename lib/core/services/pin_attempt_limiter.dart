import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class PinAttemptStatus {
  final int attempts;
  final DateTime? lockedUntil;
  const PinAttemptStatus(this.attempts, this.lockedUntil);
  bool get locked => lockedUntil != null;
}

class PinLockedException implements Exception {
  final DateTime until;
  const PinLockedException(this.until);
}

/// One serialized limiter for every AuthProvider PIN verification in this app.
/// Existing installation-wide keys are retained, including a lock set earlier.
class PinAttemptLimiter {
  static final instance = PinAttemptLimiter();
  static const attemptsKey = '_pin_attempts';
  static const lockoutKey = '_pin_lockout_until';
  static const maxAttempts = 5;
  static const lockDuration = Duration(minutes: 30);
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  PinAttemptLimiter(
      {Future<SharedPreferences> Function()? preferences,
      DateTime Function()? now})
      : _preferences = preferences ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now;

  PinAttemptStatus _read(SharedPreferences prefs) {
    final untilMs = prefs.getInt(lockoutKey) ?? 0;
    if (untilMs > _now().millisecondsSinceEpoch) {
      return PinAttemptStatus(
          maxAttempts, DateTime.fromMillisecondsSinceEpoch(untilMs));
    }
    final attempts = untilMs > 0
        ? 0
        : (prefs.getInt(attemptsKey) ?? 0).clamp(0, maxAttempts).toInt();
    // Older versions could stop between writing attempt 5 and its deadline.
    if (untilMs <= 0 && attempts >= maxAttempts) {
      return PinAttemptStatus(maxAttempts, _now().add(lockDuration));
    }
    return PinAttemptStatus(attempts, null);
  }

  Future<PinAttemptStatus> _load(SharedPreferences prefs) async {
    final state = _read(prefs);
    if (state.locked && (prefs.getInt(lockoutKey) ?? 0) <= 0) {
      if (!await prefs.setInt(
          lockoutKey, state.lockedUntil!.millisecondsSinceEpoch)) {
        throw StateError('Penguncian PIN belum dapat disimpan.');
      }
    }
    return state;
  }

  Future<PinAttemptStatus> status() =>
      _serial(() async => _load(await _preferences()));

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> verify(Future<bool> Function() checkPin) => _serial(() async {
        final prefs = await _preferences();
        final state = await _load(prefs);
        if (state.locked) throw PinLockedException(state.lockedUntil!);
        if ((prefs.getInt(lockoutKey) ?? 0) > 0) {
          if (!await prefs.remove(lockoutKey) ||
              !await prefs.remove(attemptsKey)) {
            throw StateError('Status percobaan PIN belum dapat disimpan.');
          }
        }
        // Do not attempt verification when persistent limiter state is unwritable.
        if (!await prefs.setInt(attemptsKey, state.attempts)) {
          throw StateError('Status percobaan PIN belum dapat disimpan.');
        }
        final valid = await checkPin();
        if (!valid) {
          final attempts = state.attempts + 1;
          if (attempts >= maxAttempts) {
            if (!await prefs.setInt(
                lockoutKey, _now().add(lockDuration).millisecondsSinceEpoch)) {
              throw StateError('Penguncian PIN belum dapat disimpan.');
            }
          }
          if (!await prefs.setInt(attemptsKey, attempts)) {
            throw StateError('Status percobaan PIN belum dapat disimpan.');
          }
        }
        return valid;
      });

  Future<void> resetAfterSuccess() => _serial(() async {
        final prefs = await _preferences();
        final state = await _load(prefs);
        if (state.locked) throw PinLockedException(state.lockedUntil!);
        if (!await prefs.remove(attemptsKey) ||
            !await prefs.remove(lockoutKey)) {
          throw StateError('Status percobaan PIN belum dapat disimpan.');
        }
      });
}
