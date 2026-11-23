import 'package:ingrain/features/growth/domain/growth_rules.dart';

/// How another learner stands with this one.
enum Relation { none, friends, outgoing, incoming }

/// What a learner shows friends: worked out by their app from their history.
class PublicStats {
  final int level;
  final GrowthStage stage;
  final int streak;

  const PublicStats({
    this.level = 1,
    this.stage = GrowthStage.egg,
    this.streak = 0,
  });

  Map<String, dynamic> toJson() => {
    'level': level,
    'stage': stage.name,
    'streak': streak,
  };

  static PublicStats fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return PublicStats(
      level: (map['level'] as num?)?.toInt() ?? 1,
      stage:
          GrowthStage.values
              .where((stage) => stage.name == map['stage'])
              .firstOrNull ??
          GrowthStage.egg,
      streak: (map['streak'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Another learner, by their @username. Never an email or an id.
class Person {
  final String username;
  final String? displayName;
  final String? avatarId;
  final PublicStats stats;
  final Relation relation;

  /// Their quiz today, when they have done it.
  final ({int correct, int total})? todayQuiz;

  const Person({
    required this.username,
    this.displayName,
    this.avatarId,
    this.stats = const PublicStats(),
    this.relation = Relation.none,
    this.todayQuiz,
  });

  /// Their chosen name, or the @username when they have none.
  String get name {
    final display = displayName?.trim();
    return display == null || display.isEmpty ? '@$username' : display;
  }

  Person withRelation(Relation relation) => Person(
    username: username,
    displayName: displayName,
    avatarId: avatarId,
    stats: stats,
    relation: relation,
    todayQuiz: todayQuiz,
  );
}

class SocialMe {
  final String? username;
  final PublicStats stats;

  const SocialMe({this.username, this.stats = const PublicStats()});
}

class FriendsOverview {
  final List<Person> friends;
  final List<Person> incoming;
  final List<Person> outgoing;

  const FriendsOverview({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
  });
}

/// A cheer is a pat on the back; a nudge, a reminder to study.
enum PingKind { cheer, nudge }

class PingAllowance {
  final int hourRemaining;
  final int dayRemaining;

  const PingAllowance({
    required this.hourRemaining,
    required this.dayRemaining,
  });

  bool get canSend => hourRemaining > 0 && dayRemaining > 0;
}

class ReceivedPing {
  final int id;
  final PingKind kind;
  final Person sender;
  final DateTime createdAt;
  final bool seen;

  const ReceivedPing({
    required this.id,
    required this.kind,
    required this.sender,
    required this.createdAt,
    required this.seen,
  });
}

class LeaderboardEntry {
  final int rank;
  final Person person;
  final bool isMe;
  final int weekXp;
  final int quizzes;
  final int correct;

  const LeaderboardEntry({
    required this.rank,
    required this.person,
    required this.isMe,
    required this.weekXp,
    required this.quizzes,
    required this.correct,
  });
}

/// The public board, or just the learner and their friends.
enum LeaderboardScope { everyone, friends }

class Leaderboard {
  final LeaderboardScope scope;
  final DateTime weekStart;

  /// The top of the board, best first.
  final List<LeaderboardEntry> entries;

  /// The learner's own row, also when it is below [entries].
  final LeaderboardEntry? me;

  /// Learners who took a quiz this week (the public board only).
  final int participants;

  const Leaderboard({
    required this.weekStart,
    required this.entries,
    this.scope = LeaderboardScope.friends,
    this.me,
    this.participants = 0,
  });

  /// The learner is outside [entries] and their row needs showing apart.
  bool get meIsBelow => me != null && !entries.any((entry) => entry.isMe);
}

enum ShareKind { playlist, deck }

class SharedVideo {
  final String videoId;
  final String title;
  final String? channelTitle;
  final String? thumbnailUrl;

  const SharedVideo({
    required this.videoId,
    required this.title,
    this.channelTitle,
    this.thumbnailUrl,
  });
}

class SharedCard {
  final String front;
  final String? back;

  const SharedCard({required this.front, this.back});
}

/// A playlist or deck someone shared, by its code.
class SharedCollection {
  final String code;
  final ShareKind kind;
  final String title;

  /// The sharer's @username, when they have one.
  final String? owner;
  final List<SharedVideo> videos;
  final List<SharedCard> cards;

  const SharedCollection({
    required this.code,
    required this.kind,
    required this.title,
    this.owner,
    this.videos = const [],
    this.cards = const [],
  });

  int get itemCount =>
      kind == ShareKind.playlist ? videos.length : cards.length;
}

/// A refusal the learner can act on: a taken username, a limit reached.
class SocialException implements Exception {
  /// The server's reason, e.g. `username_taken`, `ping_limit`.
  final String? code;
  final String message;

  const SocialException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Friends, cheers and nudges, the quiz leaderboard, shared collections:
/// all kept by the HitaruJP server. Failures arrive as [SocialException].
abstract interface class SocialRepository {
  Future<SocialMe> me();

  /// Claims a unique username: 3 to 20 lowercase letters, digits or `_`.
  Future<SocialMe> setUsername(String username);

  Future<void> setStats(PublicStats stats);

  Future<List<Person>> search(String query);

  Future<FriendsOverview> friends({required DateTime today});

  /// Asks to be friends, or accepts if they asked first.
  Future<Person> addFriend(String username);

  Future<Person> acceptFriend(String username);

  /// Unfriends, declines or cancels.
  Future<void> removeFriend(String username);

  Future<PingAllowance> ping(String username, PingKind kind);

  Future<PingAllowance> pingAllowance();

  Future<List<ReceivedPing>> pings();

  Future<void> markPingsSeen();

  /// Records today's quiz; returns the XP the server counted for it.
  Future<int> submitQuiz({
    required String day,
    required int correct,
    required int total,
  });

  Future<Leaderboard> leaderboard({
    required DateTime today,
    LeaderboardScope scope = LeaderboardScope.friends,
  });

  Future<SharedCollection> createShare({
    required ShareKind kind,
    required String title,
    List<SharedVideo> videos,
    List<SharedCard> cards,
  });

  Future<SharedCollection> share(String code);
}
