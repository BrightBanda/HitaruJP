import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/japanese_tokenizer.dart';

/// Turns pasted text into a readable [Dialogue].
///
/// One non-empty line per dialogue line, written
///
///     Name: 日本語[にほんご]の text | romaji | English translation
///
/// - `Name:` (ASCII or full-width colon) sets the speaker. Without any, the
///   text is a story.
/// - `漢字[かんじ]` puts a kana reading over that kanji. Kanji left without one
///   get their reading from the bundled dictionary when it knows the word.
/// - After the Japanese, `|` (or `｜`) separates the optional romaji and the
///   English translation. With a single extra part it is the translation;
///   leave the romaji empty (`text || translation`) to give only that.
class DialogueTextParser {
  const DialogueTextParser();

  static const level = 'Custom';
  static const attribution = 'Added by you';

  /// Longest prefix accepted as a speaker name, so a sentence that merely
  /// contains a colon is not mistaken for one.
  static const maxSpeakerLength = 16;

  static final _speakerLine = RegExp(
    r'^([^:：。、]{1,'
    '$maxSpeakerLength'
    r'})\s*[:：]\s*(.+)$',
  );

  static final _fieldSeparator = RegExp(r'\s*[|｜]\s*');
  static final _annotation = RegExp(r'([一-鿿々]+)\[([^\[\]]+)\]');

  Dialogue parse({
    required String id,
    required String title,
    required String text,
    required DictionaryIndex dictionary,
    DateTime? now,
  }) {
    final tokenizer = JapaneseTokenizer.dictionary(dictionary);
    final lines = <DialogueLine>[];
    final speakers = <String>[];

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      String? speaker;
      var body = trimmed;
      final match = _speakerLine.firstMatch(trimmed);
      if (match != null) {
        speaker = match.group(1)!.trim();
        body = match.group(2)!.trim();
        if (!speakers.contains(speaker)) speakers.add(speaker);
      }

      final fields = body.split(_fieldSeparator);
      final japanese = fields.first.trim();
      if (japanese.isEmpty) continue;
      String? romaji;
      String? translation;
      if (fields.length == 2) {
        translation = _blankToNull(fields[1]);
      } else if (fields.length > 2) {
        romaji = _blankToNull(fields[1]);
        translation = _blankToNull(fields.sublist(2).join(' | '));
      }

      lines.add(
        DialogueLine(
          index: lines.length,
          speaker: speaker,
          romaji: romaji,
          translation: translation,
          tokens: _tokens(japanese, tokenizer, dictionary),
        ),
      );
    }

    return Dialogue(
      id: id,
      title: title.trim(),
      level: level,
      kind: speakers.isEmpty ? DialogueKind.story : DialogueKind.dialogue,
      speakers: speakers,
      source: const DialogueSource(attribution: attribution),
      updatedAt: now,
      lines: lines,
    );
  }

  static String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Splits [text] into tokens, taking `漢字[かんじ]` readings the author wrote
  /// and falling back to the dictionary for the rest.
  List<DialogueToken> _tokens(
    String text,
    JapaneseTokenizer tokenizer,
    DictionaryIndex dictionary,
  ) {
    // Strip the annotations, remembering which stretch each one covers.
    final clean = StringBuffer();
    final spans = <({int start, int end, String reading})>[];
    var last = 0;
    for (final m in _annotation.allMatches(text)) {
      clean.write(text.substring(last, m.start));
      final start = clean.length;
      clean.write(m.group(1));
      spans.add((start: start, end: clean.length, reading: m.group(2)!.trim()));
      last = m.end;
    }
    clean.write(text.substring(last));
    final plain = clean.toString();

    // Tokens, with any that cut through an annotated stretch joined back up so
    // 日本語[にほんご] stays one tappable word.
    final pieces = <(int, int)>[];
    var offset = 0;
    for (final surface in tokenizer.tokenize(plain)) {
      pieces.add((offset, offset + surface.length));
      offset += surface.length;
    }
    final merged = <(int, int)>[];
    for (final piece in pieces) {
      if (merged.isNotEmpty) {
        final prevEnd = merged.last.$2;
        if (spans.any((s) => s.start < prevEnd && prevEnd < s.end)) {
          merged[merged.length - 1] = (merged.last.$1, piece.$2);
          continue;
        }
      }
      merged.add(piece);
    }

    return [
      for (final (start, end) in merged)
        _token(plain, start, end, spans, dictionary),
    ];
  }

  DialogueToken _token(
    String plain,
    int start,
    int end,
    List<({int start, int end, String reading})> spans,
    DictionaryIndex dictionary,
  ) {
    final surface = plain.substring(start, end);
    final inside = [
      for (final s in spans)
        if (s.start >= start && s.end <= end) s,
    ];
    if (inside.isNotEmpty) {
      // Written readings stand in for their kanji; the rest is as written.
      final reading = StringBuffer();
      var i = start;
      for (final s in inside) {
        reading.write(plain.substring(i, s.start));
        reading.write(s.reading);
        i = s.end;
      }
      reading.write(plain.substring(i, end));
      final text = reading.toString();
      if (!_hasKanji(text)) {
        return DialogueToken(
          surface: surface,
          reading: text == surface ? null : text,
        );
      }
    }
    return DialogueToken(
      surface: surface,
      reading: _readingFor(surface, dictionary),
    );
  }

  static bool _hasKanji(String text) =>
      text.runes.any((c) => c >= 0x4E00 && c <= 0x9FFF || c == 0x3005);

  /// Only worth showing when it differs from what is already written.
  static String? _readingFor(String surface, DictionaryIndex dictionary) {
    // The reading of the word as written, so 食べた gets たべた, not たべる.
    final reading = dictionary.match(surface)?.reading;
    if (reading == null || reading == surface) return null;
    return reading;
  }
}
