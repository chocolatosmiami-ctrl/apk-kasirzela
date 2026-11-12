import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'startup_policy.dart';

/// Total per-attempt deadline covers headers AND body. Production reuses one
/// connection pool; AbortableRequest cancels only the timed-out attempt.
/// Future.timeout alone does not abort I/O (or undo a server commit).
class ResilientHttpClient extends http.BaseClient {
  final http.Client Function() createClient;
  final http.Client? _shared;
  final Duration deadline;
  final Duration authenticationDeadline;
  final Future<void> Function(Duration) sleep;
  final double Function() random;
  final void Function(String, int, int, FailureKind?)? diagnostic;
  final Set<http.Client> _active = {};
  final Set<Completer<void>> _aborts = {};
  bool _closed = false;
  ResilientHttpClient({
    http.Client Function()? createClient,
    http.Client? sharedClient,
    Duration? deadline,
    Duration? authenticationDeadline,
    Future<void> Function(Duration)? sleep,
    double Function()? random,
    this.diagnostic,
  }) : assert(createClient == null || sharedClient == null),
       deadline = deadline ?? const Duration(seconds: 5),
       authenticationDeadline = authenticationDeadline ?? deadline ?? LoginTimeouts.request,
       _shared = sharedClient ?? (createClient == null ? http.Client() : null),
       createClient = createClient ?? http.Client.new,
       sleep = sleep ?? Future<void>.delayed,
       random = random ?? Random().nextDouble;

  static const readRpcs = {
    'zela_member_lookup',
    'get_menu_components',
    'get_menu_stock_today',
    'get_role_permissions',
    'get_owner_settings',
    'get_branch_print_settings_by_id',
    'get_staff_by_email',
    'get_user_pin_hash',
    'get_subscription_balance',
    'get_owner_by_branch',
    'get_table_cart',
    'get_restaurant_tables',
  };
  static const diagnosticTables = {
    'menu_items', 'categories', 'owners', 'users', 'branches',
    'subscriptions', 'wa_bot_tenants',
  };
  static bool safeRead(String method, Uri url) =>
      method == 'GET' ||
      method == 'HEAD' ||
      (method == 'POST' &&
          url.path.startsWith('/rest/v1/rpc/') &&
          readRpcs.contains(url.pathSegments.last));

  Duration deadlineFor(Uri url) =>
      url.path.startsWith('/auth/v1/') ||
          url.path == '/functions/v1/legacy-staff-login'
      ? authenticationDeadline : deadline;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Transport closed');
    final requestDeadline = deadlineFor(request.url);
    final bytes = await request.finalize().toBytes().timeout(requestDeadline);
    final limit = safeRead(request.method, request.url) ? 2 : 1;
    // Only endpoint family/name, never query parameters, headers or bodies.
    final stage = request.url.path.startsWith('/rest/v1/rpc/')
        ? 'rpc.${readRpcs.contains(request.url.pathSegments.last) ? request.url.pathSegments.last : 'write'}'
        : request.url.path.startsWith('/auth/')
        ? 'auth'
        : request.url.path.startsWith('/rest/v1/') &&
              diagnosticTables.contains(request.url.pathSegments.last)
        ? 'rest.${request.url.pathSegments.last}'
        : 'rest';
    for (var attempt = 1; ; attempt++) {
      if (_closed) throw http.ClientException('Transport closed');
      final client = _shared ?? createClient();
      final abort = Completer<void>();
      _aborts.add(abort);
      _active.add(client);
      final watch = Stopwatch()..start();
      try {
        final clone = http.AbortableRequest(request.method, request.url,
            abortTrigger: abort.future)
          ..headers.addAll(request.headers)
          ..bodyBytes = bytes
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects;
        clone.persistentConnection = request.persistentConnection;
        final response = await (() async {
          final streamed = await client.send(clone);
          return http.Response.fromStream(streamed);
        })().timeout(requestDeadline);
        final bad = response.statusCode >= 500;
        diagnostic?.call(
          stage,
          attempt,
          watch.elapsedMilliseconds,
          bad ? FailureKind.server : null,
        );
        if (!bad || attempt == limit) {
          return http.StreamedResponse(
            Stream.value(response.bodyBytes),
            response.statusCode,
            headers: response.headers,
            reasonPhrase: response.reasonPhrase,
            request: request,
            contentLength: response.bodyBytes.length,
          );
        }
      } catch (e) {
        diagnostic?.call(
          stage,
          attempt,
          watch.elapsedMilliseconds,
          failureKind(e),
        );
        if (attempt == limit) rethrow;
      } finally {
        if (!abort.isCompleted) abort.complete();
        _aborts.remove(abort);
        _active.remove(client);
        if (_shared == null) client.close();
      }
      await sleep(
        Duration(
          milliseconds: (250 * pow(2, attempt - 1) * (0.75 + random() * 0.5))
              .round(),
        ),
      );
    }
  }

  @override
  void close() {
    _closed = true;
    for (final abort in _aborts.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    _aborts.clear();
    _shared?.close();
    for (final client in _active.toList()) {
      if (!identical(client, _shared)) client.close();
    }
    _active.clear();
  }
}
