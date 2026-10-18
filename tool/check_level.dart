// Checks a book's source text against the JLPT word and kanji lists.
//
//   dart run tool/check_level.dart tool/books/ichiya_n4.txt vocab.csv kanji.csv
//
// The lists are Jonathan Waller's (CC BY, tanos.co.uk) as published in
// github.com/Bluskyo/JLPT_Vocabulary. They are for checking only and are not
// part of the app. Levels run 5 (N5, easiest) to 1 (N1).
import 'dart:convert';
import 'dart:io';

import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/japanese_tokenizer.dart';

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('usage: check_level <book.txt> <vocab.csv> <kanji.csv>');
    exit(64);
  }
  final vocab = <String, int>{}; // word or reading -> easiest level
  for (final row in File(args[1]).readAsLinesSync().skip(1)) {
    final cells = row.split(',');
    if (cells.length < 3) continue;
    final level = int.tryParse(cells.last);
    if (level == null) continue;
    for (final key in [cells[0], cells[1]]) {
      final known = vocab[key];
      if (known == null || level > known) vocab[key] = level;
    }
  }
  final kanji = <String, int>{
    for (final row in File(args[2]).readAsLinesSync().skip(1))
      if (row.split(',').length >= 2 && int.tryParse(row.split(',')[1]) != null)
        row.split(',')[0]: int.parse(row.split(',')[1]),
  };

  final dictionary = DictionaryIndex.fromJson(
    jsonDecode(File('assets/data/dictionary.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final tokenizer = JapaneseTokenizer.dictionary(dictionary);

  var tokens = 0;
  var easy = 0;
  final hardWords = <String, String>{};
  final hardKanji = <String, int?>{};
  for (var line in File(args[0]).readAsLinesSync()) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    line = line.split('|').first;
    line = line.replaceAllMapped(RegExp(r'\[[^\]]*\]'), (_) => '');
    for (final token in tokenizer.tokenize(line)) {
      // Kana-only runs are mostly particles and endings, which the dictionary
      // tokenizer lumps together; only words with kanji are checked.
      if (!token.runes.any(_isKanji)) continue;
      final match = dictionary.match(token);
      final base = match?.base ?? token;
      final level =
          vocab[base] ??
          vocab[match?.entry.surface ?? ''] ??
          vocab[match?.entry.reading ?? ''];
      tokens++;
      if (level != null && level >= 4) {
        easy++;
      } else {
        hardWords[base] = level == null ? 'not in list' : 'N$level';
      }
      for (final c in token.runes.where(_isKanji).map(String.fromCharCode)) {
        final k = kanji[c];
        if (k == null || k < 4) hardKanji[c] = k;
      }
    }
  }
  stdout.writeln(
    'Words at N5/N4: $easy of $tokens '
    '(${(100 * easy / tokens).toStringAsFixed(1)}%)\n',
  );
  stdout.writeln('Words above N4 or not in the list:');
  hardWords.forEach((w, l) => stdout.writeln('  $w\t$l'));
  stdout.writeln('\nKanji above N4 or not in the list:');
  hardKanji.forEach(
    (k, l) => stdout.writeln('  $k\t${l == null ? "not in list" : "N$l"}'),
  );
}

bool _isKanji(int c) => c >= 0x4E00 && c <= 0x9FFF || c == 0x3005;
