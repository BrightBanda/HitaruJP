import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/progress/domain/streaks.dart';

/// The same cases as the server's tests/test_streaks.py: the two must agree.
void main() {
  final today = DateTime(2026, 11, 26); // a Thursday

  /// [length] days of study ending [endDaysAgo] days ago, minus [gaps].
  Set<DateTime> run(
    int length, {
    Set<int> gaps = const {},
    int endDaysAgo = 1,
  }) {
    final last = DateTime(today.year, today.month, today.day - endDaysAgo);
    return {
      for (var i = 0; i < length; i++)
        if (!gaps.contains(endDaysAgo + i))
          DateTime(last.year, last.month, last.day - i),
    };
  }

  test('tiers', () {
    const rules = StreakFreezeRules.defaults;
    expect(
      [
        for (final n in [0, 6, 7, 100, 101, 499, 500, 900]) rules.allowance(n),
      ],
      [0, 0, 2, 2, 3, 3, 4, 4],
    );
  });

  test('no freezes before seven days', () {
    expect(streakState(run(6, gaps: {2}), today).current, 1);
  });

  test('a freeze keeps a long streak alive without growing it', () {
    final state = streakState(run(20, gaps: {5}), today);
    expect(state.current, 19);
    expect(state.allowance, 2);
  });

  test('two freezes a week, then the streak breaks', () {
    expect(streakState(run(30, endDaysAgo: 4), today).current, 0);
    final kept = streakState(run(30, endDaysAgo: 3), today);
    expect(kept.current, 30);
    expect(kept.usedThisWeek, 2);
    expect(kept.freezesLeft, 0);
  });

  test('freezes refill on Monday', () {
    final state = streakState(run(40, gaps: {8, 2}), today);
    expect(state.current, 38);
    expect(state.usedThisWeek, 1);
    expect(state.freezesLeft, 1);
  });

  test('today is never frozen', () {
    final state = streakState(run(10), today);
    expect(state.current, 10);
    expect(state.usedThisWeek, 0);
  });

  test('bigger tiers from longer streaks', () {
    final state = streakState(run(150, gaps: {1, 2, 3}), today);
    expect(state.current, 147);
    expect(state.usedThisWeek, 3);
  });

  test('tiers an admin set are followed', () {
    const rules = StreakFreezeRules([FreezeTier(3, 1)]);
    // Five days with a miss two days ago: one freeze from three days on.
    final state = streakState(run(6, gaps: {2}), today, rules);
    expect(state.current, 5);
  });

  test('rules round-trip through JSON', () {
    final json = StreakFreezeRules.defaults.toJson();
    final back = StreakFreezeRules.fromJson(json)!;
    expect(back.tiers, StreakFreezeRules.defaults.tiers);
    expect(StreakFreezeRules.fromJson({'tiers': 'nope'}), isNull);
  });
}
