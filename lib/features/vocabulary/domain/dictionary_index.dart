import 'package:ingrain/features/vocabulary/domain/deinflector.dart';

/// One dictionary headword, parsed from the bundled JMdict subset.
class DictionaryEntry {
  final String surface;
  final String reading;
  final String? pos;
  final List<String> meanings;

  /// [Conjugation] flags; 0 when the word does not conjugate or the asset
  /// predates the field.
  final int conjugation;

  /// Other spellings that open this entry (可愛い for かわいい).
  final List<String> forms;

  /// Readings besides [reading].
  final List<String> readings;

  const DictionaryEntry({
    required this.surface,
    required this.reading,
    required this.meanings,
    this.pos,
    this.conjugation = 0,
    this.forms = const [],
    this.readings = const [],
  });

  /// `cat (animal)` style single-line summary for review cards and lists.
  String get primaryMeaning => meanings.isEmpty ? '' : meanings.first;

  String get meaningLine => meanings.join('; ');

  /// `猫 (ねこ)` when the reading adds information.
  String get headword =>
      reading.isEmpty || reading == surface ? surface : '$surface ($reading)';

  int get _conjugationOrGuess =>
      conjugation != 0 ? conjugation : Conjugation.fromPos(pos);
}

/// A dictionary hit for a word as it appears in text.
class DictionaryMatch {
  final DictionaryEntry entry;

  /// The text that was looked up, which may be inflected (食べた).
  final String word;

  /// The spelling of [entry] that matched, in dictionary form: 分かる for
  /// 分からない, though the entry's surface is わかる.
  final String base;

  /// True when [word] was traced back to [entry] through its conjugation.
  final bool inflected;

  const DictionaryMatch(
    this.entry,
    this.word, {
    required this.base,
    this.inflected = false,
  });

  /// How [word] itself is read, for furigana: たべた for 食べた. Null when
  /// it cannot be worked out.
  String? get reading {
    if (!inflected) return entry.reading;
    // 来る's stem changes its reading (こない, きます), which no ending swap
    // can recover.
    if (entry.conjugation & Conjugation.kuru != 0) return null;
    // The stem is spelled the same in both, so swap the endings over in the
    // entry's reading: 食べる/たべる with 食べた gives たべた.
    var shared = 0;
    while (shared < base.length &&
        shared < word.length &&
        base.codeUnitAt(shared) == word.codeUnitAt(shared)) {
      shared++;
    }
    final baseTail = base.substring(shared);
    if (shared == 0 || !entry.reading.endsWith(baseTail)) return null;
    return entry.reading.substring(0, entry.reading.length - baseTail.length) +
        word.substring(shared);
  }
}

/// In-memory lookup over the bundled dictionary.
///
/// Words are indexed by every spelling and by their readings, so a tap on
/// ねこ or ネコ finds 猫. Inflected words are traced back to their dictionary
/// form with [Deinflector]: 食べなかった finds 食べる.
///
/// Construction takes the decoded JSON map rather than the asset bundle,
/// which keeps it unit-testable without a Flutter binding.
class DictionaryIndex {
  DictionaryIndex(List<DictionaryEntry> entries) : _entries = entries {
    // Alternative spellings first: the build script keeps one only on the
    // entry it should open, even over another entry's main spelling (事 opens
    // こと, not the rare じ).
    for (final entry in entries) {
      for (final form in entry.forms) {
        _bySurface.putIfAbsent(form, () => entry);
      }
    }
    for (final entry in entries) {
      if (entry.surface.isEmpty) continue;
      _bySurface.putIfAbsent(entry.surface, () => entry);
    }
    for (final entry in entries) {
      if (entry.reading.isEmpty) continue;
      _byReading.putIfAbsent(toHiragana(entry.reading), () => entry);
    }
    for (final entry in entries) {
      for (final reading in entry.readings) {
        _byReading.putIfAbsent(toHiragana(reading), () => entry);
      }
    }
    // Conjugating words keep every entry per spelling, so an inflected form
    // can find the one that conjugates that way: かえった is 帰る, not 蛙.
    for (final entry in entries) {
      if (entry._conjugationOrGuess == 0) continue;
      for (final key in {
        entry.surface,
        ...entry.forms,
        toHiragana(entry.reading),
        for (final reading in entry.readings) toHiragana(reading),
      }) {
        if (key.isNotEmpty) (_conjugating[key] ??= []).add(entry);
      }
    }
    for (final key in _bySurface.keys.followedBy(_byReading.keys)) {
      if (key.length > _maxWordLength) _maxWordLength = key.length;
    }
  }

  final List<DictionaryEntry> _entries;
  final Map<String, DictionaryEntry> _bySurface = {};
  final Map<String, DictionaryEntry> _byReading = {};
  final Map<String, List<DictionaryEntry>> _conjugating = {};
  int _maxWordLength = 0;

  /// Tokenizer answers, which repeat across a transcript's lines.
  final Map<String, bool> _isWordCache = {};
  static const _isWordCacheLimit = 20000;

  /// Builds an index from `assets/data/dictionary.json`.
  ///
  /// Reads the compact array rows the build script writes (format 2) as well
  /// as the older object rows, including their singular `meaning` string.
  factory DictionaryIndex.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) return DictionaryIndex(const []);

    final entries = <DictionaryEntry>[];
    for (final raw in rawEntries) {
      final entry = switch (raw) {
        List() => _fromRow(raw),
        Map() => _fromObject(raw),
        _ => null,
      };
      if (entry != null) entries.add(entry);
    }
    return DictionaryIndex(entries);
  }

  /// `[surface, reading, meanings, pos, conjugation, forms, readings]`, with
  /// trailing empty fields left out.
  static DictionaryEntry? _fromRow(List row) {
    if (row.length < 3) return null;
    final surface = row[0];
    final reading = row[1];
    final meanings = row[2];
    if (surface is! String || surface.isEmpty || meanings is! List) {
      return null;
    }
    final pos = row.length > 3 ? row[3] : null;
    final conjugation = row.length > 4 ? row[4] : null;
    return DictionaryEntry(
      surface: surface,
      reading: reading is String && reading.isNotEmpty ? reading : surface,
      meanings: meanings.whereType<String>().toList(growable: false),
      pos: pos is String && pos.isNotEmpty ? pos : null,
      conjugation: conjugation is int ? conjugation : 0,
      forms: row.length > 5 ? _strings(row[5]) : const [],
      readings: row.length > 6 ? _strings(row[6]) : const [],
    );
  }

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  static DictionaryEntry? _fromObject(Map raw) {
    final surface = (raw['surface'] as String?)?.trim();
    if (surface == null || surface.isEmpty) return null;

    final readings = raw['reading'];
    final reading = readings is String ? readings.trim() : '';

    final meanings = <String>[];
    final rawMeanings = raw['meanings'];
    if (rawMeanings is List) {
      for (final meaning in rawMeanings) {
        if (meaning is String && meaning.trim().isNotEmpty) {
          meanings.add(meaning.trim());
        }
      }
    }
    final singleMeaning = raw['meaning'];
    if (meanings.isEmpty &&
        singleMeaning is String &&
        singleMeaning.trim().isNotEmpty) {
      meanings.add(singleMeaning.trim());
    }
    if (meanings.isEmpty) return null;

    final pos = raw['pos'];
    return DictionaryEntry(
      surface: surface,
      reading: reading.isEmpty ? surface : reading,
      meanings: meanings,
      pos: pos is String && pos.trim().isNotEmpty ? pos.trim() : null,
    );
  }

  static final empty = DictionaryIndex(<DictionaryEntry>[]);

  int get length => _bySurface.length;

  /// The longest spelling or reading in the dictionary.
  int get maxWordLength => _maxWordLength;

  /// Looks up a written form, then a reading, then the dictionary form of an
  /// inflected word.
  DictionaryEntry? lookup(String word) => match(word)?.entry;

  DictionaryMatch? match(String word) {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return null;
    final exact = _exact(trimmed);
    if (exact != null) return DictionaryMatch(exact, trimmed, base: trimmed);
    return _deinflected(trimmed);
  }

  bool contains(String word) => match(word) != null;

  /// Entries for a search box, best first: the word itself (inflected forms
  /// included), then spellings and readings that start with [query], then,
  /// for Latin text, entries with a meaning containing it as a word.
  List<DictionaryEntry> search(String query, {int limit = 30}) {
    final text = query.trim();
    if (text.isEmpty || limit <= 0) return const [];
    final results = <DictionaryEntry>[];
    final seen = <DictionaryEntry>{};
    bool add(DictionaryEntry entry) {
      if (seen.add(entry)) results.add(entry);
      return results.length >= limit;
    }

    final exact = match(text);
    if (exact != null && add(exact.entry)) return results;

    if (_isLatin(text)) {
      final needle = text.toLowerCase();
      final word = RegExp('\\b${RegExp.escape(needle)}');
      // Whole-meaning matches ("cat") before looser ones ("cathedral").
      for (final strict in [true, false]) {
        for (final entry in _entries) {
          if (seen.contains(entry)) continue;
          final hit = entry.meanings.any((meaning) {
            final lower = meaning.toLowerCase();
            return strict
                ? lower == needle || lower == 'to $needle'
                : word.hasMatch(lower);
          });
          if (hit && add(entry)) return results;
        }
      }
      return results;
    }

    final folded = toHiragana(text);
    for (final entry in _entries) {
      if (seen.contains(entry)) continue;
      final hit =
          entry.surface.startsWith(text) ||
          toHiragana(entry.reading).startsWith(folded) ||
          entry.forms.any((form) => form.startsWith(text));
      if (hit && add(entry)) return results;
    }
    return results;
  }

  static bool _isLatin(String text) =>
      RegExp(r'^[A-Za-z][A-Za-z \-\x27]*$').hasMatch(text);

  /// Whether [text] is a word as written, inflected or not. Built for the
  /// tokenizer, which asks about many substrings of every line.
  bool isWord(String text) {
    if (_exact(text) != null) return true;
    if (!Deinflector.instance.mayInflect(text)) return false;
    final cached = _isWordCache[text];
    if (cached != null) return cached;
    if (_isWordCache.length >= _isWordCacheLimit) _isWordCache.clear();
    return _isWordCache[text] = _deinflected(text) != null;
  }

  DictionaryEntry? _exact(String text) {
    final hit = _bySurface[text] ?? _byReading[text];
    if (hit != null || !_isAllKatakana(text)) return hit;
    return _byReading[toHiragana(text)];
  }

  /// Only all-katakana text is folded to hiragana: ネコ is ねこ, but は + コ
  /// across a word boundary must not become はこ.
  static bool _isAllKatakana(String text) {
    if (text.isEmpty) return false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code < 0x30A1 || code > 0x30FC) return false;
    }
    return true;
  }

  DictionaryMatch? _deinflected(String text) {
    for (final candidate in Deinflector.instance.deinflect(text)) {
      final term = candidate.term;
      final entries =
          _conjugating[term] ??
          (_isAllKatakana(term) ? _conjugating[toHiragana(term)] : null);
      if (entries != null) {
        for (final entry in entries) {
          if (entry._conjugationOrGuess & candidate.types != 0) {
            return DictionaryMatch(entry, text, base: term, inflected: true);
          }
        }
      }
      // 勉強した: a noun that takes する.
      if (candidate.types & Conjugation.suru != 0 &&
          term.length > 2 &&
          term.endsWith('する')) {
        final stem = term.substring(0, term.length - 2);
        final noun = _exact(stem);
        if (noun != null && noun.conjugation & Conjugation.suruNoun != 0) {
          // The reading swap then runs over 勉強 + the inflected する.
          return DictionaryMatch(
            DictionaryEntry(
              surface: '$stemする',
              reading: '${noun.reading}する',
              meanings: noun.meanings,
              pos: noun.pos,
              conjugation: Conjugation.suru,
            ),
            text,
            base: term,
            inflected: true,
          );
        }
      }
    }
    return null;
  }

  static bool _hasKatakana(String text) {
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if ((code >= 0x30A1 && code <= 0x30F6) ||
          (code >= 0xFF66 && code <= 0xFF9D)) {
        return true;
      }
    }
    return false;
  }

  /// Folds full-width katakana to hiragana; everything else is unchanged.
  /// Readings are indexed folded, so ネコ finds ねこ.
  static String toHiragana(String text) {
    if (!_hasKatakana(text)) return text;
    final codes = text.codeUnits.toList();
    for (var i = 0; i < codes.length; i++) {
      final code = codes[i];
      if (code >= 0x30A1 && code <= 0x30F6) codes[i] = code - 0x60;
    }
    return String.fromCharCodes(codes);
  }
}
