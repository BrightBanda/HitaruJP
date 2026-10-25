import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/storage/local_document_store.dart';
import 'package:ingrain/features/auth/domain/user_profile.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/catalog/presentation/viewmodel/catalog_providers.dart';
import 'package:ingrain/features/kana/data/local_kana_progress_repository.dart';
import 'package:ingrain/features/kana/domain/kana_chart.dart';
import 'package:ingrain/features/kana/domain/kana_knowledge.dart';
import 'package:ingrain/features/kana/presentation/kana_progress_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/onboarding_view_model.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';
import 'package:ingrain/features/profile/presentation/viewmodel/edit_profile_view_model.dart';
import 'package:ingrain/features/profile/presentation/viewmodel/profile_sync_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

/// Lets the auth stream deliver and `_applySession` finish its reads.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late SharedPreferences prefs;
  late FakeAuthSession session;
  late FakeProfileSyncRepository sync;
  late FakeCatalogRepository catalog;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sync = FakeProfileSyncRepository();
    catalog = FakeCatalogRepository();
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: appTestOverrides(
        prefs,
        session: session,
        profileSync: sync,
        catalog: catalog,
      ),
    );
    addTearDown(c.dispose);
    c.read(authViewModelProvider);
    return c;
  }

  group('onboarding', () {
    setUp(() => session = FakeAuthSession(uid: 'u1', name: null));

    test('each step needs an answer before moving on', () async {
      final c = container();
      await settle();
      final vm = c.read(onboardingViewModelProvider.notifier);
      OnboardingDraft draft() => c.read(onboardingViewModelProvider);

      expect(draft().step, OnboardingStep.reasons);
      expect(vm.next(), isFalse);
      vm.toggleReason(LearningReason.travel);
      vm.toggleReason(LearningReason.media);
      vm.toggleReason(LearningReason.media);
      expect(draft().reasons, {LearningReason.travel});
      expect(vm.next(), isTrue);

      expect(draft().step, OnboardingStep.level);
      expect(draft().canContinue, isFalse);
      vm.selectUnsure();
      expect(draft().level, JlptLevel.n5, reason: 'not sure starts at N5');
      expect(draft().levelUnsure, isTrue);
      vm.selectLevel(JlptLevel.n4);
      expect(draft().levelUnsure, isFalse);
      vm.next();

      expect(draft().step, OnboardingStep.interests);
      vm.toggleInterest(ContentInterest.anime);
      expect(draft().reaction, isNotNull, reason: 'the guide reacts');
      vm.next();

      expect(draft().step, OnboardingStep.goal);
      expect(draft().reaction, isNull, reason: 'each step starts fresh');
      expect(draft().canContinue, isTrue, reason: 'a goal is preselected');
      vm.selectDailyGoal(15);
      expect(draft().dailyGoalMinutes, 15);
      vm.next();

      expect(draft().step, OnboardingStep.name);
      vm.setDisplayName('   ');
      expect(vm.next(), isFalse, reason: 'a blank name is not a name');
      vm.setDisplayName('Aiko');
      vm.next();

      expect(draft().step, OnboardingStep.avatar);
      expect(draft().isLastStep, isTrue);
      expect(vm.back(), isTrue);
      expect(draft().step, OnboardingStep.name);
      expect(draft().displayName, 'Aiko', reason: 'answers survive going back');
    });

    test(
      'finishing saves every answer and marks the learner onboarded',
      () async {
        final c = container();
        await settle();
        expect(c.read(authViewModelProvider).isOnboarded, isFalse);

        final vm = c.read(onboardingViewModelProvider.notifier)
          ..toggleReason(LearningReason.animeManga)
          ..next()
          ..selectLevel(JlptLevel.n3)
          ..next()
          ..toggleInterest(ContentInterest.music)
          ..toggleInterest(ContentInterest.gaming)
          ..next()
          ..selectDailyGoal(20)
          ..next()
          ..setDisplayName('  Ken ')
          ..next()
          ..chooseAvatar(AvatarCharacter.tanuki);
        await vm.finish();
        await settle();

        final auth = c.read(authViewModelProvider);
        expect(auth.isOnboarded, isTrue);
        expect(auth.displayName, 'Ken');
        final profile = auth.profile!;
        expect(profile.level, JlptLevel.n3);
        expect(profile.avatarId, 'tanuki');
        expect(profile.learningReasons, [LearningReason.animeManga]);
        expect(profile.interests, [
          ContentInterest.music,
          ContentInterest.gaming,
        ]);
        expect(profile.onboardingVersion, UserProfile.currentOnboardingVersion);

        // Persisted to the profile document, not just held in memory.
        expect(session.profileFields['level'], 'N3');
        expect(session.profileFields['avatarId'], 'tanuki');
        expect(session.profileFields['interests'], ['music', 'gaming']);
        expect(session.profileFields['onboardingCompletedAt'], isNotNull);
        expect(session.setDisplayNameCalls, ['Ken']);

        // The first-open tour is queued for this learner.
        final run = c.read(firstRunProvider);
        expect(run.lessonPending, isTrue);
        expect(run.homeTipsPending, isTrue);
      },
    );

    test(
      'a learner from before the flow is asked again, answers prefilled',
      () async {
        session = FakeAuthSession(
          uid: 'u1',
          name: 'Old Timer',
          onboarded: false,
        );
        final c = container();
        await settle();

        expect(c.read(authViewModelProvider).isOnboarded, isFalse);
        expect(c.read(onboardingViewModelProvider).displayName, 'Old Timer');
      },
    );
  });

  group('profile sync', () {
    setUp(() => session = FakeAuthSession(uid: 'u1', name: 'Aiko'));

    test('pushes the onboarded profile and shows the server tier', () async {
      sync.tier = SubscriptionTier.premium;
      final c = container();
      await settle();

      await c.read(profileSyncProvider.future);
      await settle();

      expect(sync.pushed.single.displayName, 'Aiko');
      expect(
        c.read(authViewModelProvider).profile!.subscriptionTier,
        SubscriptionTier.premium,
      );
      // Recording the tier must not trigger another push.
      await c.read(profileSyncProvider.future);
      expect(sync.pushed, hasLength(1));
    });

    test('a level change is pushed before new picks are fetched', () async {
      final c = container();
      await settle();
      await c.read(dailyPicksProvider.future);
      expect((sync.pushed.length, catalog.dailyCalls), (1, 1));

      final profile = c.read(authViewModelProvider).profile!;
      await c
          .read(authViewModelProvider.notifier)
          .updateProfile(profile.copyWith(level: () => JlptLevel.n2));
      await c.read(dailyPicksProvider.future);

      expect(sync.pushed.last.level, JlptLevel.n2);
      expect(catalog.dailyCalls, 2);
    });

    test('a failed sync does not block the picks', () async {
      final c = ProviderContainer(
        overrides: appTestOverrides(
          prefs,
          session: session,
          profileSync: _FailingSync(),
          catalog: catalog,
        ),
      );
      addTearDown(c.dispose);
      c.read(authViewModelProvider);
      await settle();

      final picks = await c.read(dailyPicksProvider.future);
      expect(picks.videos, isNotEmpty);
    });

    test('a visit is recorded once per onboarded sign-in', () async {
      final c = container();
      c.listen(activityTrackerProvider, (_, _) {});
      await settle();

      expect(sync.visits, 1);
    });
  });

  group('editing the profile', () {
    setUp(() => session = FakeAuthSession(uid: 'u1', name: 'Aiko'));

    test('saves a new name, character and level', () async {
      final c = container();
      await settle();
      final vm = c.read(editProfileViewModelProvider.notifier)
        ..setDisplayName('Aiko 2')
        ..chooseAvatar(AvatarCharacter.daruma)
        ..selectLevel(JlptLevel.n1)
        ..toggleInterest(ContentInterest.news);

      expect(await vm.save(), isTrue);
      final profile = c.read(authViewModelProvider).profile!;
      expect(profile.displayName, 'Aiko 2');
      expect(profile.avatarId, 'daruma');
      expect(profile.level, JlptLevel.n1);
      expect(profile.interests, [ContentInterest.news]);
      expect(session.profileFields['avatarId'], 'daruma');
    });

    test('refuses an empty name', () async {
      final c = container();
      await settle();
      final vm = c.read(editProfileViewModelProvider.notifier)
        ..setDisplayName('');

      expect(c.read(editProfileViewModelProvider).canSave, isFalse);
      expect(await vm.save(), isFalse);
    });
  });

  group('kana marks', () {
    setUp(() => session = FakeAuthSession(uid: 'u1', name: 'Aiko'));

    test('mark, change and clear, and they survive a restart', () async {
      final c = container();
      final vm = c.read(kanaProgressViewModelProvider.notifier);
      await c.read(kanaProgressViewModelProvider.future);

      await vm.mark('あ', KanaKnowledge.known);
      await vm.mark('か', KanaKnowledge.somewhat);
      await vm.mark('ア', KanaKnowledge.somewhat);
      await vm.mark('か', null);
      await vm.cycle('ア');

      expect(c.read(kanaProgressViewModelProvider).value, {
        'あ': KanaKnowledge.known,
        'ア': KanaKnowledge.known,
      });
      expect(c.read(kanaKnownCountProvider), 2);

      // A fresh repository over the same store reads the same marks back.
      final reloaded = await LocalKanaProgressRepository(
        LocalDocumentStore(prefs),
        session,
      ).load();
      expect(reloaded, {'あ': KanaKnowledge.known, 'ア': KanaKnowledge.known});
    });

    test('long-press cycles none → somewhat → known → none', () async {
      final c = container();
      final vm = c.read(kanaProgressViewModelProvider.notifier);
      await c.read(kanaProgressViewModelProvider.future);

      final seen = <KanaKnowledge?>[];
      for (var i = 0; i < 3; i++) {
        await vm.cycle('ね');
        seen.add(vm.of('ね'));
      }
      expect(seen, [KanaKnowledge.somewhat, KanaKnowledge.known, null]);
    });

    test('a failed save puts the old mark back', () async {
      final c = ProviderContainer(
        overrides: [
          ...appTestOverrides(prefs, session: session),
          kanaProgressRepositoryProvider.overrideWithValue(_FailingKana()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(kanaProgressViewModelProvider.future);

      await expectLater(
        c
            .read(kanaProgressViewModelProvider.notifier)
            .mark('あ', KanaKnowledge.known),
        throwsStateError,
      );
      expect(c.read(kanaProgressViewModelProvider).value, isEmpty);
    });

    test('tallies a script board', () {
      final sections = KanaChart.sections(KanaScript.hiragana);
      final tally = tallyKana(sections, {
        'あ': KanaKnowledge.known,
        'い': KanaKnowledge.somewhat,
        'ア': KanaKnowledge.known, // katakana: not on the hiragana board
      });

      expect(tally.known, 1);
      expect(tally.somewhat, 1);
      expect(tally.total, sections.fold<int>(0, (n, s) => n + s.count));
    });
  });
}

class _FailingSync extends FakeProfileSyncRepository {
  @override
  Future<SubscriptionTier> push(UserProfile profile) async =>
      throw StateError('offline');
}

class _FailingKana implements KanaProgressRepository {
  @override
  Future<Map<String, KanaKnowledge>> load() async => {};

  @override
  Future<void> set(String kana, KanaKnowledge? knowledge) async =>
      throw StateError('offline');
}
