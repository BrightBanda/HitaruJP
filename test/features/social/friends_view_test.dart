import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/social/data/remote_social_repository.dart';
import 'package:ingrain/core/network/api_client.dart';
import 'package:ingrain/core/error/app_error.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/view/friends_panel.dart';
import 'package:ingrain/features/social/presentation/view/leaderboard_view.dart';
import 'package:ingrain/features/social/presentation/view/search_people_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

const ken = Person(
  username: 'ken',
  displayName: 'Ken',
  avatarId: 'shiba',
  stats: PublicStats(level: 7, streak: 4),
);

void main() {
  late FakeSocialRepository social;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: appTestOverrides(
        prefs,
        session: FakeAuthSession(uid: 'u1', name: 'Aiko'),
        social: social,
      ),
    );
    addTearDown(container.dispose);
    container.read(authViewModelProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  setUp(() => social = FakeSocialRepository());

  testWidgets('first visit asks for a username, then shows the tabs', (
    tester,
  ) async {
    await pump(tester, const Scaffold(body: FriendsPanel()));
    expect(find.text('Choose a username'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Aiko_Chan');
    await tester.tap(find.text('Save username'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(social.username, 'aiko_chan');
    expect(find.text('@aiko_chan'), findsOneWidget);
    expect(find.text('Find'), findsOneWidget);
  });

  testWidgets('a taken username is explained', (tester) async {
    social.people.add(ken);
    await pump(tester, const Scaffold(body: FriendsPanel()));
    await tester.enterText(find.byType(TextField), 'ken');
    await tester.tap(find.text('Save username'));
    await tester.pumpAndSettle();
    expect(find.text('That username is taken. Try another.'), findsOneWidget);
  });

  testWidgets('cheering a friend sends it and says how many are left', (
    tester,
  ) async {
    social
      ..username = 'aiko'
      ..friendsList.add(ken.withRelation(Relation.friends));
    await pump(tester, const Scaffold(body: FriendsPanel()));

    expect(find.text('Ken'), findsOneWidget);
    expect(find.text('No quiz yet today'), findsOneWidget);
    await tester.tap(find.text('🎉'));
    await tester.pumpAndSettle();

    expect(social.sentPings.single, (username: 'ken', kind: PingKind.cheer));
    expect(find.textContaining('2 left this hour'), findsOneWidget);
  });

  testWidgets('past the limit, a nudge is refused with the reason', (
    tester,
  ) async {
    social
      ..username = 'aiko'
      ..hourRemaining = 0
      ..friendsList.add(ken.withRelation(Relation.friends));
    await pump(tester, const Scaffold(body: FriendsPanel()));

    await tester.tap(find.text('👋'));
    await tester.pumpAndSettle();
    expect(social.sentPings, isEmpty);
    expect(find.textContaining('3 cheers and nudges an hour'), findsOneWidget);
  });

  testWidgets('a friend request can be accepted', (tester) async {
    social
      ..username = 'aiko'
      ..incoming.add(ken.withRelation(Relation.incoming));
    await pump(tester, const Scaffold(body: FriendsPanel()));

    expect(find.text('Friend requests · 1'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(social.friendsList.single.username, 'ken');
    expect(find.text('Friend requests · 1'), findsNothing);
    expect(find.text('Quiz today: 0/0'), findsNothing);
    expect(find.text('Ken'), findsOneWidget);
  });

  testWidgets('the leaderboard is public, with friends a tap away', (
    tester,
  ) async {
    const stranger = Person(username: 'mio', avatarId: 'usagi');
    social
      ..username = 'aiko'
      ..people.add(stranger)
      ..friendsList.add(ken.withRelation(Relation.friends))
      ..quizzes.add((day: '2026-11-25', correct: 10, total: 12));
    await pump(tester, const LeaderboardView());

    // Everyone first: strangers too.
    expect(find.text("This week's XP"), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('@mio'), findsOneWidget);
    expect(find.text('50 XP'), findsOneWidget);
    expect(find.text('🥇'), findsOneWidget);
    expect(find.text("Start today's quiz"), findsOneWidget);

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('@mio'), findsNothing);
    expect(find.text('Ken'), findsOneWidget);
  });

  testWidgets('tapping someone on the board offers to add them', (
    tester,
  ) async {
    const stranger = Person(username: 'mio', avatarId: 'usagi');
    social
      ..username = 'aiko'
      ..people.add(stranger);
    await pump(tester, const LeaderboardView());

    await tester.tap(find.text('@mio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add friend'));
    await tester.pumpAndSettle();
    expect(find.text('Request sent'), findsOneWidget);
    expect(social.outgoing.single.username, 'mio');
  });

  testWidgets('search finds people by username and sends a request', (
    tester,
  ) async {
    social
      ..username = 'aiko'
      ..people.add(ken);
    await pump(tester, const SearchPeopleView());

    await tester.enterText(find.byType(TextField), '@ke');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Ken'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Requested'), findsOneWidget);
    expect(social.outgoing.single.username, 'ken');
  });

  group('RemoteSocialRepository', () {
    test('reads a person card', () {
      final person = RemoteSocialRepository.person({
        'username': 'ken',
        'displayName': 'Ken',
        'avatarId': 'shiba',
        'stats': {'level': 12, 'stage': 'teen', 'streak': 14},
        'relation': 'friends',
        'todayQuiz': {'correct': 10, 'total': 12},
      });
      expect(person.stats.level, 12);
      expect(person.stats.stage.name, 'teen');
      expect(person.relation, Relation.friends);
      expect(person.todayQuiz, (correct: 10, total: 12));
    });

    test('finds the code in whatever was pasted', () {
      expect(RemoteSocialRepository.normaliseCode('abcd2345'), 'ABCD2345');
      expect(
        RemoteSocialRepository.normaliseCode(
          'Try my deck! ... enter the code QRST6789',
        ),
        'QRST6789',
      );
    });

    test('explains the ping limits', () {
      ApiException limit(String per) => ApiException(
        const AppError(type: AppErrorType.rateLimited),
        status: 429,
        code: 'ping_limit',
        detail: {'per': per, 'hourly_limit': 3, 'daily_limit': 7},
      );
      expect(
        RemoteSocialRepository.messageFor(limit('hour')),
        contains('3 cheers and nudges an hour'),
      );
      expect(
        RemoteSocialRepository.messageFor(limit('day')),
        contains('7 cheers and nudges today'),
      );
    });
  });
}
