/// Streaks with streak freezes.
///
/// A missed day spends a freeze and the streak lives on, without growing.
/// How many freezes a learner may spend in a week (Monday to Sunday) depends
/// on how long their streak is when they miss: the tiers. Today is never
/// frozen: there is still time to study. The server works streaks out the
/// same way (Ingrained_backend: app/services/streaks.py); change both
/// together.
library;

/// From a streak of [fromDays] days, [freezes] streak freezes a week.
class FreezeTier {
  final int fromDays;
  final int freezes;

  const FreezeTier(this.fromDays, this.freezes);

  @override
  bool operator ==(Object other) =>
      other is FreezeTier &&
      other.fromDays == fromDays &&
      other.freezes == freezes;

  @override
  int get hashCode => Object.hash(fromDays, freezes);
}

/// The tiers in force. An admin changes them from the dashboard; the app
/// follows on its next sync.
class StreakFreezeRules {
  final List<FreezeTier> tiers;

  const StreakFreezeRules(this.tiers);

  static const defaults = StreakFreezeRules([
    FreezeTier(7, 2),
    FreezeTier(101, 3),
    FreezeTier(500, 4),
  ]);

  /// Freezes a week for a streak of [streak] days: the highest tier reached.
  int allowance(int streak) {
    var freezes = 0;
    for (final tier in [
      ...tiers,
    ]..sort((a, b) => a.fromDays.compareTo(b.fromDays))) {
      if (streak >= tier.fromDays) freezes = tier.freezes;
    }
    return freezes;
  }

  Map<String, dynamic> toJson() => {
    'tiers': [
      for (final tier in tiers)
        {'fromDays': tier.fromDays, 'freezes': tier.freezes},
    ],
  };

  /// Null for anything that is not a usable set of tiers.
  static StreakFreezeRules? fromJson(Object? json) {
    if (json is! Map || json['tiers'] is! List) return null;
    try {
      return StreakFreezeRules([
        for (final tier in json['tiers'] as List)
          FreezeTier(
            ((tier as Map)['fromDays'] as num).toInt(),
            (tier['freezes'] as num).toInt(),
          ),
      ]);
    } catch (_) {
      return null;
    }
  }
}

/// Where a streak stands today.
class StreakState {
  final int current;
  final int longest;

  /// Freezes spent in today's week, and how many the current streak allows.
  final int usedThisWeek;
  final int allowance;

  const StreakState({
    required this.current,
    required this.longest,
    required this.usedThisWeek,
    required this.allowance,
  });

  int get freezesLeft =>
      allowance - usedThisWeek < 0 ? 0 : allowance - usedThisWeek;
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime _monday(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

/// The streak on [today] from the days the learner was active.
StreakState streakState(
  Iterable<DateTime> activeDays,
  DateTime today, [
  StreakFreezeRules rules = StreakFreezeRules.defaults,
]) {
  final active = {for (final day in activeDays) _day(day)};
  final todayDay = _day(today);
  if (active.isEmpty) {
    return StreakState(
      current: 0,
      longest: 0,
      usedThisWeek: 0,
      allowance: rules.allowance(0),
    );
  }
  var streak = 0;
  var longest = 0;
  var used = 0;
  DateTime? week;
  var day = active.reduce((a, b) => a.isBefore(b) ? a : b);
  while (day.isBefore(todayDay)) {
    final monday = _monday(day);
    if (monday != week) {
      week = monday;
      used = 0;
    }
    if (active.contains(day)) {
      streak++;
    } else if (streak > 0 && used < rules.allowance(streak)) {
      used++; // frozen: the streak survives the missed day
    } else {
      streak = 0;
    }
    if (streak > longest) longest = streak;
    // Calendar days, not 24-hour steps, so daylight saving cannot skip one.
    day = DateTime(day.year, day.month, day.day + 1);
  }
  if (active.contains(todayDay)) {
    streak++;
    if (streak > longest) longest = streak;
  }
  if (_monday(todayDay) != week) used = 0;
  return StreakState(
    current: streak,
    longest: longest,
    usedThisWeek: used,
    allowance: rules.allowance(streak),
  );
}
