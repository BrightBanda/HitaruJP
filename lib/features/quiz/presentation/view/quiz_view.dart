import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/quiz/data/quiz_repository.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/quiz/presentation/viewmodel/quiz_providers.dart';

/// The daily quiz: twelve words, each with furigana and romaji, and four
/// meanings to choose from. Once a day; after that it shows the result.
class QuizView extends ConsumerWidget {
  const QuizView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(quizSessionProvider);
    final done = ref.watch(todayQuizResultProvider);

    Widget body;
    final finished = session.result;
    if (finished != null) {
      body = QuizResults(result: finished, justFinished: true);
    } else {
      body = done.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (result) => result != null
            ? QuizResults(result: result, justFinished: false)
            : ref
                  .watch(dailyQuizProvider)
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) =>
                        Center(child: Text('Could not build the quiz: $error')),
                    data: (quiz) => quiz.questions.isEmpty
                        ? const Center(child: Text('No words to quiz on yet.'))
                        : _QuizRunner(quiz: quiz),
                  ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Daily quiz')),
      body: SafeArea(child: body),
    );
  }
}

class _QuizRunner extends ConsumerWidget {
  final DailyQuiz quiz;

  const _QuizRunner({required this.quiz});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(quizSessionProvider);
    final notifier = ref.read(quizSessionProvider.notifier);
    final theme = Theme.of(context);
    final question = quiz.questions[session.index];
    final picked = session.answered ? session.answers[session.index] : null;
    final total = quiz.questions.length;
    final score = [
      for (final (i, answer) in session.answers.indexed)
        if (answer == quiz.questions[i].answerIndex) 1,
    ].length;
    final isLast = session.index + 1 == total;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                Text(
                  'Question ${session.index + 1} of $total',
                  style: theme.textTheme.labelLarge,
                ),
                const Spacer(),
                Text(
                  '$score right',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.dialogue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: (session.answers.length) / total,
              ),
            ),
            const SizedBox(height: 20),
            _WordCard(key: ValueKey(session.index), question: question),
            const SizedBox(height: 20),
            Text(
              'What does this mean?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final (i, choice) in question.choices.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _Choice(
                  text: choice,
                  state: picked == null
                      ? _ChoiceState.open
                      : i == question.answerIndex
                      ? _ChoiceState.right
                      : i == picked
                      ? _ChoiceState.wrong
                      : _ChoiceState.other,
                  onTap: () {
                    if (picked != null) return;
                    i == question.answerIndex
                        ? HapticFeedback.lightImpact()
                        : HapticFeedback.mediumImpact();
                    notifier.answer(i);
                  },
                ),
              ),
            if (picked != null) ...[
              const SizedBox(height: 4),
              Text(
                picked == question.answerIndex
                    ? 'Correct! 🎉'
                    : '${question.word} means "${question.answer}".',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: picked == question.answerIndex
                      ? AppColors.dialogue
                      : theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => notifier.next(quiz),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(isLast ? 'See my score' : 'Next'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The word with its furigana above and romaji below.
class _WordCard extends StatelessWidget {
  final QuizQuestion question;

  const _WordCard({super.key, required this.question});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.heroGradient,
          ),
        ),
        child: Column(
          children: [
            if (question.furigana != null)
              Text(
                question.furigana!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  letterSpacing: 2,
                ),
              ),
            FittedBox(
              child: Text(
                question.word,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              question.romaji,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 17,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (question.fromSaved) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'One of your words',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ChoiceState { open, right, wrong, other }

class _Choice extends StatelessWidget {
  final String text;
  final _ChoiceState state;
  final VoidCallback onTap;

  const _Choice({required this.text, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = switch (state) {
      _ChoiceState.right => (AppColors.dialogue, Icons.check_circle),
      _ChoiceState.wrong => (theme.colorScheme.error, Icons.cancel),
      _ => (theme.colorScheme.outlineVariant, null),
    };
    final highlighted =
        state == _ChoiceState.right || state == _ChoiceState.wrong;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: state == _ChoiceState.other ? 0.5 : 1,
      child: Material(
        color: highlighted
            ? color.withValues(alpha: 0.12)
            : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color, width: highlighted ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: state == _ChoiceState.open ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
                if (icon != null) Icon(icon, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The score, the XP it earned and the words to look at again.
class QuizResults extends ConsumerWidget {
  final QuizResult result;

  /// Just finished now, rather than reopened later the same day.
  final bool justFinished;

  const QuizResults({
    super.key,
    required this.result,
    required this.justFinished,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final xp = ref
        .watch(growthRulesProvider)
        .quizXp(result.correct, result.total);
    final ratio = result.total == 0 ? 0.0 : result.correct / result.total;
    final title = switch (ratio) {
      1 => 'Perfect! 🌟',
      >= 0.75 => 'Great job! 🎉',
      >= 0.5 => 'Nice work! 👍',
      _ => 'Keep going! 💪',
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: SizedBox.square(
                dimension: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: ratio),
                      duration: Duration(milliseconds: justFinished ? 900 : 0),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 12,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: AppColors.dialogue,
                      ),
                    ),
                    Center(
                      child: Text(
                        '${result.correct}/${result.total}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              justFinished ? title : "Today's quiz is done",
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Center(
              child: Chip(
                avatar: const Icon(Icons.bolt, color: AppColors.review),
                label: Text('+$xp XP for your companion'),
              ),
            ),
            if (result.missed.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Words to review', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final word in result.missed) Chip(label: Text(word)),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/leaderboard'),
              icon: const Icon(Icons.leaderboard),
              label: const Text('See the leaderboard'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/immerse'),
              child: const Text('Done'),
            ),
            const SizedBox(height: 8),
            Text(
              'Twelve new words tomorrow.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
