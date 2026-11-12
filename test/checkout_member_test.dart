import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/services/cart_session.dart';
import '../lib/core/services/checkout_member.dart';
import '../lib/core/services/order_outbox.dart';
import '../lib/core/utils/app_constants.dart';
import '../lib/core/widgets/checkout_member_field.dart';

class _Cart extends ChangeNotifier with SessionBoundCart {
  @override
  void clearSessionState() => notifyListeners();
}

class _Store implements OrderOutboxStore {
  final OutboxReceipt receipt;
  int acknowledged = 0, failures = 0;
  _Store(this.receipt);
  @override
  Future<List<OutboxReceipt>> pending(String accountId) async => [receipt];
  @override
  Future<void> acknowledge(OutboxReceipt receipt) async {
    acknowledged++;
  }

  @override
  Future<void> recordFailure(OutboxReceipt receipt, String message) async {
    failures++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final row = <String, dynamic>{
    'id': 'dummy-customer',
    'member_number': '001234',
    'nama': 'Dummy Member',
    'poin': 42
  };
  setUp(() => SharedPreferences.setMockInitialValues({
        AppConstants.keyUid: 'account-a',
        AppConstants.keyOwnerId: 'owner-a',
        AppConstants.keyBranchId: 'branch-a',
      }));

  Future<_Cart> cart() async {
    final cart = _Cart()..bindAccount('account-a', 'owner-a');
    await cart.prepareSession();
    addTearDown(cart.dispose);
    return cart;
  }

  test(
      'only a verified six-digit code can be used; leading zeros and real points survive',
      () async {
    final c = CheckoutMemberController(
        cart: await cart(),
        lookup: (_, number) async {
          expect(number, '001234');
          return row;
        });
    addTearDown(c.dispose);
    expect(c.ready, true);
    c.input.text = '001234';
    expect(c.ready, false);
    await c.verify();
    expect(c.ready, true);
    expect(c.selected!.number, '001234');
    expect(c.selected!.points, 42);
    expect(c.selected!.toPayload()['customer_id'], 'dummy-customer');
    c.input.selection = const TextSelection.collapsed(offset: 0);
    expect(c.selected, isNotNull,
        reason: 'moving the cursor must not invalidate a verified code');
    c.clear();
    expect(c.selected, isNull);
    expect(c.ready, true);
  });

  test('invalid code is rejected without contacting a service', () async {
    var calls = 0;
    final c = CheckoutMemberController(
        cart: await cart(),
        lookup: (_, __) async {
          calls++;
          return row;
        });
    addTearDown(c.dispose);
    c.input.text = '123';
    await c.verify();
    expect(calls, 0);
    expect(c.error, contains('6 digit'));
    expect(c.ready, false);
  });

  test('a delayed member response cannot cross an account or branch change',
      () async {
    final source = await cart();
    final response = Completer<Map<String, dynamic>>();
    final c = CheckoutMemberController(
        cart: source, lookup: (_, __) => response.future);
    addTearDown(c.dispose);
    c.input.text = '001234';
    final pending = c.verify();
    await Future<void>.delayed(Duration.zero);
    source.invalidateSession();
    await source.prepareSession();
    response.complete(row);
    await pending;
    expect(c.selected, isNull);
    expect(c.input.text, isEmpty);
    expect(c.ready, true);
  });

  test(
      'lookup failure can be removed so a normal non-member payment remains available',
      () async {
    final c = CheckoutMemberController(
        cart: await cart(),
        lookup: (_, __) async => throw TimeoutException('dummy'));
    addTearDown(c.dispose);
    c.input.text = '001234';
    await c.verify();
    expect(c.ready, false);
    expect(c.selected, isNull);
    expect(c.error, isNotNull);
    c.clear();
    expect(c.ready, true);
  });

  test('routing uses the existing ordinary, member food and member retail RPCs',
      () {
    expect(checkoutSyncRpc({}), 'sync_paid_food_order');
    final member = {'customer_id': 'dummy-customer', 'member_number': '001234'};
    expect(checkoutSyncRpc(member), 'zela_member_sync_food_order');
    expect(checkoutSyncRpc({...member, 'order_type': 'retail'}),
        'zela_member_sync_retail_order');
    expect(
        () => checkoutSyncRpc({'member_number': '001234'}), throwsStateError);
  });

  test(
      'member receipt waits for member_linked acknowledgement and preserves the retry payload',
      () async {
    final payload = <String, dynamic>{
      'version': 1,
      'account_id': 'account-a',
      'order_number': 'DUMMY-RECEIPT',
      'customer_id': 'dummy-customer',
      'member_number': '001234',
      'member_name': 'Dummy Member'
    };
    final store = _Store(OutboxReceipt(1, 'account-a', payload));
    final serialized = <String>[];
    final outbox = OrderOutbox(store, (sent) async {
      serialized.add(jsonEncode(sent));
      return {
        'success': true,
        'stock_applied': true,
        if (serialized.length > 1) 'member_linked': true
      };
    });
    expect((await outbox.flush('account-a')).failed, 1);
    expect(store.acknowledged, 0);
    expect((await outbox.flush('account-a')).sent, 1);
    expect(store.acknowledged, 1);
    expect(serialized[0], serialized[1]);
    expect(payload['member_number'], '001234');
  });

  testWidgets(
      'member input fits a 320px screen and supports removing a verified member',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = CheckoutMemberController(
        cart: await cart(), lookup: (_, __) async => row);
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: CheckoutMemberField(controller: c)))));
    await tester.enterText(find.byType(TextField), '001234');
    await tester.tap(find.text('Cek'));
    await tester.pumpAndSettle();
    expect(find.text('Dummy Member'), findsOneWidget);
    expect(find.textContaining('001234'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Hapus'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(c.ready, true);
  });
}
