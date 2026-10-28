import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/growth/presentation/companion_widgets.dart';
import 'package:ingrain/features/growth/presentation/growth_reveal.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/immersion/presentation/view/immersion_session_scope.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/widgets/confetti.dart';
import 'package:ingrain/features/onboarding/presentation/widgets/guide_bubble.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/presentation/widgets/avatar_painter.dart';
import 'package:ingrain/features/settings/presentation/viewmodel/settings_view_model.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/shared/layout/window_size.dart';

/// One word of the lesson, with what tapping it shows.
class LessonWord {
  final String surface;
  final String? romaji;
  final String? meaning;

  const LessonWord(this.surface, {this.romaji, this.meaning});

  bool get isWord => meaning != null;
}

class LessonLine {
  final String speaker;
  final bool isLearner;
  final List<LessonWord> words;
  final String translation;

  const LessonLine({
    required this.speaker,
    required this.isLearner,
    required this.words,
    required this.translation,
  });

  String get text => words.map((w) => w.surface).join();
}

/// The lesson itself: ordering at a café. Short, useful, and built so the
/// learner can actually say every line by the end. Written out here rather
/// than loaded, so the first impression never waits on the network.
abstract final class FirstLesson {
  static const sourceId = 'first-lesson';
  static const title = 'Your first lesson: at a café';

  static const target = LessonWord('コーヒー', romaji: 'kōhī', meaning: 'coffee');
  static const please = LessonWord(
    'ください',
    romaji: 'kudasai',
    meaning: 'please (give me)',
  );

  static const lines = [
    LessonLine(
      speaker: 'Staff',
      isLearner: false,
      words: [
        LessonWord(
          'いらっしゃいませ',
          romaji: 'irasshaimase',
          meaning: 'welcome (to a shop)',
        ),
        LessonWord('！'),
      ],
      translation: 'Welcome!',
    ),
    LessonLine(
      speaker: 'You',
      isLearner: true,
      words: [
        target,
        LessonWord('を', romaji: 'o', meaning: 'marks what you want'),
        please,
        LessonWord('。'),
      ],
      translation: 'A coffee, please.',
    ),
    LessonLine(
      speaker: 'Staff',
      isLearner: false,
      words: [
        LessonWord('はい', romaji: 'hai', meaning: 'yes / sure'),
        LessonWord('、'),
        LessonWord('どうぞ', romaji: 'dōzo', meaning: 'here you go'),
        LessonWord('。'),
      ],
      translation: 'Sure, here you go.',
    ),
    LessonLine(
      speaker: 'You',
      isLearner: true,
      words: [
        LessonWord('ありがとう', romaji: 'arigatō', meaning: 'thank you'),
        LessonWord('！'),
      ],
      translation: 'Thank you!',
    ),
  ];

  /// The quick check: what ください means, among two other lines' words.
  static const quizAnswer = 'please (give me)';
  static const quizChoices = ['thank you', 'please (give me)', 'welcome'];
}

enum _Stage { intro, reading, tapWord, wordShown, saved, quiz, done }

/// Where the first lesson's XP alone takes a new learner: out of the egg.
Growth _hatchedGrowth(WidgetRef ref) {
  final rules = ref.read(growthRulesProvider);
  return GrowthCalculator(rules).growthAt(rules.firstLessonXp);
}

/// The guided first lesson a new learner gets right after onboarding.
///
/// A café conversation appears line by line; the guide then has them tap a
/// word, save it (a real word, which lands in their flashcards), and answer
/// one quick question. It ends on a celebration that counts as their first
/// day. Time spent here is recorded as reading immersion, so the streak and
/// today's minutes start with it.
class FirstLessonView extends ConsumerStatefulWidget {
  const FirstLessonView({super.key});

  @override
  ConsumerState<FirstLessonView> createState() => _FirstLessonViewState();
}

class _FirstLessonViewState extends ConsumerState<FirstLessonView> {
  _Stage _stage = _Stage.intro;
  int _visibleLines = 0;
  LessonWord? _shownWord;
  String? _quizPick;
  bool _saving = false;
  Timer? _revealTimer;
  final _scroll = ScrollController();

  static final _stages = _Stage.values.length - 1;

  @override
  void dispose() {
    _revealTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _stage = _Stage.reading);
    _revealNext();
  }

  /// One line at a time, like a chat, then on to the word.
  void _revealNext() {
    _revealTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _visibleLines++);
      _scrollToEnd();
      if (_visibleLines < FirstLesson.lines.length) {
        _revealNext();
      } else {
        _revealTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted) setState(() => _stage = _Stage.tapWord);
        });
      }
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _tapWord(LessonWord word) {
    if (!word.isWord || _stage.index < _Stage.tapWord.index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _shownWord = word;
      if (_stage == _Stage.tapWord && word == FirstLesson.target) {
        _stage = _Stage.wordShown;
      }
    });
    _scrollToEnd();
  }

  Future<void> _saveWord() async {
    if (_saving) return;
    setState(() => _saving = true);
    const word = FirstLesson.target;
    // A word that is already saved is not saved again: saving it just records
    // another encounter. Say so instead of quietly going through the motions.
    final alreadySaved =
        await ref.read(vocabularyRepositoryProvider).findByWord(word.surface) !=
        null;
    if (!mounted) return;
    if (alreadySaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This word is already saved')),
      );
    }
    // Best effort: offline, Firestore queues the write; the lesson goes on.
    unawaited(
      ref
          .read(vocabularyViewModelProvider.notifier)
          .saveWord(
            word: word.surface,
            reading: word.surface,
            meaning: word.meaning,
            pos: 'noun',
            sourceType: SourceType.dialogue,
            sourceId: FirstLesson.sourceId,
            sourceTitle: FirstLesson.title,
            contextSentence: FirstLesson.lines[1].text,
          )
          .catchError((Object _) => null),
    );
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _stage = _Stage.saved;
    });
  }

  void _startQuiz() {
    setState(() => _stage = _Stage.quiz);
    _scrollToEnd();
  }

  void _answer(String choice) {
    if (_quizPick == FirstLesson.quizAnswer) return;
    final correct = choice == FirstLesson.quizAnswer;
    correct ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    setState(() => _quizPick = choice);
  }

  void _finish() {
    final uid = ref.read(authViewModelProvider).uid;
    if (uid.isNotEmpty) {
      ref.read(firstRunProvider.notifier).finishLesson(uid);
      // The egg hatched on the celebration screen: the home page must not
      // celebrate it a second time.
      final hatched = _hatchedGrowth(ref);
      GrowthCelebrations.markSeen(
        ref.read(sharedPreferencesProvider),
        uid,
        hatched.stage,
        hatched.level,
      );
    }
    context.go('/immerse');
  }

  (String, String?) get _guideLine => switch (_stage) {
    _Stage.intro => (
      'Let’s try your first real conversation!',
      'It takes about a minute, and I’ll help the whole way.',
    ),
    _Stage.reading => (
      'You’re at a café in Tokyo ☕',
      'Read along. The English is right underneath.',
    ),
    _Stage.tapWord => (
      'Tap the glowing word',
      'Every word in HitaruJP can be tapped, in videos too.',
    ),
    _Stage.wordShown => (
      'コーヒー means coffee!',
      'Save it, and I’ll make sure you never forget it.',
    ),
    _Stage.saved => (
      'Saved to your flashcards! 🎉',
      'It comes back for review just before you’d forget it.',
    ),
    _Stage.quiz => switch (_quizPick) {
      null => ('Quick check!', 'What does ください mean?'),
      FirstLesson.quizAnswer => (
        'Perfect! You’re a natural.',
        'You can already order a coffee in Japanese.',
      ),
      _ => ('Not quite, try again!', 'Look at what you said in line 2.'),
    },
    _Stage.done => ('', null),
  };

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.done) return _Celebration(onContinue: _finish);

    final theme = Theme.of(context);
    final (message, detail) = _guideLine;
    final avatarId = ref.watch(
      authViewModelProvider.select((s) => s.profile?.avatarId),
    );
    final character = avatarId == null
        ? guideCharacter
        : AvatarCharacter.fromId(avatarId);

    return ImmersionSessionScope(
      sourceId: 'dialogue:${FirstLesson.sourceId}',
      sourceTitle: FirstLesson.title,
      activityType: ActivityType.reading,
      child: PopScope(
        // Back skips nothing by accident: the lesson is one tap to skip.
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: MaxWidth(
              maxWidth: 640,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 4, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: _stage.index / _stages),
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) => ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: value,
                                minHeight: 12,
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _finish,
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: GuideBubble(
                      character: character,
                      message: message,
                      detail: detail,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      children: [
                        for (final (i, line)
                            in FirstLesson.lines.take(_visibleLines).indexed)
                          _ChatLine(
                            key: ValueKey(i),
                            line: line,
                            glowing: _stage == _Stage.tapWord
                                ? FirstLesson.target
                                : _stage == _Stage.quiz &&
                                      _quizPick != null &&
                                      _quizPick != FirstLesson.quizAnswer
                                ? FirstLesson.please
                                : null,
                            onTapWord: _tapWord,
                          ),
                        // Out of the way once the quiz starts, so the
                        // choices fit on screen.
                        if (_shownWord case final word?
                            when _stage != _Stage.quiz)
                          _WordCard(key: ValueKey(word.surface), word: word),
                        if (_stage == _Stage.quiz)
                          _Quiz(picked: _quizPick, onPick: _answer),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _ActionButton(
                      stage: _stage,
                      saving: _saving,
                      quizSolved: _quizPick == FirstLesson.quizAnswer,
                      onStart: _start,
                      onSave: _saveWord,
                      onQuiz: _startQuiz,
                      onDone: () {
                        HapticFeedback.mediumImpact();
                        setState(() => _stage = _Stage.done);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final _Stage stage;
  final bool saving;
  final bool quizSolved;
  final VoidCallback onStart;
  final VoidCallback onSave;
  final VoidCallback onQuiz;
  final VoidCallback onDone;

  const _ActionButton({
    required this.stage,
    required this.saving,
    required this.quizSolved,
    required this.onStart,
    required this.onSave,
    required this.onQuiz,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final (label, onPressed, icon) = switch (stage) {
      _Stage.intro => ('Let’s go', onStart, Icons.play_arrow_rounded),
      _Stage.reading || _Stage.tapWord => (
        'Tap the glowing word',
        null,
        Icons.touch_app_outlined,
      ),
      _Stage.wordShown => (
        'Save word',
        saving ? null : onSave,
        Icons.bookmark_add_outlined,
      ),
      _Stage.saved => ('Quick check', onQuiz, Icons.quiz_outlined),
      _Stage.quiz => (
        quizSolved ? 'Finish lesson' : 'Pick an answer',
        quizSolved ? onDone : null,
        quizSolved ? Icons.celebration_outlined : Icons.help_outline,
      ),
      _Stage.done => ('', null, Icons.check),
    };
    final hidden = stage == _Stage.reading;
    return AnimatedOpacity(
      opacity: hidden ? 0 : 1,
      duration: const Duration(milliseconds: 200),
      child: FilledButton.icon(
        onPressed: hidden ? null : onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

/// A line of the conversation as a chat bubble that pops in, its words
/// tappable.
class _ChatLine extends StatelessWidget {
  final LessonLine line;
  final LessonWord? glowing;
  final ValueChanged<LessonWord> onTapWord;

  const _ChatLine({
    super.key,
    required this.line,
    required this.glowing,
    required this.onTapWord,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final mine = line.isLearner;
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: mine
            ? primary.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(line.speaker, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Wrap(
            children: [
              for (final word in line.words)
                _TappableWord(
                  word: word,
                  glowing: word == glowing,
                  onTap: () => onTapWord(word),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            line.translation,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 16),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: bubble,
          ),
        ),
      ),
    );
  }
}

/// A word in a chat line; [glowing] pulses to say "tap me".
class _TappableWord extends StatefulWidget {
  final LessonWord word;
  final bool glowing;
  final VoidCallback onTap;

  const _TappableWord({
    required this.word,
    required this.glowing,
    required this.onTap,
  });

  @override
  State<_TappableWord> createState() => _TappableWordState();
}

class _TappableWordState extends State<_TappableWord>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_TappableWord oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.glowing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.glowing && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall;
    if (!widget.word.isWord) return Text(widget.word.surface, style: style);
    const glow = Color(0xFFFFC857);
    return Semantics(
      button: true,
      label: '${widget.word.surface}, tap for its meaning',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_pulse.value);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: widget.glowing
                    ? glow.withValues(alpha: 0.25 + 0.35 * t)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: widget.glowing
                    ? [
                        BoxShadow(
                          color: glow.withValues(alpha: 0.6 * t),
                          blurRadius: 14 * t,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
              ),
              child: child,
            );
          },
          child: Text(widget.word.surface, style: style),
        ),
      ),
    );
  }
}

/// What a tapped word means.
class _WordCard extends StatelessWidget {
  final LessonWord word;

  const _WordCard({super.key, required this.word});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 12),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        decoration: BoxDecoration(
          color: primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(blurRadius: 18, color: primary.withValues(alpha: 0.3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  word.surface,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                if (word.romaji case final romaji?)
                  Text(
                    romaji,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              word.meaning!,
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            if (word == FirstLesson.target) ...[
              const SizedBox(height: 6),
              Text(
                'Borrowed from English and written in katakana, the script '
                'Japanese uses for foreign words.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Quiz extends StatelessWidget {
  final String? picked;
  final ValueChanged<String> onPick;

  const _Quiz({required this.picked, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const right = Color(0xFF2FA866);
    final wrong = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ください means…', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final choice in FirstLesson.quizChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Shake(
                shaking: picked == choice && choice != FirstLesson.quizAnswer,
                child: OutlinedButton(
                  onPressed: () => onPick(choice),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(
                      width: picked == choice ? 2 : 1,
                      color: picked != choice
                          ? theme.colorScheme.outlineVariant
                          : choice == FirstLesson.quizAnswer
                          ? right
                          : wrong,
                    ),
                    backgroundColor: picked == choice
                        ? (choice == FirstLesson.quizAnswer ? right : wrong)
                              .withValues(alpha: 0.1)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(choice)),
                      if (picked == choice)
                        Icon(
                          choice == FirstLesson.quizAnswer
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: choice == FirstLesson.quizAnswer
                              ? right
                              : wrong,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shakes [child] once each time [shaking] turns on.
class _Shake extends StatefulWidget {
  final bool shaking;
  final Widget child;

  const _Shake({required this.shaking, required this.child});

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void didUpdateWidget(_Shake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shaking && !oldWidget.shaking) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Transform.translate(
      offset: Offset(
        math.sin(_controller.value * math.pi * 6) * 8 * (1 - _controller.value),
        0,
      ),
      child: child,
    ),
    child: widget.child,
  );
}

/// The end of the lesson: confetti, the learner's character, and what they
/// just achieved. (The mascot's egg will hatch here once XP arrives.)
class _Celebration extends ConsumerWidget {
  final VoidCallback onContinue;

  const _Celebration({required this.onContinue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final avatarId = ref.watch(
      authViewModelProvider.select((s) => s.profile?.avatarId),
    );
    final character = avatarId == null
        ? guideCharacter
        : AvatarCharacter.fromId(avatarId);
    final goal =
        ref.watch(settingsViewModelProvider).settings?.dailyGoalMinutes ?? 10;
    final name = ref.watch(authViewModelProvider.select((s) => s.displayName));

    return Scaffold(
      body: ConfettiBurst(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [character.background, theme.colorScheme.surface],
              stops: const [0, 0.7],
            ),
          ),
          child: SafeArea(
            child: MaxWidth(
              maxWidth: 560,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  children: [
                    const Spacer(),
                    // The lesson's XP hatches the egg, right here.
                    GrowthReveal(
                      character: character,
                      from: GrowthStage.egg,
                      to: _hatchedGrowth(ref).stage,
                      size: 140,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'First lesson complete!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name == null
                          ? 'You just ordered a coffee in Japanese. よくできました!'
                          : 'よくできました, $name! You just ordered a coffee '
                                'in Japanese.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: _Stat(
                            icon: Icons.local_fire_department,
                            color: const Color(0xFFFF9F43),
                            value: 'Day 1',
                            label: 'Streak started',
                            delay: 0,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Stat(
                            icon: Icons.bookmark_added,
                            color: theme.colorScheme.primary,
                            value: '1 word',
                            label: 'In your flashcards',
                            delay: 1,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Stat(
                            icon: Icons.auto_awesome,
                            color: const Color(0xFFFFB020),
                            value:
                                '+${ref.read(growthRulesProvider).firstLessonXp} XP',
                            label: 'Egg hatched!',
                            delay: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Your goal is $goal minutes a day. Come back tomorrow '
                      'to keep your streak going.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Spacer(flex: 2),
                    FilledButton(
                      onPressed: onContinue,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: theme.textTheme.titleMedium,
                      ),
                      child: const Text('Start exploring'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  /// Order in which the stats pop in.
  final int delay;

  const _Stat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 500 + delay * 180),
      curve: Interval(delay * 0.25, 1, curve: Curves.easeOutBack),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
