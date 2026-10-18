class DailyActivity {
  final DateTime day;
  final int seconds;
  final int reviews;

  const DailyActivity({
    required this.day,
    required this.seconds,
    this.reviews = 0,
  });

  bool get hasActivity => seconds > 0 || reviews > 0;

  Map<String, Object> toJson() => {
    'day': day.toIso8601String(),
    'seconds': seconds,
    'reviews': reviews,
  };

  factory DailyActivity.fromJson(Map<String, dynamic> json) => DailyActivity(
    day: DateTime.parse(json['day'] as String),
    seconds: (json['seconds'] as num).toInt(),
    reviews: (json['reviews'] as num?)?.toInt() ?? 0,
  );
}

class ProgressSummary {
  final int todaySeconds;
  final int weekSeconds;
  final int lifetimeSeconds;
  final int currentStreak;
  final int longestStreak;
  final int totalSentences;
  final int sentencesThisWeek;
  final int totalWords;
  final int wordsLearningOrBetter;
  final int dueCount;
  final int reviewedToday;
  final int totalReviews;
  final int dailyGoalMinutes;
  final List<DailyActivity> last7Days;

  const ProgressSummary({
    required this.todaySeconds,
    required this.weekSeconds,
    required this.lifetimeSeconds,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalSentences,
    required this.sentencesThisWeek,
    this.totalWords = 0,
    this.wordsLearningOrBetter = 0,
    required this.dueCount,
    required this.reviewedToday,
    required this.totalReviews,
    required this.dailyGoalMinutes,
    required this.last7Days,
  });

  static const ProgressSummary empty = ProgressSummary(
    todaySeconds: 0,
    weekSeconds: 0,
    lifetimeSeconds: 0,
    currentStreak: 0,
    longestStreak: 0,
    totalSentences: 0,
    sentencesThisWeek: 0,
    dueCount: 0,
    reviewedToday: 0,
    totalReviews: 0,
    dailyGoalMinutes: 30,
    last7Days: <DailyActivity>[],
  );

  int get dailyGoalSeconds => dailyGoalMinutes * 60;

  /// For the copy kept on the device between launches.
  Map<String, Object> toJson() => {
    'todaySeconds': todaySeconds,
    'weekSeconds': weekSeconds,
    'lifetimeSeconds': lifetimeSeconds,
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
    'totalSentences': totalSentences,
    'sentencesThisWeek': sentencesThisWeek,
    'totalWords': totalWords,
    'wordsLearningOrBetter': wordsLearningOrBetter,
    'dueCount': dueCount,
    'reviewedToday': reviewedToday,
    'totalReviews': totalReviews,
    'dailyGoalMinutes': dailyGoalMinutes,
    'last7Days': [for (final day in last7Days) day.toJson()],
  };

  factory ProgressSummary.fromJson(Map<String, dynamic> json) {
    int field(String name) => (json[name] as num?)?.toInt() ?? 0;
    return ProgressSummary(
      todaySeconds: field('todaySeconds'),
      weekSeconds: field('weekSeconds'),
      lifetimeSeconds: field('lifetimeSeconds'),
      currentStreak: field('currentStreak'),
      longestStreak: field('longestStreak'),
      totalSentences: field('totalSentences'),
      sentencesThisWeek: field('sentencesThisWeek'),
      totalWords: field('totalWords'),
      wordsLearningOrBetter: field('wordsLearningOrBetter'),
      dueCount: field('dueCount'),
      reviewedToday: field('reviewedToday'),
      totalReviews: field('totalReviews'),
      dailyGoalMinutes: field('dailyGoalMinutes'),
      last7Days: [
        for (final day in json['last7Days'] as List? ?? const [])
          DailyActivity.fromJson(Map<String, dynamic>.from(day as Map)),
      ],
    );
  }

  /// Clamped 0..1 progress of today's immersion time towards the daily goal.
  double get todayGoalProgress {
    if (dailyGoalSeconds <= 0) return 0;
    return (todaySeconds / dailyGoalSeconds).clamp(0.0, 1.0);
  }

  bool get isEmpty =>
      lifetimeSeconds == 0 &&
      totalSentences == 0 &&
      totalWords == 0 &&
      totalReviews == 0;
}
