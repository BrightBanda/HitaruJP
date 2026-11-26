import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';

import '../../support/quiz_fixture.dart';

VocabularyItem saved(String word, String reading, String meaning) =>
    VocabularyItem(
      id: word,
      uid: 'u1',
      word: word,
      reading: reading,
      meaning: meaning,
      sourceType: SourceType.manual,
      sourceId: 'x',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final day = DateTime(2026, 11, 25, 15);

  DailyQuiz build({String seed = 'u1', List<VocabularyItem> mine = const []}) =>
      DailyQuiz.build(
        day: day,
        seed: seed,
        saved: mine,
        dictionary: quizDictionary,
      );

  test('twelve questions, each with four different choices', () {
    final quiz = build();
    expect(quiz.questions, hasLength(DailyQuiz.length));
    for (final question in quiz.questions) {
      expect(question.choices, hasLength(4));
      expect(question.choices.toSet(), hasLength(4));
      expect(question.choices[question.answerIndex], question.answer);
    }
    expect(quiz.questions.map((q) => q.word).toSet(), hasLength(12));
  });

  test('kanji get furigana and every word gets romaji', () {
    final quiz = build();
    for (final question in quiz.questions) {
      expect(question.romaji, isNotEmpty);
      final hasKanji = RegExp(r'[㐀-鿿]').hasMatch(question.word);
      expect(question.furigana != null, hasKanji, reason: question.word);
    }
  });

  test('the same learner gets the same quiz all day', () {
    final morning = build();
    final evening = DailyQuiz.build(
      day: DateTime(2026, 11, 25, 22),
      seed: 'u1',
      saved: const [],
      dictionary: quizDictionary,
    );
    expect(
      evening.questions.map((q) => q.word),
      morning.questions.map((q) => q.word),
    );
    expect(
      build(seed: 'someone-else').questions.map((q) => q.word),
      isNot(morning.questions.map((q) => q.word)),
    );
  });

  final mine = [
    for (final (word, reading, meaning) in const [
      ('散歩', 'さんぽ', 'a walk'),
      ('静か', 'しずか', 'quiet'),
      ('楽しい', 'たのしい', 'fun'),
      ('お茶', 'おちゃ', 'tea'),
      ('映画館', 'えいがかん', 'cinema'),
      ('公園', 'こうえん', 'park'),
      ('図書館', 'としょかん', 'library'),
      ('自転車', 'じてんしゃ', 'bicycle'),
      ('教室', 'きょうしつ', 'classroom'),
      ('野菜', 'やさい', 'vegetable'),
      ('果物', 'くだもの', 'fruit'),
      ('病院', 'びょういん', 'hospital'),
      ('銀行', 'ぎんこう', 'bank'),
      ('郵便局', 'ゆうびんきょく', 'post office'),
      ('台所', 'だいどころ', 'kitchen'),
      ('窓', 'まど', 'window'),
    ])
      saved(word, reading, meaning),
  ];
  final heard = [
    for (final (surface, reading, meaning) in const [
      ('漫画', 'まんが', 'manga'),
      ('季節', 'きせつ', 'season'),
      ('旅行', 'りょこう', 'travel'),
      ('景色', 'けしき', 'scenery'),
      ('祭り', 'まつり', 'festival'),
      ('神社', 'じんじゃ', 'shrine'),
    ])
      DictionaryEntry(
        surface: surface,
        reading: reading,
        meanings: [meaning],
        pos: 'noun',
      ),
  ];

  test('mostly saved words, some from videos, a few at random', () {
    final counts = {for (final source in QuizSource.values) source: 0};
    for (var d = 0; d < 60; d++) {
      final quiz = DailyQuiz.build(
        day: DateTime(2026, 1, 1).add(Duration(days: d)),
        seed: 'u1',
        saved: mine,
        transcriptWords: heard,
        dictionary: quizDictionary,
      );
      expect(quiz.questions, hasLength(12));
      for (final question in quiz.questions) {
        counts[question.source] = counts[question.source]! + 1;
      }
    }
    final total = 60 * 12;
    expect(counts[QuizSource.saved]! / total, closeTo(0.80, 0.05));
    expect(counts[QuizSource.transcript]! / total, closeTo(0.15, 0.05));
    expect(counts[QuizSource.level]! / total, closeTo(0.05, 0.04));
  });

  test('with no saved words, videos then level words fill in', () {
    final quiz = DailyQuiz.build(
      day: day,
      seed: 'u1',
      saved: const [],
      transcriptWords: heard,
      dictionary: quizDictionary,
    );
    expect(quiz.questions, hasLength(12));
    expect(
      quiz.questions.where((q) => q.source == QuizSource.transcript),
      hasLength(heard.length),
    );
    expect(quiz.questions.where((q) => q.fromSaved), isEmpty);
  });

  test('a quiz earns 5 XP a right answer and 10 more for a perfect one', () {
    const rules = GrowthRules();
    expect(rules.quizXp(9, 12), 45);
    expect(rules.quizXp(12, 12), 70);
    final xp = rules.xpForDay(
      DayActivity(day: day, quizCorrect: 9, quizTotal: 12),
      dailyGoalMinutes: 30,
      streakDays: 0,
    );
    expect(xp[XpSource.quiz], 45);
  });
}
