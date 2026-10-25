// XP, levels and growth stages: the rules and the arithmetic, nothing else.
//
// Pure Dart with no imports from the app, so this exact file is also used by
// the admin dashboard's growth simulator (ingrain_admin_dashboard:
// lib/shared/growth/growth_rules.dart). Change both copies together.

import 'dart:math' as math;

/// How the learner's companion looks as it grows, from the egg they start
/// with to its final form. Each stage begins at [GrowthRules.stageLevels].
enum GrowthStage { egg, hatchling, child, teen, adult, master, legend }

/// Where a day's XP came from.
enum XpSource {
  watching,
  reading,
  dialogues,
  sentences,
  words,
  reviews,
  dailyGoal,
  streak,
  firstLesson,
}

/// Everything a learner did on one calendar day: the only input XP needs.
class DayActivity {
  /// Midnight of the day, local time.
  final DateTime day;

  /// Videos and audio actually playing.
  final int watchSeconds;

  /// Dialogues, stories and books open.
  final int readSeconds;

  /// All immersion time, flashcard study included: what the daily goal and
  /// the streak count.
  final int totalSeconds;

  /// Distinct dialogues read for at least a minute.
  final int dialoguesRead;
  final int sentencesMined;
  final int wordsSaved;
  final int reviews;

  /// The guided first lesson was finished this day.
  final bool firstLesson;

  const DayActivity({
    required this.day,
    this.watchSeconds = 0,
    this.readSeconds = 0,
    int? totalSeconds,
    this.dialoguesRead = 0,
    this.sentencesMined = 0,
    this.wordsSaved = 0,
    this.reviews = 0,
    this.firstLesson = false,
  }) : totalSeconds = totalSeconds ?? watchSeconds + readSeconds;

  bool get isActive => totalSeconds > 0 || reviews > 0;
}

/// The numbers behind XP and levels. Tuned in the admin dashboard's growth
/// simulator; the defaults are what the app ships with.
class GrowthRules {
  final int xpPerWatchMinute;
  final int watchMinuteCap;
  final int xpPerReadMinute;
  final int readMinuteCap;
  final int xpPerDialogue;
  final int dialogueCap;
  final int xpPerSentence;
  final int sentenceCap;
  final int xpPerWord;
  final int wordCap;

  /// Flashcards earn a small share: they are review, not immersion.
  final int xpPerReview;
  final int reviewCap;

  final int dailyGoalBonus;

  /// Extra XP, as a percentage of the day's, once a streak reaches
  /// [streakBonusFromDays] days.
  final int streakBonusPercent;
  final int streakBonusFromDays;

  /// Enough to hatch the egg straight away.
  final int firstLessonXp;

  /// Total XP to reach level `n` is `levelBase × (n − 1)^levelExponent`.
  final double levelBase;
  final double levelExponent;

  /// The level at which each stage begins, in stage order; the egg is
  /// always level 1.
  final List<int> stageLevels;

  const GrowthRules({
    this.xpPerWatchMinute = 2,
    this.watchMinuteCap = 60,
    this.xpPerReadMinute = 2,
    this.readMinuteCap = 30,
    this.xpPerDialogue = 15,
    this.dialogueCap = 6,
    this.xpPerSentence = 5,
    this.sentenceCap = 20,
    this.xpPerWord = 2,
    this.wordCap = 30,
    this.xpPerReview = 1,
    this.reviewCap = 60,
    this.dailyGoalBonus = 25,
    this.streakBonusPercent = 10,
    this.streakBonusFromDays = 3,
    this.firstLessonXp = 50,
    this.levelBase = 25,
    this.levelExponent = 1.7,
    this.stageLevels = const [1, 2, 5, 10, 20, 35, 50],
  });

  /// The highest level counted; past it XP still adds up.
  static const maxLevel = 99;

  /// Total XP needed to reach [level].
  int xpForLevel(int level) {
    if (level <= 1) return 0;
    return (levelBase * math.pow(level - 1, levelExponent)).round();
  }

  int levelFor(int xp) {
    var level = 1;
    while (level < maxLevel && xpForLevel(level + 1) <= xp) {
      level++;
    }
    return level;
  }

  GrowthStage stageFor(int level) {
    var stage = GrowthStage.egg;
    for (final candidate in GrowthStage.values) {
      if (level >= stageLevels[candidate.index]) stage = candidate;
    }
    return stage;
  }

  /// One day's XP, by source. [streakDays] is the streak that day reached.
  Map<XpSource, int> xpForDay(
    DayActivity day, {
    required int dailyGoalMinutes,
    required int streakDays,
  }) {
    int capped(int count, int cap, int each) => math.min(count, cap) * each;
    final xp = <XpSource, int>{
      XpSource.watching: capped(
        day.watchSeconds ~/ 60,
        watchMinuteCap,
        xpPerWatchMinute,
      ),
      XpSource.reading: capped(
        day.readSeconds ~/ 60,
        readMinuteCap,
        xpPerReadMinute,
      ),
      XpSource.dialogues: capped(day.dialoguesRead, dialogueCap, xpPerDialogue),
      XpSource.sentences: capped(
        day.sentencesMined,
        sentenceCap,
        xpPerSentence,
      ),
      XpSource.words: capped(day.wordsSaved, wordCap, xpPerWord),
      XpSource.reviews: capped(day.reviews, reviewCap, xpPerReview),
      XpSource.dailyGoal:
          dailyGoalMinutes > 0 && day.totalSeconds >= dailyGoalMinutes * 60
          ? dailyGoalBonus
          : 0,
    };
    final earned = xp.values.fold(0, (sum, value) => sum + value);
    xp[XpSource.streak] = streakDays >= streakBonusFromDays
        ? (earned * streakBonusPercent / 100).round()
        : 0;
    xp[XpSource.firstLesson] = day.firstLesson ? firstLessonXp : 0;
    xp.removeWhere((_, value) => value == 0);
    return xp;
  }

  GrowthRules copyWith({
    int? xpPerWatchMinute,
    int? watchMinuteCap,
    int? xpPerReadMinute,
    int? readMinuteCap,
    int? xpPerDialogue,
    int? dialogueCap,
    int? xpPerSentence,
    int? sentenceCap,
    int? xpPerWord,
    int? wordCap,
    int? xpPerReview,
    int? reviewCap,
    int? dailyGoalBonus,
    int? streakBonusPercent,
    int? streakBonusFromDays,
    int? firstLessonXp,
    double? levelBase,
    double? levelExponent,
    List<int>? stageLevels,
  }) => GrowthRules(
    xpPerWatchMinute: xpPerWatchMinute ?? this.xpPerWatchMinute,
    watchMinuteCap: watchMinuteCap ?? this.watchMinuteCap,
    xpPerReadMinute: xpPerReadMinute ?? this.xpPerReadMinute,
    readMinuteCap: readMinuteCap ?? this.readMinuteCap,
    xpPerDialogue: xpPerDialogue ?? this.xpPerDialogue,
    dialogueCap: dialogueCap ?? this.dialogueCap,
    xpPerSentence: xpPerSentence ?? this.xpPerSentence,
    sentenceCap: sentenceCap ?? this.sentenceCap,
    xpPerWord: xpPerWord ?? this.xpPerWord,
    wordCap: wordCap ?? this.wordCap,
    xpPerReview: xpPerReview ?? this.xpPerReview,
    reviewCap: reviewCap ?? this.reviewCap,
    dailyGoalBonus: dailyGoalBonus ?? this.dailyGoalBonus,
    streakBonusPercent: streakBonusPercent ?? this.streakBonusPercent,
    streakBonusFromDays: streakBonusFromDays ?? this.streakBonusFromDays,
    firstLessonXp: firstLessonXp ?? this.firstLessonXp,
    levelBase: levelBase ?? this.levelBase,
    levelExponent: levelExponent ?? this.levelExponent,
    stageLevels: stageLevels ?? this.stageLevels,
  );

  /// The rules as Dart source, for pasting tuned values into the app.
  String toDart() =>
      '''
const GrowthRules(
  xpPerWatchMinute: $xpPerWatchMinute,
  watchMinuteCap: $watchMinuteCap,
  xpPerReadMinute: $xpPerReadMinute,
  readMinuteCap: $readMinuteCap,
  xpPerDialogue: $xpPerDialogue,
  dialogueCap: $dialogueCap,
  xpPerSentence: $xpPerSentence,
  sentenceCap: $sentenceCap,
  xpPerWord: $xpPerWord,
  wordCap: $wordCap,
  xpPerReview: $xpPerReview,
  reviewCap: $reviewCap,
  dailyGoalBonus: $dailyGoalBonus,
  streakBonusPercent: $streakBonusPercent,
  streakBonusFromDays: $streakBonusFromDays,
  firstLessonXp: $firstLessonXp,
  levelBase: $levelBase,
  levelExponent: $levelExponent,
  stageLevels: $stageLevels,
)''';
}

/// One day's XP and where the learner stood at its end.
class DayXp {
  final DateTime day;
  final Map<XpSource, int> bySource;

  /// XP up to and including this day.
  final int cumulativeXp;
  final int level;
  final GrowthStage stage;

  const DayXp({
    required this.day,
    required this.bySource,
    required this.cumulativeXp,
    required this.level,
    required this.stage,
  });

  int get xp => bySource.values.fold(0, (sum, value) => sum + value);
}

/// Where a learner stands: XP, level, stage and how far to the next.
class Growth {
  final int xp;
  final int level;
  final GrowthStage stage;

  /// XP at which [level] began, and at which the next one begins.
  final int levelStartXp;
  final int nextLevelXp;

  /// The next stage and the level it begins at; null at the last stage.
  final GrowthStage? nextStage;
  final int? nextStageLevel;

  /// Today's XP by source; empty when nothing was earned today.
  final Map<XpSource, int> today;

  /// Every active day, oldest first.
  final List<DayXp> days;

  const Growth({
    required this.xp,
    required this.level,
    required this.stage,
    required this.levelStartXp,
    required this.nextLevelXp,
    this.nextStage,
    this.nextStageLevel,
    this.today = const {},
    this.days = const [],
  });

  /// 0..1 through the current level.
  double get levelProgress {
    final span = nextLevelXp - levelStartXp;
    if (span <= 0) return 1;
    return ((xp - levelStartXp) / span).clamp(0.0, 1.0);
  }

  int get xpToNextLevel => math.max(0, nextLevelXp - xp);

  int get todayXp => today.values.fold(0, (sum, value) => sum + value);
}

/// Adds up a learner's XP from their activity, day by day.
class GrowthCalculator {
  final GrowthRules rules;

  const GrowthCalculator([this.rules = const GrowthRules()]);

  /// [floorXp] is the most XP ever shown to this learner: deleting a saved
  /// word or a session must never make their companion shrink.
  Growth compute(
    Iterable<DayActivity> activity, {
    required int dailyGoalMinutes,
    required DateTime today,
    int floorXp = 0,
  }) {
    final byDay = <DateTime, DayActivity>{};
    for (final day in activity) {
      final key = _day(day.day);
      byDay[key] = _merge(byDay[key], day, key);
    }
    final ordered = byDay.keys.toList()..sort();

    final days = <DayXp>[];
    var total = 0;
    var streak = 0;
    DateTime? previous;
    for (final key in ordered) {
      final day = byDay[key]!;
      if (day.isActive) {
        final consecutive =
            previous != null && key.difference(previous).inDays == 1;
        streak = consecutive ? streak + 1 : 1;
        previous = key;
      }
      final xp = rules.xpForDay(
        day,
        dailyGoalMinutes: dailyGoalMinutes,
        streakDays: day.isActive ? streak : 0,
      );
      if (xp.isEmpty) continue;
      total += xp.values.fold(0, (sum, value) => sum + value);
      final level = rules.levelFor(total);
      days.add(
        DayXp(
          day: key,
          bySource: xp,
          cumulativeXp: total,
          level: level,
          stage: rules.stageFor(level),
        ),
      );
    }

    final xp = math.max(total, floorXp);
    final todayKey = _day(today);
    final todayXp = days.isNotEmpty && days.last.day == todayKey
        ? days.last.bySource
        : const <XpSource, int>{};
    return growthAt(xp, today: todayXp, days: days);
  }

  /// Where [xp] puts a learner.
  Growth growthAt(
    int xp, {
    Map<XpSource, int> today = const {},
    List<DayXp> days = const [],
  }) {
    final level = rules.levelFor(xp);
    final stage = rules.stageFor(level);
    final next = stage.index + 1 < GrowthStage.values.length
        ? GrowthStage.values[stage.index + 1]
        : null;
    return Growth(
      xp: xp,
      level: level,
      stage: stage,
      levelStartXp: rules.xpForLevel(level),
      nextLevelXp: rules.xpForLevel(level + 1),
      nextStage: next,
      nextStageLevel: next == null ? null : rules.stageLevels[next.index],
      today: today,
      days: days,
    );
  }

  static DateTime _day(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  static DayActivity _merge(DayActivity? a, DayActivity b, DateTime day) {
    if (a == null) return b;
    return DayActivity(
      day: day,
      watchSeconds: a.watchSeconds + b.watchSeconds,
      readSeconds: a.readSeconds + b.readSeconds,
      totalSeconds: a.totalSeconds + b.totalSeconds,
      dialoguesRead: a.dialoguesRead + b.dialoguesRead,
      sentencesMined: a.sentencesMined + b.sentencesMined,
      wordsSaved: a.wordsSaved + b.wordsSaved,
      reviews: a.reviews + b.reviews,
      firstLesson: a.firstLesson || b.firstLesson,
    );
  }
}

/// A made-up learner, for the admin's growth simulator: what they do on an
/// active day and how many days a week they show up.
class LearnerHabit {
  final int watchMinutes;
  final int readMinutes;
  final int dialogues;
  final int sentences;
  final int words;
  final int reviews;

  /// Out of 7. Active days are spread through the week, so 5 means two
  /// days off a week.
  final int daysPerWeek;
  final int dailyGoalMinutes;
  final bool firstLesson;

  const LearnerHabit({
    this.watchMinutes = 10,
    this.readMinutes = 0,
    this.dialogues = 0,
    this.sentences = 1,
    this.words = 3,
    this.reviews = 15,
    this.daysPerWeek = 5,
    this.dailyGoalMinutes = 10,
    this.firstLesson = true,
  });

  bool isActiveOn(int dayIndex) {
    if (daysPerWeek >= 7) return true;
    if (daysPerWeek <= 0) return false;
    // Spread the active days evenly through each week.
    final weekday = dayIndex % 7;
    return (weekday * daysPerWeek) ~/ 7 != ((weekday + 1) * daysPerWeek) ~/ 7;
  }

  /// [days] days of this habit, starting on [start].
  List<DayActivity> simulate(int days, {required DateTime start}) => [
    for (var i = 0; i < days; i++)
      if (isActiveOn(i) || (i == 0 && firstLesson))
        DayActivity(
          day: start.add(Duration(days: i)),
          watchSeconds: isActiveOn(i) ? watchMinutes * 60 : 0,
          readSeconds: isActiveOn(i) ? readMinutes * 60 : 0,
          // The first lesson is a minute or two of reading.
          totalSeconds:
              (isActiveOn(i) ? (watchMinutes + readMinutes) * 60 : 0) +
              (i == 0 && firstLesson ? 90 : 0),
          dialoguesRead: isActiveOn(i) ? dialogues : 0,
          sentencesMined: isActiveOn(i) ? sentences : 0,
          wordsSaved: isActiveOn(i) ? words : 0,
          reviews: isActiveOn(i) ? reviews : 0,
          firstLesson: i == 0 && firstLesson,
        ),
  ];
}
