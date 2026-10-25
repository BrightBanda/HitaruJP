import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/presentation/widgets/learner_avatar.dart';

/// The character who guides a new learner through the first open: Kitsune,
/// until the learner picks a character of their own.
const guideCharacter = AvatarCharacter.kitsune;

/// The guide talking: the character, gently bobbing, beside a speech bubble.
///
/// When [message] changes the bubble swaps its text with a little hop and the
/// character bounces, so an answer visibly gets a reaction.
class GuideBubble extends StatefulWidget {
  final AvatarCharacter character;

  /// The headline in the bubble.
  final String message;

  /// A smaller line under [message].
  final String? detail;
  final double avatarSize;

  const GuideBubble({
    super.key,
    this.character = guideCharacter,
    required this.message,
    this.detail,
    this.avatarSize = 64,
  });

  @override
  State<GuideBubble> createState() => _GuideBubbleState();
}

class _GuideBubbleState extends State<GuideBubble>
    with TickerProviderStateMixin {
  /// A slow idle bob, so the guide feels alive while the learner reads. A
  /// few cycles after each new line, then still: no endless animation.
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// A quick hop each time the guide says something new.
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  bool _reduceMotion = false;

  static const _idleCycles = 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _idle.stop();
    } else if (!_idle.isAnimating) {
      _idle.repeat(count: _idleCycles);
    }
  }

  @override
  void didUpdateWidget(GuideBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.message != widget.message ||
        oldWidget.detail != widget.detail ||
        oldWidget.character != widget.character;
    if (changed && !_reduceMotion) {
      _bounce.forward(from: 0);
      _idle.repeat(count: _idleCycles);
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = AnimatedBuilder(
      animation: Listenable.merge([_idle, _bounce]),
      builder: (context, child) {
        final bob = math.sin(_idle.value * 2 * math.pi) * 3;
        // Up and back with a small squash on landing.
        final t = _bounce.value;
        final hop = -math.sin(t * math.pi) * 12;
        final squash = 1 + math.sin(t * math.pi * 2) * 0.06 * (1 - t);
        return Transform.translate(
          offset: Offset(0, bob + hop),
          child: Transform.scale(
            scaleX: squash,
            scaleY: 2 - squash,
            child: child,
          ),
        );
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: child,
        ),
        child: AvatarPortrait(
          key: ValueKey(widget.character),
          character: widget.character,
          size: widget.avatarSize,
          rounded: true,
        ),
      ),
    );

    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(6),
        ),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topLeft,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: Column(
            key: ValueKey((widget.message, widget.detail)),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.message, style: theme.textTheme.titleLarge),
              if (widget.detail case final detail?) ...[
                const SizedBox(height: 4),
                Text(detail, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(child: bubble),
        ],
      ),
    );
  }
}
