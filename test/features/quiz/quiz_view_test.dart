import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/quiz/presentation/view/quiz_view.dart';
import 'package:ingrain/features/quiz/presentation/viewmodel/quiz_providers.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/quiz_fixture.dart';
import '../../support/test_overrides.dart';

void main() {
  testWidgets('twelve answers, a score, XP, and the result is sent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final social = FakeSocialRepository(username: 'aiko');
    final container = ProviderContainer(
      overrides: [
        ...appTestOverrides(
          prefs,
          session: FakeAuthSession(uid: 'u1', name: 'Aiko'),
          social: social,
        ),
        dictionaryProvider.overrideWith(
          (ref) async => DictionaryIndex(quizDictionary),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authViewModelProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: QuizView()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final DailyQuiz quiz = await tester.runAsync(
      () => container.read(dailyQuizProvider.future),
    ) as DailyQuiz;
    expect(find.text('Question 1 of 12'), findsOneWidget);

    for (final (i, question) in quiz.questions.indexed) {
      // Every answer right but the first.
      final pick = i == 0
          ? question.choices.firstWhere((c) => c != question.answer)
          : question.answer;
      await tester.tap(find.text(pick));
      await tester.pumpAndSettle();
      if (i == 0) {
        expect(
          find.textContaining('means "${question.answer}"'),
          findsOneWidget,
        );
      } else {
        expect(find.text('Correct! 🎉'), findsOneWidget);
      }
      await tester.tap(find.text(i == 11 ? 'See my score' : 'Next'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    expect(find.text('11/12'), findsOneWidget);
    expect(find.text('Great job! 🎉'), findsOneWidget);
    expect(find.text('+55 XP for your companion'), findsOneWidget);
    expect(find.text(quiz.questions.first.word), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    final saved = await tester.runAsync(
      () => container
          .read(quizRepositoryProvider)
          .result(quizDayKey(DateTime.now())),
    );
    expect(saved?.correct, 11);
    expect(social.quizzes.single.correct, 11);
  });
}
