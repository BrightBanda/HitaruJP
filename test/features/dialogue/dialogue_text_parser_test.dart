import 'package:ingrain/features/dialogue/domain/ruby_segments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/domain/dialogue_text_parser.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';

void main() {
  _formatTests();
  _rubyTests();
  final dictionary = DictionaryIndex(const [
    DictionaryEntry(surface: '猫', reading: 'ねこ', meanings: ['cat']),
    DictionaryEntry(surface: 'です', reading: 'です', meanings: ['to be']),
  ]);
  const parser = DialogueTextParser();

  Dialogue parse(String text) => parser.parse(
    id: 'my-1',
    title: ' Pets ',
    text: text,
    dictionary: dictionary,
  );

  test('splits speakers on ASCII and full-width colons', () {
    final dialogue = parse('Aiko: 猫です。\n\n健：はい');

    expect(dialogue.title, 'Pets');
    expect(dialogue.kind, DialogueKind.dialogue);
    expect(dialogue.speakers, ['Aiko', '健']);
    expect(dialogue.lines.map((l) => l.speaker), ['Aiko', '健']);
    expect(dialogue.lines.map((l) => l.text), ['猫です。', 'はい']);
    expect(dialogue.lines.map((l) => l.index), [0, 1]);
  });

  test('text without speakers becomes a story', () {
    final dialogue = parse('猫です。\n猫です。');

    expect(dialogue.kind, DialogueKind.story);
    expect(dialogue.speakers, isEmpty);
    expect(dialogue.lines.every((l) => l.speaker == null), isTrue);
  });

  test('tokens carry dictionary readings only when they add something', () {
    final tokens = parse('猫です').lines.single.tokens;

    expect(tokens.map((t) => t.surface), ['猫', 'です']);
    expect(tokens.first.reading, 'ねこ');
    expect(tokens.last.reading, isNull);
  });

  test('a long prefix before a colon is not a speaker', () {
    final line = parse('This sentence is far too long to be a name: 猫')
        .lines
        .single;

    expect(line.speaker, isNull);
  });
}

void _formatTests() {
  final dictionary = DictionaryIndex(const [
    DictionaryEntry(surface: '猫', reading: 'ねこ', meanings: ['cat']),
    DictionaryEntry(surface: '日本語', reading: 'にほんご', meanings: ['Japanese']),
  ]);
  const parser = DialogueTextParser();
  Dialogue parse(String text) =>
      parser.parse(id: 'my-1', title: 'T', text: text, dictionary: dictionary);

  group('line format', () {
    test('splits romaji and translation on |', () {
      final line = parse('Aiko: 猫です | neko desu | It is a cat.').lines.single;
      expect(line.text, '猫です');
      expect(line.romaji, 'neko desu');
      expect(line.translation, 'It is a cat.');
    });

    test('one extra part is the translation, || skips the romaji', () {
      expect(parse('猫 | A cat').lines.single.translation, 'A cat');
      expect(parse('猫 | A cat').lines.single.romaji, isNull);
      final skipped = parse('猫 || A cat').lines.single;
      expect(skipped.romaji, isNull);
      expect(skipped.translation, 'A cat');
    });

    test('written readings go over their kanji and stay one token', () {
      final tokens = parse('私[わたし]は日本語[にほんご]').lines.single.tokens;
      expect(tokens.map((t) => t.surface).join(), '私は日本語');
      expect(tokens.first.surface, '私');
      expect(tokens.first.reading, 'わたし');
      final word = tokens.last;
      expect(word.surface, '日本語');
      expect(word.reading, 'にほんご');
    });
  });
}

void _rubyTests() {
  group('rubySegments', () {
    test('puts kana over kanji only', () {
      expect(rubySegments('食べる', 'たべる'), [
        (text: '食', ruby: 'た'),
        (text: 'べる', ruby: null),
      ]);
      expect(rubySegments('雨ですね', 'あめですね'), [
        (text: '雨', ruby: 'あめ'),
        (text: 'ですね', ruby: null),
      ]);
      expect(rubySegments('日本語', 'にほんご'), [(text: '日本語', ruby: 'にほんご')]);
    });

    test('splits several kanji runs and falls back when misaligned', () {
      expect(rubySegments('お弁当', 'おべんとう'), [
        (text: 'お', ruby: null),
        (text: '弁当', ruby: 'べんとう'),
      ]);
      expect(rubySegments('猫', 'ねこ'), [(text: '猫', ruby: 'ねこ')]);
      expect(rubySegments('ねこ', 'ねこ'), [(text: 'ねこ', ruby: null)]);
      expect(rubySegments('食べる', 'のむ'), [(text: '食べる', ruby: 'のむ')]);
    });
  });
}
