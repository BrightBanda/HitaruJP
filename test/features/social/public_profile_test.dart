import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/settings/presentation/view/settings_view.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/view/public_profile_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

const mio = Person(
  username: 'mio',
  avatarId: 'usagi',
  stats: PublicStats(level: 21, stage: GrowthStage.adult),
);

void main() {
  late FakeSocialRepository social;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(420, 1000);
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

  setUp(() => social = FakeSocialRepository(username: 'aiko'));

  testWidgets('a profile shows join date, streaks, XP and both weeks', (
    tester,
  ) async {
    social.profiles['mio'] = PublicProfile(
      person: mio,
      joined: DateTime(2026, 3, 2),
      currentStreak: 32,
      bestStreak: 40,
      xp: 5400,
      level: 21,
      thisWeek: const WeekStanding(rank: 3, xp: 245, participants: 1284),
      lastWeek: const WeekStanding(rank: 1, xp: 410, participants: 1102),
    );
    await pump(tester, const PublicProfileView(username: 'mio'));

    expect(find.text('Joined'), findsOneWidget);
    expect(find.text('Mar 2026'), findsOneWidget);
    expect(find.text('32 days'), findsOneWidget);
    expect(find.text('40 days'), findsOneWidget);
    expect(find.text('5,400'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('245 XP · of 1,284'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Add friend'), findsOneWidget);
  });

  testWidgets('private stats are not shown', (tester) async {
    social.profiles['mio'] = const PublicProfile(
      person: mio,
      visible: false,
      visibility: ProfileVisibility.private,
    );
    await pump(tester, const PublicProfileView(username: 'mio'));

    expect(find.text('Stats kept private'), findsOneWidget);
    expect(find.text('Best streak'), findsNothing);
  });

  testWidgets('a friend request can be sent from the profile', (tester) async {
    social.people.add(mio);
    await pump(tester, const PublicProfileView(username: 'mio'));

    await tester.tap(find.text('Add friend'));
    await tester.pumpAndSettle();
    expect(find.text('Request sent'), findsOneWidget);
    expect(social.outgoing.single.username, 'mio');
  });

  testWidgets('your own profile says who sees it', (tester) async {
    social.profiles['aiko'] = const PublicProfile(
      person: Person(username: 'aiko'),
      isMe: true,
      visibility: ProfileVisibility.friends,
    );
    await pump(tester, const PublicProfileView(username: 'aiko'));
    expect(
      find.text('Your stats are visible to: friends only.'),
      findsOneWidget,
    );
    expect(find.text('Add friend'), findsNothing);
  });

  testWidgets('privacy can be set in settings', (tester) async {
    await pump(tester, const SettingsView());
    await tester.scrollUntilVisible(find.text('Only me'), 300);
    await tester.ensureVisible(find.text('Only me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only me'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(social.visibility, ProfileVisibility.private);
  });
}
