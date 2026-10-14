/// A stretch of a word, with the kana to print above it when it is kanji.
typedef RubySegment = ({String text, String? ruby});

/// Splits [surface] so kana go only over its kanji: 食べる with たべる gives
/// 食 over た, then べる with nothing above it.
///
/// The kana stretches written in [surface] (okurigana, particles) are found in
/// [reading] to work out where each kanji's reading starts and ends. When the
/// reading does not line up with the spelling, the whole word gets one reading.
/// Words with no kanji, or no distinct reading, come back as a single segment
/// with nothing above it.
List<RubySegment> rubySegments(String surface, String? reading) {
  if (reading == null || reading.isEmpty || !_hasKanji(surface)) {
    return [(text: surface, ruby: null)];
  }
  final folded = _toHiragana(reading);
  if (folded == _toHiragana(surface)) return [(text: surface, ruby: null)];

  // Runs of kanji and of everything else, in order.
  final runs = <({String text, bool kanji})>[];
  for (final char in surface.runes.map(String.fromCharCode)) {
    final kanji = _isKanji(char.runes.first);
    if (runs.isNotEmpty && runs.last.kanji == kanji) {
      runs[runs.length - 1] = (text: runs.last.text + char, kanji: kanji);
    } else {
      runs.add((text: char, kanji: kanji));
    }
  }

  final pattern = StringBuffer('^');
  for (final run in runs) {
    pattern.write(run.kanji ? '(.+?)' : RegExp.escape(_toHiragana(run.text)));
  }
  pattern.write(r'$');
  final match = RegExp(pattern.toString()).firstMatch(folded);
  if (match == null) return [(text: surface, ruby: folded)];

  var group = 1;
  return [
    for (final run in runs)
      (text: run.text, ruby: run.kanji ? match.group(group++) : null),
  ];
}

bool _isKanji(int code) => code >= 0x4E00 && code <= 0x9FFF || code == 0x3005;

bool _hasKanji(String text) => text.runes.any(_isKanji);

/// Katakana to hiragana, so ネコ and ねこ compare equal.
String _toHiragana(String text) => String.fromCharCodes([
  for (final code in text.runes)
    code >= 0x30A1 && code <= 0x30F6 ? code - 0x60 : code,
]);
