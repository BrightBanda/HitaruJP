import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/presentation/widgets/avatar_painter.dart';

// The admin dashboard draws the same companion in its growth simulator
// (ingrain_admin_dashboard: lib/shared/growth/mascot_painter.dart); only the
// imports differ. Change both copies together.

/// Which characters have their own art for every stage. The rest show their
/// portrait once hatched, until theirs are drawn.
const charactersWithStages = {AvatarCharacter.kitsune};

extension GrowthStageNames on GrowthStage {
  String get label => switch (this) {
    GrowthStage.egg => 'Egg',
    GrowthStage.hatchling => 'Hatchling',
    GrowthStage.child => 'Child',
    GrowthStage.teen => 'Teen',
    GrowthStage.adult => 'Adult',
    GrowthStage.master => 'Master',
    GrowthStage.legend => 'Legend',
  };

  /// What [character] is called at this stage. Kitsune grow tails as they
  /// grow wise, up to the legendary nine.
  String titleFor(AvatarCharacter character) {
    if (character != AvatarCharacter.kitsune) return label;
    return switch (this) {
      GrowthStage.egg => 'たまご · Egg',
      GrowthStage.hatchling => 'あかちゃん · Hatchling',
      GrowthStage.child => 'こぎつね · Kit',
      GrowthStage.teen => 'わかぎつね · Young fox',
      GrowthStage.adult => 'きつね · Shrine fox',
      GrowthStage.master => '三尾 · Three-tailed fox',
      GrowthStage.legend => '九尾 · Nine-tailed fox',
    };
  }
}

/// Draws a learner's companion at a growth stage, on the same 100×100 grid
/// as [AvatarPainter] (whose portrait it builds on).
class MascotPainter extends CustomPainter {
  final AvatarCharacter character;
  final GrowthStage stage;

  /// 0..1: how far the egg has cracked open, for the hatching animation.
  final double crack;

  const MascotPainter({
    required this.character,
    required this.stage,
    this.crack = 0,
  });

  static const _ink = Color(0xFF26232F);
  static const _foxFur = Color(0xFFF08A3C);
  static const _foxLight = Color(0xFFFFF4E6);
  static const _shrineRed = Color(0xFFD7263D);
  static const _gold = Color(0xFFF2C14E);
  static const _foxfire = Color(0xFF8FDBFF);

  bool get _hasStages => charactersWithStages.contains(character);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    if (stage == GrowthStage.egg) {
      _egg(canvas);
    } else if (!_hasStages) {
      _portrait(canvas, scale: 1);
    } else {
      switch (stage) {
        case GrowthStage.egg:
          break;
        case GrowthStage.hatchling:
          _hatchling(canvas);
        case GrowthStage.child:
          _sideTail(canvas, length: 34, scale: 0.8);
          _portrait(canvas, scale: 0.8);
        case GrowthStage.teen:
          _sideTail(canvas, length: 42, scale: 0.9);
          _portrait(canvas, scale: 0.9);
        case GrowthStage.adult:
          _sideTail(canvas, length: 50, scale: 1);
          _portrait(canvas, scale: 1);
          _collar(canvas, scale: 1);
        // A little smaller from here, so the tails fan out around the fox.
        case GrowthStage.master:
          // Off to the sides, none hidden straight behind the head.
          _fan(canvas, angles: const [-64, 56, 84], length: 62);
          _portrait(canvas, scale: 0.84);
          _collar(canvas, scale: 0.84);
          _forehead(canvas, scale: 0.84);
        case GrowthStage.legend:
          _aura(canvas);
          _fan(
            canvas,
            angles: [for (var i = 0; i < 9; i++) -95.0 + 190 * i / 8],
            length: 64,
          );
          _portrait(canvas, scale: 0.84);
          _collar(canvas, scale: 0.84);
          _forehead(canvas, scale: 0.84);
          _foxfires(canvas);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MascotPainter old) =>
      old.character != character || old.stage != stage || old.crack != crack;

  // --- The pieces ------------------------------------------------------------

  /// The character's own portrait, shrunk towards the bottom of the frame so
  /// a younger stage looks smaller.
  void _portrait(Canvas c, {required double scale}) {
    c.save();
    c.translate(50 * (1 - scale), 100 * (1 - scale));
    c.scale(scale);
    AvatarPainter(character).paint(c, const Size(100, 100));
    c.restore();
  }

  Path _eggPath() => Path()
    ..moveTo(50, 20)
    ..cubicTo(66, 20, 78, 42, 78, 60)
    ..cubicTo(78, 79, 66, 92, 50, 92)
    ..cubicTo(34, 92, 22, 79, 22, 60)
    ..cubicTo(22, 42, 34, 20, 50, 20)
    ..close();

  /// An egg in the character's colours (a kitsune's has fox markings), with
  /// cracks spreading as [crack] rises.
  void _egg(Canvas c) {
    final shell = _eggPath();
    final isFox = character == AvatarCharacter.kitsune;
    final base = isFox ? _foxFur : character.accent;
    final light = isFox
        ? _foxLight
        : Color.lerp(character.background, Colors.white, 0.6)!;

    // Soft shadow under the egg.
    c.drawOval(
      Rect.fromCenter(center: const Offset(50, 93), width: 44, height: 7),
      Paint()..color = _ink.withValues(alpha: 0.12),
    );
    c.drawPath(shell, Paint()..color = base);
    c.save();
    c.clipPath(shell);
    // A cream belly, like the fox's chest.
    c.drawOval(
      Rect.fromCenter(center: const Offset(50, 84), width: 64, height: 40),
      Paint()..color = light,
    );
    if (isFox) {
      // Two ear-shaped marks near the top, tipped in dark fur.
      for (final side in [-1.0, 1.0]) {
        final mark = Path()
          ..moveTo(50 + side * 4, 40)
          ..lineTo(50 + side * 11, 24)
          ..lineTo(50 + side * 19, 42)
          ..close();
        c.drawPath(mark, Paint()..color = _shade(base, 0.3));
      }
    } else {
      for (final (x, y, r) in [
        (38.0, 40.0, 5.0),
        (60.0, 34.0, 4.0),
        (64.0, 52.0, 6.0),
      ]) {
        c.drawCircle(
          Offset(x, y),
          r,
          Paint()..color = light.withValues(alpha: 0.7),
        );
      }
    }
    // A highlight, so it reads as round.
    c.drawOval(
      Rect.fromCenter(center: const Offset(33, 56), width: 8, height: 16),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    if (crack > 0) _cracks(c);
    c.restore();
    c.drawPath(
      shell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _shade(base, 0.35),
    );
  }

  /// A zigzag crack across the middle, drawn as far as [crack] has got, with
  /// a second branch once it is well under way.
  void _cracks(Canvas c) {
    const points = [
      Offset(24, 58),
      Offset(32, 52),
      Offset(38, 60),
      Offset(46, 51),
      Offset(53, 60),
      Offset(60, 51),
      Offset(67, 59),
      Offset(76, 52),
    ];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = _ink.withValues(alpha: 0.75);
    final shown = (crack.clamp(0.0, 1.0) * (points.length - 1));
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      if (i <= shown) {
        path.lineTo(points[i].dx, points[i].dy);
      } else {
        final t = shown - (i - 1);
        if (t > 0) {
          final p = Offset.lerp(points[i - 1], points[i], t)!;
          path.lineTo(p.dx, p.dy);
        }
        break;
      }
    }
    c.drawPath(path, paint);
    if (crack > 0.6) {
      c.drawPath(
        Path()
          ..moveTo(46, 51)
          ..lineTo(43, 43)
          ..lineTo(48, 37),
        paint,
      );
    }
  }

  /// Fresh out of the egg: a small kitsune in the bottom half of its shell.
  void _hatchling(Canvas c) {
    // Head well above the shell's rim, so the face peeks out.
    c.save();
    c.translate(19, 13);
    c.scale(0.62);
    AvatarPainter(character).paint(c, const Size(100, 100));
    c.restore();
    const top = 72.0;
    final shell = Path()..moveTo(17, top);
    // A jagged broken edge along the top.
    const teeth = 8;
    for (var i = 1; i <= teeth; i++) {
      final x = 17 + i * (66 / teeth);
      final y = i.isOdd ? top - 7 : top;
      shell.lineTo(x, y);
    }
    shell
      ..lineTo(83, top)
      ..cubicTo(83, 90, 70, 99, 50, 99)
      ..cubicTo(30, 99, 17, 90, 17, top)
      ..close();
    c.drawPath(shell, Paint()..color = const Color(0xFFFFF1E2));
    c.drawPath(
      shell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _shade(_foxFur, 0.25),
    );
    // A fox mark on the shell, so it is plainly this egg.
    c.drawCircle(
      const Offset(36, 86),
      3.2,
      Paint()..color = _foxFur.withValues(alpha: 0.7),
    );
    c.drawCircle(
      const Offset(62, 88),
      2.4,
      Paint()..color = _foxFur.withValues(alpha: 0.7),
    );
  }

  /// One fox tail curling up beside the body, as the portrait at [scale]
  /// sits: rooted at the right hip and sweeping out past the shoulder.
  void _sideTail(Canvas c, {required double length, required double scale}) {
    _tail(c, Offset(50 + 30 * scale, 100), angle: 38, length: length * scale);
  }

  /// Tails behind the fox at [angles] degrees from straight up.
  void _fan(Canvas c, {required List<double> angles, required double length}) {
    for (final angle in angles) {
      _tail(c, const Offset(50, 90), angle: angle, length: length);
    }
  }

  /// A plump fox tail with a white tip, from [root] at [angle] degrees from
  /// straight up.
  void _tail(
    Canvas c,
    Offset root, {
    required double angle,
    required double length,
  }) {
    final l = length;
    final w = l * 0.3;
    c.save();
    c.translate(root.dx, root.dy);
    c.rotate(angle * math.pi / 180);
    final tail = Path()
      ..moveTo(-3, 0)
      ..cubicTo(-w, -l * 0.3, -w, -l * 0.78, 0, -l)
      ..cubicTo(w, -l * 0.78, w, -l * 0.3, 3, 0)
      ..close();
    c.drawPath(tail, Paint()..color = _foxFur);
    c.save();
    c.clipPath(tail);
    // The white tip every fox tail has.
    c.drawRect(Rect.fromLTRB(-w, -l, w, -l * 0.72), Paint()..color = _foxLight);
    c.restore();
    c.drawPath(
      tail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _shade(_foxFur, 0.3),
    );
    c.restore();
  }

  /// A shrine fox's red collar and golden bell, on the portrait at [scale].
  void _collar(Canvas c, {required double scale}) {
    c.save();
    _alignWithPortrait(c, scale);
    final band = Path()
      ..moveTo(31, 86)
      ..quadraticBezierTo(50, 94, 69, 86)
      ..lineTo(69, 90)
      ..quadraticBezierTo(50, 98, 31, 90)
      ..close();
    c.drawPath(band, Paint()..color = _shrineRed);
    c.drawCircle(const Offset(50, 96), 4.4, Paint()..color = _gold);
    c.drawLine(
      const Offset(50, 96),
      const Offset(50, 99.5),
      Paint()
        ..strokeWidth = 1
        ..color = _shade(_gold, 0.45),
    );
    c.drawCircle(
      const Offset(48.6, 94.6),
      1.1,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
    c.restore();
  }

  /// Puts the canvas in the portrait's own grid when it is drawn at [scale].
  static void _alignWithPortrait(Canvas c, double scale) {
    c.translate(50 * (1 - scale), 100 * (1 - scale));
    c.scale(scale);
  }

  /// The red marking of a wise fox, between the ears.
  void _forehead(Canvas c, {required double scale}) {
    c.save();
    _alignWithPortrait(c, scale);
    final mark = Path()
      ..moveTo(50, 33)
      ..quadraticBezierTo(46, 39, 50, 44)
      ..quadraticBezierTo(54, 39, 50, 33)
      ..close();
    c.drawPath(mark, Paint()..color = _shrineRed);
    c.restore();
  }

  /// A warm golden glow behind the legend.
  void _aura(Canvas c) {
    c.drawCircle(
      const Offset(50, 58),
      50,
      Paint()
        ..shader =
            const RadialGradient(colors: [Color(0xCCFFE7A3), Color(0x00FFE7A3)])
                .createShader(
                  Rect.fromCircle(center: const Offset(50, 58), radius: 50),
                ),
    );
  }

  /// Kitsunebi: the pale fox-fires that float around a legendary fox.
  void _foxfires(Canvas c) {
    for (final (x, y, s) in [
      (12.0, 30.0, 1.0),
      (88.0, 26.0, 0.85),
      (82.0, 62.0, 0.7),
    ]) {
      c.save();
      c.translate(x, y);
      c.scale(s);
      final flame = Path()
        ..moveTo(0, 7)
        ..cubicTo(-6, 6, -6, -1, 0, -8)
        ..cubicTo(6, -1, 6, 6, 0, 7)
        ..close();
      c.drawPath(flame, Paint()..color = _foxfire.withValues(alpha: 0.85));
      c.drawCircle(
        const Offset(0, 2),
        2.4,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      c.restore();
    }
  }

  static Color _shade(Color color, double amount) =>
      Color.lerp(color, _ink, amount)!;
}

/// A companion on its pastel backdrop, the way [AvatarPortrait] shows a
/// character.
class MascotPortrait extends StatelessWidget {
  final AvatarCharacter character;
  final GrowthStage stage;
  final double size;
  final bool rounded;
  final bool outlined;
  final double crack;

  const MascotPortrait({
    super.key,
    required this.character,
    required this.stage,
    this.size = 96,
    this.rounded = true,
    this.outlined = false,
    this.crack = 0,
  });

  @override
  Widget build(BuildContext context) {
    final background = character.background;
    final legend =
        stage == GrowthStage.legend && charactersWithStages.contains(character);
    return Semantics(
      label: '${character.name}, ${stage.label}',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: rounded ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: rounded ? BorderRadius.circular(size * 0.3) : null,
          border: outlined
              ? Border.all(color: Colors.white, width: size * 0.045)
              : null,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: legend
                ? const [Color(0xFF3B2A5C), Color(0xFF7A4B8C)]
                : [Color.lerp(background, Colors.white, 0.35)!, background],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: MascotPainter(
            character: character,
            stage: stage,
            crack: crack,
          ),
        ),
      ),
    );
  }
}
