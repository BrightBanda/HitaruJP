import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/app/app.dart';

import 'support/test_overrides.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App shows onboarding when not onboarded', (
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
    expect(find.text('Welcome to HitaruJP'), findsOneWidget);
  });
}
