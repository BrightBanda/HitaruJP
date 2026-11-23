/// Kana to Hepburn romaji, for showing how a word is read.
///
/// Handles hiragana and katakana, the small-ya/yu/yo combinations, the small
/// tsu that doubles the next consonant, the long-vowel mark and the extended
/// katakana used for loanwords. Anything else (kanji, Latin letters) is kept
/// as it is.
String toRomaji(String kana) {
  final text = _toHiragana(kana);
  final out = StringBuffer();
  var doubleNext = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == 'っ') {
      doubleNext = true;
      continue;
    }
    if (char == 'ー') {
      // Repeat the vowel just written: ラーメン → raamen.
      final written = out.toString();
      final vowel = written.isEmpty ? '' : written[written.length - 1];
      if ('aeiou'.contains(vowel) && vowel.isNotEmpty) out.write(vowel);
      continue;
    }
    String? syllable;
    if (i + 1 < text.length) {
      syllable = _digraphs[text.substring(i, i + 2)];
      if (syllable != null) i++;
    }
    syllable ??= _monographs[char] ?? char;
    if (doubleNext) {
      doubleNext = false;
      final first = syllable.isEmpty ? '' : syllable[0];
      if (syllable.startsWith('ch')) {
        out.write('t');
      } else if (first.isNotEmpty && !'aeiou'.contains(first)) {
        out.write(first);
      }
    }
    // ん before a vowel or y is written n' so it is not misread: kin'en.
    if (char == 'ん' &&
        i + 1 < text.length &&
        'あいうえおやゆよ'.contains(text[i + 1])) {
      syllable = "n'";
    }
    out.write(syllable);
  }
  return out.toString();
}

/// Katakana folded to hiragana; the long-vowel mark is kept.
String _toHiragana(String text) {
  final codes = text.runes.map((rune) {
    // ァ (U+30A1) .. ヶ (U+30F6) sit 0x60 above their hiragana.
    if (rune >= 0x30A1 && rune <= 0x30F6) return rune - 0x60;
    return rune;
  });
  return String.fromCharCodes(codes);
}

const _monographs = {
  'あ': 'a',
  'い': 'i',
  'う': 'u',
  'え': 'e',
  'お': 'o',
  'か': 'ka',
  'き': 'ki',
  'く': 'ku',
  'け': 'ke',
  'こ': 'ko',
  'が': 'ga',
  'ぎ': 'gi',
  'ぐ': 'gu',
  'げ': 'ge',
  'ご': 'go',
  'さ': 'sa',
  'し': 'shi',
  'す': 'su',
  'せ': 'se',
  'そ': 'so',
  'ざ': 'za',
  'じ': 'ji',
  'ず': 'zu',
  'ぜ': 'ze',
  'ぞ': 'zo',
  'た': 'ta',
  'ち': 'chi',
  'つ': 'tsu',
  'て': 'te',
  'と': 'to',
  'だ': 'da',
  'ぢ': 'ji',
  'づ': 'zu',
  'で': 'de',
  'ど': 'do',
  'な': 'na',
  'に': 'ni',
  'ぬ': 'nu',
  'ね': 'ne',
  'の': 'no',
  'は': 'ha',
  'ひ': 'hi',
  'ふ': 'fu',
  'へ': 'he',
  'ほ': 'ho',
  'ば': 'ba',
  'び': 'bi',
  'ぶ': 'bu',
  'べ': 'be',
  'ぼ': 'bo',
  'ぱ': 'pa',
  'ぴ': 'pi',
  'ぷ': 'pu',
  'ぺ': 'pe',
  'ぽ': 'po',
  'ま': 'ma',
  'み': 'mi',
  'む': 'mu',
  'め': 'me',
  'も': 'mo',
  'や': 'ya',
  'ゆ': 'yu',
  'よ': 'yo',
  'ら': 'ra',
  'り': 'ri',
  'る': 'ru',
  'れ': 're',
  'ろ': 'ro',
  'わ': 'wa',
  'ゐ': 'i',
  'ゑ': 'e',
  'を': 'o',
  'ん': 'n',
  'ゔ': 'vu',
  'ぁ': 'a',
  'ぃ': 'i',
  'ぅ': 'u',
  'ぇ': 'e',
  'ぉ': 'o',
  'ゃ': 'ya',
  'ゅ': 'yu',
  'ょ': 'yo',
  'ゎ': 'wa',
  'ゕ': 'ka',
  'ゖ': 'ke',
  '、': ', ',
  '。': '. ',
  '・': ' ',
  '　': ' ',
};

const _digraphs = {
  'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
  'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
  'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho', 'しぇ': 'she',
  'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo', 'じぇ': 'je',
  'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho', 'ちぇ': 'che',
  'ぢゃ': 'ja', 'ぢゅ': 'ju', 'ぢょ': 'jo',
  'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
  'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
  'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
  'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
  'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
  'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
  // Extended katakana, folded to hiragana first.
  'ふぁ': 'fa', 'ふぃ': 'fi', 'ふぇ': 'fe', 'ふぉ': 'fo',
  'てぃ': 'ti', 'でぃ': 'di', 'とぅ': 'tu', 'どぅ': 'du',
  'うぃ': 'wi', 'うぇ': 'we', 'うぉ': 'wo',
  'ゔぁ': 'va', 'ゔぃ': 'vi', 'ゔぇ': 've', 'ゔぉ': 'vo',
  'つぁ': 'tsa', 'つぃ': 'tsi', 'つぇ': 'tse', 'つぉ': 'tso',
  'いぇ': 'ye',
};
