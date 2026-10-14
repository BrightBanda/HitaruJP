import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/vocabulary/domain/deinflector.dart';

void main() {
  final deinflector = Deinflector.instance;

  /// True when [word] can come from [term] conjugated as one of [types].
  bool yields(String word, String term, int types) => deinflector
      .deinflect(word)
      .any((d) => d.term == term && d.types & types != 0);

  group('Deinflector', () {
    test('undoes single inflections', () {
      expect(yields('食べた', '食べる', Conjugation.ichidan), isTrue);
      expect(yields('読んだ', '読む', Conjugation.godan), isTrue);
      expect(yields('書いて', '書く', Conjugation.godan), isTrue);
      expect(yields('話そう', '話す', Conjugation.godan), isTrue);
      expect(yields('帰れば', '帰る', Conjugation.godan), isTrue);
      expect(yields('高くない', '高い', Conjugation.iAdjective), isTrue);
      expect(yields('来ない', '来る', Conjugation.kuru), isTrue);
      expect(yields('しない', 'する', Conjugation.suru), isTrue);
    });

    test('chains inflections back to the dictionary form', () {
      expect(yields('食べなかった', '食べる', Conjugation.ichidan), isTrue);
      expect(yields('食べていました', '食べる', Conjugation.ichidan), isTrue);
      expect(yields('行きたくない', '行く', Conjugation.godan), isTrue);
      expect(yields('食べさせられた', '食べる', Conjugation.ichidan), isTrue);
      expect(yields('言っちゃった', '言う', Conjugation.godan), isTrue);
      expect(yields('わかんない', 'わかる', Conjugation.godan), isTrue);
    });

    test('prefers the specific rule for 行く', () {
      final first = deinflector
          .deinflect('行った')
          .firstWhere((d) => d.types & Conjugation.godan != 0);
      expect(first.term, '行く');
    });

    test('does not invent a stem from a bare word', () {
      // 食べ + る comes only after an ending such as ます is removed.
      expect(yields('見', '見る', Conjugation.ichidan), isFalse);
      expect(yields('食べます', '食べる', Conjugation.ichidan), isTrue);
    });

    test('skips words no rule can end', () {
      expect(deinflector.mayInflect('猫'), isFalse);
      expect(deinflector.deinflect('猫'), isEmpty);
      expect(deinflector.deinflect(''), isEmpty);
    });
  });
}
