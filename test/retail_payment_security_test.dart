import '../lib/core/services/checkout_member.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../lib/core/services/offline_grace_manager.dart';
import '../lib/features/auth/presentation/providers/auth_provider.dart';
import '../lib/features/retail/data/models/retail_models.dart';
import '../lib/features/retail/presentation/providers/retail_provider.dart';
import '../lib/features/retail/presentation/screens/retail_checkout_screen.dart';
import '../lib/features/subscription/presentation/providers/subscription_provider.dart';

class _RetailFixture extends RetailProvider {
  final bool empty;
  int checkoutCalls = 0;
  _RetailFixture({this.empty = false});
  @override
  Future<bool> checkout(
      {required String paymentMethod,
      required double paidAmount,
      required String cashierId,
      double discountTotal = 0,
      CheckoutMember? member}) async {
    checkoutCalls++;
    return false;
  }

  @override
  bool get cartEmpty => empty;
  @override
  double get cartTotal => empty ? 0 : 10000;
  @override
  List<RetailCartItem> get cart => empty
      ? []
      : [
          RetailCartItem(
              product: const RetailProduct(
                  id: 1,
                  name: 'Dummy',
                  sku: 'DUMMY',
                  category: 'Dummy',
                  sellPrice: 10000,
                  hpp: 4000,
                  stock: 2,
                  unit: 'pcs',
                  createdAt: '2026-01-01'),
              qty: 1,
              selectedUnit: 'pcs',
              unitPrice: 10000)
        ];
}

class _SubscriptionFixture extends SubscriptionProvider {
  int calls = 0;
  final response = Completer<TransactionPermission>();
  @override
  Future<TransactionPermission> checkAndDeduct() {
    calls++;
    return response.future;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, _RetailFixture retail,
      _SubscriptionFixture sub) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<RetailProvider>.value(value: retail),
      ChangeNotifierProvider<SubscriptionProvider>.value(value: sub),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ], child: const MaterialApp(home: RetailCheckoutScreen())));
    await tester.pump();
  }

  testWidgets('underpaid retail cash never records a subscription transaction',
      (tester) async {
    final retail = _RetailFixture();
    final sub = _SubscriptionFixture();
    addTearDown(retail.dispose);
    addTearDown(sub.dispose);
    await mount(tester, retail, sub);
    await tester.enterText(find.byType(TextField).last, '1');
    final pay = find.byType(ElevatedButton).last;
    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.pump();
    expect(sub.calls, 0);
    expect(find.textContaining('Uang kurang'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty retail cart cannot consume subscription credit',
      (tester) async {
    final retail = _RetailFixture(empty: true);
    final sub = _SubscriptionFixture();
    addTearDown(retail.dispose);
    addTearDown(sub.dispose);
    await mount(tester, retail, sub);
    final pay = find.byType(ElevatedButton).last;
    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.pump();
    expect(sub.calls, 0);
    expect(
        find.textContaining('Keranjang atau total pembayaran'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated taps during admission make only one subscription call',
      (tester) async {
    final retail = _RetailFixture();
    final sub = _SubscriptionFixture();
    addTearDown(retail.dispose);
    addTearDown(sub.dispose);
    await mount(tester, retail, sub);
    await tester.enterText(find.byType(TextField).last, '10000');
    final pay = find.byType(ElevatedButton).last;
    await tester.ensureVisible(pay);
    // Invoke the same pre-rebuild callback twice to exercise the handler guard.
    final submit = tester.widget<ElevatedButton>(pay).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(sub.calls, 1);
    // Dispose the route before resolving admission, with no real Auth/RPC.
    await tester.pumpWidget(const SizedBox.shrink());
    sub.response.completeError(StateError('dummy unavailable'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a late admission response cannot check out the next session cart',
      (tester) async {
    final retail = _RetailFixture();
    final sub = _SubscriptionFixture();
    addTearDown(retail.dispose);
    addTearDown(sub.dispose);
    await mount(tester, retail, sub);
    await tester.enterText(find.byType(TextField).last, '10000');
    final pay = find.byType(ElevatedButton).last;
    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.pump();
    expect(sub.calls, 1);
    retail.invalidateSession();
    sub.response.complete(TransactionPermission.allowed(isOnline: true));
    await tester.pump();
    expect(retail.checkoutCalls, 0);
    expect(find.textContaining('Pembayaran belum selesai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
