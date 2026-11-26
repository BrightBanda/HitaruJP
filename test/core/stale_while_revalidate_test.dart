import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/storage/snapshot_cache.dart';
import 'package:ingrain/core/storage/stale_while_revalidate.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/social/data/social_json.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_overrides.dart';

void main() {
  group('staleWhileRevalidate', () {
    late ProviderContainer container;
    late Completer<String> server;
    var fails = false;

    final provider = StreamProvider<String>(
      (ref) => staleWhileRevalidate(
        ref,
        key: 'greeting',
        fetch: () => fails ? Future.error('offline') : server.future,
        toJson: (value) => value,
        fromJson: (json) => json! as String,
      ),
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      server = Completer<String>();
      fails = false;
    });

    test('shows the kept copy at once, then the fresh one', () async {
      await container.read(snapshotCacheProvider).write('greeting', 'old');
      final seen = <String>[];
      container.listen(provider, (_, next) {
        if (next.value case final value?) seen.add(value);
      }, fireImmediately: true);
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['old']);

      server.complete('new');
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, 'new');
      expect(
        container.read(snapshotCacheProvider).read('greeting', (j) => j),
        'new',
      );
    });

    test('a failed fetch keeps the copy on screen', () async {
      await container.read(snapshotCacheProvider).write('greeting', 'old');
      fails = true;
      container.listen(provider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final state = container.read(provider);
      expect(state.value, 'old');
      expect(state.hasError, isFalse);
    });

    test('with no copy, the error shows', () async {
      fails = true;
      container.listen(provider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(provider).hasError, isTrue);
    });
  });

  test('the social summary round-trips through the device copy', () {
    final summary = SocialSummary(
      me: const SocialMe(
        username: 'aiko',
        stats: PublicStats(level: 12, streak: 14),
      ),
      friends: const FriendsOverview(
        friends: [
          Person(
            username: 'ken',
            displayName: 'Ken',
            relation: Relation.friends,
            todayQuiz: (correct: 10, total: 12),
          ),
        ],
      ),
      pings: [
        ReceivedPing(
          id: 3,
          kind: PingKind.share,
          sender: const Person(username: 'mio'),
          createdAt: DateTime.utc(2026, 11, 25, 9),
          seen: false,
          shareCode: 'ABCD2345',
          shareTitle: 'Curry',
        ),
      ],
    );
    final back = SocialJson.summary(SocialJson.summaryToJson(summary));
    expect(back.me.username, 'aiko');
    expect(back.me.stats.streak, 14);
    expect(back.friends.friends.single.todayQuiz, (correct: 10, total: 12));
    expect(back.pings.single.shareCode, 'ABCD2345');
    expect(back.pings.single.kind, PingKind.share);
  });

  test('a leaderboard round-trips through the device copy', () {
    final board = Leaderboard(
      scope: LeaderboardScope.everyone,
      weekStart: DateTime(2026, 11, 23),
      participants: 1284,
      entries: const [
        LeaderboardEntry(
          rank: 1,
          person: Person(username: 'mio'),
          isMe: false,
          weekXp: 245,
          quizzes: 3,
          correct: 47,
          todayXp: 40,
        ),
      ],
    );
    final back = SocialJson.leaderboard(SocialJson.leaderboardToJson(board));
    expect(back.scope, LeaderboardScope.everyone);
    expect(back.weekStart, DateTime(2026, 11, 23));
    expect(back.participants, 1284);
    expect(back.entries.single.todayXp, 40);
    expect(back.me, isNull);
  });

  test('opening social screens syncs at most every two minutes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final social = _CountingSocial(username: 'aiko');
    final container = ProviderContainer(
      overrides: appTestOverrides(
        prefs,
        session: FakeAuthSession(uid: 'u1', name: 'Aiko'),
        social: social,
      ),
    );
    addTearDown(container.dispose);
    container.read(authViewModelProvider);

    final sync = container.read(socialSyncProvider.notifier);
    await sync.syncIfStale();
    await sync.syncIfStale();
    expect(social.statsCalls, 1);
    await sync.syncAll();
    expect(social.statsCalls, 2);
  });
}

class _CountingSocial extends FakeSocialRepository {
  _CountingSocial({super.username});

  int statsCalls = 0;

  @override
  Future<void> setStats(PublicStats stats) async {
    statsCalls++;
    await super.setStats(stats);
  }
}
