import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';

void main() {
  const rules = GrowthRules();
  const calculator = GrowthCalculator();
  final start = DateTime(2026, 10, 1);

  DateTime day(int n) => start.add(Duration(days: n));

  group('levels', () {
    test('level 1 needs nothing and each level needs more', () {
      expect(rules.xpForLevel(1), 0);
      for (var level = 2; level < 60; level++) {
        expect(
          rules.xpForLevel(level + 1) - rules.xpForLevel(level),
          greaterThan(rules.xpForLevel(level) - rules.xpForLevel(level - 1)),
        );
      }
    });

    test('levelFor is the inverse of xpForLevel', () {
      for (var level = 1; level < 60; level++) {
        expect(rules.levelFor(rules.xpForLevel(level)), level);
        expect(rules.levelFor(rules.xpForLevel(level + 1) - 1), level);
      }
    });

    test('stages begin at their levels', () {
      expect(rules.stageFor(1), GrowthStage.egg);
      expect(rules.stageFor(2), GrowthStage.hatchling);
      expect(rules.stageFor(4), GrowthStage.hatchling);
      expect(rules.stageFor(5), GrowthStage.child);
      expect(rules.stageFor(50), GrowthStage.legend);
      expect(rules.stageFor(99), GrowthStage.legend);
    });
  });

  group('a day of XP', () {
    test('each activity is capped', () {
      final xp = rules.xpForDay(
        DayActivity(day: start, watchSeconds: 5 * 3600, reviews: 500),
        dailyGoalMinutes: 0,
        streakDays: 1,
      );
      expect(xp[XpSource.watching], 60 * 2, reason: 'an hour counts at most');
      expect(xp[XpSource.reviews], 60, reason: 'flashcards earn a small share');
    });

    test('meeting the goal and keeping a streak add bonuses', () {
      final activity = DayActivity(day: start, watchSeconds: 10 * 60);
      final plain = rules.xpForDay(
        activity,
        dailyGoalMinutes: 15,
        streakDays: 1,
      );
      expect(plain, {XpSource.watching: 20});

      final good = rules.xpForDay(
        activity,
        dailyGoalMinutes: 10,
        streakDays: 3,
      );
      expect(good[XpSource.dailyGoal], 25);
      expect(good[XpSource.streak], 5, reason: '10% of 45');
    });
  });

  group('GrowthCalculator', () {
    test('the first lesson hatches the egg', () {
      final growth = calculator.compute(
        [DayActivity(day: start, readSeconds: 90, firstLesson: true)],
        dailyGoalMinutes: 10,
        today: start,
      );
      expect(growth.stage, GrowthStage.hatchling);
      expect(growth.today[XpSource.firstLesson], 50);
    });

    test('a streak only counts consecutive active days', () {
      final growth = calculator.compute(
        [
          for (final n in [0, 1, 2, 4])
            DayActivity(day: day(n), watchSeconds: 600),
        ],
        dailyGoalMinutes: 0,
        today: day(4),
      );
      final streakXp = [
        for (final d in growth.days) d.bySource[XpSource.streak] ?? 0,
      ];
      expect(streakXp, [0, 0, 2, 0], reason: 'day 3 of a run, then a gap');
    });

    test('several entries for one day add up', () {
      final growth = calculator.compute(
        [
          DayActivity(day: start.add(const Duration(hours: 9)), wordsSaved: 2),
          DayActivity(day: start.add(const Duration(hours: 20)), wordsSaved: 3),
        ],
        dailyGoalMinutes: 0,
        today: start,
      );
      expect(growth.days, hasLength(1));
      expect(growth.xp, 10);
    });

    test('XP never drops below what was already shown', () {
      final growth = calculator.compute(
        const [],
        dailyGoalMinutes: 10,
        today: start,
        floorXp: 1200,
      );
      expect(growth.xp, 1200);
      expect(growth.level, rules.levelFor(1200));
    });
  });

  group('growth pace with the default rules', () {
    Growth after(LearnerHabit habit, int days) => calculator.compute(
      habit.simulate(days, start: start),
      dailyGoalMinutes: habit.dailyGoalMinutes,
      today: day(days - 1),
    );

    const regular = LearnerHabit(); // 10 minutes, 5 days a week

    test('a regular learner grows a stage within the first week', () {
      expect(
        after(regular, 7).stage.index,
        greaterThanOrEqualTo(GrowthStage.child.index),
      );
    });

    test('a regular learner reaches adult in about two months', () {
      final stage = after(regular, 60).stage;
      expect(stage.index, greaterThanOrEqualTo(GrowthStage.teen.index));
      expect(stage.index, lessThanOrEqualTo(GrowthStage.adult.index));
    });

    test('the legend takes a long, dedicated time', () {
      expect(after(regular, 180).stage, isNot(GrowthStage.legend));
    });

    test('active days are spread through the week', () {
      const habit = LearnerHabit(daysPerWeek: 5);
      final active = [for (var i = 0; i < 7; i++) habit.isActiveOn(i)];
      expect(active.where((a) => a), hasLength(5));
    });
  });
}
