import 'package:flutter/material.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/domain/ruby_segments.dart';

class DialogueTokenRow extends StatelessWidget {
  final DialogueLine line;
  final bool showRomaji;
  final bool showFurigana;

  /// Gap between words: wider for chat lines, tight for running text.
  final double spacing;

  /// The reading to print over a word that has none of its own.
  final String? Function(String surface)? fallbackReading;
  final ValueChanged<DialogueToken> onTokenTap;

  const DialogueTokenRow({
    super.key,
    required this.line,
    required this.showRomaji,
    this.showFurigana = false,
    this.spacing = 5,
    this.fallbackReading,
    required this.onTokenTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: spacing,
      runSpacing: 8,
      children: [
        for (final token in line.tokens)
          InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: () => onTokenTap(token),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showFurigana)
                    _RubyText(
                      token: token,
                      reading:
                          token.reading ?? fallbackReading?.call(token.surface),
                      style: theme.textTheme.bodyLarge,
                    )
                  else
                    Text(token.surface, style: theme.textTheme.bodyLarge),
                  if (showRomaji && token.romaji != null)
                    Text(
                      token.romaji!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        height: 1.1,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A word with its hiragana over each kanji. Kana in the word get blank space
/// above them, so the kanji and their readings stay lined up.
class _RubyText extends StatelessWidget {
  final DialogueToken token;
  final String? reading;
  final TextStyle? style;

  const _RubyText({
    required this.token,
    required this.reading,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final segments = rubySegments(token.surface, reading);
    final rubyStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontSize: 10, height: 1.1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final segment in segments)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // Always drawn, blank over kana, so every word on the line is
                // the same height.
                segment.ruby ?? '',
                style: rubyStyle,
              ),
              Text(segment.text, style: style),
            ],
          ),
      ],
    );
  }
}
