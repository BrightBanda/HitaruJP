import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
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

  test('includes up to six of the learner\'s own words', () {
    final mine = [
      saved('散歩', 'さんぽ', 'a walk'),
      saved('静か', 'しずか', 'quiet'),
      saved('楽しい', 'たのしい', 'fun'),
      saved('お茶', 'おちゃ', 'tea'),
      saved('映画館', 'えいがかん', 'cinema'),
      saved('公園', 'こうえん', 'park'),
      saved('図書館', 'としょかん', 'library'),
      saved('自転車', 'じてんしゃ', 'bicycle'),
    ];
    final quiz = build(mine: mine);
    final own = quiz.questions.where((q) => q.fromSaved).toList();
    expect(own, hasLength(DailyQuiz.savedShare));
    expect(quiz.questions, hasLength(12));
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
