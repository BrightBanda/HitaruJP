import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/growth/presentation/mascot_painter.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';

/// The companion growing from [from] into [to], played once.
///
/// Out of the egg: it wobbles, cracks, and bursts open. Any later stage:
/// a gathering glow, a flash, and the new form pops in. Under reduced motion
/// it simply shows [to].
class GrowthReveal extends StatefulWidget {
  final AvatarCharacter character;
  final GrowthStage from;
  final GrowthStage to;
  final double size;

  /// Called once the new form is showing.
  final VoidCallback? onRevealed;

  const GrowthReveal({
    super.key,
    required this.character,
    required this.from,
    required this.to,
    this.size = 180,
    this.onRevealed,
  });

  @override
  State<GrowthReveal> createState() => _GrowthRevealState();
}

class _GrowthRevealState extends State<GrowthReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _hatching ? 2600 : 1800),
  );

  bool get _hatching => widget.from == GrowthStage.egg;

  /// The moment the new form replaces the old, as a fraction of the run.
  double get _swap => _hatching ? 0.72 : 0.55;

  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  void _onTick() {
    if (!_revealed && _controller.value >= _swap) {
      _revealed = true;
      HapticFeedback.heavyImpact();
      widget.onRevealed?.call();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size * 1.3,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final before = t < _swap;
          // Before: wobble (hatching) or pulse (growing), faster towards the
          // swap. After: an overshooting pop.
          double angle = 0;
          double scale = 1;
          double crack = 0;
          if (before) {
            final p = t / _swap;
            if (_hatching) {
              angle = math.sin(p * p * 26) * 0.12 * p;
              crack = ((p - 0.3) / 0.7).clamp(0.0, 1.0);
            } else {
              scale = 1 + math.sin(p * p * 20) * 0.04 * p;
            }
          } else {
            final p = ((t - _swap) / (1 - _swap)).clamp(0.0, 1.0);
            scale = 0.6 + 0.4 * Curves.elasticOut.transform(p);
          }
          // A flash of light at the swap.
          final flash = math.max(0.0, 1 - (t - _swap).abs() / 0.12);
          final glow = before ? (t / _swap) : 1 - ((t - _swap) / (1 - _swap));

          return Stack(
            alignment: Alignment.center,
            children: [
              // Light rays behind, gathering before the swap.
              Opacity(
                opacity: (glow * 0.9).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: t * math.pi,
                  child: CustomPaint(
                    size: Size.square(widget.size * 1.3),
                    painter: _RaysPainter(
                      color: widget.character == AvatarCharacter.kitsune
                          ? const Color(0xFFFFC857)
                          : Colors.white,
                    ),
                  ),
                ),
              ),
              Transform.rotate(
                angle: angle,
                child: Transform.scale(
                  scale: scale,
                  child: MascotPortrait(
                    character: widget.character,
                    stage: before ? widget.from : widget.to,
                    crack: crack,
                    size: widget.size,
                    outlined: true,
                  ),
                ),
              ),
              IgnorePointer(
                child: Opacity(
                  opacity: flash.clamp(0.0, 1.0),
                  child: Container(
                    width: widget.size * 1.2,
                    height: widget.size * 1.2,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Colors.white, Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  final Color color;

  const _RaysPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    const rays = 12;
    for (var i = 0; i < rays; i++) {
      final a = i * 2 * math.pi / rays;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + math.cos(a - 0.09) * radius,
          center.dy + math.sin(a - 0.09) * radius,
        )
        ..lineTo(
          center.dx + math.cos(a + 0.09) * radius,
          center.dy + math.sin(a + 0.09) * radius,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}
