import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/presentation/widgets/avatar_painter.dart';

// The admin dashboard draws the same companion in its growth simulator
// (ingrain_admin_dashboard: lib/shared/growth/mascot_painter.dart); only the
// imports differ. Change both copies together.

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

  /// What [character] is called at this stage. Each grows into a figure from
  /// Japanese folklore: kitsune grow tails as they grow wise, up to the
  /// legendary nine; a neko becomes a lucky cat, then a cat spirit.
  String titleFor(AvatarCharacter character) {
    switch (this) {
      case GrowthStage.egg:
        return 'たまご · Egg';
      case GrowthStage.hatchling:
        return 'あかちゃん · Hatchling';
      default:
    }
    final names = switch (character) {
      AvatarCharacter.kitsune => const [
        'こぎつね · Kit',
        'わかぎつね · Young fox',
        'きつね · Shrine fox',
        '三尾 · Three-tailed fox',
        '九尾 · Nine-tailed fox',
      ],
      AvatarCharacter.neko => const [
        '子猫 · Kitten',
        '若猫 · Young cat',
        '招き猫 · Lucky cat',
        '福猫 · Fortune cat',
        '猫神 · Cat spirit',
      ],
      AvatarCharacter.shiba => const [
        '子犬 · Puppy',
        '若柴 · Young shiba',
        '柴犬 · Shiba',
        '狛犬 · Komainu',
        '金狛犬 · Golden guardian',
      ],
      AvatarCharacter.tanuki => const [
        '子狸 · Cub',
        '若狸 · Young tanuki',
        '信楽狸 · Lucky tanuki',
        '化け狸 · Shape-shifter',
        '狸大将 · Tanuki general',
      ],
      AvatarCharacter.panda => const [
        '子パンダ · Cub',
        '若パンダ · Young panda',
        'パンダ · Panda',
        '竹林の賢者 · Bamboo sage',
        '仙パンダ · Immortal panda',
      ],
      AvatarCharacter.usagi => const [
        '子うさぎ · Bunny',
        '若うさぎ · Young rabbit',
        '餅つきうさぎ · Mochi maker',
        '月うさぎ · Moon rabbit',
        '玉兎 · Jade rabbit',
      ],
      AvatarCharacter.kuma => const [
        '子熊 · Cub',
        '若熊 · Young bear',
        '鮭熊 · Salmon catcher',
        '森の主 · Forest lord',
        '山の神 · Mountain god',
      ],
      AvatarCharacter.kappa => const [
        '子河童 · Little kappa',
        '若河童 · Young kappa',
        '河童 · Kappa',
        '河童の親分 · Kappa boss',
        '水神 · Water god',
      ],
      AvatarCharacter.oni => const [
        '子鬼 · Little oni',
        '若鬼 · Young oni',
        '赤鬼 · Red oni',
        '鬼の大将 · Oni chief',
        '雷神 · Thunder god',
      ],
      AvatarCharacter.ninja => const [
        '見習い · Apprentice',
        '下忍 · Genin',
        '中忍 · Chūnin',
        '上忍 · Jōnin',
        '影 · Shadow master',
      ],
      AvatarCharacter.daruma => const [
        '小だるま · Little daruma',
        '若だるま · Young daruma',
        'だるま · Daruma',
        '願い叶う · Wish granted',
        '金だるま · Golden daruma',
      ],
      AvatarCharacter.onigiri => const [
        '一口おにぎり · Bite-size',
        '梅おにぎり · Umeboshi',
        '竹皮おにぎり · Wrapped onigiri',
        '特上おにぎり · Deluxe',
        'おにぎり王 · Onigiri king',
      ],
    };
    return names[index - GrowthStage.child.index];
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

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    if (stage == GrowthStage.egg) {
      _egg(canvas);
    } else if (stage == GrowthStage.hatchling) {
      _hatchling(canvas);
    } else if (character != AvatarCharacter.kitsune) {
      _grown(canvas);
    } else {
      switch (stage) {
        case GrowthStage.egg:
          break;
        case GrowthStage.hatchling:
          _hatchling(canvas);
        case GrowthStage.child:
          _sideTail(canvas, length: 34, scale: 0.8);
          _portrait(canvas, scale: 0.8);
          canvas.save();
          _alignWithPortrait(canvas, 0.8);
          _held(canvas, _inariSushi);
          canvas.restore();
        case GrowthStage.teen:
          // The first fox-fire: the kit's magic waking up.
          _sideTail(canvas, length: 42, scale: 0.9);
          _portrait(canvas, scale: 0.9);
          _foxfires(canvas, count: 1);
        case GrowthStage.adult:
          _sideTail(canvas, length: 50, scale: 1);
          _portrait(canvas, scale: 1);
          _collar(canvas, scale: 1);
          _foxfires(canvas, count: 1);
        // A little smaller from here, so the tails fan out around the fox.
        case GrowthStage.master:
          // Off to the sides, none hidden straight behind the head.
          _fan(canvas, angles: const [-64, 56, 84], length: 62);
          _portrait(canvas, scale: 0.84);
          _collar(canvas, scale: 0.84);
          _forehead(canvas, scale: 0.84);
          _foxfires(canvas, count: 2);
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

  /// Fresh out of the egg: a small companion in the bottom half of its shell.
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
    final isFox = character == AvatarCharacter.kitsune;
    final mark = isFox ? _foxFur : character.accent;
    c.drawPath(
      shell,
      Paint()
        ..color = isFox
            ? const Color(0xFFFFF1E2)
            : Color.lerp(character.background, Colors.white, 0.55)!,
    );
    c.drawPath(
      shell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _shade(mark, 0.25),
    );
    // The egg's own markings on the shell, so it is plainly this egg.
    c.drawCircle(
      const Offset(36, 86),
      3.2,
      Paint()..color = mark.withValues(alpha: 0.7),
    );
    c.drawCircle(
      const Offset(62, 88),
      2.4,
      Paint()..color = mark.withValues(alpha: 0.7),
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
    _collarShape(c);
    c.restore();
  }

  /// A collar band round the neck in the portrait's grid, with a golden bell.
  void _collarShape(Canvas c, {Color color = _shrineRed, bool bell = true}) {
    final band = Path()
      ..moveTo(31, 86)
      ..quadraticBezierTo(50, 94, 69, 86)
      ..lineTo(69, 90)
      ..quadraticBezierTo(50, 98, 31, 90)
      ..close();
    c.drawPath(band, Paint()..color = color);
    if (!bell) return;
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

  /// A glow behind the legend: warm gold unless [color] says otherwise.
  void _aura(Canvas c, {Color color = const Color(0xFFFFE7A3)}) {
    c.drawCircle(
      const Offset(50, 58),
      50,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                color.withValues(alpha: 0.8),
                color.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: const Offset(50, 58), radius: 50),
            ),
    );
  }

  /// Kitsunebi: the pale fox-fires that float round a fox, one more as its
  /// magic grows, up to three round the legend.
  void _foxfires(Canvas c, {int count = 3}) {
    for (final (x, y, s) in [
      (88.0, 26.0, 0.85),
      (12.0, 30.0, 1.0),
      (82.0, 62.0, 0.7),
    ].take(count)) {
      _flame(c, Offset(x, y), s, _foxfire);
    }
  }

  /// A small spirit flame with a white heart, centred on [at].
  void _flame(Canvas c, Offset at, double scale, Color color) {
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(scale);
    final flame = Path()
      ..moveTo(0, 7)
      ..cubicTo(-6, 6, -6, -1, 0, -8)
      ..cubicTo(6, -1, 6, 6, 0, 7)
      ..close();
    c.drawPath(flame, Paint()..color = color.withValues(alpha: 0.85));
    c.drawCircle(
      const Offset(0, 2),
      2.4,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    c.restore();
  }

  // --- Every other character -------------------------------------------------

  /// How big the portrait is at each grown stage: growing up to adult, then a
  /// little smaller again so what a master carries fits around it.
  static double _scaleFor(GrowthStage stage) => switch (stage) {
    GrowthStage.child => 0.8,
    GrowthStage.teen => 0.9,
    GrowthStage.adult => 1,
    _ => 0.84,
  };

  bool _atLeast(GrowthStage other) => stage.index >= other.index;
  bool get _isLegend => stage == GrowthStage.legend;

  /// A grown companion in layers: scenery, things behind the portrait, the
  /// portrait, what it wears or holds, then effects floating in front.
  void _grown(Canvas c) {
    final scale = _scaleFor(stage);
    if (_isLegend) _aura(c, color: _auraColor);
    _scenery(c);
    c.save();
    _alignWithPortrait(c, scale);
    _behind(c);
    c.restore();
    _portrait(c, scale: scale);
    c.save();
    _alignWithPortrait(c, scale);
    _front(c);
    c.restore();
    _effects(c);
  }

  Color get _auraColor => switch (character) {
    AvatarCharacter.usagi => const Color(0xFFE3ECFF),
    AvatarCharacter.kappa => const Color(0xFF9FE8F0),
    AvatarCharacter.panda => const Color(0xFFB8F0C8),
    AvatarCharacter.ninja => const Color(0xFFB9A8FF),
    _ => const Color(0xFFFFE7A3),
  };

  /// Full-frame scenery behind everything, for the legends.
  void _scenery(Canvas c) {
    if (!_isLegend) return;
    switch (character) {
      case AvatarCharacter.kuma:
        _mountains(c);
      case AvatarCharacter.oni:
        _drums(c);
      case AvatarCharacter.ninja:
        _crescent(c, const Offset(80, 18), 12, const Color(0xFFFFF3C4));
        _shadowClones(c);
      default:
    }
  }

  /// Behind the portrait, in its grid: tails, manes, moons, bamboo.
  void _behind(Canvas c) {
    switch (character) {
      case AvatarCharacter.neko:
        _catTail(c);
      case AvatarCharacter.shiba:
        if (_atLeast(GrowthStage.master)) _mane(c);
        _curlTail(c);
      case AvatarCharacter.tanuki:
        _tanukiTail(c);
      case AvatarCharacter.panda:
        if (_atLeast(GrowthStage.master)) _bamboo(c, x: 24, top: 26, width: 5);
        if (_atLeast(GrowthStage.teen)) _bamboo(c, x: 10, top: 12);
        if (_atLeast(GrowthStage.adult)) _bamboo(c, x: 90, top: 4);
      case AvatarCharacter.usagi:
        if (_atLeast(GrowthStage.master)) {
          _fullMoon(c);
        } else if (_atLeast(GrowthStage.teen)) {
          _crescent(c, const Offset(84, 16), 9, const Color(0xFFFFE9A8));
        }
      case AvatarCharacter.kappa:
        if (_atLeast(GrowthStage.master)) _lotusLeaf(c);
        if (_atLeast(GrowthStage.teen)) _shell(c);
      case AvatarCharacter.oni:
        if (_atLeast(GrowthStage.adult)) _kanabo(c);
      case AvatarCharacter.ninja:
        if (_atLeast(GrowthStage.adult)) _katana(c);
      case AvatarCharacter.onigiri:
        if (_atLeast(GrowthStage.adult)) _bambooWrap(c);
      default:
    }
  }

  /// In front of the portrait, in its grid: what it wears and holds.
  void _front(Canvas c) {
    switch (character) {
      case AvatarCharacter.neko:
        if (stage == GrowthStage.child) _held(c, _yarnBall);
        if (_atLeast(GrowthStage.teen)) _collarShape(c);
        if (_atLeast(GrowthStage.adult)) _beckoningPaw(c);
        if (_atLeast(GrowthStage.master)) _koban(c, const Offset(76, 92), 1);
      case AvatarCharacter.shiba:
        if (stage == GrowthStage.child) _held(c, _bone);
        if (_atLeast(GrowthStage.teen)) _bandana(c);
      case AvatarCharacter.tanuki:
        // A cub practising with its first shape-shifting leaf.
        if (stage == GrowthStage.child) {
          _leaf(c, const Offset(80, 92), 1.6, _leafGreen);
        }
        if (_atLeast(GrowthStage.teen)) _kasa(c);
        if (_atLeast(GrowthStage.adult)) _gourd(c);
      case AvatarCharacter.panda:
        if (_atLeast(GrowthStage.master)) {
          _beard(c);
          _glasses(c);
        } else {
          _bambooSprig(c);
        }
        if (stage == GrowthStage.teen) _takenoko(c);
      case AvatarCharacter.usagi:
        if (_atLeast(GrowthStage.teen)) _earRibbon(c);
        if (_atLeast(GrowthStage.adult)) {
          _mortar(c);
        } else {
          _mochiInPaws(c);
        }
      case AvatarCharacter.kuma:
        if (stage == GrowthStage.child) _held(c, _acorn);
        if (_atLeast(GrowthStage.teen)) {
          _collarShape(c, color: const Color(0xFF3E8E5A), bell: false);
        }
        if (_atLeast(GrowthStage.adult)) _salmon(c);
        if (_atLeast(GrowthStage.master)) _leafCrown(c);
      case AvatarCharacter.kappa:
        _cucumber(c);
        // A grown kappa's dish brims with river water, the source of its
        // strength.
        if (_atLeast(GrowthStage.adult)) _dishWater(c);
      case AvatarCharacter.oni:
        if (stage == GrowthStage.child) _held(c, _toyClub);
        if (_atLeast(GrowthStage.teen)) _tigerScarf(c);
        if (_atLeast(GrowthStage.master)) _tigerShoulders(c);
      case AvatarCharacter.ninja:
        if (_atLeast(GrowthStage.master)) {
          _scroll(c);
        } else if (_atLeast(GrowthStage.teen)) {
          _shuriken(c, const Offset(78, 92), 8);
        } else {
          _held(c, _paperShuriken);
        }
      case AvatarCharacter.daruma:
        if (_isLegend) _goldenBody(c);
        if (stage == GrowthStage.child) _brush(c);
        if (_atLeast(GrowthStage.teen)) _plumSprig(c);
        if (_atLeast(GrowthStage.adult)) _hachimaki(c);
        if (_atLeast(GrowthStage.master)) _secondEye(c);
      case AvatarCharacter.onigiri:
        if (stage == GrowthStage.child) _furikake(c);
        if (_atLeast(GrowthStage.master)) _takuan(c);
        if (_atLeast(GrowthStage.teen)) _umeboshi(c);
        if (_atLeast(GrowthStage.master)) _ikura(c);
        if (_isLegend) _crown(c);
      default:
    }
  }

  /// Full-frame effects in front of everything.
  void _effects(Canvas c) {
    switch (character) {
      case AvatarCharacter.neko:
        if (_isLegend) {
          _koban(c, const Offset(12, 22), 0.6);
          _koban(c, const Offset(88, 16), 0.5);
          _koban(c, const Offset(10, 60), 0.45);
        }
      case AvatarCharacter.shiba:
        if (_isLegend) {
          _tama(c);
          _sparkles(c, _gold);
        }
      case AvatarCharacter.tanuki:
        if (_atLeast(GrowthStage.master)) {
          _smoke(c);
          _floatingLeaves(c);
        }
      case AvatarCharacter.panda:
        if (_isLegend) _clouds(c);
      case AvatarCharacter.usagi:
        if (_isLegend) _sparkles(c, const Color(0xFFFFF3C4));
      case AvatarCharacter.kuma:
        if (_isLegend) _sparkles(c, _gold);
      case AvatarCharacter.kappa:
        if (_isLegend) _waves(c);
      case AvatarCharacter.oni:
        if (_isLegend) _lightning(c);
      case AvatarCharacter.ninja:
        if (_atLeast(GrowthStage.master)) {
          _smoke(c, color: const Color(0xFFB8BCC8));
        }
      case AvatarCharacter.daruma:
        if (_atLeast(GrowthStage.master)) _sparkles(c, _gold);
      case AvatarCharacter.onigiri:
        if (_isLegend) _sparkles(c, _gold);
      default:
    }
  }

  // --- Neko: lucky cat, then nekomata -----------------------------------------

  static const _nekoFur = Color(0xFF8E9BB3);
  static const _nekoLight = Color(0xFFF1F3F8);
  static const _onibi = Color(0xFFB79CFF);

  /// A long cat tail curling up beside the body, tied with a red bow from
  /// master and tipped with a spirit flame for the legend.
  void _catTail(Canvas c) {
    final tail = Path()
      ..moveTo(72, 100)
      ..cubicTo(98, 98, 100, 70, 94, 52)
      ..quadraticBezierTo(91, 43, 85, 46);
    c.drawPath(tail, _line(_shade(_nekoFur, 0.3), 9.5));
    c.drawPath(tail, _line(_nekoFur, 7));
    if (_atLeast(GrowthStage.master)) {
      // Where the tail runs straight up, so the bow sits square across it.
      const knot = Offset(96.8, 66.8);
      for (final side in [-1.0, 1.0]) {
        final loop = Path()
          ..moveTo(knot.dx, knot.dy)
          ..lineTo(knot.dx + side * 6.5, knot.dy - 4)
          ..lineTo(knot.dx + side * 6.5, knot.dy + 4)
          ..close();
        c.drawPath(loop, Paint()..color = _shrineRed);
      }
      c.drawCircle(knot, 2, Paint()..color = _shade(_shrineRed, 0.2));
    }
    if (_isLegend) _flame(c, const Offset(85, 38), 0.9, _onibi);
  }

  /// The maneki-neko's raised paw, beckoning good luck in: an arm rising
  /// from the left shoulder, outlined so it stands out against the head.
  void _beckoningPaw(Canvas c) {
    const shoulder = Offset(27, 100);
    const paw = Offset(19, 75);
    c.drawLine(shoulder, paw, _line(_shade(_nekoFur, 0.3), 14.4));
    c.drawLine(shoulder, paw, _line(_nekoFur, 12));
    c.drawCircle(paw, 8.5, Paint()..color = _nekoLight);
    c.drawCircle(paw, 8.5, _line(_shade(_nekoFur, 0.3), 1.2));
    final pad = Paint()..color = const Color(0xFFF7B3C6);
    c.drawOval(
      Rect.fromCenter(
        center: paw + const Offset(0, 2.5),
        width: 6,
        height: 4.6,
      ),
      pad,
    );
    for (final toe in const [
      Offset(-4.4, -2.4),
      Offset(0, -4.2),
      Offset(4.4, -2.4),
    ]) {
      c.drawCircle(paw + toe, 1.5, pad);
    }
  }

  /// A gold koban coin, the lucky cat's treasure.
  void _koban(Canvas c, Offset at, double scale) {
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(scale);
    final coin = Rect.fromCenter(center: Offset.zero, width: 15, height: 21);
    c.drawOval(coin, Paint()..color = _gold);
    c.drawOval(coin, _line(_shade(_gold, 0.4), 1.2));
    final lines = _line(_shade(_gold, 0.3), 0.9);
    for (final y in [-4.0, 0.0, 4.0]) {
      c.drawLine(Offset(-4, y), Offset(4, y), lines);
    }
    c.drawOval(
      Rect.fromCenter(center: const Offset(-3.4, -5), width: 2.6, height: 5),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
    c.restore();
  }

  // --- Shiba: faithful dog, then komainu ----------------------------------------

  static const _shibaFur = Color(0xFFE09A4F);
  static const _shibaLight = Color(0xFFFFF7EA);

  /// The shiba's tightly curled tail, peeking over a shoulder.
  void _curlTail(Canvas c) {
    final r = _atLeast(GrowthStage.adult) ? 12.0 : 10.0;
    const centre = Offset(87, 76);
    c.drawCircle(centre, r, Paint()..color = _shibaFur);
    c.drawCircle(centre, r, _line(_shade(_shibaFur, 0.3), 1.2));
    c.drawCircle(
      centre + const Offset(-2, 2),
      r * 0.45,
      Paint()..color = _shibaLight,
    );
  }

  /// A komainu's mane of curls framing the face; golden for the legend.
  void _mane(Canvas c) {
    final color = _isLegend ? _gold : const Color(0xFFB8733A);
    const count = 13;
    for (var i = 0; i < count; i++) {
      final a = math.pi * (0.85 + 1.3 * i / (count - 1));
      final at = Offset(50 + 37 * math.cos(a), 57 + 34 * math.sin(a));
      c.drawCircle(at, 8.5, Paint()..color = color);
      c.drawCircle(at, 3.4, _line(_shade(color, 0.3), 1.3));
    }
  }

  /// A red bandana tied under the chin, spotted and medalled once grown.
  void _bandana(Canvas c) {
    final scarf = Path()
      ..moveTo(29, 84)
      ..quadraticBezierTo(50, 91, 71, 84)
      ..lineTo(50, 101)
      ..close();
    c.drawPath(scarf, Paint()..color = const Color(0xFFE63946));
    if (!_atLeast(GrowthStage.adult)) return;
    for (final (x, y) in [(42.0, 89.0), (58.0, 89.0)]) {
      c.drawCircle(Offset(x, y), 1.5, Paint()..color = Colors.white);
    }
    // A faithful dog's gold medal.
    c.drawCircle(const Offset(50, 95), 3.8, Paint()..color = _gold);
    c.drawCircle(const Offset(50, 95), 3.8, _line(_shade(_gold, 0.4), 0.9));
    c.drawCircle(
      const Offset(48.8, 93.8),
      1,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  /// The jewel a komainu guards under its paw.
  void _tama(Canvas c) {
    const centre = Offset(84, 88);
    c.drawCircle(
      centre,
      9,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFE8FFF4), Color(0xFF4CC9A0)],
        ).createShader(Rect.fromCircle(center: centre, radius: 9)),
    );
    c.drawCircle(centre, 9, _line(_shade(_gold, 0.2), 1.6));
  }

  // --- Tanuki: lucky statue, then shape-shifter -------------------------------

  static const _tanukiFur = Color(0xFF9A7655);
  static const _tanukiMask = Color(0xFF5B4535);
  static const _leafGreen = Color(0xFF4CAF6A);

  /// A big bushy tail with dark rings.
  void _tanukiTail(Canvas c) {
    c.save();
    c.translate(86, 80);
    c.rotate(0.5);
    final rect = Rect.fromCenter(center: Offset.zero, width: 18, height: 34);
    c.drawOval(rect, Paint()..color = _tanukiFur);
    c.save();
    c.clipPath(Path()..addOval(rect));
    for (final y in [-12.0, -3.0]) {
      c.drawRect(Rect.fromLTWH(-10, y, 20, 4), Paint()..color = _tanukiMask);
    }
    c.restore();
    c.drawOval(rect, _line(_shade(_tanukiFur, 0.3), 1.2));
    c.restore();
  }

  /// A straw kasa hat, with the shape-shifting leaf still on top.
  void _kasa(Canvas c) {
    const straw = Color(0xFFD9B26F);
    final hat = Path()
      ..moveTo(10, 38)
      ..quadraticBezierTo(50, 2, 90, 38)
      ..quadraticBezierTo(50, 46, 10, 38)
      ..close();
    c.drawPath(hat, Paint()..color = straw);
    final weave = _line(_shade(straw, 0.2), 0.9);
    for (final x in [26.0, 38.0, 50.0, 62.0, 74.0]) {
      c.drawLine(const Offset(50, 21), Offset(x, 41), weave);
    }
    c.drawPath(hat, _line(_shade(straw, 0.35), 1.2));
    _leaf(c, const Offset(50, 21), 1, _isLegend ? _gold : _leafGreen);
  }

  /// A leaf standing up from [base], like the one on the tanuki's head.
  void _leaf(Canvas c, Offset base, double scale, Color color) {
    c.save();
    c.translate(base.dx, base.dy);
    c.scale(scale);
    final leaf = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-11, -6, -6, -17)
      ..quadraticBezierTo(5, -14, 0, 0)
      ..close();
    c.drawPath(leaf, Paint()..color = color);
    c.drawLine(
      Offset.zero,
      const Offset(-4.5, -13),
      _line(_shade(color, 0.3), 1),
    );
    c.restore();
  }

  /// A gourd flask tied with a red cord.
  void _gourd(Canvas c) {
    const gourd = Color(0xFFE8B84A);
    final edge = _line(_shade(gourd, 0.35), 1.1);
    c.drawCircle(const Offset(17, 91), 8, Paint()..color = gourd);
    c.drawCircle(const Offset(17, 91), 8, edge);
    c.drawCircle(const Offset(17, 79), 5.5, Paint()..color = gourd);
    c.drawCircle(const Offset(17, 79), 5.5, edge);
    c.drawRect(
      const Rect.fromLTWH(13, 83.6, 8, 2.4),
      Paint()..color = _shrineRed,
    );
    c.drawLine(
      const Offset(17, 73.5),
      const Offset(17, 71),
      _line(_tanukiMask, 1.8),
    );
  }

  /// Leaves spinning round a shape-shifter: three, or six golden ones.
  void _floatingLeaves(Canvas c) {
    final spots = [
      (12.0, 34.0, -0.5),
      (90.0, 38.0, 0.6),
      (16.0, 74.0, -0.9),
      if (_isLegend) ...[
        (86.0, 76.0, 0.9),
        (28.0, 12.0, -0.2),
        (74.0, 12.0, 0.3),
      ],
    ];
    for (final (x, y, a) in spots) {
      c.save();
      c.translate(x, y);
      c.rotate(a);
      _leaf(c, const Offset(3, 8), 0.7, _isLegend ? _gold : _leafGreen);
      c.restore();
    }
  }

  /// Puffs of transformation smoke along the bottom.
  void _smoke(Canvas c, {Color color = Colors.white}) {
    final puff = Paint()..color = color.withValues(alpha: 0.8);
    for (final (x, y, r) in [
      (6.0, 96.0, 9.0),
      (18.0, 100.0, 8.0),
      (94.0, 95.0, 9.0),
      (82.0, 100.0, 7.0),
    ]) {
      c.drawCircle(Offset(x, y), r, puff);
    }
  }

  // --- Panda: bamboo sage ---------------------------------------------------

  static const _bambooGreen = Color(0xFF6DBE6A);

  /// A bamboo stalk from the bottom edge up to [top], with leaves.
  void _bamboo(
    Canvas c, {
    required double x,
    required double top,
    double width = 7,
  }) {
    c.drawRRect(
      RRect.fromLTRBR(
        x - width / 2,
        top,
        x + width / 2,
        102,
        const Radius.circular(2),
      ),
      Paint()..color = _bambooGreen,
    );
    final node = _line(_shade(_bambooGreen, 0.25), 1.2);
    for (var y = top + 16; y < 100; y += 18) {
      c.drawLine(Offset(x - width / 2, y), Offset(x + width / 2, y), node);
    }
    final leaf = Paint()..color = _shade(_bambooGreen, 0.12);
    for (final (dx, dy, a) in [(7.0, 4.0, 1.1), (-7.0, 9.0, -1.1)]) {
      c.save();
      c.translate(x + dx, top + dy);
      c.rotate(a);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 4.4, height: 13),
        leaf,
      );
      c.restore();
    }
  }

  /// A bamboo shoot held up to nibble.
  void _bambooSprig(Canvas c) {
    c.drawLine(
      const Offset(62, 102),
      const Offset(80, 74),
      _line(_bambooGreen, 3.6),
    );
    final leaf = Paint()..color = _shade(_bambooGreen, 0.12);
    for (final (x, y, a) in [(85.0, 72.0, 0.9), (77.0, 70.0, -0.4)]) {
      c.save();
      c.translate(x, y);
      c.rotate(a);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 4.4, height: 12),
        leaf,
      );
      c.restore();
    }
  }

  /// A sage's long white beard.
  void _beard(Canvas c) {
    final beard = Path()
      ..moveTo(40, 75)
      ..quadraticBezierTo(43, 93, 50, 100)
      ..quadraticBezierTo(57, 93, 60, 75)
      ..quadraticBezierTo(50, 81, 40, 75)
      ..close();
    c.drawPath(beard, Paint()..color = const Color(0xFFF4F4F6));
    c.drawPath(beard, _line(const Color(0xFFD4D4DC), 1));
  }

  /// Little clouds for an immortal to ride.
  void _clouds(Canvas c) {
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.92);
    for (final (x, y, s) in [
      (12.0, 92.0, 1.0),
      (88.0, 90.0, 1.0),
      (86.0, 26.0, 0.6),
    ]) {
      for (final (dx, dy, r) in [
        (-7.0, 2.0, 6.0),
        (0.0, -2.0, 8.0),
        (8.0, 2.0, 6.0),
      ]) {
        c.drawCircle(Offset(x + dx * s, y + dy * s), r * s, cloud);
      }
    }
  }

  // --- Usagi: mochi maker, then moon rabbit -----------------------------------

  static const _usagiFur = Color(0xFFF7F3FA);
  static const _usagiEdge = Color(0xFFE6DDF0);

  /// A ball of mochi held in both paws.
  void _mochiInPaws(Canvas c) {
    final mochi = Rect.fromCenter(
      center: const Offset(50, 92),
      width: 20,
      height: 13,
    );
    c.drawOval(mochi, Paint()..color = Colors.white);
    c.drawOval(mochi, _line(_usagiEdge, 1.2));
    c.drawCircle(
      const Offset(54, 90),
      2,
      Paint()..color = const Color(0xFFF7A6C2).withValues(alpha: 0.6),
    );
    for (final x in [39.0, 61.0]) {
      final paw = Rect.fromCenter(center: Offset(x, 94), width: 10, height: 8);
      c.drawOval(paw, Paint()..color = _usagiFur);
      c.drawOval(paw, _line(_usagiEdge, 1.2));
    }
  }

  /// A mochi mortar (usu) with its mallet (kine).
  void _mortar(Canvas c) {
    const wood = Color(0xFF9C6B3F);
    c.save();
    c.translate(92, 64);
    c.rotate(0.6);
    c.drawLine(
      Offset.zero,
      const Offset(0, 30),
      _line(_shade(wood, -0.1), 2.6),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 15, height: 7),
        const Radius.circular(2),
      ),
      Paint()..color = wood,
    );
    c.restore();
    final usu = Path()
      ..moveTo(67, 86)
      ..lineTo(91, 86)
      ..lineTo(88, 101)
      ..lineTo(70, 101)
      ..close();
    c.drawPath(usu, Paint()..color = wood);
    c.drawPath(usu, _line(_shade(wood, 0.3), 1.1));
    c.drawOval(
      Rect.fromCenter(center: const Offset(79, 86), width: 24, height: 6),
      Paint()..color = _shade(wood, 0.25),
    );
    c.drawOval(
      Rect.fromCenter(center: const Offset(79, 84.5), width: 15, height: 6),
      Paint()..color = Colors.white,
    );
  }

  /// A crescent moon around [centre].
  void _crescent(Canvas c, Offset centre, double r, Color color) {
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: centre, radius: r)),
      Path()..addOval(
        Rect.fromCircle(
          center: centre + Offset(r * 0.45, -r * 0.25),
          radius: r * 0.85,
        ),
      ),
    );
    c.drawPath(moon, Paint()..color = color);
  }

  /// The full moon the rabbit lives on, with faint craters.
  void _fullMoon(Canvas c) {
    const moon = Color(0xFFFFF3C4);
    c.drawCircle(const Offset(50, 40), 40, Paint()..color = moon);
    final crater = Paint()..color = _shade(moon, 0.08).withValues(alpha: 0.7);
    for (final (x, y, r) in [
      (22.0, 26.0, 5.0),
      (80.0, 22.0, 4.0),
      (82.0, 48.0, 6.0),
    ]) {
      c.drawCircle(Offset(x, y), r, crater);
    }
  }

  // --- Kuma: salmon catcher, then mountain god ---------------------------------

  /// An acorn, found on a cub's first walk.
  void _acorn(Canvas c) {
    c.drawOval(
      Rect.fromCenter(center: const Offset(76, 93), width: 10, height: 12),
      Paint()..color = const Color(0xFFB07A44),
    );
    c.drawArc(
      Rect.fromCenter(center: const Offset(76, 89), width: 12, height: 8),
      math.pi,
      math.pi,
      true,
      Paint()..color = const Color(0xFF6B4226),
    );
    c.drawLine(
      const Offset(76, 85),
      const Offset(77.5, 82),
      _line(const Color(0xFF6B4226), 1.6),
    );
  }

  /// A salmon held across the chest, like the carved bears of Hokkaido.
  void _salmon(Canvas c) {
    const fish = Color(0xFFF28C6B);
    c.save();
    c.translate(52, 93);
    c.rotate(-0.3);
    final tail = Path()
      ..moveTo(-18, 0)
      ..lineTo(-27, -7)
      ..lineTo(-25, 0)
      ..lineTo(-27, 7)
      ..close();
    c.drawPath(tail, Paint()..color = _shade(fish, 0.12));
    final body = Rect.fromCenter(center: Offset.zero, width: 40, height: 12);
    c.drawOval(body, Paint()..color = fish);
    c.drawOval(
      Rect.fromCenter(center: const Offset(0, 3), width: 32, height: 5),
      Paint()..color = const Color(0xFFFFD3C2),
    );
    c.drawOval(body, _line(_shade(fish, 0.3), 1));
    c.drawCircle(const Offset(14, -1.5), 1.4, Paint()..color = _ink);
    c.drawArc(
      Rect.fromCenter(center: const Offset(10, 0), width: 6, height: 9),
      -0.9,
      1.8,
      false,
      _line(_shade(fish, 0.3), 0.9),
    );
    c.restore();
  }

  /// A crown of leaves between the ears; golden for the legend.
  void _leafCrown(Canvas c) {
    final color = _isLegend ? _gold : const Color(0xFF5DAE4B);
    const count = 7;
    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      c.save();
      c.translate(30 + 40 * t, 33 - 6 * math.sin(math.pi * t));
      c.rotate((t - 0.5) * 1.4);
      final leaf = Rect.fromCenter(
        center: const Offset(0, -3),
        width: 6,
        height: 11,
      );
      c.drawOval(leaf, Paint()..color = color);
      c.drawOval(leaf, _line(_shade(color, 0.3), 0.8));
      c.restore();
    }
  }

  /// Snow-capped peaks behind the mountain god.
  void _mountains(Canvas c) {
    const rock = Color(0xFF6E7FA8);
    for (final (left, peak, right) in [
      (const Offset(-6, 100), const Offset(24, 54), const Offset(54, 100)),
      (const Offset(46, 100), const Offset(80, 48), const Offset(110, 100)),
    ]) {
      final mountain = Path()
        ..moveTo(left.dx, left.dy)
        ..lineTo(peak.dx, peak.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      c.drawPath(mountain, Paint()..color = rock);
      final snow = Path()
        ..moveTo(peak.dx - 8, peak.dy + 12)
        ..lineTo(peak.dx, peak.dy)
        ..lineTo(peak.dx + 8, peak.dy + 12)
        ..lineTo(peak.dx + 3, peak.dy + 9)
        ..lineTo(peak.dx, peak.dy + 13)
        ..lineTo(peak.dx - 3, peak.dy + 9)
        ..close();
      c.drawPath(snow, Paint()..color = Colors.white);
    }
  }

  // --- Kappa: river boss, then water god ---------------------------------------

  static const _kappaGreen = Color(0xFF4E9F3D);

  /// The kappa's shell, showing round its shoulders.
  void _shell(Canvas c) {
    const shell = Color(0xFF5E8A4A);
    final rect = Rect.fromCenter(
      center: const Offset(50, 98),
      width: 98,
      height: 50,
    );
    c.drawOval(rect, Paint()..color = shell);
    c.drawOval(rect, _line(_shade(shell, 0.3), 2));
    if (!_atLeast(GrowthStage.master)) return;
    final plates = _line(_shade(shell, 0.25), 1.4);
    for (final x in [12.0, 88.0]) {
      c.drawCircle(Offset(x, 92), 5, plates);
    }
  }

  /// A lotus leaf held up as an umbrella.
  void _lotusLeaf(Canvas c) {
    c.drawLine(
      const Offset(78, 80),
      const Offset(86, 24),
      _line(_shade(_kappaGreen, 0.2), 2.6),
    );
    const centre = Offset(86, 20);
    c.drawCircle(centre, 17, Paint()..color = _kappaGreen);
    final vein = _line(_shade(_kappaGreen, -0.12), 1);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      c.drawLine(centre, centre + Offset(math.cos(a), math.sin(a)) * 15, vein);
    }
  }

  /// A kappa's favourite snack.
  void _cucumber(Canvas c) {
    c.save();
    c.translate(26, 90);
    c.rotate(-0.6);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 30, height: 9),
      const Radius.circular(4.5),
    );
    c.drawRRect(body, Paint()..color = _kappaGreen);
    c.drawRRect(body, _line(_shade(_kappaGreen, 0.3), 1));
    final bump = Paint()..color = _shade(_kappaGreen, -0.15);
    for (final x in [-9.0, -3.0, 3.0, 9.0]) {
      c.drawCircle(Offset(x, -1.5), 0.9, bump);
    }
    c.restore();
  }

  /// Rolling waves along the bottom for the water god.
  void _waves(Canvas c) {
    const sea = Color(0xFF3A86C8);
    final crest = _line(Colors.white.withValues(alpha: 0.85), 1.2);
    for (var row = 0; row < 2; row++) {
      final y = 104.0 - row * 6;
      for (var x = row * 9.0 - 9; x <= 110; x += 18) {
        final centre = Offset(x, y);
        c.drawCircle(centre, 10, Paint()..color = _shade(sea, row * 0.08));
        for (final r in [10.0, 6.5, 3.0]) {
          c.drawArc(
            Rect.fromCircle(center: centre, radius: r),
            math.pi,
            math.pi,
            false,
            crest,
          );
        }
      }
    }
  }

  // --- Oni: red oni, then Raijin ------------------------------------------------

  static const _tigerYellow = Color(0xFFF2B33D);

  /// A studded iron club standing beside the oni.
  void _kanabo(Canvas c) {
    const iron = Color(0xFF4A4E5A);
    c.save();
    c.translate(84, 104);
    c.rotate(0.14);
    final club = Path()
      ..moveTo(-2.5, 0)
      ..lineTo(-6.5, -76)
      ..quadraticBezierTo(0, -84, 6.5, -76)
      ..lineTo(2.5, 0)
      ..close();
    c.drawPath(club, Paint()..color = iron);
    c.drawPath(club, _line(_shade(iron, 0.4), 1));
    final stud = Paint()..color = const Color(0xFFCBD3DE);
    for (var y = -36.0; y > -76; y -= 8) {
      c.drawCircle(Offset(-2.6, y), 1.4, stud);
      c.drawCircle(Offset(2.6, y - 4), 1.4, stud);
    }
    c.restore();
  }

  /// A tiger-skin scarf, as oni wear.
  void _tigerScarf(Canvas c) {
    _collarShape(c, color: _tigerYellow, bell: false);
    final stripe = _line(_ink, 1.6);
    for (final x in [36.0, 44.0, 56.0, 64.0]) {
      c.drawLine(Offset(x, 87), Offset(x + 1.5, 92), stripe);
    }
  }

  /// A tiger pelt draped over both shoulders.
  void _tigerShoulders(Canvas c) {
    for (final x in [20.0, 80.0]) {
      final pad = Rect.fromCenter(center: Offset(x, 96), width: 28, height: 15);
      c.drawOval(pad, Paint()..color = _tigerYellow);
      c.save();
      c.clipPath(Path()..addOval(pad));
      final stripe = _line(_ink, 2);
      for (final dx in [-8.0, 0.0, 8.0]) {
        c.drawLine(Offset(x + dx - 2, 89), Offset(x + dx + 2, 99), stripe);
      }
      c.restore();
    }
  }

  /// Raijin's ring of thunder drums.
  void _drums(Canvas c) {
    const centre = Offset(50, 52);
    c.drawCircle(centre, 44, _line(_gold, 2));
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final at = centre + Offset(math.cos(a), math.sin(a)) * 44;
      c.drawCircle(at, 7, Paint()..color = const Color(0xFFC0392B));
      c.drawCircle(at, 5, Paint()..color = const Color(0xFFF5E6C8));
      c.drawCircle(at + const Offset(1, -1), 1.8, Paint()..color = _ink);
    }
  }

  /// Lightning bolts crackling either side.
  void _lightning(Canvas c) {
    for (final (x, y, s) in [(12.0, 30.0, 1.0), (88.0, 60.0, 0.85)]) {
      c.save();
      c.translate(x, y);
      c.scale(s);
      final bolt = Path()
        ..moveTo(2, -14)
        ..lineTo(-6, 1)
        ..lineTo(0, 1)
        ..lineTo(-3, 14)
        ..lineTo(7, -3)
        ..lineTo(1, -3)
        ..lineTo(5, -14)
        ..close();
      c.drawPath(bolt, Paint()..color = const Color(0xFFFFE14D));
      c.drawPath(bolt, _line(const Color(0xFFE0A800), 1));
      c.restore();
    }
  }

  // --- Ninja: rising ranks, then shadow master ---------------------------------

  /// A katana slung across the back, hilt over the right shoulder.
  void _katana(Canvas c) {
    c.drawLine(
      const Offset(14, 100),
      const Offset(80, 21),
      _line(const Color(0xFF2B2B35), 5),
    );
    c.drawOval(
      Rect.fromCenter(center: const Offset(80, 21), width: 9, height: 4),
      Paint()..color = _gold,
    );
    c.drawLine(
      const Offset(81.5, 19),
      const Offset(90, 9),
      _line(const Color(0xFFE63946), 4.4),
    );
    final wrap = _line(Colors.white, 0.9);
    for (final t in [0.25, 0.5, 0.75]) {
      final p = Offset.lerp(const Offset(81.5, 19), const Offset(90, 9), t)!;
      c.drawLine(
        p + const Offset(-1.6, -1.2),
        p + const Offset(1.6, 1.2),
        wrap,
      );
    }
  }

  /// A four-pointed shuriken.
  void _shuriken(Canvas c, Offset at, double r) {
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(0.3);
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final len = i.isEven ? r : r * 0.32;
      final p = Offset(math.cos(a), math.sin(a)) * len;
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    c.drawPath(star, Paint()..color = const Color(0xFFCBD3DE));
    c.drawPath(star, _line(const Color(0xFF6B7385), 1));
    c.drawCircle(
      Offset.zero,
      r * 0.18,
      Paint()..color = const Color(0xFF2F3652),
    );
    c.restore();
  }

  /// A secret scroll held in the teeth, as a ninja casts a jutsu.
  void _scroll(Canvas c) {
    c.drawRRect(
      RRect.fromLTRBR(32, 67, 68, 74, const Radius.circular(2)),
      Paint()..color = const Color(0xFFF3E3C3),
    );
    c.drawLine(
      const Offset(40, 70.5),
      const Offset(60, 70.5),
      _line(_ink.withValues(alpha: 0.5), 1),
    );
    final cap = Paint()..color = const Color(0xFFE63946);
    c.drawRRect(
      RRect.fromLTRBR(29, 65.5, 33, 75.5, const Radius.circular(1.5)),
      cap,
    );
    c.drawRRect(
      RRect.fromLTRBR(67, 65.5, 71, 75.5, const Radius.circular(1.5)),
      cap,
    );
  }

  /// Two shadow clones either side of the master.
  void _shadowClones(Canvas c) {
    for (final dx in [-30.0, 30.0]) {
      c.saveLayer(
        const Rect.fromLTWH(-50, 0, 200, 100),
        Paint()
          ..colorFilter = const ColorFilter.mode(
            Color(0x806A5ACD),
            BlendMode.srcIn,
          ),
      );
      c.translate(dx + 50 * (1 - 0.6), 100 * (1 - 0.6) - 4);
      c.scale(0.6);
      AvatarPainter(character).paint(c, const Size(100, 100));
      c.restore();
    }
  }

  // --- Daruma: the wish comes true ---------------------------------------------

  /// A plum blossom sprig: the first flower of the year, for perseverance.
  void _plumSprig(Canvas c) {
    c.drawPath(
      Path()
        ..moveTo(100, 16)
        ..quadraticBezierTo(88, 20, 80, 34),
      _line(const Color(0xFF6B4226), 2),
    );
    for (final (x, y, s) in [
      (84.0, 26.0, 1.0),
      (93.0, 18.0, 0.8),
      (79.0, 35.0, 0.7),
    ]) {
      for (var i = 0; i < 5; i++) {
        final a = -math.pi / 2 + i * 2 * math.pi / 5;
        c.drawCircle(
          Offset(x, y) + Offset(math.cos(a), math.sin(a)) * 2.6 * s,
          2.2 * s,
          Paint()..color = const Color(0xFFF7A6C2),
        );
      }
      c.drawCircle(Offset(x, y), 1.1 * s, Paint()..color = _gold);
    }
  }

  /// A hachimaki headband, tied on with determination.
  void _hachimaki(Canvas c) {
    final body = Path()
      ..addOval(
        Rect.fromCenter(center: const Offset(50, 66), width: 80, height: 76),
      );
    c.save();
    c.clipPath(body);
    c.drawRect(
      const Rect.fromLTRB(0, 30, 100, 36),
      Paint()..color = Colors.white,
    );
    c.restore();
    c.drawCircle(const Offset(50, 33), 2.4, Paint()..color = _shrineRed);
    // The knot at the side of the head, its ends flying out.
    const knot = Offset(70, 33);
    for (final (dx, dy) in [(10.0, -6.0), (11.0, 2.0)]) {
      c.drawLine(knot, knot + Offset(dx, dy), _line(Colors.white, 3));
    }
    c.drawCircle(knot, 2.6, Paint()..color = Colors.white);
  }

  /// The second eye painted in: the daruma's wish has come true.
  void _secondEye(Canvas c) {
    c.drawOval(
      Rect.fromCenter(center: const Offset(59, 53), width: 9.2, height: 9.2),
      Paint()..color = _ink,
    );
    c.drawCircle(const Offset(60.4, 51.6), 1.5, Paint()..color = Colors.white);
  }

  /// Gold leaf over the red body, leaving the face as it is.
  void _goldenBody(Canvas c) {
    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(
        Rect.fromCenter(center: const Offset(50, 66), width: 80, height: 76),
      )
      ..addOval(
        Rect.fromCenter(center: const Offset(50, 54), width: 46, height: 38),
      );
    c.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE89A), Color(0xFFE0A93A)],
        ).createShader(const Rect.fromLTRB(10, 28, 90, 104)),
    );
    final text = TextPainter(
      text: const TextSpan(
        text: '福',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: _shrineRed,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(c, Offset(50 - text.width / 2, 75));
    text.dispose();
  }

  // --- Onigiri: toppings, then a crown ------------------------------------------

  /// The bamboo-bark wrapper an onigiri sits on.
  void _bambooWrap(Canvas c) {
    const bark = Color(0xFFC9B27C);
    final wrap = Rect.fromCenter(
      center: const Offset(50, 94),
      width: 104,
      height: 22,
    );
    c.drawOval(wrap, Paint()..color = bark);
    c.drawOval(wrap, _line(_shade(bark, 0.3), 1.2));
    c.drawLine(
      const Offset(4, 94),
      const Offset(96, 94),
      _line(_shade(bark, 0.2), 0.9),
    );
  }

  /// An umeboshi plum on top.
  void _umeboshi(Canvas c) {
    c.drawCircle(
      const Offset(50, 22),
      6,
      Paint()..color = const Color(0xFFC8324A),
    );
    c.drawCircle(
      const Offset(48, 20),
      1.6,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  /// Salmon roe either side of the plum.
  void _ikura(Canvas c) {
    final roe = Paint()..color = const Color(0xFFF57C20);
    for (final (x, y) in [
      (42.0, 26.0),
      (58.0, 26.0),
      (44.0, 31.0),
      (56.0, 31.0),
    ]) {
      c.drawCircle(Offset(x, y), 2.4, roe);
      c.drawCircle(
        Offset(x - 0.8, y - 0.8),
        0.7,
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
    }
  }

  /// Slices of yellow pickled radish on the wrapper.
  void _takuan(Canvas c) {
    const pickle = Color(0xFFF2D04B);
    for (final (x, y) in [(14.0, 90.0), (86.0, 90.0)]) {
      c.drawArc(
        Rect.fromCenter(center: Offset(x, y), width: 13, height: 13),
        math.pi,
        math.pi,
        true,
        Paint()..color = pickle,
      );
    }
  }

  /// A small gold crown on the tip.
  void _crown(Canvas c) {
    final crown = Path()
      ..moveTo(38, 14)
      ..lineTo(37, 3)
      ..lineTo(44, 8)
      ..lineTo(50, 0)
      ..lineTo(56, 8)
      ..lineTo(63, 3)
      ..lineTo(62, 14)
      ..close();
    c.drawPath(crown, Paint()..color = _gold);
    c.drawPath(crown, _line(_shade(_gold, 0.4), 1));
    c.drawCircle(const Offset(50, 10), 1.8, Paint()..color = _shrineRed);
  }

  // --- First keepsakes and new details per stage ------------------------------

  /// Draws a child's keepsake, laid out around (77, 93), larger and lifted
  /// clear of the bottom edge so it reads at a small size.
  void _held(Canvas c, void Function(Canvas) keepsake) {
    c.save();
    c.translate(77, 84);
    c.scale(1.45);
    c.translate(-77, -93);
    keepsake(c);
    c.restore();
  }

  /// An inari sushi, a fox's favourite, held up by the kit.
  void _inariSushi(Canvas c) {
    const tofu = Color(0xFFD99A4E);
    final pouch = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(77, 93), width: 18, height: 12),
      const Radius.circular(6),
    );
    c.drawRRect(pouch, Paint()..color = tofu);
    c.drawRRect(pouch, _line(_shade(tofu, 0.3), 1));
    c.drawOval(
      Rect.fromCenter(center: const Offset(77, 88.5), width: 14, height: 4),
      Paint()..color = Colors.white,
    );
  }

  /// A kitten's ball of yarn, a loose end trailing.
  void _yarnBall(Canvas c) {
    const yarn = Color(0xFFF7A6C2);
    const centre = Offset(77, 92);
    c.drawCircle(centre, 8, Paint()..color = yarn);
    final strand = _line(_shade(yarn, 0.2), 1);
    c.drawArc(
      Rect.fromCircle(center: centre + const Offset(-3, 0), radius: 7),
      -1.2,
      2.4,
      false,
      strand,
    );
    c.drawArc(
      Rect.fromCircle(center: centre + const Offset(3, 1), radius: 6),
      1.9,
      2.4,
      false,
      strand,
    );
    c.drawPath(
      Path()
        ..moveTo(84, 96)
        ..quadraticBezierTo(92, 98, 90, 102),
      _line(yarn, 1.4),
    );
  }

  /// A puppy's chew bone.
  void _bone(Canvas c) {
    const ivory = Color(0xFFFFF7EA);
    final edge = _line(const Color(0xFFD9C3A0), 1);
    c.save();
    c.translate(77, 93);
    c.rotate(-0.4);
    final bar = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 16, height: 5),
      const Radius.circular(2),
    );
    for (final (x, y) in [(-8.0, -2.4), (-8.0, 2.4), (8.0, -2.4), (8.0, 2.4)]) {
      c.drawCircle(Offset(x, y), 3, Paint()..color = ivory);
      c.drawCircle(Offset(x, y), 3, edge);
    }
    c.drawRRect(bar, Paint()..color = ivory);
    c.restore();
  }

  /// A young bamboo shoot (takenoko) poking up.
  void _takenoko(Canvas c) {
    const husk = Color(0xFFB98A4E);
    for (final (y, w) in [(100.0, 14.0), (94.0, 10.0), (88.0, 6.0)]) {
      final layer = Path()
        ..moveTo(84 - w / 2, y)
        ..lineTo(84, y - 12)
        ..lineTo(84 + w / 2, y)
        ..close();
      c.drawPath(layer, Paint()..color = husk);
      c.drawPath(layer, _line(_shade(husk, 0.3), 0.9));
    }
    c.drawCircle(const Offset(84, 76), 1.6, Paint()..color = _bambooGreen);
  }

  /// A sage's round spectacles.
  void _glasses(Canvas c) {
    final rim = _line(_gold, 1.4);
    for (final x in [38.5, 61.5]) {
      c.drawCircle(Offset(x, 55.5), 6.8, rim);
    }
    c.drawLine(const Offset(45.3, 55), const Offset(54.7, 55), rim);
  }

  /// A ribbon tied at the base of the rabbit's ear.
  void _earRibbon(Canvas c) {
    const ribbon = Color(0xFFE85D8A);
    const knot = Offset(64, 34);
    for (final side in [-1.0, 1.0]) {
      final loop = Path()
        ..moveTo(knot.dx, knot.dy)
        ..lineTo(knot.dx + side * 7, knot.dy - 4)
        ..lineTo(knot.dx + side * 7, knot.dy + 4)
        ..close();
      c.drawPath(loop, Paint()..color = ribbon);
    }
    c.drawCircle(knot, 2, Paint()..color = _shade(ribbon, 0.2));
  }

  /// Water brimming in the kappa's dish, with drops running down.
  void _dishWater(Canvas c) {
    const water = Color(0xFF7FC8F8);
    c.drawOval(
      Rect.fromCenter(center: const Offset(50, 30.6), width: 22, height: 6.4),
      Paint()..color = water,
    );
    _sparkle(c, const Offset(56, 29.6), 2.6, Colors.white);
    for (final (x, y) in [(33.0, 38.0), (68.0, 40.0)]) {
      final drop = Path()
        ..moveTo(x, y - 3.4)
        ..quadraticBezierTo(x + 2.4, y, x, y + 2)
        ..quadraticBezierTo(x - 2.4, y, x, y - 3.4)
        ..close();
      c.drawPath(drop, Paint()..color = water);
    }
  }

  /// A little oni's wooden toy club.
  void _toyClub(Canvas c) {
    const wood = Color(0xFFC48A55);
    c.save();
    c.translate(78, 102);
    c.rotate(0.3);
    final club = Path()
      ..moveTo(-1.6, 0)
      ..lineTo(-3.6, -22)
      ..quadraticBezierTo(0, -26, 3.6, -22)
      ..lineTo(1.6, 0)
      ..close();
    c.drawPath(club, Paint()..color = wood);
    c.drawPath(club, _line(_shade(wood, 0.35), 1));
    final knob = Paint()..color = _shade(wood, 0.25);
    for (final y in [-10.0, -16.0, -21.0]) {
      c.drawCircle(Offset(0, y), 1, knob);
    }
    c.restore();
  }

  /// An apprentice's folded-paper shuriken, in two colours.
  void _paperShuriken(Canvas c) {
    c.save();
    c.translate(78, 93);
    c.rotate(0.4);
    const colors = [Color(0xFF4A7BD0), Color(0xFFE63946)];
    for (var i = 0; i < 4; i++) {
      c.save();
      c.rotate(i * math.pi / 2);
      final blade = Path()
        ..moveTo(0, 0)
        ..lineTo(0, -8)
        ..lineTo(4.5, -3)
        ..close();
      c.drawPath(blade, Paint()..color = colors[i % 2]);
      c.restore();
    }
    c.restore();
  }

  /// The brush that will one day paint the daruma's second eye.
  void _brush(Canvas c) {
    c.drawLine(
      const Offset(84, 102),
      const Offset(91, 78),
      _line(const Color(0xFFD9B26F), 2.6),
    );
    c.drawLine(
      const Offset(90.4, 80),
      const Offset(91.6, 76),
      _line(_shade(_gold, 0.4), 3),
    );
    final tip = Path()
      ..moveTo(90.4, 76)
      ..quadraticBezierTo(91.5, 68, 94, 66)
      ..quadraticBezierTo(94.4, 72, 93, 76.6)
      ..close();
    c.drawPath(tip, Paint()..color = _ink);
  }

  /// A sprinkle of colourful furikake on a bite-size onigiri.
  void _furikake(Canvas c) {
    for (final (x, y, color) in [
      (44.0, 36.0, const Color(0xFF5DAE4B)),
      (55.0, 38.0, const Color(0xFFF2C14E)),
      (49.0, 41.0, const Color(0xFFF57C20)),
      (40.0, 42.0, const Color(0xFFF2C14E)),
      (60.0, 43.0, const Color(0xFF5DAE4B)),
      (52.0, 33.0, const Color(0xFFF57C20)),
    ]) {
      c.drawCircle(Offset(x, y), 1.1, Paint()..color = color);
    }
  }

  // --- Shared sparkle helpers ----------------------------------------------------

  /// A four-pointed twinkle.
  void _sparkle(Canvas c, Offset at, double r, Color color) {
    final star = Path()
      ..moveTo(at.dx, at.dy - r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r)
      ..close();
    c.drawPath(star, Paint()..color = color);
  }

  /// Twinkles scattered round the edges.
  void _sparkles(Canvas c, Color color) {
    for (final (x, y, r) in [
      (12.0, 18.0, 4.0),
      (88.0, 12.0, 3.0),
      (92.0, 46.0, 3.6),
      (8.0, 56.0, 3.0),
      (22.0, 6.0, 2.4),
    ]) {
      _sparkle(c, Offset(x, y), r, color);
    }
  }

  static Paint _line(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

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
    final legend = stage == GrowthStage.legend;
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
