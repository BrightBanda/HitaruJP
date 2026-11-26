import 'package:ingrain/features/social/domain/social.dart';

/// An in-memory friends service: a few learners to find, and a record of
/// what the app sent.
class FakeSocialRepository implements SocialRepository {
  FakeSocialRepository({this.username});

  String? username;
  PublicStats? lastStats;
  final List<Person> people = [];
  final List<Person> friendsList = [];
  final List<Person> incoming = [];
  final List<Person> outgoing = [];
  final List<ReceivedPing> received = [];
  final List<({String username, PingKind kind})> sentPings = [];
  final List<({String day, int correct, int total})> quizzes = [];
  final List<SharedCollection> shares = [];
  int hourRemaining = 3;
  int dayRemaining = 7;

  /// Set to make every call fail with it.
  Object? error;

  void _check() {
    final error = this.error;
    if (error != null) throw error;
  }

  @override
  Future<SocialMe> me() async {
    _check();
    return SocialMe(
      username: username,
      stats: lastStats ?? const PublicStats(),
    );
  }

  @override
  Future<SocialMe> setUsername(String username) async {
    _check();
    if (people.any((p) => p.username == username)) {
      throw const SocialException(
        'That username is taken. Try another.',
        code: 'username_taken',
      );
    }
    this.username = username;
    return SocialMe(username: username);
  }

  @override
  Future<void> setStats(PublicStats stats) async {
    _check();
    lastStats = stats;
  }

  @override
  Future<List<Person>> search(String query) async {
    _check();
    return [
      for (final person in people)
        if (person.username.startsWith(query)) person,
    ];
  }

  @override
  Future<FriendsOverview> friends({required DateTime today}) async {
    _check();
    return FriendsOverview(
      friends: [...friendsList],
      incoming: [...incoming],
      outgoing: [...outgoing],
    );
  }

  @override
  Future<Person> addFriend(String username) async {
    _check();
    final person = people.firstWhere((p) => p.username == username);
    final asked = incoming.where((p) => p.username == username).firstOrNull;
    if (asked != null) {
      incoming.remove(asked);
      final friend = person.withRelation(Relation.friends);
      friendsList.add(friend);
      return friend;
    }
    final request = person.withRelation(Relation.outgoing);
    outgoing.add(request);
    return request;
  }

  @override
  Future<Person> acceptFriend(String username) async {
    _check();
    final asked = incoming.firstWhere((p) => p.username == username);
    incoming.remove(asked);
    final friend = asked.withRelation(Relation.friends);
    friendsList.add(friend);
    return friend;
  }

  @override
  Future<void> removeFriend(String username) async {
    _check();
    for (final list in [friendsList, incoming, outgoing]) {
      list.removeWhere((p) => p.username == username);
    }
  }

  @override
  Future<PingAllowance> ping(String username, PingKind kind) async {
    _check();
    if (hourRemaining == 0 || dayRemaining == 0) {
      throw const SocialException(
        'You can send 3 cheers and nudges an hour.',
        code: 'ping_limit',
      );
    }
    sentPings.add((username: username, kind: kind));
    hourRemaining--;
    dayRemaining--;
    return PingAllowance(
      hourRemaining: hourRemaining,
      dayRemaining: dayRemaining,
    );
  }

  @override
  Future<PingAllowance> pingAllowance() async =>
      PingAllowance(hourRemaining: hourRemaining, dayRemaining: dayRemaining);

  @override
  Future<List<ReceivedPing>> pings() async {
    _check();
    return [...received];
  }

  int seenCalls = 0;
  final List<({String username, String code})> sharedWith = [];
  final List<ActivityDay> reported = [];

  @override
  Future<void> shareWithFriend(String username, String code) async {
    _check();
    sharedWith.add((username: username, code: code));
  }

  @override
  Future<void> reportActivity(List<ActivityDay> days) async {
    _check();
    reported
      ..clear()
      ..addAll(days);
  }

  @override
  Future<void> markPingsSeen() async => seenCalls++;

  @override
  Future<int> submitQuiz({
    required String day,
    required int correct,
    required int total,
  }) async {
    _check();
    if (quizzes.any((q) => q.day == day)) {
      throw const SocialException('done', code: 'quiz_done');
    }
    quizzes.add((day: day, correct: correct, total: total));
    return correct * 5 + (correct == total ? 10 : 0);
  }

  @override
  Future<Leaderboard> leaderboard({
    required DateTime today,
    LeaderboardScope scope = LeaderboardScope.friends,
  }) async {
    _check();
    final me = Person(username: username ?? 'me');
    final mine = quizzes.fold(0, (sum, q) => sum + q.correct * 5);
    final entries = [
      (person: me, xp: mine, isMe: true),
      for (final friend in friendsList) (person: friend, xp: 30, isMe: false),
      if (scope == LeaderboardScope.everyone)
        for (final stranger in people) (person: stranger, xp: 20, isMe: false),
    ]..sort((a, b) => b.xp.compareTo(a.xp));
    return Leaderboard(
      scope: scope,
      participants: entries.length,
      weekStart: today,
      entries: [
        for (final (i, e) in entries.indexed)
          LeaderboardEntry(
            rank: i + 1,
            person: e.person,
            isMe: e.isMe,
            weekXp: e.xp,
            quizzes: e.isMe ? quizzes.length : 1,
            correct: e.xp ~/ 5,
          ),
      ],
    );
  }

  @override
  Future<SharedCollection> createShare({
    required ShareKind kind,
    required String title,
    List<SharedVideo> videos = const [],
    List<SharedCard> cards = const [],
  }) async {
    _check();
    final shared = SharedCollection(
      code: 'ABCD${2345 + shares.length}',
      kind: kind,
      title: title,
      owner: username,
      videos: videos,
      cards: cards,
    );
    shares.add(shared);
    return shared;
  }

  @override
  Future<SharedCollection> share(String code) async {
    _check();
    return shares.firstWhere(
      (s) => s.code == code.toUpperCase(),
      orElse: () => throw const SocialException(
        'No collection has that code.',
        code: 'share_not_found',
      ),
    );
  }
}
