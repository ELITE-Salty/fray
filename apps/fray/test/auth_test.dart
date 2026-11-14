import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fray/src/app.dart';
import 'package:fray/src/data.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<void> press(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

void main() {
  testWidgets(
    'Password screen precedes MFA; invalid codes keep workspace locked',
    (tester) async {
      var attempts = 0;
      final requests = <http.Request>[];
      final store = FrayStore(
        client: MockClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/api/auth/csrf' => response({'csrfToken': 'csrf-before-login'}),
            '/api/auth/challenge' => response({'stage': 'credentials'}),
            '/api/auth/login/start' => response({
              'stage': 'mfa',
              'email': 'person@example.test',
            }),
            '/api/auth/login/verify' =>
              ++attempts == 1
                  ? response({'error': 'Incorrect security code'}, 400)
                  : response({
                      'name': 'Person',
                      'email': 'person@example.test',
                      'csrfToken': 'csrf-after-login',
                    }),
            '/api/auth/me' => response({
              'name': 'Person',
              'email': 'person@example.test',
            }),
            '/api/templates' => response({'templates': []}),
            '/api/preferences' => response({'weeklyGoalMinutes': 0}),
            '/api/items' => response({'items': []}),
            '/api/entries' => response({'entries': []}),
            _ => response({}),
          };
        }),
      );
      addTearDown(store.dispose);
      await tester.pumpWidget(FrayApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Authenticator or recovery code'), findsNothing);
      await enter(tester, 'Email', 'person@example.test');
      await enter(tester, 'Password', 'Secret-password-221!');
      await press(tester, 'Sign in');
      expect(store.name, isNull);
      expect(find.text('Password'), findsNothing);
      expect(find.text('Enter your security code'), findsOneWidget);
      final credentials = jsonDecode(
        requests.firstWhere((r) => r.url.path.endsWith('/start')).body,
      );
      expect(credentials.containsKey('code'), isFalse);
      await enter(tester, 'Authenticator or recovery code', 'wrong');
      await press(tester, 'Verify and sign in');
      expect(find.text('Incorrect security code'), findsOneWidget);
      expect(store.name, isNull);
      await enter(tester, 'Authenticator or recovery code', '123456');
      await press(tester, 'Verify and sign in');
      expect(store.name, 'Person');
      final verification = jsonDecode(
        requests.lastWhere((r) => r.url.path.endsWith('/verify')).body,
      );
      expect(verification, {'code': '123456'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Mobile signup verifies email, enrolls MFA and acknowledges recovery codes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var signupCalls = 0;
      final store = FrayStore(
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/api/auth/csrf':
              return response({'csrfToken': 'csrf'});
            case '/api/auth/challenge':
              return response({'stage': 'credentials'});
            case '/api/auth/signup':
              signupCalls++;
              return response({
                'stage': 'email',
                'email': 'new@example.test',
              }, 201);
            case '/api/auth/signup/email':
              return response({
                'stage': 'enroll',
                'email': 'new@example.test',
                'secret': 'JBSWY3DPEHPK3PXP',
                'uri': 'otpauth://totp/Fray:test?secret=JBSWY3DPEHPK3PXP&issuer=Fray',
              });
            case '/api/auth/signup/finish':
              return response({
                'name': 'New Person',
                'email': 'new@example.test',
                'csrfToken': 'rotated',
                'recoveryCodes': List.generate(
                  8,
                  (i) => 'test-recovery-code-$i',
                ),
              });
            case '/api/auth/me':
              return response({
                'name': 'New Person',
                'email': 'new@example.test',
              });
            case '/api/templates':
              return response({'templates': []});
            case '/api/preferences':
              return response({'weeklyGoalMinutes': 0});
            case '/api/items':
              return response({'items': []});
            case '/api/entries':
              return response({'entries': []});
            default:
              return response({});
          }
        }),
      );
      addTearDown(store.dispose);
      await tester.pumpWidget(FrayApp(store: store));
      await tester.pumpAndSettle();
      await press(tester, 'Create an account');
      await enter(tester, 'Email', 'new@example.test');
      await enter(tester, 'Password', 'New-password-933!');
      await enter(tester, 'Confirm password', 'mismatch');
      await press(tester, 'Create account');
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(signupCalls, 0);
      await enter(tester, 'Confirm password', 'New-password-933!');
      await press(tester, 'Create account');
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.text('Copy setup key'), findsNothing);
      await enter(tester, 'Email verification code', '123456');
      await press(tester, 'Verify email');
      expect(find.text('Protect your account'), findsOneWidget);
      expect(store.name, isNull);
      await enter(tester, 'Authenticator code', '654321');
      await press(tester, 'Finish setup');
      expect(find.text('Keep a way back in'), findsOneWidget);
      expect(store.name, isNull);
      final open = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Open my workspace'),
      );
      expect(open.onPressed, isNull);
      await press(tester, 'I have saved my recovery codes');
      await press(tester, 'Open my workspace');
      expect(store.name, 'New Person');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('An interrupted challenge resumes and can be cancelled', (
    tester,
  ) async {
    var cancelled = false;
    final store = FrayStore(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/csrf')) {
          return response({'csrfToken': 'csrf'});
        }
        if (request.url.path.endsWith('/cancel')) {
          cancelled = true;
          return response({'ok': true});
        }
        return response({'stage': 'email', 'email': 'pending@example.test'});
      }),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(FrayApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
    await press(tester, 'Back to sign in');
    expect(cancelled, isTrue);
    expect(find.text('Password'), findsOneWidget);
    expect(store.name, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
