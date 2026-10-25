import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/view/first_lesson_view.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

/// Lets the auth stream deliver and the profile read finish.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer container({String uid = 'u1'}) {
    final c = ProviderContainer(
      overrides: appTestOverrides(
        prefs,
        session: FakeAuthSession(uid: uid, name: 'Aiko'),
      ),
    );
    addTearDown(c.dispose);
    c.read(authViewModelProvider);
    return c;
  }

  group('FirstRunViewModel', () {
    test('nothing is pending for a learner who never onboarded here', () async {
      final c = container();
      await settle();
      final run = c.read(firstRunProvider);
      expect(run.welcomeSeen, isFalse);
      expect(run.lessonPending, isFalse);
      expect(run.homeTipsPending, isFalse);
    });

    test('the tour is queued, then each part is finished in turn', () async {
      final c = container();
      await settle();
      final vm = c.read(firstRunProvider.notifier)..startTour('u1');
      expect(c.read(firstRunProvider).lessonPending, isTrue);

      vm.finishLesson('u1');
      expect(c.read(firstRunProvider).lessonPending, isFalse);
      expect(c.read(firstRunProvider).homeTipsPending, isTrue);

      vm.finishHomeTips('u1');
      expect(c.read(firstRunProvider).homeTipsPending, isFalse);
    });

    test('progress survives a restart and stays with its learner', () async {
      container().read(firstRunProvider.notifier)
        ..markWelcomeSeen()
        ..startTour('u1');

      final again = container();
      await settle();
      expect(again.read(firstRunProvider).welcomeSeen, isTrue);
      expect(again.read(firstRunProvider).lessonPending, isTrue);

      final other = container(uid: 'u2');
      await settle();
      expect(other.read(firstRunProvider).welcomeSeen, isTrue);
      expect(
        other.read(firstRunProvider).lessonPending,
        isFalse,
        reason: 'the lesson belongs to the learner who onboarded',
      );
    });
  });

  testWidgets('the first lesson: read, tap, save, answer, celebrate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = container();
    await tester.runAsync(settle);
    c.read(firstRunProvider.notifier).startTour('u1');
    final router = GoRouter(
      initialLocation: '/first-lesson',
      routes: [
        GoRoute(
          path: '/first-lesson',
          builder: (_, _) => const FirstLessonView(),
        ),
        GoRoute(path: '/immerse', builder: (_, _) => const Text('home')),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Let’s try your first real conversation!'),
      findsOneWidget,
    );
    await tester.tap(find.text('Let’s go'));
    // The four lines appear one by one, then the guide asks for a tap. The
    // glowing word pulses for as long as it waits, so time is pumped by hand.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Tap the glowing word'), findsWidgets);

    await tester.tap(find.text('コーヒー'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('coffee'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save word'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved to your flashcards! 🎉'), findsOneWidget);
    final saved = await tester.runAsync(
      () => c.read(vocabularyRepositoryProvider).findByWord('コーヒー'),
    );
    expect(saved?.meaning, 'coffee', reason: 'a real word, in real flashcards');

    await tester.tap(find.text('Quick check'));
    // The list scrolls down to the choices.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('thank you'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Not quite, try again!'), findsOneWidget);
    await tester.tap(find.text('please (give me)'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Perfect! You’re a natural.'), findsOneWidget);

    await tester.tap(find.text('Finish lesson'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('First lesson complete!'), findsOneWidget);
    expect(find.text('Day 1'), findsOneWidget);

    await tester.tap(find.text('Start exploring'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(c.read(firstRunProvider).lessonPending, isFalse);
    expect(c.read(firstRunProvider).homeTipsPending, isTrue);
  });
}
