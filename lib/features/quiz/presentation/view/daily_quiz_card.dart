import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/quiz/presentation/viewmodel/quiz_providers.dart';

/// The home screen's invitation to today's quiz, or its score once done.
class DailyQuizCard extends ConsumerWidget {
  const DailyQuizCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final result = ref.watch(todayQuizResultProvider).value;
    final done = result != null;
    const color = AppColors.podcast;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: color.withValues(alpha: 0.1),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => done ? context.go('/leaderboard') : context.push('/quiz'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  done ? Icons.emoji_events : Icons.quiz,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done
                          ? "Today's quiz: ${result.correct}/${result.total}"
                          : 'Daily quiz',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      done
                          ? 'See how your friends did this week'
                          : '${DailyQuiz.length} words · up to 70 XP',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              done
                  ? const Icon(Icons.leaderboard, color: color)
                  : FilledButton(
                      onPressed: () => context.push('/quiz'),
                      style: FilledButton.styleFrom(backgroundColor: color),
                      child: const Text('Start'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
