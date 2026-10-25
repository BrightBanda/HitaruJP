import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ingrain/features/onboarding/presentation/widgets/guide_bubble.dart';
import 'package:ingrain/features/profile/presentation/widgets/avatar_painter.dart';
import 'package:ingrain/features/profile/presentation/widgets/learner_avatar.dart';
import 'package:ingrain/shared/layout/window_size.dart';
import 'package:ingrain/shared/widgets/double_back_to_exit.dart';

/// The first thing a new install shows: what HitaruJP is, before any account.
///
/// Three pages the learner can swipe through or skip, ending on "Get started"
/// (a new account) or "I already have an account".
class WelcomeView extends StatefulWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const WelcomeView({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  @override
  State<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<WelcomeView> {
  final _pages = PageController();
  int _page = 0;

  static const _content = [
    (
      'Learn Japanese from things you love',
      'Real videos, dialogues and stories, not textbook drills.',
    ),
    (
      'Tap any word. Get it instantly.',
      'Meanings and readings in one tap, saved straight into your flashcards.',
    ),
    (
      'A few minutes a day, every day',
      'Keep your streak, hit your goal, and watch your companion grow with you.',
    ),
  ];

  bool get _isLast => _page == _content.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onGetStarted();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final character = guideCharacter;
    return DoubleBackToExit(
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                character.background.withValues(alpha: 0.9),
                theme.colorScheme.surface,
              ],
              stops: const [0, 0.65],
            ),
          ),
          child: SafeArea(
            child: MaxWidth(
              maxWidth: 560,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
                      child: AnimatedOpacity(
                        opacity: _isLast ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: TextButton(
                          onPressed: _isLast ? null : widget.onGetStarted,
                          child: const Text('Skip'),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _content.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) {
                        final (title, body) = _content[index];
                        return _WelcomePage(
                          illustration: switch (index) {
                            0 => const _FloatingKana(),
                            1 => const _TapAWord(),
                            _ => const _DailyHabit(),
                          },
                          title: title,
                          body: body,
                        );
                      },
                    ),
                  ),
                  _Dots(count: _content.length, current: _page),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: theme.textTheme.titleMedium,
                      ),
                      child: Text(_isLast ? 'Get started' : 'Next'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextButton(
                      onPressed: widget.onSignIn,
                      child: const Text('I already have an account'),
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

class _WelcomePage extends StatelessWidget {
  final Widget illustration;
  final String title;
  final String body;

  const _WelcomePage({
    required this.illustration,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 260, child: Center(child: illustration)),
              const SizedBox(height: 28),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int current;

  const _Dots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == current ? 26 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current ? primary : primary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
        ],
      ),
    );
  }
}

/// A slow animation for an illustration: a few loops, ending on its final
/// frame. Still under reduced motion.
mixin _Looping<T extends StatefulWidget> on State<T>, TickerProvider {
  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      loop.stop();
    } else if (!loop.isAnimating && loop.value == 0) {
      loop.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}

/// Kitsune in the middle, with Japanese drifting around it.
class _FloatingKana extends StatefulWidget {
  const _FloatingKana();

  @override
  State<_FloatingKana> createState() => _FloatingKanaState();
}

class _FloatingKanaState extends State<_FloatingKana>
    with SingleTickerProviderStateMixin, _Looping {
  static const _words = ['こんにちは', '日本', 'あ', 'ありがとう', '猫', 'すごい'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = guideCharacter.accent;
    return SizedBox(
      width: 280,
      height: 260,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final t = loop.value * 2 * math.pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final (i, word) in _words.indexed)
                Transform.translate(
                  offset: Offset(
                    math.cos(t + i * math.pi / 3) * 118,
                    math.sin(t + i * math.pi / 3) * 92 +
                        math.sin(t * 2 + i) * 6,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      word,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(0, math.sin(t * 2) * 4),
                child: const AvatarPortrait(
                  character: guideCharacter,
                  size: 132,
                  rounded: true,
                  outlined: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A transcript line where tapping a word pops up its meaning, on a loop.
class _TapAWord extends StatefulWidget {
  const _TapAWord();

  @override
  State<_TapAWord> createState() => _TapAWordState();
}

class _TapAWordState extends State<_TapAWord>
    with SingleTickerProviderStateMixin, _Looping {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        // Tap at a third of the way through, meaning shown until the end.
        final tapped = loop.value > 0.3 || !loop.isAnimating;
        final press = (loop.value - 0.26).abs() < 0.04;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: tapped ? 1 : 0.6,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: tapped ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 16,
                        color: primary.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'コーヒー · kōhī',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'coffee',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: press ? 0.9 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: tapped ? 0.18 : 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('コーヒー', style: theme.textTheme.headlineSmall),
                    ),
                  ),
                  Text('をください。', style: theme.textTheme.headlineSmall),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coffee, please.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A week of days filling in, with the streak flame growing.
class _DailyHabit extends StatefulWidget {
  const _DailyHabit();

  @override
  State<_DailyHabit> createState() => _DailyHabitState();
}

class _DailyHabitState extends State<_DailyHabit>
    with SingleTickerProviderStateMixin, _Looping {
  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const flame = Color(0xFFFF9F43);
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        final filled = loop.isAnimating
            ? (loop.value * (_days.length + 2)).floor().clamp(0, _days.length)
            : _days.length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const AvatarPortrait(
                  character: guideCharacter,
                  size: 104,
                  rounded: true,
                  outlined: true,
                ),
                const SizedBox(width: 12),
                AnimatedScale(
                  scale: 0.8 + filled * 0.06,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: Column(
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        color: flame,
                        size: 54,
                      ),
                      Text(
                        '$filled',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: flame,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, day) in _days.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < filled
                                ? flame
                                : flame.withValues(alpha: 0.15),
                          ),
                          child: i < filled
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(day, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
