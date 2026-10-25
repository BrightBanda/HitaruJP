import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A one-off burst of confetti over [child], for a moment worth celebrating.
///
/// One controller and one painter for every piece, behind its own repaint
/// boundary, so it costs a single cheap layer per frame and nothing once it
/// has fallen. Skipped when the system asks for reduced motion.
class ConfettiBurst extends StatefulWidget {
  final Widget child;
  final List<Color> colors;

  const ConfettiBurst({
    super.key,
    required this.child,
    this.colors = const [
      Color(0xFFFF8FA3),
      Color(0xFFFFC857),
      Color(0xFF6BCB77),
      Color(0xFF4D96FF),
      Color(0xFFB983FF),
      Color(0xFFFF9F43),
    ],
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    _pieces = List.generate(90, (i) {
      // Two cannons, bottom left and bottom right, firing up and inwards.
      final fromLeft = i.isEven;
      final angle =
          (fromLeft ? -math.pi / 3 : -2 * math.pi / 3) +
          (random.nextDouble() - 0.5) * 0.7;
      final speed = 1.8 + random.nextDouble() * 0.8;
      return _Piece(
        startX: fromLeft ? 0.05 : 0.95,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        spin: (random.nextDouble() - 0.5) * 18,
        size: 6 + random.nextDouble() * 6,
        color: widget.colors[i % widget.colors.length],
        round: random.nextDouble() < 0.3,
        delay: random.nextDouble() * 0.15,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) &&
        _controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ConfettiPainter(_pieces, _controller),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Piece {
  final double startX;
  final double vx;
  final double vy;
  final double spin;
  final double size;
  final Color color;
  final bool round;
  final double delay;

  const _Piece({
    required this.startX,
    required this.vx,
    required this.vy,
    required this.spin,
    required this.size,
    required this.color,
    required this.round,
    required this.delay,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final Animation<double> progress;

  _ConfettiPainter(this.pieces, this.progress) : super(repaint: progress);

  static const _gravity = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t == 0 || t == 1) return;
    final paint = Paint();
    for (final piece in pieces) {
      final local = ((t - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (local == 0) continue;
      // Ballistic flight in screen-sized units: up from the bottom edge to
      // near the top, then back down.
      final time = local * 1.6;
      final x = piece.startX + piece.vx * time * 0.35;
      final y = 1.0 + piece.vy * time + 0.5 * _gravity * time * time;
      if (y > 1.1) continue;
      final opacity = local > 0.75 ? (1 - local) / 0.25 : 1.0;
      paint.color = piece.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(piece.spin * time);
      if (piece.round) {
        canvas.drawCircle(Offset.zero, piece.size / 2, paint);
      } else {
        // Flutter like paper: the width shrinks and grows as it turns.
        final flip = math.cos(piece.spin * time * 1.3).abs();
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.size * (0.3 + flip * 0.7),
            height: piece.size * 0.6,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => false;
}
