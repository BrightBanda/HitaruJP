import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/vocabulary/data/asset_dictionary_loader.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/japanese_tokenizer.dart';

const _dictionaryJson = '''
{
  "meta": {"entryCount": 2},
  "entries": [
    {
      "surface": "猫",
      "reading": "ねこ",
      "pos": "noun",
      "meanings": ["cat (animal)", "feline"]
    },
    {"surface": "日本語", "reading": "にほんご", "meanings": ["Japanese"]}
  ]
}
''';

void main() {
  group('DictionaryIndex', () {
    test('looks a word up by its written form', () {
      final index = DictionaryIndex.fromJson(jsonDecode(_dictionaryJson));

      final entry = index.lookup('猫');

      expect(entry, isNotNull);
      expect(entry!.reading, 'ねこ');
      expect(entry.pos, 'noun');
      expect(entry.meanings, ['cat (animal)', 'feline']);
      expect(entry.primaryMeaning, 'cat (animal)');
      expect(entry.meaningLine, 'cat (animal); feline');
      expect(entry.headword, '猫 (ねこ)');
    });

    test('looks a word up by its reading', () {
      final index = DictionaryIndex.fromJson(jsonDecode(_dictionaryJson));

      expect(index.lookup('にほんご')?.surface, '日本語');
    });

    test('returns null for unknown, empty and blank queries', () {
      final index = DictionaryIndex.fromJson(jsonDecode(_dictionaryJson));

      expect(index.lookup('犬'), isNull);
      expect(index.lookup(''), isNull);
      expect(index.lookup('   '), isNull);
      expect(index.contains('犬'), isFalse);
    });

    test('accepts the singular meaning string of an older asset', () {
      final index = DictionaryIndex.fromJson({
        'entries': [
          {
            'surface': '猫',
            'reading': 'ねこ',
            'pos': 'noun',
            'meaning': 'cat (animal)',
          },
        ],
      });

      expect(index.lookup('猫')?.meanings, ['cat (animal)']);
    });

    test('skips entries without a usable meaning', () {
      final index = DictionaryIndex.fromJson({
        'entries': [
          {'surface': '空', 'reading': 'そら'},
          {
            'surface': '猫',
            'reading': 'ねこ',
            'meanings': ['cat'],
          },
          'not-an-entry',
        ],
      });

      expect(index.length, 1);
      expect(index.lookup('空'), isNull);
    });

    test('falls back to the surface when the reading is missing', () {
      final index = DictionaryIndex.fromJson({
        'entries': [
          {
            'surface': '空',
            'meanings': ['sky'],
          },
        ],
      });

      final entry = index.lookup('空');

      expect(entry?.reading, '空');
      expect(entry?.headword, '空');
    });

    test('survives a payload without an entries list', () {
      expect(DictionaryIndex.fromJson(const {}).length, 0);
      expect(DictionaryIndex.fromJson(const {'entries': 'nope'}).length, 0);
    });
  });

  group('AssetDictionaryLoader', () {
    test('builds an index from the injected bundle', () async {
      final loader = AssetDictionaryLoader(
        assetBundle: _StubBundle(_dictionaryJson),
      );

      final index = await loader.load();

      expect(index.length, 2);
      expect(index.lookup('猫')?.reading, 'ねこ');
    });

    test('returns an empty index when the asset has no entries list', () async {
      final loader = AssetDictionaryLoader(assetBundle: _StubBundle('{}'));

      expect((await loader.load()).length, 0);
    });
  });

  group('DictionaryIndex compact format and inflections', () {
    DictionaryIndex index() => DictionaryIndex.fromJson({
      'format': 2,
      'entries': [
        [
          '食べる',
          'たべる',
          ['to eat'],
          'verb',
          1,
        ],
        [
          'わかる',
          'わかる',
          ['to understand'],
          'verb',
          2,
          ['分かる'],
        ],
        [
          '蛙',
          'かえる',
          ['frog'],
          'noun',
        ],
        [
          '帰る',
          'かえる',
          ['to return'],
          'verb',
          2,
        ],
        [
          '勉強',
          'べんきょう',
          ['study'],
          'noun',
          512,
        ],
        [
          '猫',
          'ねこ',
          ['cat'],
          'noun',
        ],
        [
          '高い',
          'たかい',
          ['high'],
          'i-adjective',
          16,
        ],
      ],
    });

    test('reads rows with alternative spellings', () {
      expect(index().lookup('分かる')?.surface, 'わかる');
      expect(index().lookup('ねこ')?.surface, '猫');
    });

    test('finds katakana words through their hiragana reading', () {
      expect(index().lookup('ネコ')?.surface, '猫');
    });

    test('traces inflected words to the entry that conjugates that way', () {
      final match = index().match('食べなかった')!;
      expect(match.entry.surface, '食べる');
      expect(match.inflected, isTrue);
      expect(match.reading, 'たべなかった');

      // かえった is 帰る; 蛙 the frog does not conjugate.
      expect(index().lookup('かえった')?.surface, '帰る');
      expect(index().match('分からない')?.reading, 'わからない');
      expect(index().match('高くて')?.entry.surface, '高い');
    });

    test('recognises suru nouns with an inflected する', () {
      final match = index().match('勉強しました')!;
      expect(match.entry.surface, '勉強する');
      expect(match.entry.primaryMeaning, 'study');
      expect(match.reading, 'べんきょうしました');
    });

    test('isWord drives the tokenizer, inflections included', () {
      final tokenizer = JapaneseTokenizer.dictionary(index());
      expect(tokenizer.tokenize('猫は食べなかった'), ['猫', 'は', '食べなかった']);
      expect(index().isWord('ネコ'), isTrue);
      // Mixed scripts are not folded: は + コ is not はこ.
      expect(index().isWord('はコ'), isFalse);
    });
  });
}

class _StubBundle extends CachingAssetBundle {
  _StubBundle(this.contents);

  final String contents;

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(contents);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
