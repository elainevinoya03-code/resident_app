import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:resident_app/login.dart';

void main() {
  testWidgets('registration flow skips OTP and reaches the profile form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: LoginFlow(
          initialStep: LoginStep.landing,
          onLoginSuccess: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resident Login'), findsOneWidget);

    // Landing → Create Account → email entry screen.
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Let’s create your account'), findsOneWidget);

    // Enter an email and Continue → profile form (no OTP step).
    await tester.enterText(find.byType(TextField).first, 'user@email.com');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Enter verification code to log in'), findsNothing);
  });
}