import 'package:ingrain/core/network/api_client.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/social/domain/social.dart';

/// [SocialRepository] on the HitaruJP API's `/social` and `/shares` routes.
class RemoteSocialRepository implements SocialRepository {
  final ApiClient _api;

  RemoteSocialRepository(this._api);

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on ApiException catch (error) {
      throw SocialException(
        messageFor(error),
        code: error.code ?? (error.status == 404 ? 'not_found' : null),
      );
    }
  }

  /// What to tell the learner for a refused request. Public for tests.
  static String messageFor(ApiException error) {
    final detail = error.detail;
    return switch (error.code) {
      'username_taken' => 'That username is taken. Try another.',
      'username_required' => 'Choose a username first.',
      'user_not_found' => 'No one has that username.',
      'already_friends' => "You're already friends.",
      'not_friends' => 'You can only cheer and nudge friends.',
      'ping_limit' =>
        detail['per'] == 'day'
            ? "You've sent ${detail['daily_limit'] ?? 7} cheers and nudges "
                  'today. More tomorrow!'
            : 'You can send ${detail['hourly_limit'] ?? 3} cheers and nudges '
                  'an hour. Try again a little later.',
      'quiz_done' => "Today's quiz is already done.",
      'share_not_found' =>
        'No collection has that code. Check it and try again.',
      'share_limit' =>
        "You've shared ${detail['daily_limit'] ?? 20} things today. More "
            'tomorrow!',
      'empty_share' => 'There is nothing to share yet.',
      'terms_not_accepted' => 'Accept the terms to use friends.',
      _ when error.status == 422 =>
        'Usernames are 3 to 20 lowercase letters, numbers or _.',
      _ => error.error.message ?? 'Something went wrong. Try again.',
    };
  }

  @override
  Future<SocialMe> me() => _call(() async => _me(await _api.get('/social/me')));

  @override
  Future<SocialMe> setUsername(String username) => _call(
    () async => _me(await _api.put('/social/username', {'username': username})),
  );

  @override
  Future<void> setStats(PublicStats stats) =>
      _call(() => _api.put('/social/stats', stats.toJson()));

  @override
  Future<List<Person>> search(String query) => _call(() async {
    final body = await _api.get('/social/search', query: {'q': query});
    return [for (final item in body! as List) person(item)];
  });

  @override
  Future<PublicProfile> profile(String username, {required DateTime today}) =>
      _call(() async {
        final map = _map(
          await _api.get(
            '/social/people/${Uri.encodeComponent(username)}',
            query: {'today': quizDayKey(today)},
          ),
        );
        WeekStanding? week(Object? json) {
          if (json is! Map) return null;
          return WeekStanding(
            rank: (json['rank'] as num).toInt(),
            xp: (json['xp'] as num).toInt(),
            participants: (json['participants'] as num).toInt(),
          );
        }

        return PublicProfile(
          person: person(map['person']),
          isMe: map['isMe'] == true,
          visible: map['visible'] != false,
          visibility: _visibility(map['visibility']),
          joined: DateTime.tryParse(map['joined'] as String? ?? ''),
          currentStreak: (map['currentStreak'] as num?)?.toInt(),
          bestStreak: (map['bestStreak'] as num?)?.toInt(),
          xp: (map['xp'] as num?)?.toInt(),
          level: (map['level'] as num?)?.toInt(),
          thisWeek: week(map['thisWeek']),
          lastWeek: week(map['lastWeek']),
        );
      });

  @override
  Future<ProfileVisibility> privacy() => _call(
    () async => _visibility(
      _map(await _api.get('/social/privacy'))['profileVisibility'],
    ),
  );

  @override
  Future<void> setPrivacy(ProfileVisibility visibility) => _call(
    () => _api.put('/social/privacy', {'profileVisibility': visibility.name}),
  );

  static ProfileVisibility _visibility(Object? name) =>
      ProfileVisibility.values.where((v) => v.name == name).firstOrNull ??
      ProfileVisibility.everyone;

  @override
  Future<FriendsOverview> friends({required DateTime today}) => _call(() async {
    final body = _map(
      await _api.get('/social/friends', query: {'today': quizDayKey(today)}),
    );
    List<Person> people(String key) => [
      for (final item in body[key] as List? ?? const []) person(item),
    ];
    return FriendsOverview(
      friends: people('friends'),
      incoming: people('incoming'),
      outgoing: people('outgoing'),
    );
  });

  @override
  Future<Person> addFriend(String username) => _call(
    () async =>
        person(await _api.post('/social/friends', {'username': username})),
  );

  @override
  Future<Person> acceptFriend(String username) => _call(
    () async => person(
      await _api.post(
        '/social/friends/${Uri.encodeComponent(username)}/accept',
      ),
    ),
  );

  @override
  Future<void> removeFriend(String username) => _call(
    () => _api.delete('/social/friends/${Uri.encodeComponent(username)}'),
  );

  @override
  Future<PingAllowance> ping(String username, PingKind kind) => _call(
    () async => _allowance(
      await _api.post('/social/pings', {
        'username': username,
        'kind': kind.name,
      }),
    ),
  );

  @override
  Future<PingAllowance> pingAllowance() =>
      _call(() async => _allowance(await _api.get('/social/pings/allowance')));

  @override
  Future<List<ReceivedPing>> pings() => _call(() async {
    final body = await _api.get('/social/pings');
    return [
      for (final item in body! as List)
        () {
          final map = _map(item);
          return ReceivedPing(
            id: (map['id'] as num).toInt(),
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
        }(),
    ];
  });

  @override
  Future<void> markPingsSeen() => _call(() => _api.post('/social/pings/seen'));

  @override
  Future<void> shareWithFriend(String username, String code) => _call(
    () => _api.post('/social/share', {'username': username, 'code': code}),
  );

  @override
  Future<void> reportActivity(List<ActivityDay> days) => _call(
    () => _api.put('/social/activity', {
      'days': [for (final day in days) day.toJson()],
    }),
  );

  @override
  Future<int> submitQuiz({
    required String day,
    required int correct,
    required int total,
  }) => _call(() async {
    final body = _map(
      await _api.post('/social/quiz', {
        'day': day,
        'correct': correct,
        'total': total,
      }),
    );
    return (body['xp'] as num).toInt();
  });

  @override
  Future<Leaderboard> leaderboard({
    required DateTime today,
    LeaderboardScope scope = LeaderboardScope.friends,
  }) => _call(() async {
    final body = _map(
      await _api.get(
        '/social/leaderboard',
        query: {'today': quizDayKey(today), 'scope': scope.name},
      ),
    );
    return Leaderboard(
      scope: body['scope'] == 'everyone'
          ? LeaderboardScope.everyone
          : LeaderboardScope.friends,
      weekStart: DateTime.parse(body['weekStart'] as String),
      entries: [for (final item in body['entries'] as List) entry(item)],
      me: body['me'] == null ? null : entry(body['me']),
      participants: (body['participants'] as num?)?.toInt() ?? 0,
    );
  });

  /// Public for tests.
  static LeaderboardEntry entry(Object? json) {
    final map = _map(json);
    return LeaderboardEntry(
      rank: (map['rank'] as num).toInt(),
      person: person(map['person']),
      isMe: map['isMe'] == true,
      weekXp: (map['weekXp'] as num).toInt(),
      quizzes: (map['quizzes'] as num).toInt(),
      correct: (map['correct'] as num).toInt(),
      quizXp: (map['quizXp'] as num?)?.toInt() ?? 0,
      videoXp: (map['videoXp'] as num?)?.toInt() ?? 0,
      dialogueXp: (map['dialogueXp'] as num?)?.toInt() ?? 0,
      flashcardXp: (map['flashcardXp'] as num?)?.toInt() ?? 0,
      todayXp: (map['todayXp'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<SharedCollection> createShare({
    required ShareKind kind,
    required String title,
    List<SharedVideo> videos = const [],
    List<SharedCard> cards = const [],
  }) => _call(
    () async => shared(
      await _api.post('/shares', {
        'kind': kind.name,
        'title': title,
        'videos': [
          for (final video in videos)
            {
              'videoId': video.videoId,
              'title': video.title,
              if (video.channelTitle != null)
                'channelTitle': video.channelTitle,
              if (video.thumbnailUrl != null)
                'thumbnailUrl': video.thumbnailUrl,
            },
        ],
        'cards': [
          for (final card in cards)
            {'front': card.front, if (card.back != null) 'back': card.back},
        ],
      }),
    ),
  );

  @override
  Future<SharedCollection> share(String code) => _call(
    () async => shared(
      await _api.get('/shares/${Uri.encodeComponent(normaliseCode(code))}'),
    ),
  );

  /// `abcd-2345`, a pasted link or a whole message with the code in it, to
  /// `ABCD2345`. Public for tests.
  static String normaliseCode(String input) {
    final joined = input.replaceAllMapped(
      RegExp(r'\b([A-Za-z0-9]{4})-([A-Za-z0-9]{4})\b'),
      (m) => '${m[1]}${m[2]}',
    );
    final words = RegExp(r'\b[A-HJ-NP-Za-hj-np-z2-9]{8}\b')
        .allMatches(joined)
        .map((m) => m.group(0)!)
        .toList();
    // In a message, the code is the word in capitals or with digits in it.
    final code = words.lastWhere(
      (w) => w == w.toUpperCase() || RegExp(r'\d').hasMatch(w),
      orElse: () => words.isEmpty ? input : words.last,
    );
    return code.trim().toUpperCase();
  }

  // --- JSON ----------------------------------------------------------------

  static Map<String, dynamic> _map(Object? json) =>
      Map<String, dynamic>.from(json! as Map);

  static SocialMe _me(Object? json) {
    final map = _map(json);
    return SocialMe(
      username: map['username'] as String?,
      stats: PublicStats.fromJson(map['stats']),
    );
  }

  static PingAllowance _allowance(Object? json) {
    final map = _map(json);
    return PingAllowance(
      hourRemaining: (map['hourRemaining'] as num).toInt(),
      dayRemaining: (map['dayRemaining'] as num).toInt(),
    );
  }

  /// Public for tests.
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
          ? (
              correct: (quiz['correct'] as num).toInt(),
              total: (quiz['total'] as num).toInt(),
            )
          : null,
    );
  }

  /// Public for tests.
  static SharedCollection shared(Object? json) {
    final map = _map(json);
    return SharedCollection(
      code: map['code'] as String,
      kind: map['kind'] == 'deck' ? ShareKind.deck : ShareKind.playlist,
      title: map['title'] as String,
      owner: map['owner'] as String?,
      videos: [
        for (final item in map['videos'] as List? ?? const [])
          () {
            final video = _map(item);
            return SharedVideo(
              videoId: video['videoId'] as String,
              title: video['title'] as String,
              channelTitle: video['channelTitle'] as String?,
              thumbnailUrl: video['thumbnailUrl'] as String?,
            );
          }(),
      ],
      cards: [
        for (final item in map['cards'] as List? ?? const [])
          () {
            final card = _map(item);
            return SharedCard(
              front: card['front'] as String,
              back: card['back'] as String?,
            );
          }(),
      ],
    );
  }
}
