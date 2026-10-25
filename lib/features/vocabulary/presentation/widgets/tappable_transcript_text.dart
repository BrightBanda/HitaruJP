import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Renders transcript text with one tap target per token.
///
/// A stateful widget is required because every token owns a
/// [TapGestureRecognizer], and those have to be disposed when the sentence
/// changes or the row leaves the tree.
///
/// The word under the finger lights up as it is pressed and fades after, so
/// the learner can see which word their tap landed on.
class TappableTranscriptText extends StatefulWidget {
  /// Tokenised form of the sentence; concatenating them rebuilds the text.
  final List<String> tokens;
  final TextStyle? style;
  final Color? highlightColor;

  /// Behind the word being tapped; the theme's primary colour by default.
  final Color? tapColor;
  final void Function(String token) onTokenTap;

  const TappableTranscriptText({
    super.key,
    required this.tokens,
    required this.onTokenTap,
    this.style,
    this.highlightColor,
    this.tapColor,
  });

  @override
  State<TappableTranscriptText> createState() => _TappableTranscriptTextState();
}

class _TappableTranscriptTextState extends State<TappableTranscriptText>
    with SingleTickerProviderStateMixin {
  /// 1 while the finger is down on [_tapped], fading to 0 after. Only this
  /// line rebuilds while it runs, and only for that moment.
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  int? _tapped;

  /// One recognizer per token, kept across rebuilds. A transcript line rebuilds
  /// whenever the current line moves, and churning a recognizer per word on
  /// each of those frames competed with video playback for the UI thread.
  final List<TapGestureRecognizer> _recognizers = [];
  List<String>? _recognizedTokens;

  @override
  void dispose() {
    _flash.dispose();
    _disposeRecognizers();
    super.dispose();
  }

  void _press(int index) {
    setState(() => _tapped = index);
    _flash.value = 1;
  }

  void _release({required bool tapped}) {
    // Linger a moment at full strength, so even a quick tap is seen.
    _flash.animateTo(
      0,
      duration: Duration(milliseconds: tapped ? 550 : 150),
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(TappableTranscriptText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.tokens, widget.tokens)) _disposeRecognizers();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _recognizedTokens = null;
  }

  /// Creates the recognizers once per token list. Each reads `widget` when
  /// tapped, so a new callback from the parent is still honoured.
  void _ensureRecognizers() {
    if (_recognizedTokens != null) return;
    for (final (index, token) in widget.tokens.indexed) {
      _recognizers.add(
        TapGestureRecognizer()
          ..onTapDown = ((_) => _press(index))
          ..onTapCancel = (() => _release(tapped: false))
          ..onTap = () {
            // A tap shorter than the press delay never reports tap-down.
            if (_tapped != index || _flash.value == 0) _press(index);
            _release(tapped: true);
            widget.onTokenTap(token);
          },
      );
    }
    _recognizedTokens = widget.tokens;
  }

  @override
  Widget build(BuildContext context) {
    _ensureRecognizers();

    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final highlight = widget.highlightColor;
    final tapColor = widget.tapColor ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _flash,
      builder: (context, _) {
        final strength = _flash.value;
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              for (final (index, token) in widget.tokens.indexed)
                if (_isTapTarget(token))
                  TextSpan(
                    text: token,
                    style: TextStyle(
                      color: highlight,
                      backgroundColor: index == _tapped && strength > 0
                          ? tapColor.withValues(alpha: 0.28 * strength)
                          : null,
                    ),
                    recognizer: _recognizers[index],
                  )
                else
                  TextSpan(text: token),
            ],
          ),
        );
      },
    );
  }

  bool _isTapTarget(String token) {
    // Punctuation, spaces and the like are not words, so they stay inert.
    return token.trim().isNotEmpty;
  }
}
