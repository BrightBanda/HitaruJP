import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/progress/domain/progress_summary.dart';
import 'package:ingrain/features/progress/domain/streaks.dart';
import 'package:ingrain/features/sentence_mining/domain/sentence_item.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_event.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';

/// Pure progress aggregation. Every entry point takes an explicit `today` so
/// the results are deterministic and unit testable.
///
/// A session crossing midnight is attributed to the local day of its
/// `startedAt`, and only its accumulated `durationSeconds` counts (pause time
/// is already excluded by the session ViewModel).
class ProgressCalculator {
  const ProgressCalculator();

  static const int weekDayCount = 7;

  ProgressSummary summarize({
    required List<ImmersionSession> sessions,
    required List<SentenceItem> sentences,
    required List<VocabularyItem> vocabulary,
    required List<ReviewCard> dueCards,
    required List<ReviewEvent> reviewEvents,
    required DateTime today,
    required int dailyGoalMinutes,
    StreakFreezeRules freezeRules = StreakFreezeRules.defaults,
  }) {
    final todayDay = _day(today);

    final secondsByDay = <DateTime, int>{};
    var lifetimeSeconds = 0;
    for (final session in sessions) {
      final seconds = session.durationSeconds;
      if (seconds <= 0) continue;
      final day = _day(session.startedAt.toLocal());
      secondsByDay.update(
        day,
        (value) => value + seconds,
        ifAbsent: () => seconds,
      );
      lifetimeSeconds += seconds;
    }

    final reviewsByDay = <DateTime, int>{};
    for (final event in reviewEvents) {
      final day = _day(event.reviewedAt.toLocal());
      reviewsByDay.update(day, (value) => value + 1, ifAbsent: () => 1);
    }

    final last7Days = <DailyActivity>[];
    var todaySeconds = 0;
    var weekSeconds = 0;
    for (var offset = weekDayCount - 1; offset >= 0; offset--) {
      final day = _shiftDays(todayDay, -offset);
      final seconds = secondsByDay[day] ?? 0;
      final reviews = reviewsByDay[day] ?? 0;
      if (offset == 0) todaySeconds = seconds;
      weekSeconds += seconds;
      last7Days.add(
        DailyActivity(day: day, seconds: seconds, reviews: reviews),
      );
    }

    final weekStart = _shiftDays(todayDay, -(weekDayCount - 1));
    final sentencesThisWeek = sentences.where((s) {
      final created = _day(s.createdAt.toLocal());
      return !created.isBefore(weekStart);
    }).length;

    final endOfToday = _shiftDays(todayDay, 1);
    final dueCount = dueCards
        .where((card) => card.dueAt.toLocal().isBefore(endOfToday))
        .length;

    final reviewedToday = reviewsByDay[todayDay] ?? 0;
    final streak = streakState(secondsByDay.keys, todayDay, freezeRules);

    return ProgressSummary(
      todaySeconds: todaySeconds,
      weekSeconds: weekSeconds,
      lifetimeSeconds: lifetimeSeconds,
      currentStreak: streak.current,
      longestStreak: streak.longest,
      freezesUsedThisWeek: streak.usedThisWeek,
      freezeAllowance: streak.allowance,
      totalSentences: sentences.length,
      sentencesThisWeek: sentencesThisWeek,
      totalWords: vocabulary.length,
      wordsLearningOrBetter: vocabulary
          .where((word) => word.state.isAtLeast(VocabState.learning))
          .length,
      dueCount: dueCount,
      reviewedToday: reviewedToday,
      totalReviews: reviewEvents.length,
      dailyGoalMinutes: dailyGoalMinutes,
      last7Days: last7Days,
    );
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Calendar-day arithmetic, avoiding `Duration` so DST transitions cannot
  /// shift the resulting date.
  static DateTime _shiftDays(DateTime day, int delta) =>
      DateTime(day.year, day.month, day.day + delta);
}
