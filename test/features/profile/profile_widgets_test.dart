import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/kana/domain/kana_knowledge.dart';
import 'package:ingrain/features/kana/presentation/kana_progress_view_model.dart';
import 'package:ingrain/features/kana/presentation/kana_view.dart';
import 'package:ingrain/features/onboarding/presentation/view/onboarding_flow_view.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/presentation/widgets/learner_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget child, {
    FakeAuthSession? session,
  }) async {
    final container = ProviderContainer(
      overrides: appTestOverrides(prefs, session: session),
    );
    addTearDown(container.dispose);
    container.read(authViewModelProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> continueOn(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  testWidgets('a new learner answers all six questions', (tester) async {
    phone(tester);
    final session = FakeAuthSession(uid: 'u1', name: null);
    final container = await pump(
      tester,
      const OnboardingFlowView(),
      session: session,
    );

    expect(find.text('Why are you learning Japanese?'), findsOneWidget);
    expect(find.text('1/6'), findsOneWidget);
    await tapVisible(tester, find.text('Travel'));
    await tapVisible(tester, find.text('Anime & Manga'));
    await continueOn(tester, 'Continue');

    expect(find.text('How much Japanese do you know?'), findsOneWidget);
    expect(
      find.text(
        'Can understand basic everyday Japanese and simple conversations.',
      ),
      findsOneWidget,
      reason: 'every level explains itself',
    );
    await tapVisible(tester, find.text('I’m not sure'));
    expect(find.textContaining('We’ll start you at N5'), findsOneWidget);
    await tapVisible(tester, find.text('Elementary'));
    await continueOn(tester, 'Continue');

    expect(find.text('What do you love watching?'), findsOneWidget);
    await tapVisible(tester, find.text('Podcasts'));
    expect(
      find.text('Great for listening on the go.'),
      findsOneWidget,
      reason: 'the guide reacts to the answer',
    );
    await continueOn(tester, 'Continue');

    expect(find.text('How much time a day?'), findsOneWidget);
    await tapVisible(tester, find.text('Serious'));
    await continueOn(tester, 'Continue');

    expect(find.text('What should we call you?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Aiko');
    await tester.pumpAndSettle();
    await continueOn(tester, 'Continue');

    expect(find.text('Pick your character!'), findsOneWidget);
    await tapVisible(tester, find.text('Kitsune'));
    expect(find.text('Clever fox'), findsOneWidget);
    // In the app the router leaves onboarding now; here the button just keeps
    // its spinner, so pump a moment instead of settling.
    await tester.tap(find.widgetWithText(FilledButton, 'Start learning'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final auth = container.read(authViewModelProvider);
    expect(auth.isOnboarded, isTrue);
    expect(session.profileFields['level'], 'N4');
    expect(session.profileFields['learningReasons'], ['travel', 'anime_manga']);
    expect(session.profileFields['interests'], ['podcasts']);
    expect(session.profileFields['avatarId'], 'kitsune');
    expect(session.name, 'Aiko');
  });

  testWidgets('back steps through the questions', (tester) async {
    phone(tester);
    await pump(
      tester,
      const OnboardingFlowView(),
      session: FakeAuthSession(uid: 'u1', name: null),
    );

    await tapVisible(tester, find.text('Travel'));
    await continueOn(tester, 'Continue');
    expect(find.text('2/6'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('1/6'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('kana tiles are marked by long-press and from the sheet', (
    tester,
  ) async {
    phone(tester);
    final container = await pump(tester, const KanaView());
    KanaKnowledge? markOf(String kana) =>
        container.read(kanaProgressViewModelProvider).value?[kana];

    expect(find.text('of 104 fully known'), findsOneWidget);

    await tester.longPress(find.text('あ'));
    await tester.pumpAndSettle();
    expect(markOf('あ'), KanaKnowledge.somewhat);

    await tester.longPress(find.text('あ'));
    await tester.pumpAndSettle();
    expect(markOf('あ'), KanaKnowledge.known);
    expect(find.text('Fully know · 1'), findsOneWidget);

    await tester.tap(find.text('い'));
    await tester.pumpAndSettle();
    expect(find.text('How well do you know it?'), findsOneWidget);
    await tester.tap(find.text('Somewhat know'));
    await tester.pumpAndSettle();
    expect(markOf('い'), KanaKnowledge.somewhat);
    expect(find.text('I somewhat know this character.'), findsOneWidget);

    await tester.tap(find.text('Not set'));
    await tester.pumpAndSettle();
    expect(markOf('い'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every character renders at small and large sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final character in AvatarCharacter.values) ...[
                AvatarPortrait(character: character, size: 32),
                AvatarPortrait(
                  character: character,
                  size: 120,
                  rounded: true,
                  outlined: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byType(AvatarPortrait),
      findsNWidgets(AvatarCharacter.values.length * 2),
    );
    expect(find.bySemanticsLabel('Daruma avatar'), findsNWidgets(2));
  });
}
