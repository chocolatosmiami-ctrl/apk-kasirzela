import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/core/services/startup_policy.dart';
import '../lib/core/services/supabase_auth_service.dart';
import '../lib/core/utils/app_constants.dart';
import '../lib/features/auth/presentation/providers/auth_provider.dart';
import '../lib/features/auth/presentation/screens/firebase_login_screen.dart';
import '../lib/features/auth/presentation/screens/splash_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        AppConstants.keyUid: 'dummy-account',
        'pending_receipt_fixture': 'keep-this-local-receipt',
      }));

  Future<void> mount(WidgetTester tester, AuthProvider auth) async {
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth, child: const MaterialApp(home: SplashScreen())));
    await tester.pump();
    await tester.pump();
  }

  test('startup diagnostics distinguish token, schema and network failures',
      () {
    expect(
        startupFailureCode(
            const AuthException('dummy', code: 'refresh_token_not_found')),
        'STARTUP_SIGN_IN');
    expect(
        startupFailureCode(
            const PostgrestException(message: 'dummy', code: 'PGRST201')),
        'PROFILE_CONFIGURATION');
    expect(
        startupFailureCode(
            const PostgrestException(message: 'dummy', code: 'PGRST301')),
        'STARTUP_SIGN_IN');
    expect(startupFailureCode(TimeoutException('dummy')), 'STARTUP_TIMEOUT');
    final code = startupFailureCode(StateError('DUMMY_PRIVATE_VALUE'));
    expect(code, 'STARTUP_UNKNOWN');
    expect(startupFailureMessage(code), isNot(contains('DUMMY_PRIVATE_VALUE')));
  });

  testWidgets(
      'failed profile can open credential login without signing out or deleting local data',
      (tester) async {
    var signOutCalls = 0;
    final auth = AuthProvider(
        sessionReader: () async =>
            throw const AuthException('dummy', code: 'refresh_token_not_found'),
        signOut: () async {
          signOutCalls++;
        });
    addTearDown(auth.dispose);
    await mount(tester, auth);
    expect(find.text('Kode: STARTUP_SIGN_IN'), findsOneWidget);
    await tester.tap(find.text('Login kembali'));
    await tester.pumpAndSettle();
    expect(find.byType(FirebaseLoginScreen), findsOneWidget);
    expect(signOutCalls, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppConstants.keyUid), 'dummy-account');
    expect(
        prefs.getString('pending_receipt_fixture'), 'keep-this-local-receipt');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'recovery retry returns to login when the SDK no longer has a session',
      (tester) async {
    var calls = 0;
    final auth = AuthProvider(sessionReader: () async {
      if (calls++ == 0) throw TimeoutException('dummy');
      return null;
    });
    addTearDown(auth.dispose);
    await mount(tester, auth);
    expect(find.text('Kode: STARTUP_TIMEOUT'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(FirebaseLoginScreen), findsOneWidget);
  });

  testWidgets(
      'late background profile cannot restore authority after login is opened',
      (tester) async {
    var calls = 0;
    final pending = Completer<AppUserProfile?>();
    final auth = AuthProvider(sessionReader: () {
      if (calls++ == 0) return Future.error(TimeoutException('dummy'));
      return pending.future;
    });
    addTearDown(auth.dispose);
    await mount(tester, auth);
    final oldRead = auth.checkSession();
    await tester.tap(find.text('Login kembali'));
    await tester.pumpAndSettle();
    pending.complete(AppUserProfile(
        authId: 'dummy-account',
        email: 'dummy@example.invalid',
        name: 'Dummy',
        role: 'kasir',
        ownerId: 'dummy-owner',
        branchId: 'dummy-branch',
        branchName: 'Dummy',
        branchMode: 'food'));
    await oldRead;
    await tester.pump();
    expect(auth.currentUser, isNull);
    expect(find.byType(FirebaseLoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
