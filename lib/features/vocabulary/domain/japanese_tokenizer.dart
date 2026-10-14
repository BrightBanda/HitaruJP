import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';

/// Splits Japanese text into tap-targetable tokens.
///
/// There is no morphological analyser in the app, so segmentation is driven by
/// the bundled dictionary: the longest known word starting at the cursor wins,
/// which keeps compounds like 日本語 from being torn into 日本 + 語, and an
/// inflected word like 食べなかった whole. Anything the dictionary does not know
/// still becomes a token (a single kanji, a kana run, a latin word, a number),
/// so every character on screen stays tappable.
class JapaneseTokenizer {
  JapaneseTokenizer(Set<String> knownWords)
    : _isWord = knownWords.contains,
      _maxWordLength = knownWords.fold<int>(
        0,
        (longest, word) => word.length > longest ? word.length : longest,
      );

  /// Recognises everything [dictionary] does, inflected forms included.
  JapaneseTokenizer.dictionary(DictionaryIndex dictionary)
    : _isWord = dictionary.isWord,
      _maxWordLength = dictionary.maxWordLength == 0
          ? 0
          : (dictionary.maxWordLength + _inflectionAllowance).clamp(
              0,
              _maxCandidateLength,
            );

  /// Inflection can make a word longer than its dictionary form:
  /// 食べる (3) → 食べさせられなかった (10).
  static const _inflectionAllowance = 8;

  /// Longer candidates are almost never words, and each one costs a lookup.
  static const _maxCandidateLength = 16;

  final bool Function(String) _isWord;
  final int _maxWordLength;

  int get maxWordLength => _maxWordLength;

  List<String> tokenize(String text) {
    final tokens = <String>[];
    var index = 0;

    while (index < text.length) {
      final codeUnit = text.codeUnitAt(index);
      final kind = _classify(codeUnit);

      if (kind == _TokenKind.whitespace || kind == _TokenKind.punctuation) {
        final start = index;
        while (index < text.length &&
            _classify(text.codeUnitAt(index)) == kind) {
          index++;
        }
        tokens.add(text.substring(start, index));
        continue;
      }

      final word = _longestKnownWord(text, index);
      if (word != null) {
        tokens.add(word);
        index += word.length;
        continue;
      }

      if (kind == _TokenKind.hiragana ||
          kind == _TokenKind.katakana ||
          kind == _TokenKind.latin ||
          kind == _TokenKind.digit) {
        final start = index;
        while (index < text.length &&
            _classify(text.codeUnitAt(index)) == kind) {
          index++;
        }
        tokens.add(text.substring(start, index));
        continue;
      }

      // Unknown kanji: keep it tappable on its own.
      tokens.add(text[index]);
      index++;
    }

    return tokens;
  }

  String? _longestKnownWord(String text, int index) {
    if (_maxWordLength == 0) return null;
    final remaining = text.length - index;
    final longest = _maxWordLength < remaining ? _maxWordLength : remaining;

    for (var length = longest; length >= 1; length--) {
      final candidate = text.substring(index, index + length);
      if (_isWord(candidate)) return candidate;
    }
    return null;
  }

  static _TokenKind _classify(int codeUnit) {
    if (_isWhitespace(codeUnit)) return _TokenKind.whitespace;
    if (_isPunctuation(codeUnit)) return _TokenKind.punctuation;
    if (_isHiragana(codeUnit)) return _TokenKind.hiragana;
    if (_isKatakana(codeUnit)) return _TokenKind.katakana;
    if (_isLatin(codeUnit)) return _TokenKind.latin;
    if (_isDigit(codeUnit)) return _TokenKind.digit;
    return _TokenKind.other;
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D ||
      codeUnit == 0x3000;

  /// Japanese punctuation and the ASCII symbols that behave like it.
  static bool _isPunctuation(int codeUnit) =>
      codeUnit == 0x3001 || // 、
      codeUnit == 0x3002 || // 。
      codeUnit == 0x300C || // 「
      codeUnit == 0x300D || // 」
      codeUnit == 0x300E || // 『
      codeUnit == 0x300F || // 』
      codeUnit == 0xFF01 || // ！
      codeUnit == 0xFF1F || // ？
      codeUnit == 0xFF0C || // ，
      codeUnit == 0xFF0E || // ．
      codeUnit == 0xFF1A || // ：
      codeUnit == 0xFF1B || // ；
      codeUnit == 0xFF08 || // （
      codeUnit == 0xFF09 || // ）
      codeUnit == 0x2018 ||
      codeUnit == 0x2019 ||
      codeUnit == 0x201C ||
      codeUnit == 0x201D ||
      codeUnit == 0x2026 || // …
      codeUnit == 0xFF5E || // ～
      codeUnit >= 0x21 && codeUnit <= 0x2F ||
      codeUnit >= 0x3A && codeUnit <= 0x40 ||
      codeUnit >= 0x5B && codeUnit <= 0x60 ||
      codeUnit >= 0x7B && codeUnit <= 0x7E;

  static bool _isHiragana(int codeUnit) =>
      codeUnit >= 0x3041 && codeUnit <= 0x309F;

  /// Includes the prolonged sound mark, the iteration marks and both
  /// halfwidth katakana forms.
  static bool _isKatakana(int codeUnit) =>
      codeUnit >= 0x30A0 && codeUnit <= 0x30FF ||
      codeUnit >= 0x31F0 && codeUnit <= 0x31FF ||
      codeUnit >= 0xFF66 && codeUnit <= 0xFF9D;

  static bool _isLatin(int codeUnit) =>
      codeUnit >= 0x41 && codeUnit <= 0x5A ||
      codeUnit >= 0x61 && codeUnit <= 0x7A ||
      codeUnit >= 0xFF21 && codeUnit <= 0xFF3A ||
      codeUnit >= 0xFF41 && codeUnit <= 0xFF5A;

  static bool _isDigit(int codeUnit) =>
      codeUnit >= 0x30 && codeUnit <= 0x39 ||
      codeUnit >= 0xFF10 && codeUnit <= 0xFF19;
}

enum _TokenKind {
  whitespace,
  punctuation,
  hiragana,
  katakana,
  latin,
  digit,
  other,
}
