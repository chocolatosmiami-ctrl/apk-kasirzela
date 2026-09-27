// App-wide constants — single source of truth
// BUG 17 FIX: Semua file menggunakan konstanta ini, bukan string hardcoded.
class AppConstants {
  // Subscription pricing
  static const double costPerTransaction = 500.0;
  static const double trialBalance       = 25000.0;
  static const int    trialTransactions  = 166;
  static const double superAdminBalance  = 999999.0;
  static const double warningThreshold   = 15000.0;

  // Roles
  static const String roleSuperAdmin = 'superadmin';
  static const String roleOwner      = 'owner';
  static const String roleManajer    = 'manajer';
  static const String roleKasir      = 'kasir';

  // Branch modes
  static const String modeFood   = 'food';
  static const String modeRetail = 'retail';

  // SharedPreferences keys
  static const String keyUid        = 'sb_uid';   // auth_id dari Supabase Auth
  static const String keyAuthId     = 'sb_uid';   // alias, sama dengan keyUid
  static const String keyUsersId    = 'sb_users_id'; // id dari tabel public.users
  static const String keyName       = 'sb_name';
  static const String keyEmail      = 'sb_email';
  static const String keyRole       = 'sb_role';
  static const String keyOwnerId    = 'sb_owner_id';
  static const String keyBranchId   = 'sb_branch_id';
  static const String keyBranchName = 'sb_branch_name';
  static const String keyBranchMode = 'branch_mode';
  static const String keyKasirName  = 'kasir_name';
  static const String keyPinHash    = 'sb_pin_hash';

  // Pagination
  static const int defaultPageSize = 50;

  // PIN
  static const int pinMinLength   = 4;
  static const int pinMaxLength   = 6;
  static const int maxPinAttempts = 5;
}