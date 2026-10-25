import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/app/app.dart';

import 'support/test_overrides.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a new install is welcomed, then asked to sign in', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        // A signed-out session is what sends the router to /onboarding.
        overrides: appTestOverrides(prefs, session: FakeAuthSession(uid: '')),
        child: const IngrApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Learn Japanese from things you love'), findsOneWidget);

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to HitaruJP'), findsOneWidget);
    expect(prefs.getBool('first_run_welcome_seen'), isTrue);
  });
}
