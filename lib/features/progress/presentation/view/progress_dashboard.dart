import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/core/utils/duration_format.dart';
import 'package:ingrain/features/progress/domain/progress_summary.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// The progress and analytics dashboard, shown on the Profile tab.
class ProgressDashboard extends ConsumerWidget {
  const ProgressDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(progressViewModelProvider);

    if (uiState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (uiState.error != null) {
      return Center(
        child: Text('Error: ${uiState.error!.message ?? 'unknown'}'),
      );
    }
    return _buildDashboard(context, ref, uiState.summary!);
  }

  Widget _buildDashboard(
    BuildContext context,
    WidgetRef ref,
    ProgressSummary summary,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(progressViewModelProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _TodayCard(summary: summary),
          const SizedBox(height: 12),
          _StatGrid(summary: summary),
          const SizedBox(height: 12),
          _WeeklyChart(activities: summary.last7Days),
          const SizedBox(height: 12),
          _LearningCard(summary: summary),
          if (summary.dueCount > 0) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              style: accentButtonStyle(AppColors.primaryMain),
              onPressed: () => context.go('/flashcards'),
              icon: const Icon(Icons.school),
              label: Text('Review ${summary.dueCount} due now'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: _tintedButton(AppColors.primaryMain),
            onPressed: () =>
                context.push('/flashcards/deck/$minedPhrasesDeckId'),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Browse mined phrases'),
          ),
          if (summary.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Start an immersion session and mine a sentence to see your '
                'progress here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

ButtonStyle _tintedButton(Color color) => OutlinedButton.styleFrom(
  foregroundColor: color,
  backgroundColor: color.withValues(alpha: 0.12),
);

/// Today's immersion against the daily goal, drawn as the dashboard hero.
class _TodayCard extends StatelessWidget {
  final ProgressSummary summary;

  const _TodayCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final goalReached = summary.todaySeconds >= summary.dailyGoalSeconds;
    final theme = Theme.of(context);

    return GradientPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Today',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                '${summary.dailyGoalMinutes} min goal',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatDurationCompact(Duration(seconds: summary.todaySeconds)),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: summary.todayGoalProgress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            goalReached
                ? 'Daily goal reached 🎉'
                : '${formatDurationCompact(Duration(seconds: summary.dailyGoalSeconds - summary.todaySeconds))} to go',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final ProgressSummary summary;

  const _StatGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'This week',
            value: formatDurationCompact(
              Duration(seconds: summary.weekSeconds),
            ),
            icon: Icons.date_range,
            accentColor: AppColors.primaryMain,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'All time',
            value: formatDurationCompact(
              Duration(seconds: summary.lifetimeSeconds),
            ),
            icon: Icons.history,
            accentColor: AppColors.primaryMain,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Streak',
            value: '${summary.currentStreak}d',
            icon: Icons.local_fire_department,
            accentColor: AppColors.primaryMain,
            caption: summary.longestStreak > 0
                ? 'best ${summary.longestStreak}d'
                : null,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;
  final String? caption;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;

    return TintedSurface(
      color: accent,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            IconBadge(color: accent, icon: icon, size: 36, solid: true),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                color: accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
            if (caption != null)
              Text(
                caption!,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  final List<DailyActivity> activities;

  const _WeeklyChart({required this.activities});

  static const double _maxBarHeight = 96;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final maxSeconds = activities.fold<int>(
      0,
      (max, a) => a.seconds > max ? a.seconds : max,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 7 days', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: _maxBarHeight + 34,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final activity in activities)
                    Expanded(
                      child: _DayBar(
                        activity: activity,
                        maxSeconds: maxSeconds,
                        maxBarHeight: _maxBarHeight,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final DailyActivity activity;
  final int maxSeconds;
  final double maxBarHeight;

  const _DayBar({
    required this.activity,
    required this.maxSeconds,
    required this.maxBarHeight,
  });

  static const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = maxSeconds <= 0 ? 0.0 : activity.seconds / maxSeconds;
    final isActive = activity.hasActivity;

    final bar = BoxDecoration(
      gradient: isActive
          ? const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: AppColors.heroGradient,
            )
          : null,
      color: isActive
          ? null
          : theme.colorScheme.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
    );

    return Column(
      children: [
        // The bar takes whatever height is left after the labels, so a day
        // with a review count, or larger system text, never pushes the
        // weekday label out of the chart.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const countHeight = 14.0;
              const margin = 6.0;
              final room = (constraints.maxHeight - countHeight - margin).clamp(
                2.0,
                maxBarHeight,
              );
              final height = maxSeconds <= 0
                  ? 2.0
                  : (fraction * room).clamp(2.0, room);
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: countHeight,
                    child: activity.reviews > 0
                        ? FittedBox(
                            child: Text(
                              '${activity.reviews}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryMain,
                              ),
                            ),
                          )
                        : null,
                  ),
                  Container(
                    height: height,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: margin / 2,
                    ),
                    decoration: bar,
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _weekdayLabels[activity.day.weekday - 1],
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _LearningCard extends StatelessWidget {
  final ProgressSummary summary;

  const _LearningCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Learning', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _LearningRow(
              icon: Icons.bookmark,
              color: AppColors.primaryMain,
              label: 'Sentences mined',
              value: '${summary.totalSentences}',
              caption: '${summary.sentencesThisWeek} this week',
            ),
            const Divider(height: 20),
            _LearningRow(
              icon: Icons.translate,
              color: AppColors.primaryMain,
              label: 'Words saved',
              value: '${summary.totalWords}',
              caption: '${summary.wordsLearningOrBetter} learning or better',
            ),
            const Divider(height: 20),
            _LearningRow(
              icon: Icons.pending_actions,
              color: AppColors.primaryMain,
              label: 'Due for review',
              value: '${summary.dueCount}',
            ),
            const Divider(height: 20),
            _LearningRow(
              icon: Icons.check_circle_outline,
              color: AppColors.primaryMain,
              label: 'Reviewed today',
              value: '${summary.reviewedToday}',
              caption: '${summary.totalReviews} all time',
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? caption;

  const _LearningRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        IconBadge(color: color, icon: icon, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyLarge),
              if (caption != null)
                Text(caption!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            color: color,
          ),
        ),
      ],
    );
  }
}
