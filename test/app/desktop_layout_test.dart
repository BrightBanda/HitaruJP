import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/router.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/shared/layout/window_size.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_overrides.dart';
import 'navigation_test.dart' show NavigationDialogueRepository;

const desktop = Size(1440, 900);
const tablet = Size(1000, 760);
const phone = Size(390, 844);

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        ...appTestOverrides(await SharedPreferences.getInstance()),
        dialogueRepositoryProvider.overrideWithValue(
          NavigationDialogueRepository(),
        ),
        dictionaryProvider.overrideWith(
          (ref) async => DictionaryIndex(const []),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authViewModelProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // Watched, as the app does: the router is rebuilt once sign-in settles.
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, String path) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
    await tester.pumpAndSettle();
  }

  test('window sizes follow the breakpoints', () {
    expect(WindowSize.forWidth(390), WindowSize.compact);
    expect(WindowSize.forWidth(839), WindowSize.compact);
    expect(WindowSize.forWidth(840), WindowSize.medium);
    expect(WindowSize.forWidth(1279), WindowSize.medium);
    expect(WindowSize.forWidth(1280), WindowSize.expanded);
  });

  testWidgets('phones keep the bottom bar', (tester) async {
    await pumpAt(tester, phone);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('tablets get a side rail with every destination', (tester) async {
    await pumpAt(tester, tablet);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
    // Vocab and Kana have their own entries rather than a Learn menu.
    final rail = find.byType(NavigationRail);
    expect(find.descendant(of: rail, matching: find.text('Kana')), findsOne);
    expect(find.descendant(of: rail, matching: find.text('Vocab')), findsOne);
    expect(find.text('Learn'), findsNothing);
  });

  testWidgets('desktop sidebar navigates straight to each page', (
    tester,
  ) async {
    await pumpAt(tester, desktop);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);

    // The sidebar comes first in the tree; the home page also has a Kana
    // shortcut further along.
    await tester.tap(find.text('Kana').first);
    await tester.pumpAndSettle();
    // Wide enough for both scripts at once: no tabs.
    expect(find.text('Hiragana  あ'), findsOneWidget);
    expect(find.text('Katakana  ア'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);

    await tester.tap(find.text('Vocab').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Vocabulary'), findsOneWidget);
  });

  for (final (label, size) in [('desktop', desktop), ('tablet', tablet)]) {
    testWidgets('every main page fits a $label window', (tester) async {
      await pumpAt(tester, size);
      for (final path in [
        '/immerse',
        '/library',
        '/leaderboard',
        '/flashcards',
        '/learn/vocab',
        '/learn/kana',
        '/profile',
        '/search',
        '/flashcards/settings',
        '/profile/edit',
      ]) {
        await go(tester, path);
        expect(tester.takeException(), isNull, reason: path);
      }
    });
  }

  testWidgets('wide profile keeps the character beside the tabs', (
    tester,
  ) async {
    await pumpAt(tester, desktop);
    await go(tester, '/profile');

    expect(find.byType(NestedScrollView), findsNothing);
    final tabs = tester.getTopLeft(find.byType(TabBar));
    final name = tester.getTopLeft(find.text('Tester').last);
    expect(name.dx, lessThan(tabs.dx), reason: 'card column on the left');
    expect(tabs.dy, lessThan(200), reason: 'tabs at the top, not below');
  });
}
