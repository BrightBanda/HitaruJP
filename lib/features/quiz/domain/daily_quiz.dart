import 'dart:math';

import 'package:ingrain/core/text/romaji.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';

/// A Japanese word and four meanings, one of them right.
class QuizQuestion {
  final String word;

  /// Shown above the word as furigana; null when the word is all kana.
  final String? furigana;
  final String romaji;
  final List<String> choices;
  final int answerIndex;

  /// One of the learner's own saved words, rather than one at their level.
  final bool fromSaved;

  const QuizQuestion({
    required this.word,
    required this.furigana,
    required this.romaji,
    required this.choices,
    required this.answerIndex,
    this.fromSaved = false,
  });

  String get answer => choices[answerIndex];
}

/// Today's quiz: the same twelve words however often it is opened that day.
class DailyQuiz {
  static const length = 12;

  /// At most this many of the learner's own saved words; the rest come from
  /// common words at their level.
  static const savedShare = 6;

  final DateTime day;
  final List<QuizQuestion> questions;

  const DailyQuiz({required this.day, required this.questions});

  /// Builds the quiz for [day] from [saved] words and the [dictionary], for a
  /// learner at [level]. [seed] (their uid) makes it theirs: the same day
  /// gives the same quiz, and different learners get different ones.
  factory DailyQuiz.build({
    required DateTime day,
    required String seed,
    required List<VocabularyItem> saved,
    required List<DictionaryEntry> dictionary,
    JlptLevel? level,
  }) {
    final random = Random(_hash('$seed:${quizDayKey(day)}'));
    final (start, end) = levelBand(level);
    final band = <_Word>[];
    for (var i = start; i < end && i < dictionary.length; i++) {
      final word = _Word.fromEntry(dictionary[i]);
      if (word != null) band.add(word);
    }
    // Distractors need meanings to pick from even if the band is thin.
    final pool = band.length >= 50
        ? band
        : [for (final entry in dictionary.take(3000)) ?_Word.fromEntry(entry)];

    final readings = {
      for (final entry in dictionary.take(20000)) entry.surface: entry.reading,
    };
    final mine = [
      for (final item in saved) ?_Word.ofSaved(item, readings[item.word]),
    ]..shuffle(random);

    final chosen = <_Word>[];
    final seen = <String>{};
    void take(_Word word) {
      if (chosen.length >= length) return;
      if (seen.add(word.surface) &&
          seen.add('m:${word.meaning.toLowerCase()}')) {
        chosen.add(word);
      }
    }

    for (final word in mine.take(savedShare)) {
      take(word);
    }
    final shuffledBand = [...band]..shuffle(random);
    for (final word in shuffledBand) {
      if (chosen.length >= length) break;
      take(word);
    }
    chosen.shuffle(random);

    return DailyQuiz(
      day: DateTime(day.year, day.month, day.day),
      questions: [for (final word in chosen) _question(word, pool, random)],
    );
  }

  /// The slice of the frequency-ordered dictionary that suits [level].
  static (int, int) levelBand(JlptLevel? level) => switch (level) {
    JlptLevel.n4 => (300, 2000),
    JlptLevel.n3 => (1000, 4000),
    JlptLevel.n2 => (2500, 7000),
    JlptLevel.n1 => (5000, 12000),
    _ => (0, 1000),
  };

  static QuizQuestion _question(_Word word, List<_Word> pool, Random random) {
    final wrong = <String>[];
    final taken = {word.meaning.toLowerCase()};
    // Same kind of word first (a noun among nouns), so the answer is not
    // given away by its grammar.
    final sameKind = pool.where((w) => w.kind == word.kind).toList()
      ..shuffle(random);
    final anyKind = [...pool]..shuffle(random);
    for (final other in [...sameKind, ...anyKind]) {
      if (wrong.length == 3) break;
      if (other.surface == word.surface) continue;
      if (taken.add(other.meaning.toLowerCase())) wrong.add(other.meaning);
    }
    final choices = [...wrong, word.meaning]..shuffle(random);
    return QuizQuestion(
      word: word.surface,
      furigana: word.hasKanji ? word.reading : null,
      romaji: toRomaji(word.reading),
      choices: choices,
      answerIndex: choices.indexOf(word.meaning),
      fromSaved: word.fromSaved,
    );
  }

  /// FNV-1a: stable across runs and platforms, unlike `String.hashCode`.
  static int _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

/// `2026-11-25`: the key a quiz is stored and submitted under.
String quizDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

class _Word {
  final String surface;
  final String reading;
  final String meaning;
  final String kind;
  final bool fromSaved;

  const _Word(
    this.surface,
    this.reading,
    this.meaning,
    this.kind, {
    this.fromSaved = false,
  });

  bool get hasKanji => _kanji.hasMatch(surface);

  static final _kanji = RegExp(r'[㐀-鿿]');
  static final _japanese = RegExp(r'^[぀-ヿ㐀-鿿ー々]+$');
  static const _kinds = {
    'noun',
    'na-adjective',
    'i-adjective',
    'adverb',
    'verb',
    'numeral',
  };

  static _Word? fromEntry(DictionaryEntry entry) {
    if (!_kinds.contains(entry.pos)) return null;
    final meaning = _meaning(entry.primaryMeaning);
    if (meaning == null) return null;
    if (!_japanese.hasMatch(entry.surface) || entry.surface.length > 6) {
      return null;
    }
    return _Word(entry.surface, entry.reading, meaning, entry.pos!);
  }

  static _Word? ofSaved(VocabularyItem item, String? dictionaryReading) {
    final surface = item.word.trim();
    final meaning = _meaning(item.meaning?.split(';').first ?? '');
    final reading = item.reading ?? dictionaryReading;
    if (meaning == null || surface.isEmpty || !_japanese.hasMatch(surface)) {
      return null;
    }
    // Without a reading a kanji word could not be given furigana or romaji.
    if (reading == null && _kanji.hasMatch(surface)) return null;
    return _Word(
      surface,
      reading ?? surface,
      meaning,
      item.pos ?? 'noun',
      fromSaved: true,
    );
  }

  /// A short, clean meaning, or null for one too long to be a choice.
  static String? _meaning(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.length > 40) return null;
    return text;
  }
}
