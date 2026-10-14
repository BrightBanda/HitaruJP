import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/japanese_tokenizer.dart';

/// Turns pasted text into a readable [Dialogue].
///
/// One non-empty line per dialogue line. A line written `Name: text` (ASCII or
/// full-width colon) is attributed to `Name`; anything else has no speaker, and
/// a text with no speakers at all is treated as a story. Tokens get their
/// reading from the bundled dictionary when it knows the word, and no romaji,
/// since the app has no kana-to-romaji converter.
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

      lines.add(
        DialogueLine(
          index: lines.length,
          speaker: speaker,
          tokens: [
            for (final surface in tokenizer.tokenize(body))
              DialogueToken(
                surface: surface,
                reading: _readingFor(surface, dictionary),
              ),
          ],
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

  /// Only worth showing when it differs from what is already written.
  static String? _readingFor(String surface, DictionaryIndex dictionary) {
    // The reading of the word as written, so 食べた gets たべた, not たべる.
    final reading = dictionary.match(surface)?.reading;
    if (reading == null || reading == surface) return null;
    return reading;
  }
}
