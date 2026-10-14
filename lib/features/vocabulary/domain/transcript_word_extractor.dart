import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/japanese_tokenizer.dart';

/// One distinct word found in a transcript.
class ExtractedWord {
  /// The word in dictionary form (食べる for 食べた).
  final String word;
  final DictionaryEntry entry;

  /// How many times it occurs in the transcript, inflected forms included.
  final int count;

  /// The first sentence it occurs in, for context and "play from here".
  final TranscriptSentence firstSentence;

  const ExtractedWord({
    required this.word,
    required this.entry,
    required this.count,
    required this.firstSentence,
  });
}

/// Lists the distinct dictionary words in a transcript, one row per word.
///
/// Every occurrence is looked up in the bundled dictionary and folded onto its
/// dictionary form, so 食べた and 食べない count towards 食べる. Particles and
/// other kana-only function words are left out by default: a list of は, の
/// and です is no use for study.
class TranscriptWordExtractor {
  final DictionaryIndex dictionary;
  final JapaneseTokenizer tokenizer;

  TranscriptWordExtractor(this.dictionary)
    : tokenizer = JapaneseTokenizer.dictionary(dictionary);

  /// Hiragana words this short are almost always particles or auxiliaries.
  static const _minKanaOnlyLength = 3;

  /// Words in order of first appearance. With [includeKanaOnly] false, words
  /// written only in kana and shorter than three characters are skipped.
  List<ExtractedWord> extract(
    List<TranscriptSentence> sentences, {
    bool includeKanaOnly = false,
  }) {
    final counts = <String, int>{};
    final entries = <String, DictionaryEntry>{};
    final firsts = <String, TranscriptSentence>{};

    for (final sentence in sentences) {
      for (final token in tokenizer.tokenize(sentence.text)) {
        if (!_isJapaneseWord(token)) continue;
        final match = dictionary.match(token);
        if (match == null) continue;
        final word = match.base;
        if (!includeKanaOnly &&
            _isKanaOnly(word) &&
            word.length < _minKanaOnlyLength) {
          continue;
        }
        counts[word] = (counts[word] ?? 0) + 1;
        entries.putIfAbsent(word, () => match.entry);
        firsts.putIfAbsent(word, () => sentence);
      }
    }

    return [
      for (final word in counts.keys)
        ExtractedWord(
          word: word,
          entry: entries[word]!,
          count: counts[word]!,
          firstSentence: firsts[word]!,
        ),
    ];
  }

  static bool _isJapaneseWord(String token) {
    for (final code in token.runes) {
      final japanese =
          (code >= 0x3041 && code <= 0x309F) ||
          (code >= 0x30A1 && code <= 0x30FF) ||
          (code >= 0x4E00 && code <= 0x9FFF) ||
          code == 0x3005;
      if (japanese) return true;
    }
    return false;
  }

  static bool _isKanaOnly(String word) {
    for (final code in word.runes) {
      if (code >= 0x4E00 && code <= 0x9FFF) return false;
    }
    return true;
  }
}
