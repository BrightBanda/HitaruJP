import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/quiz/data/quiz_repository.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';

final quizRepositoryProvider = Provider<QuizRepository>(
  (ref) => QuizRepository(
    ref.watch(documentStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);

/// The learner's calendar day, which the quiz belongs to.
DateTime quizToday(Ref ref) {
  final now = ref.read(clockProvider).now;
  return DateTime(now.year, now.month, now.day);
}

/// Today's finished quiz, or null while it is still to do.
final todayQuizResultProvider = FutureProvider<QuizResult?>((ref) async {
  ref.watch(authViewModelProvider.select((auth) => auth.uid));
  return ref.read(quizRepositoryProvider).result(quizDayKey(quizToday(ref)));
});

/// Today's twelve words, from the learner's saved words and their level.
final dailyQuizProvider = FutureProvider<DailyQuiz>((ref) async {
  final auth = ref.watch(authViewModelProvider);
  final dictionary = await ref.watch(dictionaryProvider.future);
  final saved = await ref.read(vocabularyRepositoryProvider).watchAll().first;
  return DailyQuiz.build(
    day: quizToday(ref),
    seed: auth.uid,
    saved: saved,
    dictionary: dictionary.entries,
    level: auth.profile?.level,
  );
});

class QuizSessionState {
  final int index;

  /// The choice picked for each question answered so far.
  final List<int> answers;

  /// Set once the last question is answered and the result saved.
  final QuizResult? result;

  const QuizSessionState({
    this.index = 0,
    this.answers = const [],
    this.result,
  });

  /// The current question has been answered and is showing its feedback.
  bool get answered => answers.length > index;
}

final quizSessionProvider =
    NotifierProvider.autoDispose<QuizSessionNotifier, QuizSessionState>(
      QuizSessionNotifier.new,
    );

class QuizSessionNotifier extends Notifier<QuizSessionState> {
  @override
  QuizSessionState build() => const QuizSessionState();

  void answer(int choice) {
    if (state.answered || state.result != null) return;
    state = QuizSessionState(
      index: state.index,
      answers: [...state.answers, choice],
    );
  }

  /// Moves on, or finishes after the last question.
  Future<void> next(DailyQuiz quiz) async {
    if (!state.answered) return;
    if (state.index + 1 < quiz.questions.length) {
      state = QuizSessionState(index: state.index + 1, answers: state.answers);
      return;
    }
    await _finish(quiz);
  }

  Future<void> _finish(DailyQuiz quiz) async {
    var correct = 0;
    final missed = <String>[];
    for (final (i, question) in quiz.questions.indexed) {
      if (state.answers[i] == question.answerIndex) {
        correct++;
      } else {
        missed.add(question.word);
      }
    }
    final result = QuizResult(
      day: quizDayKey(quiz.day),
      // A short quiz (a tiny dictionary) still counts as the daily one.
      correct: correct,
      total: quiz.questions.length,
      completedAt: ref.read(clockProvider).now,
      missed: missed,
    );
    await ref.read(quizRepositoryProvider).save(result);
    if (!ref.mounted) return;
    state = QuizSessionState(
      index: state.index,
      answers: state.answers,
      result: result,
    );
    ref.invalidate(todayQuizResultProvider);
    // The quiz's XP feeds the companion.
    unawaited(ref.read(progressViewModelProvider.notifier).refresh());
    unawaited(ref.read(socialSyncProvider.notifier).syncAll());
  }
}
