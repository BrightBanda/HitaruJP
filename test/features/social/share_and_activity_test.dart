import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/share_video_sheet.dart';
import 'package:ingrain/features/social/presentation/view/friends_panel.dart';
import 'package:ingrain/features/social/presentation/view/leaderboard_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

const ken = Person(
  username: 'ken',
  displayName: 'Ken',
  avatarId: 'shiba',
  relation: Relation.friends,
);

final video = ContentItem(
  id: 'abc123',
  sourceUrl: 'https://www.youtube.com/watch?v=abc123',
  sourceType: SourceType.youtube,
  title: 'Curry at home',
  channelTitle: 'Kitchen Kotoba',
  lastOpenedAt: DateTime(2026, 11, 25),
);

void main() {
  late FakeSocialRepository social;
  late ProviderContainer container;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: appTestOverrides(
        prefs,
        session: FakeAuthSession(uid: 'u1', name: 'Aiko'),
        social: social,
      ),
    );
    addTearDown(container.dispose);
    container.read(authViewModelProvider);
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setUpContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  setUp(() => social = FakeSocialRepository(username: 'aiko'));

  testWidgets('a video goes to a friend from the share sheet', (tester) async {
    social.friendsList.add(ken);
    await pump(tester, Scaffold(body: ShareVideoSheet(video: video)));

    expect(find.text('Send to a friend'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
    await tester.tap(find.text('Ken'));
    await tester.pumpAndSettle();

    expect(find.text('Sent'), findsOneWidget);
    final shared = social.shares.single;
    expect(shared.videos.single.videoId, 'abc123');
    expect(social.sharedWith.single, (username: 'ken', code: shared.code));
  });

  testWidgets('without friends, the sheet points to finding some', (
    tester,
  ) async {
    await pump(tester, Scaffold(body: ShareVideoSheet(video: video)));
    expect(find.text('Find people'), findsOneWidget);
  });

  testWidgets('a shared video shows in Friends with a way to add it', (
    tester,
  ) async {
    social.received.add(
      ReceivedPing(
        id: 1,
        kind: PingKind.share,
        sender: ken,
        createdAt: DateTime.now(),
        seen: false,
        shareCode: 'ABCD2345',
        shareTitle: 'Curry at home',
      ),
    );
    await pump(tester, const Scaffold(body: FriendsPanel()));
    expect(find.text('Ken shared "Curry at home"'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('the board shows where each learner\'s XP came from', (
    tester,
  ) async {
    await pump(tester, const LeaderboardView());
    expect(find.text("This week's XP"), findsOneWidget);
    expect(
      find.textContaining('videos, dialogues and flashcards'),
      findsOneWidget,
    );
  });

  test('video, dialogue and flashcard XP is reported for the board', () async {
    await setUpContainer();
    final now = DateTime.now();
    final immersion = container.read(immersionRepositoryProvider);
    final session = await immersion.startSession(
      sourceId: 'abc123',
      activityType: ActivityType.watching,
      startedAt: now.subtract(const Duration(minutes: 20)),
    );
    await immersion.updateDuration(session.id, 10 * 60);
    await immersion.stopSession(session.id, now);

    await container.read(progressViewModelProvider.notifier).refresh();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final today = social.reported.firstWhere(
      (day) => day.day == quizDayKey(now),
    );
    expect(today.videos, 20); // 10 minutes at 2 XP
    expect(today.dialogues, 0);
  });
}
