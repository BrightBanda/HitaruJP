import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/growth/presentation/growth_reveal.dart';
import 'package:ingrain/features/growth/presentation/mascot_painter.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/widgets/confetti.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/presentation/widgets/avatar_painter.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The learner's chosen character, which is their companion.
final companionCharacterProvider = Provider<AvatarCharacter>((ref) {
  final id = ref.watch(
    authViewModelProvider.select((s) => s.profile?.avatarId),
  );
  return id == null ? AvatarCharacter.kitsune : AvatarCharacter.fromId(id);
});

/// The companion, its level and how close the next one is. Opens the
/// companion page.
class CompanionCard extends ConsumerWidget {
  const CompanionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final growth = ref.watch(growthProvider);
    final character = ref.watch(companionCharacterProvider);
    final theme = Theme.of(context);
    if (growth == null) return const SizedBox.shrink();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/companion'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              MascotPortrait(
                character: character,
                stage: growth.stage,
                size: 64,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${growth.level} · '
                      '${growth.stage.titleFor(character)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    XpBar(growth: growth),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${growth.xpToNextLevel} XP to level '
                            '${growth.level + 1}',
                        if (growth.todayXp > 0) '+${growth.todayXp} today',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// The companion as a small portrait with its level, for tight spots such
/// as the home greeting. Opens the companion page.
class CompanionBadge extends ConsumerWidget {
  final double size;

  const CompanionBadge({super.key, this.size = 56});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final growth = ref.watch(growthProvider);
    final character = ref.watch(companionCharacterProvider);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: growth == null
          ? 'Your companion'
          : 'Your companion, level ${growth.level}',
      child: GestureDetector(
        onTap: () => context.push('/companion'),
        child: SizedBox(
          width: size,
          height: size + 8,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              MascotPortrait(
                character: character,
                stage: growth?.stage ?? GrowthStage.egg,
                size: size,
              ),
              if (growth != null)
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB020),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      'Lv ${growth.level}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progress through the current level, filling smoothly when XP comes in.
class XpBar extends StatelessWidget {
  final Growth growth;
  final double height;

  const XpBar({super.key, required this.growth, this.height = 8});

  @override
  Widget build(BuildContext context) {
    const xpColor = Color(0xFFFFB020);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: growth.levelProgress),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: value,
          minHeight: height,
          color: xpColor,
          backgroundColor: xpColor.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}

/// Watches the learner's growth and celebrates it: a full-screen moment when
/// the companion reaches a new stage, a quick note for a new level.
///
/// What was last celebrated is kept per learner on the device, so each
/// moment plays once. It waits while the first-open tour is still running.
class GrowthCelebrations extends ConsumerStatefulWidget {
  final Widget child;

  const GrowthCelebrations({super.key, required this.child});

  /// Records [stage] and [level] as seen, so they are not celebrated again;
  /// the first lesson calls this after hatching the egg itself.
  static void markSeen(
    SharedPreferences prefs,
    String uid,
    GrowthStage stage,
    int level,
  ) {
    prefs.setString(_stageKey(uid), stage.name);
    prefs.setInt(_levelKey(uid), level);
  }

  static String _stageKey(String uid) => 'growth_seen_stage_$uid';
  static String _levelKey(String uid) => 'growth_seen_level_$uid';

  @override
  ConsumerState<GrowthCelebrations> createState() => _GrowthCelebrationsState();
}

class _GrowthCelebrationsState extends ConsumerState<GrowthCelebrations> {
  bool _showing = false;

  void _check(Growth? growth) {
    if (growth == null || _showing || !mounted) return;
    final run = ref.read(firstRunProvider);
    if (run.lessonPending || run.homeTipsPending) return;
    final uid = ref.read(authViewModelProvider).uid;
    if (uid.isEmpty) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final seenStageName = prefs.getString(GrowthCelebrations._stageKey(uid));
    final seenStage = GrowthStage.values
        .where((s) => s.name == seenStageName)
        .firstOrNull;
    final seenLevel = prefs.getInt(GrowthCelebrations._levelKey(uid));

    void markSeen() =>
        GrowthCelebrations.markSeen(prefs, uid, growth.stage, growth.level);

    // Never celebrated before: a learner from before companions existed
    // meets theirs, grown as far as their history takes it.
    final from = seenStage ?? GrowthStage.egg;
    if (growth.stage.index > from.index) {
      _showing = true;
      markSeen();
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => _StageUpView(
          character: ref.read(companionCharacterProvider),
          from: from,
          growth: growth,
          firstMeeting: seenStage == null,
        ),
      ).whenComplete(() => _showing = false);
      return;
    }
    if (seenLevel != null && growth.level > seenLevel) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Level up! You’re level ${growth.level}. '
            '${growth.xpToNextLevel} XP to the next.',
          ),
          action: SnackBarAction(
            label: 'See',
            onPressed: () => context.push('/companion'),
          ),
        ),
      );
    }
    if (seenStage != growth.stage || seenLevel != growth.level) markSeen();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(growthProvider, (_, next) => _check(next));
    // Also once the tour finishes, which does not change the growth.
    ref.listen(firstRunProvider, (_, _) => _check(ref.read(growthProvider)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check(ref.read(growthProvider));
    });
    return widget.child;
  }
}

class _StageUpView extends StatefulWidget {
  final AvatarCharacter character;
  final GrowthStage from;
  final Growth growth;
  final bool firstMeeting;

  const _StageUpView({
    required this.character,
    required this.from,
    required this.growth,
    required this.firstMeeting,
  });

  @override
  State<_StageUpView> createState() => _StageUpViewState();
}

class _StageUpViewState extends State<_StageUpView> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.growth.stage.titleFor(widget.character);
    final message = widget.firstMeeting
        ? 'Meet your companion! All your immersion so far has grown it into '
              'a ${widget.growth.stage.label.toLowerCase()}.'
        : widget.from == GrowthStage.egg
        ? 'Your egg hatched!'
        : 'Your ${widget.character.name} grew!';
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GrowthReveal(
              character: widget.character,
              from: widget.from,
              to: widget.growth.stage,
              onRevealed: () => setState(() => _revealed = true),
            ),
            const SizedBox(height: 12),
            AnimatedOpacity(
              opacity: _revealed ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$message\nLevel ${widget.growth.level}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _revealed
                        ? () => Navigator.of(context).pop()
                        : null,
                    child: const Text('Keep going'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: _revealed ? ConfettiBurst(child: content) : content,
    );
  }
}

/// Everything about the companion: how it looks now, every stage it can
/// reach, today's XP, and how XP is earned.
class CompanionView extends ConsumerWidget {
  const CompanionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final growth = ref.watch(growthProvider);
    final character = ref.watch(companionCharacterProvider);
    final rules = ref.watch(growthRulesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Your companion')),
      body: growth == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Center(
                  child: MascotPortrait(
                    character: character,
                    stage: growth.stage,
                    size: 168,
                    outlined: true,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  growth.stage.titleFor(character),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Level ${growth.level} · ${growth.xp} XP',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                XpBar(growth: growth, height: 12),
                const SizedBox(height: 6),
                Text(
                  [
                    '${growth.xpToNextLevel} XP to level ${growth.level + 1}',
                    if (growth.nextStage case final next?)
                      '${next.label} at level ${growth.nextStageLevel}',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                Text('Stages', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                SizedBox(
                  // The portrait and its frame, plus two lines of label at
                  // the learner's text size.
                  height: 104 + MediaQuery.textScalerOf(context).scale(16) * 3,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: GrowthStage.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final stage = GrowthStage.values[index];
                      return _StageTile(
                        character: character,
                        stage: stage,
                        level: rules.stageLevels[index],
                        reached: stage.index <= growth.stage.index,
                        current: stage == growth.stage,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text('Today', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                if (growth.today.isEmpty)
                  Text(
                    'No XP yet today. Watch, read or review to earn some!',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  for (final MapEntry(key: source, value: xp)
                      in growth.today.entries)
                    _XpRow(label: _sourceLabel(source), value: '+$xp XP'),
                const SizedBox(height: 24),
                Text('How to earn XP', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final (label, value) in _howToEarn(rules))
                  _XpRow(label: label, value: value),
                const SizedBox(height: 8),
                Text(
                  'Your companion never shrinks: XP you have earned is yours '
                  'to keep.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  static String _sourceLabel(XpSource source) => switch (source) {
    XpSource.watching => 'Watching',
    XpSource.reading => 'Reading',
    XpSource.dialogues => 'Dialogues read',
    XpSource.sentences => 'Sentences mined',
    XpSource.words => 'Words saved',
    XpSource.reviews => 'Flashcard reviews',
    XpSource.dailyGoal => 'Daily goal reached',
    XpSource.streak => 'Streak bonus',
    XpSource.firstLesson => 'First lesson',
  };

  static List<(String, String)> _howToEarn(GrowthRules r) => [
    (
      'Watching or listening',
      '${r.xpPerWatchMinute} XP a minute, up to ${r.watchMinuteCap} min',
    ),
    (
      'Reading',
      '${r.xpPerReadMinute} XP a minute, up to ${r.readMinuteCap} min',
    ),
    ('Reading a dialogue', '${r.xpPerDialogue} XP, up to ${r.dialogueCap}'),
    ('Mining a sentence', '${r.xpPerSentence} XP, up to ${r.sentenceCap}'),
    ('Saving a word', '${r.xpPerWord} XP, up to ${r.wordCap}'),
    ('Flashcard review', '${r.xpPerReview} XP, up to ${r.reviewCap}'),
    ('Reaching your daily goal', '+${r.dailyGoalBonus} XP'),
    (
      'A ${r.streakBonusFromDays}-day streak or more',
      '+${r.streakBonusPercent}% of the day',
    ),
  ];
}

class _XpRow extends StatelessWidget {
  final String label;
  final String value;

  const _XpRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  final AvatarCharacter character;
  final GrowthStage stage;
  final int level;
  final bool reached;
  final bool current;

  const _StageTile({
    required this.character,
    required this.stage,
    required this.level,
    required this.reached,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget portrait = MascotPortrait(
      character: character,
      stage: stage,
      size: 84,
    );
    if (!reached) {
      // A silhouette: what is coming, without spoiling it.
      portrait = Stack(
        alignment: Alignment.center,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFF2C2A36),
              BlendMode.srcATop,
            ),
            child: Opacity(opacity: 0.35, child: portrait),
          ),
          const Icon(Icons.lock_outline, color: Colors.white70),
        ],
      );
    }
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: current ? character.accent : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: portrait,
          ),
          const SizedBox(height: 4),
          Text(
            stage.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: current ? FontWeight.w800 : null,
            ),
          ),
          Text('Lv $level', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
