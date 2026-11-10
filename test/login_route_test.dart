import '../lib/core/services/login_route.dart';
void check(bool value, String message) { if (!value) throw StateError(message); }
void main() {
  for (final role in ['kasir', 'manajer', 'admin', ' KASIR ']) {
    check(usesStaffLogin(role), 'Staff must use migration/Auth flow regardless of tile');
  }
  for (final role in ['owner', 'superadmin', '', 'unknown', null]) {
    check(!usesStaffLogin(role), 'Unknown or owner must not be granted a staff role');
  }
  check(requiresFirstOnlineLogin(''), 'Legacy PIN-only identity must return to password login');
  check(!requiresFirstOnlineLogin('existing-auth-id'), 'Known offline identity remains available');
  check(canUseCachedIdentity('a', 'a'), 'Same-account cache may recover after network failure');
  check(canUseCachedIdentity('a', ''), 'Offline identity is retained');
  check(!canUseCachedIdentity('a', 'b'), 'Never show previous cashier cache under another session');
  check(!canUseCachedIdentity('', 'b'), 'Empty legacy UID cannot impersonate server user');
  check(needsServerLogin(false, true, null), 'Missing Auth session needs password login');
  check(!needsServerLogin(true, true, 'PostgrestException JWT expired PGRST301'), 'Expired access token during refresh outage is not a revoked session');
  check(!needsServerLogin(true, true, 'network down'), 'Network failure is not invalid credentials');
  check(!needsServerLogin(true, true, 'stock missing'), 'Stock conflict is not invalid credentials');
  check(!needsServerLogin(false, false, null), 'Do not prompt brand-new signed-out user');
  print('PASS: staff/owner routing, unknown role, first online login versus offline identity');
}
