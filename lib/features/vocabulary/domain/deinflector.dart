/// Conjugation classes a dictionary entry can have, as bit flags.
///
/// The values are shared with `tool/build_dictionary.py`, which writes them
/// into the bundled dictionary.
abstract final class Conjugation {
  static const ichidan = 1;
  static const godan = 2;
  static const kuru = 4;
  static const suru = 8;
  static const iAdjective = 16;
  static const copula = 32;

  /// A noun that becomes a verb with する (勉強 → 勉強する).
  static const suruNoun = 512;

  static const verbs = ichidan | godan | kuru | suru;

  /// What an entry with only a coarse part of speech may conjugate as. Used
  /// for dictionaries that predate the conjugation field.
  static int fromPos(String? pos) => switch (pos) {
    'verb' => verbs,
    'i-adjective' => iAdjective,
    _ => 0,
  };
}

/// One candidate dictionary form of an inflected word.
///
/// [types] says what the candidate has to be for the guess to hold: 食べた
/// yields 食べる only as an ichidan verb. A candidate is right only when the
/// dictionary has [term] with one of those conjugation classes.
class Deinflection {
  final String term;
  final int types;

  const Deinflection(this.term, this.types);
}

/// Turns inflected Japanese verbs and adjectives back into dictionary form.
///
/// Rule-based, in the style of the Yomichan/Yomitan browser dictionaries:
/// each rule swaps an ending (なかった → ない) and says which form it reads
/// and which it produces, so rules chain: 食べなかった → 食べない → 食べる.
/// It only proposes candidates; the dictionary decides which are real.
///
/// Rules are bucketed by the last character of their ending, so a word only
/// meets the handful of rules that could apply to it.
class Deinflector {
  Deinflector._() {
    for (final rule in _rules) {
      if (rule.from.isEmpty) {
        _emptyRules.add(rule);
      } else {
        (_rulesByLastChar[rule.from.codeUnitAt(rule.from.length - 1)] ??= [])
            .add(rule);
      }
    }
    // Longest ending first, so a specific rule beats a general one that also
    // fits: 行った is 行く before it is 行う.
    for (final rules in _rulesByLastChar.values) {
      rules.sort((a, b) => b.from.length.compareTo(a.from.length));
    }
  }

  static final instance = Deinflector._();

  final Map<int, List<_Rule>> _rulesByLastChar = {};
  final List<_Rule> _emptyRules = [];

  /// Guards against pathological input; real words need a handful of steps.
  static const _maxCandidates = 64;

  /// False when no rule ends the way [word] does, so it cannot be inflected.
  /// Cheap enough to call on every substring the tokenizer tries.
  bool mayInflect(String word) =>
      word.isNotEmpty &&
      _rulesByLastChar.containsKey(word.codeUnitAt(word.length - 1));

  /// Every dictionary form [word] could come from, nearest first. The word
  /// itself is not included.
  List<Deinflection> deinflect(String word) {
    if (!mayInflect(word)) return const [];

    final results = <Deinflection>[Deinflection(word, 0)];
    final seen = <String>{'$word\u0000'};

    for (var i = 0; i < results.length; i++) {
      final current = results[i];
      final term = current.term;
      if (term.isEmpty) continue;
      final initial = current.types == 0;

      final rules = _rulesByLastChar[term.codeUnitAt(term.length - 1)];
      if (rules != null) {
        for (final rule in rules) {
          if (!initial && current.types & rule.typesIn == 0) continue;
          if (!term.endsWith(rule.from)) continue;
          _add(results, seen, rule, term);
        }
      }
      // Rules that add an ending outright (食べ → 食べる) only follow a rule
      // that left a stem; on a bare word they would match nearly anything.
      if (!initial && current.types & _stem != 0) {
        for (final rule in _emptyRules) {
          _add(results, seen, rule, term);
        }
      }
      if (results.length >= _maxCandidates) break;
    }
    return results.sublist(1);
  }

  static void _add(
    List<Deinflection> results,
    Set<String> seen,
    _Rule rule,
    String term,
  ) {
    final next = term.substring(0, term.length - rule.from.length) + rule.to;
    if (next.isEmpty) return;
    if (seen.add('$next\u0000${rule.typesOut}')) {
      results.add(Deinflection(next, rule.typesOut));
    }
  }
}

class _Rule {
  final String from;
  final String to;

  /// Forms this rule reads; 0 means it only applies to the word as written.
  final int typesIn;
  final int typesOut;

  const _Rule(this.from, this.to, this.typesIn, this.typesOut);
}

// Intermediate forms. They never match a dictionary entry themselves; they
// let one rule hand over to the next.
const _stem = 64; // 食べ, 行き: the masu stem
const _te = 128; // 食べて
const _ta = 256; // 食べた

const _v1 = Conjugation.ichidan;
const _v5 = Conjugation.godan;
const _vk = Conjugation.kuru;
const _vs = Conjugation.suru;
const _adj = Conjugation.iAdjective;
const _cop = Conjugation.copula;

/// Godan endings by row: dictionary form, then the a, i, e and o columns and
/// the te and ta forms.
const _godanRows = [
  ('う', 'わ', 'い', 'え', 'お', 'って', 'った'),
  ('く', 'か', 'き', 'け', 'こ', 'いて', 'いた'),
  ('ぐ', 'が', 'ぎ', 'げ', 'ご', 'いで', 'いだ'),
  ('す', 'さ', 'し', 'せ', 'そ', 'して', 'した'),
  ('つ', 'た', 'ち', 'て', 'と', 'って', 'った'),
  ('ぬ', 'な', 'に', 'ね', 'の', 'んで', 'んだ'),
  ('ぶ', 'ば', 'び', 'べ', 'ぼ', 'んで', 'んだ'),
  ('む', 'ま', 'み', 'め', 'も', 'んで', 'んだ'),
  ('る', 'ら', 'り', 'れ', 'ろ', 'って', 'った'),
];

final List<_Rule> _rules = [
  // Past (and the た that たら/たり leave behind).
  const _Rule('た', 'る', _ta, _v1),
  for (final r in _godanRows) _Rule(r.$7, r.$1, _ta, _v5),
  const _Rule('行った', '行く', _ta, _v5),
  const _Rule('いった', 'いく', _ta, _v5),
  const _Rule('きた', 'くる', _ta, _vk),
  const _Rule('来た', '来る', _ta, _vk),
  const _Rule('した', 'する', _ta, _vs),
  const _Rule('かった', 'い', _ta, _adj),
  const _Rule('だった', 'だ', _ta, _cop),
  const _Rule('でした', 'です', _ta, _cop),
  const _Rule('たら', 'た', 0, _ta),
  const _Rule('たり', 'た', 0, _ta),
  const _Rule('だら', 'だ', 0, _ta),
  const _Rule('だり', 'だ', 0, _ta),

  // Te form.
  const _Rule('て', 'る', _te, _v1),
  for (final r in _godanRows) _Rule(r.$6, r.$1, _te, _v5),
  const _Rule('行って', '行く', _te, _v5),
  const _Rule('いって', 'いく', _te, _v5),
  const _Rule('きて', 'くる', _te, _vk),
  const _Rule('来て', '来る', _te, _vk),
  const _Rule('して', 'する', _te, _vs),
  const _Rule('くて', 'い', _te, _adj),

  // Auxiliaries that follow the te form.
  const _Rule('ている', 'て', _v1, _te),
  const _Rule('でいる', 'で', _v1, _te),
  const _Rule('てる', 'て', _v1, _te),
  const _Rule('でる', 'で', _v1, _te),
  const _Rule('てしまう', 'て', _v5, _te),
  const _Rule('でしまう', 'で', _v5, _te),
  const _Rule('ちゃう', 'て', _v5, _te),
  const _Rule('じゃう', 'で', _v5, _te),
  const _Rule('ちまう', 'て', _v5, _te),
  const _Rule('ておく', 'て', _v5, _te),
  const _Rule('でおく', 'で', _v5, _te),
  const _Rule('とく', 'て', _v5, _te),
  const _Rule('どく', 'で', _v5, _te),
  const _Rule('ていく', 'て', _v5, _te),
  const _Rule('でいく', 'で', _v5, _te),
  const _Rule('てある', 'て', _v5, _te),
  const _Rule('てくる', 'て', _vk, _te),
  const _Rule('でくる', 'で', _vk, _te),
  const _Rule('てください', 'て', 0, _te),
  const _Rule('でください', 'で', 0, _te),
  const _Rule('ては', 'て', 0, _te),
  const _Rule('ても', 'て', 0, _te),
  const _Rule('では', 'で', 0, _te),
  const _Rule('でも', 'で', 0, _te),
  const _Rule('ちゃ', 'て', 0, _te),
  const _Rule('じゃ', 'で', 0, _te),

  // Endings that attach to the masu stem.
  for (final ending in const [
    'ます',
    'ました',
    'ません',
    'ませんでした',
    'ましょう',
    'まして',
    'ませ',
    'ながら',
    'なさい',
    'そう',
  ])
    _Rule(ending, '', 0, _stem),
  const _Rule('たい', '', _adj, _stem),
  const _Rule('たがる', '', _v5, _stem),
  const _Rule('すぎる', '', _v1, _stem),
  const _Rule('やすい', '', _adj, _stem),
  const _Rule('にくい', '', _adj, _stem),

  // Masu stem back to dictionary form.
  const _Rule('', 'る', _stem, _v1),
  for (final r in _godanRows) _Rule(r.$3, r.$1, _stem, _v5),
  const _Rule('き', 'くる', _stem, _vk),
  const _Rule('来', '来る', _stem, _vk),
  const _Rule('し', 'する', _stem, _vs),

  // Negative. ない conjugates as an adjective, hence the adjective input.
  const _Rule('ない', 'る', _adj, _v1),
  for (final r in _godanRows) _Rule('${r.$2}ない', r.$1, _adj, _v5),
  const _Rule('こない', 'くる', _adj, _vk),
  const _Rule('来ない', '来る', _adj, _vk),
  const _Rule('しない', 'する', _adj, _vs),
  const _Rule('くない', 'い', _adj, _adj),
  const _Rule('じゃない', 'だ', _adj, _cop),
  const _Rule('んない', 'らない', _adj, _adj), // わかんない, colloquial
  const _Rule('ではない', 'だ', _adj, _cop),
  for (final zu in const ['ず', 'ずに']) ...[
    _Rule(zu, 'る', 0, _v1),
    for (final r in _godanRows) _Rule('${r.$2}$zu', r.$1, 0, _v5),
    _Rule('せ$zu', 'する', 0, _vs),
    _Rule('こ$zu', 'くる', 0, _vk),
  ],

  // Passive, potential and causative all conjugate as ichidan verbs.
  const _Rule('られる', 'る', _v1, _v1),
  const _Rule('れる', 'る', _v1, _v1), // 食べれる, the colloquial potential
  const _Rule('させる', 'る', _v1, _v1),
  const _Rule('させられる', 'る', _v1, _v1),
  for (final r in _godanRows) ...[
    _Rule('${r.$2}れる', r.$1, _v1, _v5),
    _Rule('${r.$4}る', r.$1, _v1, _v5),
    _Rule('${r.$2}せる', r.$1, _v1, _v5),
    _Rule('${r.$2}される', r.$1, _v1, _v5),
    _Rule('${r.$2}せられる', r.$1, _v1, _v5),
  ],
  const _Rule('こられる', 'くる', _v1, _vk),
  const _Rule('これる', 'くる', _v1, _vk),
  const _Rule('こさせる', 'くる', _v1, _vk),
  const _Rule('される', 'する', _v1, _vs),
  const _Rule('させる', 'する', _v1, _vs),
  const _Rule('させられる', 'する', _v1, _vs),

  // Volitional.
  const _Rule('よう', 'る', 0, _v1),
  for (final r in _godanRows) _Rule('${r.$5}う', r.$1, 0, _v5),
  const _Rule('こよう', 'くる', 0, _vk),
  const _Rule('しよう', 'する', 0, _vs),
  const _Rule('だろう', 'だ', 0, _cop),
  const _Rule('でしょう', 'です', 0, _cop),

  // Conditional.
  const _Rule('れば', 'る', 0, _v1),
  for (final r in _godanRows) _Rule('${r.$4}ば', r.$1, 0, _v5),
  const _Rule('くれば', 'くる', 0, _vk),
  const _Rule('すれば', 'する', 0, _vs),
  const _Rule('ければ', 'い', 0, _adj),

  // Imperative.
  const _Rule('ろ', 'る', 0, _v1),
  const _Rule('よ', 'る', 0, _v1),
  for (final r in _godanRows) _Rule(r.$4, r.$1, 0, _v5),
  const _Rule('こい', 'くる', 0, _vk),
  const _Rule('しろ', 'する', 0, _vs),
  const _Rule('せよ', 'する', 0, _vs),

  // Other adjective forms.
  const _Rule('く', 'い', 0, _adj),
  const _Rule('くなる', 'い', _v5, _adj),
  const _Rule('すぎる', 'い', _v1, _adj),
  const _Rule('そう', 'い', 0, _adj),
  const _Rule('かろう', 'い', 0, _adj),
];
