import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/transcript_word_extractor.dart';

TranscriptSentence _line(int index, String text) => TranscriptSentence(
  index: index,
  text: text,
  startSeconds: index * 5,
  endSeconds: index * 5 + 4,
);

void main() {
  final dictionary = DictionaryIndex([
    const DictionaryEntry(surface: '猫', reading: 'ねこ', meanings: ['cat']),
    const DictionaryEntry(surface: '犬', reading: 'いぬ', meanings: ['dog']),
    const DictionaryEntry(
      surface: '食べる',
      reading: 'たべる',
      meanings: ['to eat'],
      pos: 'verb',
    ),
    const DictionaryEntry(surface: 'は', reading: 'は', meanings: ['topic']),
  ]);
  final extractor = TranscriptWordExtractor(dictionary);

  group('DictionaryIndex.search', () {
    test('finds by written form, reading prefix and English meaning', () {
      expect(dictionary.search('猫').first.surface, '猫');
      expect(dictionary.search('ねこ').first.surface, '猫');
      expect(dictionary.search('ね').map((e) => e.surface), contains('猫'));
      expect(dictionary.search('dog').single.surface, '犬');
      expect(dictionary.search('eat').first.surface, '食べる');
    });

    test('finds an inflected word and ignores empty input', () {
      expect(dictionary.search('食べた').first.surface, '食べる');
      expect(dictionary.search('  '), isEmpty);
    });
  });

  group('TranscriptWordExtractor', () {
    test('folds inflections onto one row and counts them', () {
      final words = extractor.extract([
        _line(0, '猫は食べる'),
        _line(1, '猫が食べた'),
        _line(2, '犬'),
      ]);

      expect(words.map((w) => w.word), ['猫', '食べる', '犬']);
      expect(words[0].count, 2);
      expect(words[1].count, 2);
      expect(words[1].firstSentence.index, 0);
    });

    test('skips short kana-only words unless asked', () {
      final lines = [_line(0, '猫は犬')];
      expect(extractor.extract(lines).map((w) => w.word), ['猫', '犬']);
      expect(
        extractor.extract(lines, includeKanaOnly: true).map((w) => w.word),
        ['猫', 'は', '犬'],
      );
    });
  });
}
