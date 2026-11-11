import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/pin_attempt_limiter.dart';
import '../lib/core/services/supabase_auth_service.dart';
import '../lib/core/utils/app_constants.dart';
import '../lib/features/auth/presentation/providers/auth_provider.dart';
import '../lib/features/auth/presentation/screens/pin_verify_screen.dart';
import '../lib/features/cashier/presentation/providers/cashier_provider.dart';
import '../lib/features/menu/data/models/menu_models.dart';
import '../lib/features/retail/data/models/retail_models.dart';
import '../lib/features/retail/presentation/providers/retail_provider.dart';
import '../lib/features/shift/presentation/providers/shift_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 1, 1, 12);
  const product = RetailProduct(
      id: 11,
      branchId: 'branch-a',
      name: 'Dummy A',
      sku: 'DUMMY-A',
      category: 'Dummy',
      sellPrice: 10,
      hpp: 4,
      stock: 2,
      unit: 'pcs',
      createdAt: '2026-01-01');
  const menu = MenuItemModel(
      id: 21,
      branchId: 'branch-a',
      categoryId: 1,
      name: 'Dummy A',
      price: 10,
      createdAt: '2026-01-01');

  setUp(() => SharedPreferences.setMockInitialValues({
        AppConstants.keyUid: 'account-a',
        AppConstants.keyOwnerId: 'owner-a',
        AppConstants.keyBranchId: 'branch-a',
      }));

  AppUserProfile profile(String id) => AppUserProfile(
      authId: id,
      email: '$id@example.invalid',
      name: 'Dummy',
      role: 'kasir',
      ownerId: 'owner-a',
      branchId: 'branch-a',
      branchName: 'Dummy branch',
      branchMode: 'food');

  test(
      'a completed old profile request cannot overwrite or un-coalesce the new login',
      () async {
    final a = Completer<AppUserProfile?>();
    final b = Completer<AppUserProfile?>();
    var reads = 0;
    final auth = AuthProvider(
        sessionReader: () => reads++ == 0 ? a.future : b.future,
        signOut: () async {});
    addTearDown(auth.dispose);
    final oldRequest = auth.checkSession();
    await auth.logout();
    final currentRequest = auth.checkSession();
    a.complete(profile('account-a'));
    await oldRequest;
    expect(auth.currentUser, isNull);
    final duplicateRequest = auth.checkSession();
    expect(identical(currentRequest, duplicateRequest), true);
    b.complete(profile('account-b'));
    await currentRequest;
    expect(reads, 2);
    expect(auth.currentUser!.authId, 'account-b');
  });

  test(
      'logout clears identity immediately and coalesces pending sign-out requests',
      () async {
    final done = Completer<void>();
    var signOuts = 0;
    var reads = 0;
    final auth = AuthProvider(sessionReader: () async {
      reads++;
      return profile('account-a');
    }, signOut: () {
      signOuts++;
      return done.future;
    });
    addTearDown(auth.dispose);
    await auth.checkSession();
    final first = auth.logout();
    final second = auth.logout();
    expect(auth.currentUser, isNull);
    expect(identical(first, second), true);
    await auth.checkSession();
    expect(reads, 1,
        reason: 'old SDK identity must not be reloaded during sign-out');
    done.complete();
    await first;
    expect(signOuts, 1);
    expect(auth.currentUser, isNull);
  });

  test('persisted lock survives a fresh limiter and cannot be reset as success',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PinAttemptLimiter.lockoutKey,
        now.add(const Duration(minutes: 30)).millisecondsSinceEpoch);
    var verifications = 0;
    for (var i = 0; i < 2; i++) {
      final limiter = PinAttemptLimiter(now: () => now);
      await expectLater(limiter.verify(() async {
        verifications++;
        return true;
      }), throwsA(isA<PinLockedException>()));
      await expectLater(
          limiter.resetAfterSuccess(), throwsA(isA<PinLockedException>()));
    }
    expect(verifications, 0);
  });

  test('concurrent fifth and sixth attempts only invoke one verifier',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PinAttemptLimiter.attemptsKey, 4);
    final limiter = PinAttemptLimiter(now: () => now);
    final answer = Completer<bool>();
    var calls = 0;
    final fifth = limiter.verify(() {
      calls++;
      return answer.future;
    });
    final sixth = limiter.verify(() async {
      calls++;
      return true;
    });
    final sixthCheck = expectLater(sixth, throwsA(isA<PinLockedException>()));
    answer.complete(false);
    expect(await fifth, false);
    await sixthCheck;
    expect(calls, 1);
    expect((await limiter.status()).locked, true);
  });

  test('expiry restores attempts; a correct fifth PIN may still succeed',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PinAttemptLimiter.attemptsKey, 5);
    await prefs.setInt(
        PinAttemptLimiter.lockoutKey, now.millisecondsSinceEpoch);
    final limiter = PinAttemptLimiter(now: () => now);
    expect(await limiter.verify(() async => false), false);
    expect((await limiter.status()).attempts, 1);
    await prefs.setInt(PinAttemptLimiter.attemptsKey, 4);
    expect(await limiter.verify(() async => true), true);
    await limiter.resetAfterSuccess();
    expect((await limiter.status()).attempts, 0);
    expect((await limiter.status()).locked, false);
  });

  test('unavailable verifier does not consume a wrong-PIN attempt or jam queue',
      () async {
    final limiter = PinAttemptLimiter(now: () => now);
    await expectLater(
        limiter.verify(() async => throw StateError('dummy unavailable')),
        throwsStateError);
    expect((await limiter.status()).attempts, 0);
    expect(await limiter.verify(() async => false), false);
    expect((await limiter.status()).attempts, 1);
  });

  test('AuthProvider enforces persisted lock before any Auth/DB access',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PinAttemptLimiter.lockoutKey,
        DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch);
    // No Supabase or database is initialized: a lock must stop before either.
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    await expectLater(
        auth.verifyPin('123456'), throwsA(isA<PinLockedException>()));
  });

  testWidgets(
      'a remounted PIN screen disables input/submit during persisted lock',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PinAttemptLimiter.lockoutKey,
        DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch);
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(const MaterialApp(
          home: PinVerifyScreen(userName: 'Dummy', userRole: 'kasir')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '1'))
              .onPressed,
          isNull);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(find.textContaining('Terlalu banyak percobaan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  test('food draft clears immediately on account change and rejects old epoch',
      () async {
    final food = CashierProvider();
    addTearDown(food.dispose);
    food.bindAccount('account-a', 'owner-a');
    final scope = (await food.prepareSession())!;
    await food.addItem(menu);
    final epoch = food.cartSessionEpoch;
    final prefs = await SharedPreferences.getInstance();
    expect(food.cartItems.length, 1);
    food.bindAccount('account-b', 'owner-b');
    expect(food.cartItems, isEmpty);
    expect(food.isCurrentSession(scope, epoch, prefs), false);
    expect(() => food.requireCurrentSession(scope, epoch, prefs),
        throwsStateError);
  });

  test(
      'held table survives clearing its draft but is detached on account switch',
      () async {
    final calls = <Map<String, dynamic>>[];
    final food = CashierProvider(tableRpc: (method, params) async {
      calls.add({'method': method, ...params});
      return null;
    });
    addTearDown(food.dispose);
    food.bindAccount('account-a', 'owner-a');
    await food.prepareSession();
    food.setCurrentTable(7);
    await food.addItem(menu);
    await food.clearDraft();
    await food.addItem(menu);
    expect(calls.length, 3);
    expect(calls[1]['p_items'], isEmpty);
    expect(
        calls.every((call) =>
            call['p_branch_id'] == 'branch-a' && call['p_table_id'] == 7),
        true);
    food.bindAccount('account-b', 'owner-b');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyUid, 'account-b');
    await prefs.setString(AppConstants.keyOwnerId, 'owner-b');
    await prefs.setString(AppConstants.keyBranchId, 'branch-b');
    await food.addItem(const MenuItemModel(
        id: 23,
        branchId: 'branch-b',
        categoryId: 1,
        name: 'Dummy B',
        price: 3,
        createdAt: '2026-01-01'));
    expect(food.cartItems.single.menuItem.name, 'Dummy B');
    expect(calls.length, 3,
        reason: 'new account must not autosave to the old table');
  });

  test('failed table load cannot overwrite held items with a partial new draft',
      () async {
    var reads = 0;
    var writes = 0;
    final food = CashierProvider(tableRpc: (method, params) async {
      if (method == 'get_table_cart') {
        reads++;
        if (reads == 1) throw StateError('dummy unavailable');
        return <Map<String, dynamic>>[];
      }
      writes++;
      return null;
    });
    addTearDown(food.dispose);
    food.bindAccount('account-a', 'owner-a');
    expect(await food.loadTableCart(7, [menu]), false);
    expect(food.tableCartReady, false);
    await expectLater(food.addItem(menu), throwsStateError);
    await expectLater(food.clearDraft(), throwsStateError);
    expect(writes, 0);
    expect(food.cartItems, isEmpty);
    expect(await food.loadTableCart(7, [menu]), true);
    await food.addItem(menu);
    expect(writes, 1);
  });

  test('late table response cannot replace the new account draft', () async {
    final sent = Completer<void>();
    final response = Completer<dynamic>();
    final food = CashierProvider(tableRpc: (method, params) {
      expect(method, 'get_table_cart');
      expect(params['p_branch_id'], 'branch-a');
      sent.complete();
      return response.future;
    });
    addTearDown(food.dispose);
    food.bindAccount('account-a', 'owner-a');
    final load = food.loadTableCart(7, [menu]);
    await sent.future;
    food.bindAccount('account-b', 'owner-b');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyUid, 'account-b');
    await prefs.setString(AppConstants.keyOwnerId, 'owner-b');
    await prefs.setString(AppConstants.keyBranchId, 'branch-b');
    await food.addItem(const MenuItemModel(
        id: 23,
        branchId: 'branch-b',
        categoryId: 1,
        name: 'Dummy B',
        price: 3,
        createdAt: '2026-01-01'));
    response.complete([
      {
        'menu_name': 'Dummy A',
        'menu_price': 10,
        'qty': 1,
        'note': 'Dummy A private'
      }
    ]);
    await load;
    expect(food.cartItems.single.menuItem.name, 'Dummy B');
    expect(food.cartItems.single.note, isNull);
  });

  test('a save waiting for preferences cannot be sent as the next account',
      () async {
    var calls = 0;
    final food = CashierProvider(tableRpc: (method, params) async {
      calls++;
      return null;
    });
    addTearDown(food.dispose);
    food.bindAccount('account-a', 'owner-a');
    await food.prepareSession();
    final save = food.saveTableCart(7);
    food.bindAccount('account-b', 'owner-b');
    await save;
    expect(calls, 0);
  });

  test(
      'legacy fifth-attempt record without deadline becomes a stable persisted lock',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PinAttemptLimiter.attemptsKey, 5);
    var clock = now;
    final limiter = PinAttemptLimiter(now: () => clock);
    final first = await limiter.status();
    clock = clock.add(const Duration(minutes: 1));
    final second = await limiter.status();
    expect(first.locked, true);
    expect(second.lockedUntil, first.lockedUntil);
    var calls = 0;
    await expectLater(limiter.verify(() async {
      calls++;
      return true;
    }), throwsA(isA<PinLockedException>()));
    expect(calls, 0);
  });

  test('same context retains retail draft; changing only branch clears it',
      () async {
    final retail = RetailProvider();
    addTearDown(retail.dispose);
    retail.bindAccount('account-a', 'owner-a');
    final scope = (await retail.prepareSession())!;
    retail.addToCart(product);
    final epoch = retail.cartSessionEpoch;
    await retail.prepareSession();
    expect(identical(scope, retail.cartScope), true);
    expect(retail.cartCount, 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyBranchId, 'branch-b');
    expect(retail.isCurrentSession(scope, epoch, prefs), false);
    await retail.prepareSession();
    expect(retail.cart, isEmpty);
  });

  test('logout/login of the same UID still invalidates an old async result',
      () async {
    final retail = RetailProvider();
    addTearDown(retail.dispose);
    retail.bindAccount('account-a', 'owner-a');
    final before = (await retail.prepareSession())!;
    final epoch = retail.cartSessionEpoch;
    retail.addToCart(product);
    retail.bindAccount('', '');
    expect(retail.cart, isEmpty);
    retail.bindAccount('account-a', 'owner-a');
    await retail.prepareSession();
    expect(
        retail.isCurrentSession(before, retail.cartSessionEpoch,
            await SharedPreferences.getInstance()),
        false);
    expect(
        retail.isCurrentSession(
            before, epoch, await SharedPreferences.getInstance()),
        false);
  });

  test(
      'retail model retains branch and a stale product cannot enter a new branch cart',
      () async {
    final retail = RetailProvider();
    addTearDown(retail.dispose);
    retail.bindAccount('account-a', 'owner-a');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyBranchId, 'branch-b');
    await retail.prepareSession();
    retail.addToCart(product);
    expect(retail.cart, isEmpty);
    final localB =
        RetailProduct.fromMap({...product.toMap(), 'branch_id': 'branch-b'})
            .copyWith(stock: 7);
    expect(localB.branchId, 'branch-b');
    retail.addToCart(localB);
    expect(retail.cart.single.product.branchId, 'branch-b');
  });

  test(
      'profile reassignment or role change invalidates drafts even for the same UID',
      () async {
    final retail = RetailProvider();
    addTearDown(retail.dispose);
    retail.bindAccount('account-a', 'owner-a',
        branchId: 'branch-a', role: 'manajer');
    await retail.prepareSession();
    retail.addToCart(product);
    expect(retail.cartCount, 1);
    retail.bindAccount('account-a', 'owner-a',
        branchId: 'branch-b', role: 'kasir');
    expect(retail.cart, isEmpty);
  });

  test('shift cannot request another principal before any database access',
      () async {
    final shift = ShiftProvider();
    addTearDown(shift.dispose);
    shift.bindAccount('account-a');
    await expectLater(shift.loadActiveShift('account-b'), throwsStateError);
    expect(shift.hasActiveShift, false);
    expect(shift.activeLoadFailed, true);
    expect(shift.activeLoading, false);
  });

  test(
      'foreign food menu is rejected but explicitly global menu remains usable',
      () async {
    final food = CashierProvider();
    addTearDown(food.dispose);
    food.bindAccount('account-a', 'owner-a');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyBranchId, 'branch-b');
    await expectLater(food.addItem(menu), throwsStateError);
    expect(food.cartItems, isEmpty);
    await food.addItem(const MenuItemModel(
        id: 22,
        categoryId: 1,
        name: 'Dummy global',
        price: 5,
        createdAt: '2026-01-01'));
    expect(food.cartItems.single.menuItem.name, 'Dummy global');
  });
}
