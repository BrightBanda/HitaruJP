// Builds a book from its source text and writes it where the app and the
// server read it.
//
//   dart run tool/build_book.dart tool/books/ichiya_n4.txt
//
// The source is a header of `# key: value` lines, then one story line per
// line in the dialogue format (`日本語 | romaji | English`). Readings for
// kanji come from the bundled dictionary unless written as `漢字[かな]`. The
// tool prints every kanji word with its reading, so they can be checked.
import 'dart:convert';
import 'dart:io';

import 'package:ingrain/features/dialogue/data/dialogue_dto.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/domain/dialogue_text_parser.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/build_book.dart <book.txt>');
    exit(64);
  }
  final header = <String, String>{};
  final body = StringBuffer();
  for (final line in File(args.first).readAsLinesSync()) {
    final meta = RegExp(r'^#\s*(\w+):\s*(.*)$').firstMatch(line);
    if (meta != null) {
      header[meta.group(1)!] = meta.group(2)!.trim();
    } else if (line.trim().isNotEmpty) {
      body.writeln(line);
    }
  }
  for (final key in ['id', 'title', 'level', 'author', 'out']) {
    if (!header.containsKey(key)) {
      stderr.writeln('missing header "# $key:"');
      exit(65);
    }
  }

  final dictionary = DictionaryIndex.fromJson(
    jsonDecode(File('assets/data/dictionary.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final parsed = const DialogueTextParser().parse(
    id: header['id']!,
    title: header['title']!,
    text: body.toString(),
    dictionary: dictionary,
  );
  final book = Dialogue(
    id: parsed.id,
    title: parsed.title,
    level: header['level']!,
    kind: DialogueKind.book,
    source: DialogueSource(
      attribution: header['attribution'],
      url: header['sourceUrl'],
    ),
    updatedAt: DateTime.now().toUtc(),
    book: BookInfo(
      author: header['author']!,
      originalTitle: header['originalTitle'],
      originalYear: int.tryParse(header['originalYear'] ?? ''),
      summary: header['description'],
    ),
    lines: parsed.lines,
  );

  final map = dialogueToMap(book);
  File(
    header['out']!,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(map)}\n');
  _upsertSample(map);

  // For review: every kanji word and the reading it will show.
  final seen = <String>{};
  for (final line in book.lines) {
    for (final token in line.tokens) {
      final hasKanji = token.surface.runes.any(
        (c) => c >= 0x4E00 && c <= 0x9FFF,
      );
      if (hasKanji && seen.add(token.surface)) {
        stdout.writeln('${token.surface}\t${token.reading ?? "!! no reading"}');
      }
    }
  }
  stdout.writeln('\n${book.lines.length} lines -> ${header['out']}');
}

/// Keeps the bundled offline copy in step with the server file.
void _upsertSample(Map<String, dynamic> map) {
  final file = File('assets/data/sample_dialogues.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final list = (json['dialogues'] as List).cast<Map<String, dynamic>>();
  list.removeWhere((d) => d['id'] == map['id']);
  list.add(map);
  json['dialogues'] = list;
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
}
