import 'dart:async';

/// Only coalesces overlapping reads. Does not cache stock or suppress a later
/// explicit refresh. Identity/branch/filter must be included in the key.
class ReadFlights<T> {
  final _jobs = <String, Future<T>>{};
  Future<T> run(String key, Future<T> Function() read) {
    final existing = _jobs[key];
    if (existing != null) return existing;
    final job = Future<T>.sync(read).whenComplete(() {
      _jobs.remove(key);
    });
    _jobs[key] = job;
    return job;
  }
}

/// Shared read polling with no overlap and no timer without listeners.
/// Each new subscriber requests a fresh read, without replaying another
/// account's previously emitted value. Stop never cancels an in-flight write:
/// this helper is intentionally for reads only.
class SharedReadPoller<T> {
  final Future<T> Function() read;
  final Duration interval;
  Timer? _timer;
  Future<void>? _active;
  bool _enabled = true;
  int _epoch = 0;
  late final _events = StreamController<T>.broadcast(
    onListen: () {
      _epoch++;
    },
    onCancel: () {
      _epoch++;
      _timer?.cancel();
      _timer = null;
    },
  );
  late final Stream<T> stream = Stream<T>.multi((sink) {
    final subscription = _events.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
    unawaited(refresh());
  }, isBroadcast: true);

  SharedReadPoller(this.read, {this.interval = const Duration(seconds: 60)});
  bool get _allowed => _enabled && _events.hasListener;
  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _epoch++;
    _timer?.cancel();
    _timer = null;
    if (_allowed) unawaited(refresh());
  }

  Future<void> refresh() {
    if (!_allowed) return Future.value();
    return _active ??= _poll().whenComplete(() => _active = null);
  }

  Future<void> _poll() async {
    _timer?.cancel();
    final epoch = _epoch;
    try {
      final value = await read();
      if (_allowed && epoch == _epoch) _events.add(value);
    } catch (e, st) {
      if (_allowed && epoch == _epoch) _events.addError(e, st);
    } finally {
      if (_allowed) {
        // A subscriber may arrive while an obsolete read is still finishing.
        _timer = Timer(
          epoch == _epoch ? interval : Duration.zero,
          () => unawaited(refresh()),
        );
      }
    }
  }
}

/// Batches item reads within SQLite's conservative bind-parameter limit.
/// This changes query count, not ordering, receipt IDs, totals or item fields.
Future<Map<int, List<Map<String, dynamic>>>> readOrderItemBatches(
  Iterable<int> orderIds,
  Future<List<Map<String, dynamic>>> Function(String, List<Object?>) query,
) async {
  final ids = orderIds.toSet().toList();
  final result = <int, List<Map<String, dynamic>>>{};
  for (var start = 0; start < ids.length; start += 400) {
    final end = start + 400 < ids.length ? start + 400 : ids.length;
    final chunk = ids.sublist(start, end);
    final rows = await query(
      'SELECT * FROM order_items WHERE order_id IN (${List.filled(chunk.length, '?').join(',')}) ORDER BY order_id, id',
      chunk,
    );
    for (final row in rows) {
      result.putIfAbsent(row['order_id'] as int, () => []).add(row);
    }
  }
  return result;
}

/// Read-only fan-out: fixed worker count, original result ordering, no retries.
Future<List<R>> mapReadsBounded<T, R>(List<T> values,
    Future<R> Function(T) read, {int parallelism = 2}) async {
  if (parallelism < 1) throw ArgumentError.value(parallelism);
  final results = List<R?>.filled(values.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < values.length) {
      final index = next++;
      results[index] = await read(values[index]);
    }
  }
  await Future.wait(List.generate(
      values.length < parallelism ? values.length : parallelism, (_) => worker()));
  return results.cast<R>();
}
