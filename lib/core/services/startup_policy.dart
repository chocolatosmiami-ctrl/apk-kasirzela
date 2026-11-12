import 'dart:async';
import 'dart:io';

enum FailureKind { timeout, network, server, invalidSession, denied, unknown }

FailureKind failureKind(Object error) {
  if (error is TimeoutException) return FailureKind.timeout;
  if (error is SocketException || error is HandshakeException)
    return FailureKind.network;
  // Read only well-known fields; never log exception messages/HTTP bodies.
  String code = '', status = '';
  try {
    code = (error as dynamic).code?.toString() ?? '';
  } catch (_) {}
  try {
    status = (error as dynamic).statusCode?.toString() ?? '';
  } catch (_) {}
  final n = int.tryParse(status) ?? int.tryParse(code);
  if (n != null && n >= 500) return FailureKind.server;
  if (const [
    'refresh_token_not_found',
    'refresh_token_already_used',
    'session_not_found',
    'user_banned',
    'user_not_found',
  ].contains(code))
    return FailureKind.invalidSession;
  if (code == '42501' || status == '403') return FailureKind.denied;
  return FailureKind.unknown;
}

bool validCacheAge(DateTime? verified, DateTime now) =>
    verified != null &&
    !now.isBefore(verified) &&
    now.difference(verified) <= const Duration(hours: 24);

/// Fixed diagnostic labels only: never show exception bodies, JWTs or URLs.
String startupFailureCode(Object error) {
  final kind = failureKind(error);
  if (kind == FailureKind.timeout) return 'STARTUP_TIMEOUT';
  if (kind == FailureKind.network) return 'STARTUP_NETWORK';
  if (kind == FailureKind.server) return 'STARTUP_SERVICE';
  if (kind == FailureKind.invalidSession) return 'STARTUP_SIGN_IN';
  if (kind == FailureKind.denied) return 'STARTUP_ACCESS';
  String code = '';
  try { code = (error as dynamic).code?.toString() ?? ''; } catch (_) {}
  if (const {'PGRST200', 'PGRST201', 'PGRST204', '42703', '42P01'}.contains(code)) {
    return 'PROFILE_CONFIGURATION';
  }
  if (const {'PGRST301', 'PGRST302', 'PGRST303', 'bad_jwt', 'jwt_expired'}.contains(code)) {
    return 'STARTUP_SIGN_IN';
  }
  return 'STARTUP_UNKNOWN';
}

String startupFailureMessage(String code) {
  if (code == 'STARTUP_SIGN_IN') {
    return 'Sesi server perlu diperbarui. Pilih Login kembali dan masuk dengan akun Anda. '
        'Transaksi tersimpan tetap dipertahankan.';
  }
  if (code == 'STARTUP_ACCESS') {
    return 'Profil belum dapat diakses. Login kembali atau hubungi owner untuk memeriksa hak akses akun.';
  }
  if (code == 'PROFILE_CONFIGURATION') {
    return 'Profil belum dapat dimuat karena konfigurasi data server. '
        'Hubungi pengelola aplikasi dan sertakan kode di bawah.';
  }
  if (const {'STARTUP_TIMEOUT', 'STARTUP_NETWORK', 'STARTUP_SERVICE'}.contains(code)) {
    return 'Koneksi ke layanan belum berhasil. Periksa jaringan lalu coba lagi. '
        'Anda juga dapat membuka halaman login tanpa menghapus transaksi tersimpan.';
  }
  return 'Sesi tersimpan belum dapat diverifikasi. Coba lagi atau pilih Login kembali. '
      'Jika tetap gagal, sertakan kode di bawah saat menghubungi pengelola.';
}

bool canUseProfileCache(
  Map<String, dynamic> row,
  String uid,
  DateTime? verified,
  DateTime now,
) =>
    uid.isNotEmpty &&
    row['auth_id'] == uid &&
    row['is_active'] == true &&
    row['is_approved'] == true &&
    validCacheAge(verified, now);

/// A UI timeout is not cancellation. Callers must test this ticket after await
/// and before navigation/cache writes; a superseded operation is never applied.
class AttemptEpoch {
  int _value = 0;
  bool _disposed = false;
  int begin() => ++_value;
  bool current(int ticket) => !_disposed && ticket == _value;
  void dispose() {
    _disposed = true;
    _value++;
  }
}

/// Catch detached work explicitly; auxiliary data must not fail its siblings.
Future<void> supplemental(
  String stage,
  Future<void> Function() task, {
  void Function(String, FailureKind)? log,
}) async {
  try {
    await task().timeout(const Duration(seconds: 15));
  } catch (e) {
    log?.call(stage, failureKind(e));
  }
}

/// Coalesce repeated taps/reconnect events; failures release the next attempt.
class SingleFlight {
  Future<void>? _active;
  bool get running => _active != null;
  Future<void> run(Future<void> Function() operation) => _active ??=
      Future<void>.sync(operation).whenComplete(() => _active = null);
}
