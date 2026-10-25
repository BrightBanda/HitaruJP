import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/onboarding_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/widgets/guide_bubble.dart';
import 'package:ingrain/features/profile/presentation/widgets/preference_pickers.dart';
import 'package:ingrain/shared/layout/window_size.dart';
import 'package:ingrain/shared/widgets/double_back_to_exit.dart';

/// First-run questions, one per screen: why, level, interests, daily goal,
/// name, avatar. The guide (Kitsune, then the learner's own pick) asks each
/// one and reacts to the answers.
///
/// Shown to a signed-in learner who has not finished onboarding. Back steps
/// through the questions; on the first one it behaves like any root screen.
class OnboardingFlowView extends ConsumerWidget {
  const OnboardingFlowView({super.key});

  static const _copy = {
    OnboardingStep.reasons: (
      'Why are you learning Japanese?',
      'Pick as many as you like.',
    ),
    OnboardingStep.level: (
      'How much Japanese do you know?',
      'We’ll match videos to your level. Not sure? That’s fine too.',
    ),
    OnboardingStep.interests: (
      'What do you love watching?',
      'Your daily videos will lean towards these.',
    ),
    OnboardingStep.goal: (
      'How much time a day?',
      'Pick a goal you can keep. You can change it any time.',
    ),
    OnboardingStep.name: (
      'What should we call you?',
      'This is the name HitaruJP shows — never your email.',
    ),
    OnboardingStep.avatar: (
      'Pick your character!',
      'They’ll be with you on your profile and across the app.',
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingViewModelProvider);
    final viewModel = ref.read(onboardingViewModelProvider.notifier);
    final theme = Theme.of(context);
    final (title, subtitle) = _copy[draft.step]!;

    final screen = Scaffold(
      body: SafeArea(
        // A comfortable column on desktop; edge to edge on phones.
        child: MaxWidth(
          maxWidth: 640,
          child: Column(
            children: [
              _TopBar(draft: draft, onBack: viewModel.back),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0.06, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: ListView(
                    key: ValueKey(draft.step),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      GuideBubble(
                        character: draft.avatar ?? guideCharacter,
                        message: title,
                        detail: draft.reaction ?? subtitle,
                      ),
                      const SizedBox(height: 20),
                      switch (draft.step) {
                        OnboardingStep.reasons => ReasonPicker(
                          selected: draft.reasons,
                          onToggle: viewModel.toggleReason,
                        ),
                        OnboardingStep.level => LevelPicker(
                          selected: draft.level,
                          unsure: draft.levelUnsure,
                          onSelect: viewModel.selectLevel,
                          onUnsure: viewModel.selectUnsure,
                        ),
                        OnboardingStep.interests => InterestPicker(
                          selected: draft.interests,
                          onToggle: viewModel.toggleInterest,
                        ),
                        OnboardingStep.goal => _GoalPicker(
                          selected: draft.dailyGoalMinutes,
                          onSelect: viewModel.selectDailyGoal,
                        ),
                        OnboardingStep.name => _NameField(
                          onSubmitted: viewModel.next,
                        ),
                        OnboardingStep.avatar => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AvatarShowcase(
                              character: draft.avatar ?? guideCharacter,
                              displayName: draft.displayName,
                            ),
                            const SizedBox(height: 20),
                            AvatarPicker(
                              selected: draft.avatar,
                              onSelect: viewModel.chooseAvatar,
                            ),
                          ],
                        ),
                      },
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton(
                  onPressed: !draft.canContinue || draft.isSaving
                      ? null
                      : draft.isLastStep
                      ? viewModel.finish
                      : viewModel.next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: theme.textTheme.titleMedium,
                  ),
                  child: draft.isSaving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Text(draft.isLastStep ? 'Start learning' : 'Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (draft.isFirstStep) return DoubleBackToExit(child: screen);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) viewModel.back();
      },
      child: screen,
    );
  }
}

class _TopBar extends StatelessWidget {
  final OnboardingDraft draft;
  final VoidCallback onBack;

  const _TopBar({required this.draft, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = OnboardingStep.values.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 20, 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: draft.isFirstStep
                ? null
                : IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: onBack,
                  ),
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: draft.progress),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 12,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${draft.step.index + 1}/$total',
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

/// The daily goal choices, each with what it amounts to.
class _GoalPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _GoalPicker({required this.selected, required this.onSelect});

  static const _details = {
    5: ('Casual', 'A short clip or one dialogue', Icons.eco_outlined),
    10: ('Regular', 'One video, a few new words', Icons.local_cafe_outlined),
    15: ('Serious', 'A video and a quick review', Icons.trending_up),
    20: ('Intense', 'Real immersion, every day', Icons.local_fire_department),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Column(
      children: [
        for (final minutes in dailyGoalChoices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              selected: minutes == selected,
              button: true,
              child: Material(
                color: minutes == selected
                    ? primary.withValues(alpha: 0.12)
                    : theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: minutes == selected
                        ? primary
                        : theme.colorScheme.outlineVariant,
                    width: minutes == selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(minutes),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        Icon(_details[minutes]!.$3, color: primary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _details[minutes]!.$1,
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                _details[minutes]!.$2,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$minutes min',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NameField extends ConsumerStatefulWidget {
  final VoidCallback onSubmitted;

  const _NameField({required this.onSubmitted});

  @override
  ConsumerState<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends ConsumerState<_NameField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(onboardingViewModelProvider).displayName,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The suggested name can arrive after the field is built.
    ref.listen(onboardingViewModelProvider.select((d) => d.displayName), (
      _,
      name,
    ) {
      if (_controller.text != name) _controller.text = name;
    });
    final draft = ref.watch(onboardingViewModelProvider);
    final showError = draft.displayName.isNotEmpty && draft.nameError != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: OnboardingDraft.maxNameLength,
          style: Theme.of(context).textTheme.titleLarge,
          decoration: InputDecoration(
            hintText: 'Your name',
            prefixIcon: const Icon(Icons.badge_outlined),
            errorText: showError ? draft.nameError : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onChanged: ref
              .read(onboardingViewModelProvider.notifier)
              .setDisplayName,
          onSubmitted: (_) => widget.onSubmitted(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 16,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'You can change it later from your profile.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
