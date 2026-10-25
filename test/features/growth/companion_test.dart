import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/growth/presentation/companion_widgets.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

void main() {
  const calculator = GrowthCalculator();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, Widget child, Growth growth) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: child),
        ),
        GoRoute(path: '/companion', builder: (_, _) => const CompanionView()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(prefs, session: FakeAuthSession(uid: 'u1')),
          growthProvider.overrideWithValue(growth),
          companionCharacterProvider.overrideWithValue(AvatarCharacter.kitsune),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  testWidgets('the companion page shows the stage, level and what is next', (
    tester,
  ) async {
    await pump(tester, const CompanionView(), calculator.growthAt(300));
    await tester.pumpAndSettle();

    final growth = calculator.growthAt(300);
    expect(find.text('こぎつね · Kit'), findsOneWidget);
    expect(find.text('Level ${growth.level} · 300 XP'), findsOneWidget);
    expect(find.textContaining('Teen at level 10'), findsOneWidget);
    expect(
      find.byIcon(Icons.lock_outline),
      findsWidgets,
      reason: 'stages ahead',
    );
    await tester.scrollUntilVisible(
      find.text('Flashcard review'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Flashcard review'), findsOneWidget);
  });

  testWidgets('reaching a new stage is celebrated once', (tester) async {
    GrowthCelebrations.markSeen(prefs, 'u1', GrowthStage.hatchling, 3);
    final grown = calculator.growthAt(300); // a child
    await pump(tester, const GrowthCelebrations(child: Text('home')), grown);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Your kitsune grew!\nLevel ${grown.level}'), findsNothing);

    // The reveal plays, then the words and the button appear.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('こぎつね · Kit'), findsOneWidget);
    expect(
      find.text('Your Kitsune grew!\nLevel ${grown.level}'),
      findsOneWidget,
    );

    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Keep going'), findsNothing);
    expect(prefs.getString('growth_seen_stage_u1'), 'child');
  });

  testWidgets('a new level within a stage gets a quick note', (tester) async {
    final growth = calculator.growthAt(300);
    GrowthCelebrations.markSeen(prefs, 'u1', growth.stage, growth.level - 1);
    await pump(tester, const GrowthCelebrations(child: Text('home')), growth);
    await tester.pump();
    expect(find.textContaining('Level up!'), findsOneWidget);
    expect(find.text('Keep going'), findsNothing);
  });
}
