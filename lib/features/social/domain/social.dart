import 'package:ingrain/features/growth/domain/growth_rules.dart';

/// How another learner stands with this one.
enum Relation { none, friends, outgoing, incoming }

/// What a learner shows others: worked out by their app from their history.
/// Who sees the streaks, XP and join date is up to their privacy setting.
class PublicStats {
  final int level;
  final GrowthStage stage;
  final int streak;
  final int bestStreak;
  final int xp;
  final DateTime? joined;

  const PublicStats({
    this.level = 1,
    this.stage = GrowthStage.egg,
    this.streak = 0,
    this.bestStreak = 0,
    this.xp = 0,
    this.joined,
  });

  Map<String, dynamic> toJson() => {
    'level': level,
    'stage': stage.name,
    'streak': streak,
    'bestStreak': bestStreak,
    'xp': xp,
    if (joined case final joined?)
      'joined':
          '${joined.year.toString().padLeft(4, '0')}-'
          '${joined.month.toString().padLeft(2, '0')}-'
          '${joined.day.toString().padLeft(2, '0')}',
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
      bestStreak: (map['bestStreak'] as num?)?.toInt() ?? 0,
      xp: (map['xp'] as num?)?.toInt() ?? 0,
      joined: DateTime.tryParse(map['joined'] as String? ?? ''),
    );
  }
}

/// Who may see a learner's profile stats.
enum ProfileVisibility {
  everyone('Everyone'),
  friends('Friends only'),
  private('Only me');

  const ProfileVisibility(this.label);

  final String label;
}

/// A place on the public board for one week.
class WeekStanding {
  final int rank;
  final int xp;
  final int participants;

  const WeekStanding({
    required this.rank,
    required this.xp,
    required this.participants,
  });
}

/// Someone's profile page. With [visible] false their stats are private to
/// this viewer, and every stat is null.
class PublicProfile {
  final Person person;
  final bool isMe;
  final bool visible;
  final ProfileVisibility visibility;
  final DateTime? joined;
  final int? currentStreak;
  final int? bestStreak;
  final int? xp;
  final int? level;
  final WeekStanding? thisWeek;
  final WeekStanding? lastWeek;

  const PublicProfile({
    required this.person,
    this.isMe = false,
    this.visible = true,
    this.visibility = ProfileVisibility.everyone,
    this.joined,
    this.currentStreak,
    this.bestStreak,
    this.xp,
    this.level,
    this.thisWeek,
    this.lastWeek,
  });
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

/// A cheer is a pat on the back; a nudge, a reminder to study; a share,
/// something sent to watch or study.
enum PingKind { cheer, nudge, share }

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

  /// For a share: the code to import it, and what it is.
  final String? shareCode;
  final String? shareTitle;

  const ReceivedPing({
    required this.id,
    required this.kind,
    required this.sender,
    required this.createdAt,
    required this.seen,
    this.shareCode,
    this.shareTitle,
  });
}

/// One day's XP from videos, dialogues and flashcards, for the leaderboard.
class ActivityDay {
  /// `2026-11-25`.
  final String day;
  final int videos;
  final int dialogues;
  final int flashcards;

  const ActivityDay({
    required this.day,
    this.videos = 0,
    this.dialogues = 0,
    this.flashcards = 0,
  });

  Map<String, dynamic> toJson() => {
    'day': day,
    'videos': videos,
    'dialogues': dialogues,
    'flashcards': flashcards,
  };
}

class LeaderboardEntry {
  final int rank;
  final Person person;
  final bool isMe;

  /// The week's XP: the four sources below added up.
  final int weekXp;
  final int quizzes;
  final int correct;
  final int quizXp;
  final int videoXp;
  final int dialogueXp;
  final int flashcardXp;

  /// XP earned today, all sources.
  final int todayXp;

  const LeaderboardEntry({
    required this.rank,
    required this.person,
    required this.isMe,
    required this.weekXp,
    required this.quizzes,
    required this.correct,
    this.quizXp = 0,
    this.videoXp = 0,
    this.dialogueXp = 0,
    this.flashcardXp = 0,
    this.todayXp = 0,
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

  /// [username]'s profile page, as this learner may see it.
  Future<PublicProfile> profile(String username, {required DateTime today});

  Future<ProfileVisibility> privacy();

  Future<void> setPrivacy(ProfileVisibility visibility);

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

  /// Sends a friend something shared, by its code.
  Future<void> shareWithFriend(String username, String code);

  /// The learner's XP from videos, dialogues and flashcards, day by day.
  Future<void> reportActivity(List<ActivityDay> days);

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
