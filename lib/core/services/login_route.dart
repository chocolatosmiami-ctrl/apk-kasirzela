/// The entry tile is a presentation choice, never the account's role.
bool usesStaffLogin(String? role) => const {'kasir', 'manajer', 'admin'}
    .contains(role?.trim().toLowerCase());

bool requiresFirstOnlineLogin(String authId) => authId.trim().isEmpty;

bool canUseCachedIdentity(String cachedUid, String serverUid) =>
    serverUid.isEmpty || (cachedUid.isNotEmpty && cachedUid == serverUid);

bool needsServerLogin(bool hasUser, bool hasCachedAccount, String? error) {
  if (!hasUser && hasCachedAccount) return true;
  final message = error?.toLowerCase() ?? '';
  return const ['invalid refresh token', 'refresh_token_not_found',
      'session_not_found', 'login kembali dengan akun pembuat']
      .any(message.contains);
}
