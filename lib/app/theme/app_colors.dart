import 'package:flutter/material.dart';

/// Static brand and semantic colors.
///
/// Widgets should prefer `Theme.of(context).colorScheme` over these constants
/// so both the light and dark themes stay supported automatically; the
/// constants exist to seed the schemes and for the few places where a fixed
/// brand color is wanted regardless of brightness.
abstract final class AppColors {
  // Brand hues.
  static const Color primaryDark = Color(
    0xFF12305E,
  ); // deep navy — headings, text on pale containers
  static const Color primaryMain = Color(
    0xFF2F6FED,
  ); // vivid blue — primary interactive color
  static const Color primaryLight = Color(
    0xFF9DB8F0,
  ); // softened blue — accents on dark surfaces

  // Accents. Each kind of content and activity has its own hue so the app
  // reads at a glance; use them for icons, tinted tiles and highlights.
  static const Color video = Color(0xFFFF5A5F); // coral
  static const Color podcast = Color(0xFF9B5DE5); // violet
  static const Color dialogue = Color(0xFF00B894); // teal
  static const Color story = Color(0xFF6C63FF); // indigo
  static const Color review = Color(0xFFFFA62B); // amber
  static const Color streak = Color(0xFFFF7A45); // orange
  static const Color vocabulary = Color(0xFFF15BB5); // pink
  static const Color sentences = Color(0xFF00A6ED); // sky

  /// Hero panels: a light sky blue settling into the brand blue. Both stops
  /// share one hue, so there is no drift towards violet; the seigaiha pattern
  /// on top (`SeigaihaPattern`) gives heroes their texture.
  static const List<Color> heroGradient = [
    Color(0xFF5094F7),
    Color(0xFF2F6FED),
  ];

  // Backgrounds.
  static const Color backgroundLight = Color(0xFFF1F6FE);
  static const Color backgroundDark = Color(0xFF0D1015);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF161B24);

  // Text.
  static const Color textPrimary = Color(0xFF141B2D);
  static const Color textSecondary = Color(0xFF5B6577);
  static const Color textOnPrimary = Colors.white;

  // Self-assessed knowledge (the kana board): yellow for "somewhat know",
  // green for "fully know".
  static const Color somewhatKnown = Color(0xFFF5B90F);
  static const Color fullyKnown = Color(0xFF22B573);

  // Semantic.
  static const Color error = Color(0xFFB3261E);
  static const Color success = Color(0xFF188857);
  static const Color warning = Color(0xFFB25E00);

  // Hairlines.
  static const Color outlineLight = Color(0xFFDCE2EC);
  static const Color outlineDark = Color(0xFF39414F);
}
