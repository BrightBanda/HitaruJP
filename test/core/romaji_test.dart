import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/text/romaji.dart';

void main() {
  test('plain hiragana and katakana', () {
    expect(toRomaji('ねこ'), 'neko');
    expect(toRomaji('あたたかい'), 'atatakai');
    expect(toRomaji('カメラ'), 'kamera');
  });

  test('combinations and shi/chi/tsu/fu', () {
    expect(toRomaji('しゃしん'), 'shashin');
    expect(toRomaji('ちょっと'), 'chotto');
    expect(toRomaji('つくえ'), 'tsukue');
    expect(toRomaji('ふじさん'), 'fujisan');
    expect(toRomaji('りょこう'), 'ryokou');
  });

  test('the small tsu doubles the next consonant', () {
    expect(toRomaji('きって'), 'kitte');
    expect(toRomaji('まっちゃ'), 'matcha');
    expect(toRomaji('がっこう'), 'gakkou');
  });

  test('long vowels and loanwords', () {
    expect(toRomaji('コーヒー'), 'koohii');
    expect(toRomaji('ラーメン'), 'raamen');
    expect(toRomaji('パーティー'), 'paatii');
    expect(toRomaji('ファイル'), 'fairu');
  });

  test('n before a vowel is marked', () {
    expect(toRomaji('きんえん'), "kin'en");
    expect(toRomaji('こんにちは'), 'konnichiha');
  });
}
