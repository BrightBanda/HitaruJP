import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';
import 'package:ingrain/features/settings/presentation/viewmodel/settings_view_model.dart';

/// The questions, in the order they are asked.
enum OnboardingStep { reasons, level, interests, goal, name, avatar }

/// The daily goals offered, in minutes.
const dailyGoalChoices = [5, 10, 15, 20];

/// The answers so far. Nothing is saved until [OnboardingViewModel.finish].
class OnboardingDraft {
  static const maxNameLength = 40;

  final OnboardingStep step;
  final Set<LearningReason> reasons;
  final JlptLevel? level;

  /// "I'm not sure" was chosen: [level] is then the beginner fallback.
  final bool levelUnsure;
  final Set<ContentInterest> interests;

  /// Minutes a day; a sensible default is already picked.
  final int dailyGoalMinutes;
  final String displayName;
  final AvatarCharacter? avatar;
  final bool isSaving;

  /// What the guide says about the latest answer on this step; null until
  /// one is given.
  final String? reaction;

  const OnboardingDraft({
    this.step = OnboardingStep.reasons,
    this.reasons = const {},
    this.level,
    this.levelUnsure = false,
    this.interests = const {},
    this.dailyGoalMinutes = 10,
    this.displayName = '',
    this.avatar,
    this.isSaving = false,
    this.reaction,
  });

  bool get isFirstStep => step.index == 0;
  bool get isLastStep => step == OnboardingStep.values.last;

  /// 0..1 across the whole flow, counting the current step as begun.
  double get progress => (step.index + 1) / OnboardingStep.values.length;

  String? get nameError {
    final name = displayName.trim();
    if (name.isEmpty) return 'Enter a name';
    if (name.length > maxNameLength) {
      return 'Keep it under $maxNameLength characters';
    }
    return null;
  }

  bool get canContinue => switch (step) {
    OnboardingStep.reasons => reasons.isNotEmpty,
    OnboardingStep.level => level != null,
    OnboardingStep.interests => interests.isNotEmpty,
    OnboardingStep.goal => true,
    OnboardingStep.name => nameError == null,
    OnboardingStep.avatar => avatar != null,
  };

  OnboardingDraft copyWith({
    OnboardingStep? step,
    Set<LearningReason>? reasons,
    JlptLevel? level,
    bool? levelUnsure,
    Set<ContentInterest>? interests,
    int? dailyGoalMinutes,
    String? displayName,
    AvatarCharacter? avatar,
    bool? isSaving,
    String? Function()? reaction,
  }) {
    return OnboardingDraft(
      step: step ?? this.step,
      reasons: reasons ?? this.reasons,
      level: level ?? this.level,
      levelUnsure: levelUnsure ?? this.levelUnsure,
      interests: interests ?? this.interests,
      dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
      displayName: displayName ?? this.displayName,
      avatar: avatar ?? this.avatar,
      isSaving: isSaving ?? this.isSaving,
      reaction: reaction != null ? reaction() : this.reaction,
    );
  }
}

class OnboardingViewModel extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() {
    // A learner from before this flow existed already has some answers (at
    // least a name); start from those rather than a blank slate.
    final profile = ref.read(authViewModelProvider).profile;
    final draft = OnboardingDraft(
      reasons: {...?profile?.learningReasons},
      level: profile?.level,
      interests: {...?profile?.interests},
      displayName: profile?.displayName ?? '',
      avatar: profile?.avatarId == null
          ? null
          : AvatarCharacter.fromId(profile!.avatarId),
    );
    if (draft.displayName.isEmpty) unawaited(_suggestName());
    return draft;
  }

  /// Prefills the name with the Google name or email local part, unless the
  /// learner has typed something by then.
  Future<void> _suggestName() async {
    final suggested = await ref
        .read(authViewModelProvider.notifier)
        .suggestedDisplayName();
    if (!ref.mounted || suggested == null || state.displayName.isNotEmpty) {
      return;
    }
    final trimmed = suggested.trim();
    state = state.copyWith(
      displayName: trimmed.length > OnboardingDraft.maxNameLength
          ? trimmed.substring(0, OnboardingDraft.maxNameLength)
          : trimmed,
    );
  }

  void toggleReason(LearningReason reason) {
    final next = {...state.reasons};
    final added = !next.remove(reason);
    if (added) next.add(reason);
    state = state.copyWith(
      reasons: next,
      reaction: added ? () => GuideReactions.reason(reason) : null,
    );
  }

  void selectLevel(JlptLevel level) => state = state.copyWith(
    level: level,
    levelUnsure: false,
    reaction: () => GuideReactions.level(level),
  );

  /// "I'm not sure": start at beginner, and say so.
  void selectUnsure() => state = state.copyWith(
    level: JlptLevel.fallback,
    levelUnsure: true,
    reaction: () => GuideReactions.unsure,
  );

  void toggleInterest(ContentInterest interest) {
    final next = {...state.interests};
    final added = !next.remove(interest);
    if (added) next.add(interest);
    state = state.copyWith(
      interests: next,
      reaction: added ? () => GuideReactions.interest(interest) : null,
    );
  }

  void selectDailyGoal(int minutes) => state = state.copyWith(
    dailyGoalMinutes: minutes,
    reaction: () => GuideReactions.goal(minutes),
  );

  void setDisplayName(String name) => state = state.copyWith(displayName: name);

  void chooseAvatar(AvatarCharacter avatar) => state = state.copyWith(
    avatar: avatar,
    reaction: () => GuideReactions.avatar(avatar),
  );

  /// Moves on when the current step is answered. Returns false otherwise.
  bool next() {
    if (!state.canContinue || state.isLastStep) return false;
    state = state.copyWith(
      step: OnboardingStep.values[state.step.index + 1],
      reaction: () => null,
    );
    return true;
  }

  /// Steps back. Returns false on the first step.
  bool back() {
    if (state.isFirstStep) return false;
    state = state.copyWith(
      step: OnboardingStep.values[state.step.index - 1],
      reaction: () => null,
    );
    return true;
  }

  /// Saves every answer to the profile. The router leaves onboarding as soon as
  /// the session flips to onboarded, without waiting for the writes; a failed
  /// write surfaces through the auth state's error.
  Future<void> finish() async {
    if (!state.canContinue || !state.isLastStep || state.isSaving) return;
    state = state.copyWith(isSaving: true);
    final draft = state;
    // Before the profile flips to onboarded, so the router finds the first
    // lesson waiting when it leaves this screen.
    final uid = ref.read(authViewModelProvider).uid;
    if (uid.isNotEmpty) ref.read(firstRunProvider.notifier).startTour(uid);
    unawaited(
      ref
          .read(settingsViewModelProvider.notifier)
          .setDailyGoalMinutes(draft.dailyGoalMinutes)
          .catchError((Object _) {}),
    );
    unawaited(
      ref
          .read(authViewModelProvider.notifier)
          .completeOnboarding(
            displayName: draft.displayName,
            avatarId: draft.avatar!.id,
            level: draft.level,
            learningReasons: draft.reasons.toList(),
            interests: draft.interests.toList(),
          )
          .catchError((Object _) {}),
    );
  }
}

/// What the guide says back to each answer: short, warm, and specific
/// enough that the learner feels heard.
abstract final class GuideReactions {
  static String reason(LearningReason reason) => switch (reason) {
    LearningReason.travel =>
      'Travel! I’ll have you ordering ramen like a local.',
    LearningReason.animeManga =>
      'Anime without subtitles? Let’s get you there!',
    LearningReason.career => 'がんばって! Japanese opens a lot of doors at work.',
    LearningReason.school => 'Study buddy mode: on.',
    LearningReason.livingInJapan =>
      'Moving to Japan? すごい! Everyday Japanese it is.',
    LearningReason.friends => 'Friends are the best reason of all.',
    LearningReason.hobby => 'Learning for fun is how it sticks best.',
    LearningReason.media => 'Films, songs, shows. We’ll learn from all of it.',
    LearningReason.other => 'Every reason is a good reason!',
  };

  static String level(JlptLevel level) => switch (level) {
    JlptLevel.n5 => 'Starting fresh? Perfect, we’ll go step by step.',
    JlptLevel.n4 => 'Nice, you’ve got the basics down!',
    JlptLevel.n3 => 'Intermediate! Real videos are going to be fun.',
    JlptLevel.n2 => 'Impressive! Native content is your playground.',
    JlptLevel.n1 => '上級者! Let’s keep it sharp.',
  };

  static const unsure = 'No worries, we’ll start gentle and adjust as you go.';

  static String interest(ContentInterest interest) => switch (interest) {
    ContentInterest.anime => 'Anime it is! いいね!',
    ContentInterest.youtube => 'Japanese YouTube is full of gems.',
    ContentInterest.podcasts => 'Great for listening on the go.',
    ContentInterest.music => 'Songs stick in your head, and so will the words.',
    ContentInterest.news => 'News Japanese: clear and useful.',
    ContentInterest.conversations => 'Real conversations, real Japanese.',
    ContentInterest.travel => 'I’ll find you videos from all over Japan.',
    ContentInterest.reading => 'Stories and books, coming right up.',
    ContentInterest.gaming => 'Level up your Japanese like a game.',
    ContentInterest.culture => 'Festivals, food, history. So much to explore!',
  };

  static String goal(int minutes) => switch (minutes) {
    <= 5 => 'Small steps every day add up fast.',
    <= 10 => 'A great daily habit. You’ve got this!',
    <= 15 => 'A serious learner! 💪',
    _ => 'Wow, real immersion! I’m impressed.',
  };

  static String avatar(AvatarCharacter avatar) =>
      '${avatar.name}! ${avatar.tagline}. Great choice.';
}

final onboardingViewModelProvider =
    NotifierProvider.autoDispose<OnboardingViewModel, OnboardingDraft>(
      OnboardingViewModel.new,
    );
