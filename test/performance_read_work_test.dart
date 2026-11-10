// In-process tests of production read scheduling, not production traffic.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../lib/core/services/read_work.dart';
import '../lib/core/services/resilient_http_client.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 2));
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw StateError('wait deadline');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class AbortTransport extends http.BaseClient {
  bool closed = false;
  int calls = 0, aborted = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    if (request.url.path.endsWith('/slow')) {
      final done = Completer<http.StreamedResponse>();
      check(request is http.Abortable, 'each production request is abortable');
      (request as http.Abortable).abortTrigger!.then((_) {
        aborted++;
        done.completeError(http.RequestAbortedException(request.url));
      });
      return done.future;
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  }

  @override
  void close() {
    closed = true;
  }
}

Future<void> main() => run().timeout(const Duration(seconds: 8));
Future<void> run() async {
  final flights = ReadFlights<int>();
  var calls = 0;
  final pending = Completer<int>();
  Future<int> read() {
    calls++;
    return pending.future;
  }

  final jobs = List.generate(50, (_) => flights.run('user:branch', read));
  check(
    calls == 1 && jobs.every((f) => identical(f, jobs.first)),
    '50 overlapping reads become one',
  );
  final other = flights.run('other-user:branch', () async => 9);
  pending.complete(7);
  check(
    (await Future.wait(jobs)).every((v) => v == 7) && await other == 9,
    'account keys remain separate',
  );
  check(
    await flights.run('user:branch', () async => 8) == 8,
    'later refresh remains fresh; no stock TTL',
  );
  try {
    await flights.run('failed', () async => throw StateError('temporary'));
  } catch (_) {}
  check(
    await flights.run('failed', () async => 10) == 10,
    'failure releases read gate',
  );
  print(
    'PASS overlapping reads, account isolation, fresh later read, recovery after failure',
  );

  var reads = 0;
  final waiting = <Completer<int>>[];
  final poller = SharedReadPoller<int>(() {
    reads++;
    final done = Completer<int>();
    waiting.add(done);
    return done.future;
  }, interval: const Duration(milliseconds: 12));
  final firstValues = <int>[], secondValues = <int>[];
  final a = poller.stream.listen(firstValues.add);
  final b = poller.stream.listen(secondValues.add);
  check(reads == 1, 'two listeners share pending request');
  await Future<void>.delayed(const Duration(milliseconds: 40));
  check(reads == 1, 'timer cannot overlap a slow read');
  waiting[0].complete(1);
  await until(() => firstValues.length == 1 && secondValues.length == 1);
  await until(() => reads == 2);
  await a.cancel();
  await b.cancel();
  waiting[1].complete(2);
  await Future<void>.delayed(const Duration(milliseconds: 40));
  check(
    reads == 2 && firstValues.length == 1,
    'last cancel stops timer and ignores late result',
  );
  print(
    'PASS shared polling, slow read, last unsubscribe, late result suppression',
  );

  poller.setEnabled(false);
  final resumed = <int>[];
  final c = poller.stream.listen(resumed.add);
  check(reads == 2, 'background subscriber cannot start polling');
  poller.setEnabled(true);
  check(reads == 3, 'foreground resumes immediately');
  poller.setEnabled(false);
  waiting[2].complete(3);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  check(resumed.isEmpty, 'paused result does not reach UI');
  poller.setEnabled(true);
  await until(() => reads == 4);
  waiting[3].complete(4);
  await until(() => resumed.isNotEmpty);
  check(resumed.single == 4, 'fresh result after recovery');
  await c.cancel();
  print('PASS background pause, resume, no stale replay');

  var attempt = 0;
  final values = <int>[], errors = <Object>[];
  final recovering = SharedReadPoller<int>(() async {
    if (++attempt == 1) throw StateError('temporary');
    return attempt;
  }, interval: const Duration(milliseconds: 10));
  final d = recovering.stream.listen(values.add, onError: errors.add);
  await until(() => values.isNotEmpty);
  check(
    errors.length == 1 && values.first == 2,
    'polling recovers after read failure',
  );
  await d.cancel();
  print('PASS read failure does not kill polling permanently');

  var queries = 0;
  final lengths = <int>[];
  final items = await readOrderItemBatches(List.generate(500, (i) => i + 1), (
    sql,
    args,
  ) async {
    queries++;
    lengths.add(args.length);
    check(sql.contains('ORDER BY order_id, id'), 'stable item order');
    return args
        .expand(
          (id) => [
            {'id': (id as int) * 2, 'order_id': id, 'subtotal': 28000},
            {'id': id * 2 + 1, 'order_id': id, 'subtotal': 1000},
          ],
        )
        .toList();
  });
  check(
    queries == 2 && lengths[0] == 400 && lengths[1] == 100,
    '500 item reads become two queries',
  );
  check(
    items.length == 500 &&
        items.values.every(
          (rows) =>
              rows.length == 2 &&
              rows.fold<int>(0, (sum, r) => sum + (r['subtotal'] as int)) ==
                  29000,
        ),
    'all receipt items and amounts retained',
  );
  await readOrderItemBatches([], (_, __) async {
    throw StateError('empty read must not query');
  });
  final deduplicated = await readOrderItemBatches([1, 1], (_, args) async {
    check(args.length == 1, 'duplicate IDs do not duplicate items');
    return [
      {'id': 1, 'order_id': 1},
    ];
  });
  check(deduplicated[1]!.length == 1, 'no duplicate items');
  print(
    'PASS history batching, bind limit, amounts, empty request, duplicate IDs',
  );

  final transport = AbortTransport();
  final client = ResilientHttpClient(
    sharedClient: transport,
    deadline: const Duration(milliseconds: 12),
    sleep: (_) async {},
  );
  await Future.wait([
    client.get(Uri.parse('https://unit.invalid/healthy')),
    client.get(Uri.parse('https://unit.invalid/healthy')),
  ]);
  check(
    !transport.closed && transport.calls == 2,
    'healthy requests reuse one pool',
  );
  try {
    await client.get(Uri.parse('https://unit.invalid/slow'));
  } on TimeoutException {
    /* Timeout is expected. */
  }
  await until(() => transport.aborted == 2);
  check(
    !transport.closed,
    'timeout aborts request without killing shared pool',
  );
  check(
    (await client.get(Uri.parse('https://unit.invalid/healthy'))).statusCode ==
        200,
    'healthy request still works after timeout',
  );
  client.close();
  check(transport.closed, 'app disposal closes the pool');
  print('PASS pooled HTTP, per-attempt abort, timeout recovery, disposal');
  var active = 0, maximum = 0;
  final ordered = await mapReadsBounded<int,int>([1,2,3,4,5,6], (n) async {
    active++; if (active > maximum) maximum = active;
    await Future<void>.delayed(Duration(milliseconds: n.isOdd ? 8 : 1));
    active--; return n*10;
  });
  check(maximum == 2 && active == 0, 'report fan-out capped at two reads');
  check(ordered.join(',') == '10,20,30,40,50,60', 'all branches retained in original order');
  print('PASS bounded report concurrency, complete branch coverage, stable ordering');
}
