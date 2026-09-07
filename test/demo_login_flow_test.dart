import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:resident_app/login.dart';

void main() {
  testWidgets(
    'demo Log In reaches onLoginSuccess via any number + demo PIN',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var loggedIn = false;

      await tester.pumpWidget(
        MaterialApp(
          home: LoginFlow(
            initialStep: LoginStep.landing,
            onLoginSuccess: () => loggedIn = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Log In'), findsWidgets);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '9171234567');
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Enter verification code to log in'), findsOneWidget);

      final otpFields = find.byType(TextField);
      expect(otpFields, findsNWidgets(6));
      for (var i = 0; i < 6; i++) {
        await tester.enterText(otpFields.at(i), '${i + 1}');
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Enter Code'), findsOneWidget);

      final codeFields = find.byType(TextField);
      expect(codeFields, findsNWidgets(6));
      for (var i = 0; i < 6; i++) {
        await tester.enterText(codeFields.at(i), '${9 - i}');
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Enter your 4–6 digit PIN'), findsOneWidget);

      final pinFields = find.byType(TextField);
      expect(pinFields, findsNWidgets(6));
      for (var i = 0; i < 6; i++) {
        await tester.enterText(pinFields.at(i), '${i + 1}');
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 1200));

      expect(loggedIn, isTrue);
    },
  );
}