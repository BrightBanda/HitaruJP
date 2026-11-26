import 'package:ingrain/features/social/domain/social.dart';

/// The API's camelCase JSON for the social models, both ways. The same shape
/// is written to the on-device cache, so a cached copy reads like a fresh one.
abstract final class SocialJson {
  static Map<String, dynamic> _map(Object? json) =>
      Map<String, dynamic>.from(json! as Map);

  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;

  static String _day(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  // --- People -------------------------------------------------------------

  static Person person(Object? json) {
    final map = _map(json);
    final quiz = map['todayQuiz'];
    return Person(
      username: map['username'] as String,
      displayName: map['displayName'] as String?,
      avatarId: map['avatarId'] as String?,
      stats: PublicStats.fromJson(map['stats']),
      relation:
          Relation.values
              .where((relation) => relation.name == map['relation'])
              .firstOrNull ??
          Relation.none,
      todayQuiz: quiz is Map
          ? (correct: _int(quiz['correct']), total: _int(quiz['total']))
          : null,
    );
  }

  static Map<String, dynamic> personToJson(Person person) => {
    'username': person.username,
    'displayName': person.displayName,
    'avatarId': person.avatarId,
    'stats': person.stats.toJson(),
    'relation': person.relation.name,
    if (person.todayQuiz case final quiz?)
      'todayQuiz': {'correct': quiz.correct, 'total': quiz.total},
  };

  static SocialMe me(Object? json) {
    final map = _map(json);
    return SocialMe(
      username: map['username'] as String?,
      stats: PublicStats.fromJson(map['stats']),
    );
  }

  static Map<String, dynamic> meToJson(SocialMe me) => {
    'username': me.username,
    'stats': me.stats.toJson(),
  };

  static FriendsOverview friends(Object? json) {
    final map = _map(json);
    List<Person> people(String key) => [
      for (final item in map[key] as List? ?? const []) person(item),
    ];
    return FriendsOverview(
      friends: people('friends'),
      incoming: people('incoming'),
      outgoing: people('outgoing'),
    );
  }

  static Map<String, dynamic> friendsToJson(FriendsOverview overview) => {
    'friends': [for (final p in overview.friends) personToJson(p)],
    'incoming': [for (final p in overview.incoming) personToJson(p)],
    'outgoing': [for (final p in overview.outgoing) personToJson(p)],
  };

  // --- Cheers, nudges and shares --------------------------------------------

  static ReceivedPing ping(Object? json) {
    final map = _map(json);
    return ReceivedPing(
      id: _int(map['id']),
      kind:
          PingKind.values
              .where((kind) => kind.name == map['kind'])
              .firstOrNull ??
          PingKind.cheer,
      sender: person(map['sender']),
      createdAt: DateTime.parse(map['createdAt'] as String).toLocal(),
      seen: map['seen'] == true,
      shareCode: map['shareCode'] as String?,
      shareTitle: map['shareTitle'] as String?,
    );
  }

  static List<ReceivedPing> pings(Object? json) => [
    for (final item in json as List? ?? const []) ping(item),
  ];

  static Map<String, dynamic> pingToJson(ReceivedPing ping) => {
    'id': ping.id,
    'kind': ping.kind.name,
    'sender': personToJson(ping.sender),
    'createdAt': ping.createdAt.toUtc().toIso8601String(),
    'seen': ping.seen,
    'shareCode': ping.shareCode,
    'shareTitle': ping.shareTitle,
  };

  // --- Everything the Friends tab needs, in one ------------------------------

  static SocialSummary summary(Object? json) {
    final map = _map(json);
    return SocialSummary(
      me: me(map['me']),
      friends: friends(map['friends']),
      pings: pings(map['pings']),
    );
  }

  static Map<String, dynamic> summaryToJson(SocialSummary summary) => {
    'me': meToJson(summary.me),
    'friends': friendsToJson(summary.friends),
    'pings': [for (final p in summary.pings) pingToJson(p)],
  };

  // --- The leaderboard -------------------------------------------------------

  static LeaderboardEntry entry(Object? json) {
    final map = _map(json);
    return LeaderboardEntry(
      rank: _int(map['rank']),
      person: person(map['person']),
      isMe: map['isMe'] == true,
      weekXp: _int(map['weekXp']),
      quizzes: _int(map['quizzes']),
      correct: _int(map['correct']),
      quizXp: _int(map['quizXp']),
      videoXp: _int(map['videoXp']),
      dialogueXp: _int(map['dialogueXp']),
      flashcardXp: _int(map['flashcardXp']),
      todayXp: _int(map['todayXp']),
    );
  }

  static Map<String, dynamic> entryToJson(LeaderboardEntry entry) => {
    'rank': entry.rank,
    'person': personToJson(entry.person),
    'isMe': entry.isMe,
    'weekXp': entry.weekXp,
    'quizzes': entry.quizzes,
    'correct': entry.correct,
    'quizXp': entry.quizXp,
    'videoXp': entry.videoXp,
    'dialogueXp': entry.dialogueXp,
    'flashcardXp': entry.flashcardXp,
    'todayXp': entry.todayXp,
  };

  static Leaderboard leaderboard(Object? json) {
    final map = _map(json);
    return Leaderboard(
      scope: map['scope'] == 'everyone'
          ? LeaderboardScope.everyone
          : LeaderboardScope.friends,
      weekStart: DateTime.parse(map['weekStart'] as String),
      entries: [for (final item in map['entries'] as List) entry(item)],
      me: map['me'] == null ? null : entry(map['me']),
      participants: _int(map['participants']),
    );
  }

  static Map<String, dynamic> leaderboardToJson(Leaderboard board) => {
    'scope': board.scope.name,
    'weekStart': _day(board.weekStart),
    'entries': [for (final e in board.entries) entryToJson(e)],
    'me': board.me == null ? null : entryToJson(board.me!),
    'participants': board.participants,
  };

  // --- Profiles ---------------------------------------------------------------

  static WeekStanding? _week(Object? json) {
    if (json is! Map) return null;
    return WeekStanding(
      rank: _int(json['rank']),
      xp: _int(json['xp']),
      participants: _int(json['participants']),
    );
  }

  static Map<String, dynamic>? _weekToJson(WeekStanding? week) => week == null
      ? null
      : {'rank': week.rank, 'xp': week.xp, 'participants': week.participants};

  static ProfileVisibility visibility(Object? name) =>
      ProfileVisibility.values.where((v) => v.name == name).firstOrNull ??
      ProfileVisibility.everyone;

  static PublicProfile profile(Object? json) {
    final map = _map(json);
    return PublicProfile(
      person: person(map['person']),
      isMe: map['isMe'] == true,
      visible: map['visible'] != false,
      visibility: visibility(map['visibility']),
      joined: DateTime.tryParse(map['joined'] as String? ?? ''),
      currentStreak: (map['currentStreak'] as num?)?.toInt(),
      bestStreak: (map['bestStreak'] as num?)?.toInt(),
      xp: (map['xp'] as num?)?.toInt(),
      level: (map['level'] as num?)?.toInt(),
      thisWeek: _week(map['thisWeek']),
      lastWeek: _week(map['lastWeek']),
    );
  }

  static Map<String, dynamic> profileToJson(PublicProfile profile) => {
    'person': personToJson(profile.person),
    'isMe': profile.isMe,
    'visible': profile.visible,
    'visibility': profile.visibility.name,
    'joined': profile.joined == null ? null : _day(profile.joined!),
    'currentStreak': profile.currentStreak,
    'bestStreak': profile.bestStreak,
    'xp': profile.xp,
    'level': profile.level,
    'thisWeek': _weekToJson(profile.thisWeek),
    'lastWeek': _weekToJson(profile.lastWeek),
  };
}
