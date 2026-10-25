import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:ingrain/features/settings/presentation/viewmodel/settings_view_model.dart';

/// The parts of the app the home tour points at. Each key is placed on the
/// widget it names by whichever layout is on screen (phone bar, rail or
/// sidebar), so the tour works at every window size.
abstract final class HomeTourTargets {
  static final goal = GlobalKey(debugLabel: 'tour: goal');
  static final picks = GlobalKey(debugLabel: 'tour: picks');
  static final library = GlobalKey(debugLabel: 'tour: library');
  static final flashcards = GlobalKey(debugLabel: 'tour: flashcards');
}

class _TourStep {
  final GlobalKey target;
  final String title;
  final String body;

  const _TourStep(this.target, this.title, this.body);
}

/// Starts the home tour over [child] once, for a learner fresh out of the
/// first lesson.
class HomeTourLauncher extends ConsumerStatefulWidget {
  final Widget child;

  const HomeTourLauncher({super.key, required this.child});

  @override
  ConsumerState<HomeTourLauncher> createState() => _HomeTourLauncherState();
}

class _HomeTourLauncherState extends ConsumerState<HomeTourLauncher> {
  OverlayEntry? _entry;
  bool _scheduled = false;

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _maybeStart() {
    if (_scheduled) return;
    final run = ref.read(firstRunProvider);
    if (!run.homeTipsPending || run.lessonPending) return;
    _scheduled = true;
    // Give the page a moment to settle (data, layout) before pointing at it.
    Future.delayed(const Duration(milliseconds: 700), _start);
  }

  void _start() {
    if (!mounted || _entry != null) return;
    final goalMinutes = ref
        .read(settingsViewModelProvider)
        .settings
        ?.dailyGoalMinutes;
    final steps = [
      _TourStep(
        HomeTourTargets.goal,
        'Your daily goal',
        goalMinutes == null
            ? 'Immerse a little every day to fill it and keep your streak.'
            : 'Immerse $goalMinutes minutes a day to fill it and keep your '
                  'streak.',
      ),
      _TourStep(
        HomeTourTargets.picks,
        'Today’s picks',
        'Fresh videos at your level, chosen for you every day.',
      ),
      _TourStep(
        HomeTourTargets.library,
        'Your library',
        'Everything you watch, read or add lives here.',
      ),
      _TourStep(
        HomeTourTargets.flashcards,
        'Flashcards',
        'コーヒー is already waiting for you here!',
      ),
    ].where((step) => step.target.currentContext != null).toList();
    if (steps.isEmpty) return _finish();

    _entry = OverlayEntry(
      builder: (_) => _HomeTour(steps: steps, onDone: _finish),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _finish() {
    _entry?.remove();
    _entry = null;
    final uid = ref.read(authViewModelProvider).uid;
    if (uid.isNotEmpty) ref.read(firstRunProvider.notifier).finishHomeTips(uid);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeStart();
    });
    return widget.child;
  }
}

/// The overlay: the page dimmed except for a lit-up cut-out around the step's
/// target, with a card explaining it. Tap anywhere to go on.
class _HomeTour extends StatefulWidget {
  final List<_TourStep> steps;
  final VoidCallback onDone;

  const _HomeTour({required this.steps, required this.onDone});

  @override
  State<_HomeTour> createState() => _HomeTourState();
}

class _HomeTourState extends State<_HomeTour> {
  int _index = 0;
  Rect? _hole;

  _TourStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  /// Scrolls the target into view if needed, then measures it.
  Future<void> _locate() async {
    final target = _step.target.currentContext;
    if (target == null) return _next();
    final scrollable = Scrollable.maybeOf(target);
    if (scrollable != null) {
      await Scrollable.ensureVisible(
        target,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    final box = _step.target.currentContext?.findRenderObject();
    final overlay = context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox || !box.hasSize) {
      return _next();
    }
    setState(() {
      _hole = (box.localToGlobal(Offset.zero, ancestor: overlay) & box.size)
          .inflate(8);
    });
  }

  void _next() {
    if (_isLast) return widget.onDone();
    setState(() => _index++);
    _locate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final hole = _hole;
    // Below the target when the card fits there, else above, else pinned to
    // the bottom of the screen over a target too tall for either.
    const cardRoom = 180.0;
    double? top;
    double? bottom;
    if (hole != null) {
      if (size.height - padding.bottom - hole.bottom >= cardRoom) {
        top = hole.bottom + 14;
      } else if (hole.top - padding.top >= cardRoom) {
        bottom = size.height - hole.top + 14;
      } else {
        bottom = padding.bottom + 24;
      }
    }

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _next,
        child: Stack(
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: hole ?? Rect.zero),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, rect, _) => CustomPaint(
                  painter: _ScrimPainter(
                    hole: rect ?? Rect.zero,
                    color: Colors.black.withValues(alpha: 0.68),
                  ),
                ),
              ),
            ),
            if (hole != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: 16,
                right: 16,
                top: top,
                bottom: bottom,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _TipCard(
                      key: ValueKey(_index),
                      title: _step.title,
                      body: _step.body,
                      index: _index,
                      count: widget.steps.length,
                      isLast: _isLast,
                      onNext: _next,
                      onSkip: widget.onDone,
                      theme: theme,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final String title;
  final String body;
  final int index;
  final int count;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final ThemeData theme;

  const _TipCard({
    super.key,
    required this.title,
    required this.body,
    required this.index,
    required this.count,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black38)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${index + 1} of $count',
                  style: theme.textTheme.labelSmall,
                ),
                const Spacer(),
                if (!isLast)
                  TextButton(onPressed: onSkip, child: const Text('Skip')),
                FilledButton(
                  onPressed: onNext,
                  child: Text(isLast ? 'Got it!' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything except a rounded cut-out at [hole].
class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final Color color;

  const _ScrimPainter({required this.hole, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (!hole.isEmpty) {
      path.addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(18)));
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.color != color;
}
