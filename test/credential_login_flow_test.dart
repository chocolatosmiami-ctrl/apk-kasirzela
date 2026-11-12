import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/core/services/staff_login_service.dart';

void main() {
  test(
      'a valid Auth account signs in without any anonymous profile discovery or legacy call',
      () async {
    final calls = <String>[];
    final flow = CredentialLoginFlow(passwordSignIn: () async {
      calls.add('auth');
      return 'dummy-auth-uid';
    }, legacySignIn: () async {
      throw StateError('legacy must not run for an existing Auth account');
    });
    expect(await flow.signIn(), 'dummy-auth-uid');
    expect(calls, ['auth']);
  });

  test(
      'only invalid_credentials invokes the existing server-side migration flow once',
      () async {
    final calls = <String>[];
    final flow = CredentialLoginFlow(passwordSignIn: () async {
      calls.add('auth');
      throw const AuthException('dummy', code: 'invalid_credentials');
    }, legacySignIn: () async {
      calls.add('server-migration');
      return 'dummy-migrated-uid';
    });
    expect(await flow.signIn(), 'dummy-migrated-uid');
    expect(calls, ['auth', 'server-migration']);
  });

  for (final error in <Object>[
    TimeoutException('dummy'),
    AuthRetryableFetchException(),
    const AuthException('dummy', statusCode: '429'),
    const AuthException('dummy', statusCode: '401', code: 'bad_jwt'),
    const AuthException('dummy', code: 'email_not_confirmed'),
  ]) {
    test(
        '${error.runtimeType} without invalid_credentials cannot invoke legacy migration',
        () async {
      var migrations = 0;
      final flow = CredentialLoginFlow(
          passwordSignIn: () async => throw error,
          legacySignIn: () async {
            migrations++;
            return 'unexpected';
          });
      await expectLater(flow.signIn(), throwsA(same(error)));
      expect(migrations, 0);
    });
  }

  test(
      'migration rejection propagates without retrying credentials or inventing an identity',
      () async {
    var attempts = 0;
    final rejected = const AuthException('dummy', code: 'invalid_credentials');
    final flow = CredentialLoginFlow(
        passwordSignIn: () async => throw rejected,
        legacySignIn: () async {
          attempts++;
          throw rejected;
        });
    await expectLater(flow.signIn(), throwsA(same(rejected)));
    expect(attempts, 1);
  });
}
