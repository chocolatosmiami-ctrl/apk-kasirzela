import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/branch_receipt_branding.dart';
import '../lib/core/utils/app_constants.dart';
import '../lib/features/settings/presentation/providers/settings_provider.dart';

const account = 'dummy-account';
const owner = 'dummy-owner';
const logoA = 'https://example.invalid/branch-a.png';
const logoB = 'https://example.invalid/branch-b.png';
Map<String, dynamic> branding(String? logo, String name) => {
      'logo_url': logo,
      'struk_nama': name,
      'struk_alamat': '',
      'struk_telp': '',
      'struk_footer': '',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyUid: account,
      AppConstants.keyOwnerId: owner,
      AppConstants.keyBranchId: 'a',
      AppConstants.keyBranchName: 'Branch A',
      AppConstants.keyEmail: 'same-user@example.invalid',
    });
    prefs = await SharedPreferences.getInstance();
  });

  test(
      'unknown branch never substitutes owner logo; explicit empty branch logo does',
      () {
    final state = BranchReceiptBranding();
    const scope = ReceiptBrandingScope(account, owner, 'a');
    state.bind(scope);
    expect(state.effectiveLogo('https://example.invalid/owner.png'), isEmpty);
    state.accept(
        state.ticket, BranchReceiptSnapshot(scope, branding(logoA, 'A')));
    expect(state.effectiveLogo('owner-logo'), logoA);
    state.accept(
        state.ticket, BranchReceiptSnapshot(scope, branding(null, 'A')));
    expect(state.effectiveLogo('owner-logo'), 'owner-logo');
  });

  test(
      'cache binds account, owner and branch and rejects corrupt/mismatched identity',
      () {
    const a = ReceiptBrandingScope(account, owner, 'a');
    final saved = BranchReceiptSnapshot(a, branding(logoA, 'A')).encode();
    expect(BranchReceiptSnapshot.decode(saved, a)?.fields['logo_url'], logoA);
    for (final scope in [
      const ReceiptBrandingScope('other', owner, 'a'),
      const ReceiptBrandingScope(account, 'other', 'a'),
      const ReceiptBrandingScope(account, owner, 'b')
    ]) {
      expect(BranchReceiptSnapshot.decode(saved, scope), isNull);
      expect(scope.cacheKey, isNot(a.cacheKey));
    }
    expect(BranchReceiptSnapshot.decode('{broken', a), isNull);
    final invalid = jsonDecode(saved) as Map<String, dynamic>;
    (invalid['fields'] as Map)['logo_url'] = 123;
    expect(BranchReceiptSnapshot.decode(jsonEncode(invalid), a), isNull);
  });

  test('same-email branch switch ignores a late response from previous branch',
      () async {
    final old = Completer<dynamic>();
    final started = Completer<void>();
    final provider = SettingsProvider(branchReader: (branch) {
      if (branch == 'a') {
        started.complete();
        return old.future;
      }
      return Future.value(branding(logoB, 'Branch B'));
    });
    provider.bindAccount(account, owner);
    final first = provider.loadBranchSettings('a');
    await started.future;
    await prefs.setString(AppConstants.keyBranchId, 'b');
    await provider.loadBranchSettings('b');
    expect(provider.effectiveLogoUrl, logoB);
    old.complete(branding(logoA, 'Branch A'));
    await first;
    expect(provider.effectiveLogoUrl, logoB);
    expect(provider.effectiveStoreName, 'Branch B');
    provider.dispose();
  });

  test(
      'A to B to A does not revive the first A request or coalesce it into new A',
      () async {
    final old = Completer<dynamic>();
    final started = Completer<void>();
    var aReads = 0;
    final provider = SettingsProvider(branchReader: (branch) {
      if (branch == 'a' && ++aReads == 1) {
        started.complete();
        return old.future;
      }
      return Future.value(branding(branch == 'a' ? logoA : logoB, branch));
    });
    provider.bindAccount(account, owner);
    final first = provider.loadBranchSettings('a');
    await started.future;
    await prefs.setString(AppConstants.keyBranchId, 'b');
    await provider.loadBranchSettings('b');
    await prefs.setString(AppConstants.keyBranchId, 'a');
    await provider.loadBranchSettings('a');
    expect(aReads, 2);
    expect(provider.effectiveLogoUrl, logoA);
    old.complete(branding('https://example.invalid/stale.png', 'Stale'));
    await first;
    expect(provider.effectiveLogoUrl, logoA);
    expect(provider.effectiveStoreName, 'a');
    provider.dispose();
  });

  test('offline startup restores only the active branch branding', () async {
    const scope = ReceiptBrandingScope(account, owner, 'a');
    await prefs.setString(scope.cacheKey,
        BranchReceiptSnapshot(scope, branding(logoA, 'Cached A')).encode());
    final provider = SettingsProvider(
        branchReader: (_) => Future.error(StateError('offline')));
    provider.bindAccount(account, owner);
    await provider.loadBranchSettings('a');
    expect(provider.effectiveLogoUrl, logoA);
    expect(provider.effectiveStoreName, 'Cached A');
    await prefs.setString(AppConstants.keyBranchId, 'b');
    await provider.loadBranchSettings('b');
    expect(provider.effectiveLogoUrl, isEmpty);
    provider.dispose();
  });

  test('logout clears branding immediately and rejects still-running requests',
      () async {
    final pending = Completer<dynamic>();
    final started = Completer<void>();
    final provider = SettingsProvider(branchReader: (_) {
      started.complete();
      return pending.future;
    });
    provider.bindAccount(account, owner);
    final job = provider.loadBranchSettings('a');
    await started.future;
    provider.bindAccount('', '');
    expect(provider.effectiveLogoUrl, isEmpty);
    pending.complete(branding(logoA, 'Old account'));
    await job;
    expect(provider.effectiveLogoUrl, isEmpty);
    expect(
        prefs.containsKey(
            const ReceiptBrandingScope(account, owner, 'a').cacheKey),
        isFalse);
    provider.dispose();
  });

  test(
      'malformed branch response cannot establish that a branch has no override',
      () async {
    final provider =
        SettingsProvider(branchReader: (_) async => {'logo_url': 123});
    provider.bindAccount(account, owner);
    await provider.loadBranchSettings('a');
    expect(provider.effectiveLogoUrl, isEmpty);
    expect(
        prefs.containsKey(
            const ReceiptBrandingScope(account, owner, 'a').cacheKey),
        isFalse);
    provider.dispose();
  });
}
