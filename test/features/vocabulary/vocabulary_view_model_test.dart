import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/utils/clock.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_event.dart';
import 'package:ingrain/features/srs/domain/review_repository.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';

class TestClock extends Clock {
  TestClock(this.current);

  DateTime current;

  @override
  DateTime get now => current;
}

class InMemoryVocabularyRepository implements VocabularyRepository {
  final List<VocabularyItem> words;
  int _nextId = 0;

  InMemoryVocabularyRepository([List<VocabularyItem>? seed])
    : words = [...?seed];

  @override
  Future<VocabularyItem> save({
    required String word,
    String? reading,
    String? meaning,
    String? pos,
    required SourceType sourceType,
    required String sourceId,
    String? sourceTitle,
    int? timestampSeconds,
    String? contextSentence,
    String? sessionId,
    VocabState state = VocabState.encountered,
    DateTime? createdAt,
  }) async {
    final now = createdAt ?? DateTime(2026, 3, 15, 12);
    final item = VocabularyItem(
      id: 'word-${_nextId++}',
      uid: 'uid-1',
      word: word,
      reading: reading,
      meaning: meaning,
      pos: pos,
      sourceType: sourceType,
      sourceId: sourceId,
      sourceTitle: sourceTitle,
      timestampSeconds: timestampSeconds,
      contextSentence: contextSentence,
      sessionId: sessionId,
      state: state,
      createdAt: now,
      updatedAt: now,
    );
    words.add(item);
    return item;
  }

  @override
  Future<VocabularyItem?> get(String id) async {
    for (final word in words) {
      if (word.id == id) return word;
    }
    return null;
  }

  @override
  Future<void> update(VocabularyItem item) async {
    final index = words.indexWhere((w) => w.id == item.id);
    if (index != -1) words[index] = item;
  }

  @override
  Future<void> delete(String id) async {
    words.removeWhere((w) => w.id == id);
  }

  @override
  Stream<List<VocabularyItem>> watchAll() async* {
    final sorted = [...words]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    yield sorted;
  }

  @override
  Future<VocabularyItem?> findByWord(String word) async {
    for (final item in words) {
      if (item.word == word) return item;
    }
    return null;
  }

  @override
  Future<VocabularyItem?> recordEncounter(
    String id, {
    DateTime? encounteredAt,
  }) async {
    final existing = await get(id);
    if (existing == null) return null;
    final updated = existing.copyWith(
      encounterCount: existing.encounterCount + 1,
      updatedAt: encounteredAt ?? DateTime(2026, 3, 15, 12),
    );
    await update(updated);
    return updated;
  }

  @override
  Future<int> count() async => words.length;

  @override
  Future<Map<VocabState, int>> countByState() async {
    final counts = {for (final state in VocabState.values) state: 0};
    for (final word in words) {
      counts[word.state] = counts[word.state]! + 1;
    }
    return counts;
  }
}

class FakeReviewRepository implements ReviewRepository {
  final List<ReviewCard> cards = [];
  int _nextId = 0;

  @override
  Future<ReviewCard> createCard({
    required CardType cardType,
    required String sourceItemId,
    required String promptText,
    String? answerText,
    DateTime? createdAt,
    DateTime? dueAt,
  }) async {
    final created = createdAt ?? DateTime(2026, 3, 15, 12);
    final card = ReviewCard(
      id: 'card-${_nextId++}',
      uid: 'uid-1',
      cardType: cardType,
      sourceItemId: sourceItemId,
      promptText: promptText,
      answerText: answerText,
      createdAt: created,
      dueAt: dueAt ?? created,
    );
    cards.add(card);
    return card;
  }

  @override
  Future<void> saveCards(
    List<ReviewCard> cards, {
    void Function(int saved)? onProgress,
  }) async {
    for (final card in cards) {
      await saveCard(card);
    }
    onProgress?.call(cards.length);
  }

  @override
  Future<void> deleteCards(List<String> cardIds) async {
    cards.removeWhere((card) => cardIds.contains(card.id));
  }

  @override
  Future<void> saveCard(ReviewCard card) async {
    final index = cards.indexWhere((c) => c.id == card.id);
    index < 0 ? cards.add(card) : cards[index] = card;
  }

  @override
  Future<List<ReviewCard>> listDue({DateTime? now}) async =>
      cards.where((c) => c.isDueAt(now ?? DateTime(2026, 3, 15, 12))).toList();

  @override
  Future<List<ReviewCard>> listAllCards() async => List.of(cards);

  @override
  Future<ReviewEvent> recordReview({
    required String cardId,
    required CardType cardType,
    required Rating rating,
    required DateTime reviewedAt,
    required int intervalDaysAfter,
  }) async => throw UnimplementedError();

  @override
  Future<List<ReviewEvent>> listReviewHistory({int limit = 200}) async =>
      const [];

  @override
  Future<void> deleteCardsForSource(String sourceItemId) async {
    cards.removeWhere((c) => c.sourceItemId == sourceItemId);
  }

  @override
  Future<int> countDue({DateTime? now}) async =>
      cards.where((c) => c.isDueAt(now ?? DateTime(2026, 3, 15, 12))).length;
}

const _transcript = [
  TranscriptSentence(index: 0, text: '前の行', startSeconds: 0, endSeconds: 5),
  TranscriptSentence(
    index: 1,
    text: '猫が好きです。',
    startSeconds: 5,
    endSeconds: 12,
  ),
  TranscriptSentence(index: 2, text: '次の行', startSeconds: 12, endSeconds: 20),
];

void main() {
  late TestClock clock;
  late InMemoryVocabularyRepository vocabulary;
  late FakeReviewRepository reviews;
  late ProviderContainer container;

  Future<void> build() async {
    clock = TestClock(DateTime(2026, 3, 15, 12));
    vocabulary = InMemoryVocabularyRepository();
    reviews = FakeReviewRepository();
    container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        vocabularyRepositoryProvider.overrideWithValue(vocabulary),
        reviewRepositoryProvider.overrideWithValue(reviews),
      ],
    );
    addTearDown(container.dispose);
    await container.read(vocabularyViewModelProvider.future);
  }

  VocabularyViewModel notifier() =>
      container.read(vocabularyViewModelProvider.notifier);

  group('VocabularyViewModel', () {
    test('starts empty', () async {
      await build();

      expect(container.read(vocabularyViewModelProvider).value, isEmpty);
    });

    test(
      'saving a word stores it with its immersion memory and queues review',
      () async {
        await build();

        final saved = await notifier().saveFromTranscript(
          contentId: 'content-1',
          word: '猫',
          sentence: _transcript[1],
          transcript: _transcript,
          contentTitle: 'My Video',
          sessionId: 'session-1',
          reading: 'ねこ',
          meaning: 'cat (animal)',
          pos: 'noun',
        );

        expect(saved, isNotNull);
        expect(vocabulary.words, hasLength(1));
        final word = vocabulary.words.single;
        expect(word.word, '猫');
        expect(word.reading, 'ねこ');
        expect(word.meaning, 'cat (animal)');
        expect(word.sourceId, 'content-1');
        expect(word.sourceTitle, 'My Video');
        expect(word.timestampSeconds, 5);
        expect(word.contextSentence, '前の行 猫が好きです。 次の行');
        expect(word.sessionId, 'session-1');
        expect(word.state, VocabState.encountered);
        expect(word.createdAt, clock.now);

        expect(reviews.cards, hasLength(1));
        final card = reviews.cards.single;
        expect(card.cardType, CardType.vocabulary);
        expect(card.promptText, '猫');
        expect(card.answerText, 'ねこ — cat (animal)');
        expect(card.sourceItemId, word.id);
      },
    );

    test('a word saved to another deck puts its card there', () async {
      await build();

      await notifier().saveWord(
        word: '猫',
        sourceType: SourceType.manual,
        sourceId: 'manual',
        deckId: 'deck-animals',
      );
      await notifier().saveWord(
        word: '犬',
        sourceType: SourceType.manual,
        sourceId: 'manual',
      );

      expect(reviews.cards, hasLength(2));
      expect(reviews.cards.first.deckId, 'deck-animals');
      expect(reviews.cards.last.deckId, 'mined-phrases');
    });

    test('saving a blank word is rejected', () async {
      await build();

      final saved = await notifier().saveWord(
        word: '   ',
        sourceType: SourceType.manual,
        sourceId: 'manual',
      );

      expect(saved, isNull);
      expect(vocabulary.words, isEmpty);
      expect(reviews.cards, isEmpty);
    });

    test('saving an already saved word records an encounter instead', () async {
      await build();

      final first = await notifier().saveWord(
        word: '猫',
        meaning: 'cat (animal)',
        sourceType: SourceType.manual,
        sourceId: 'manual',
      );
      clock.current = DateTime(2026, 3, 16, 9);
      final second = await notifier().saveWord(
        word: '猫',
        sourceType: SourceType.youtube,
        sourceId: 'content-2',
        sourceTitle: 'Another Video',
      );

      expect(vocabulary.words, hasLength(1));
      expect(second!.id, first!.id);
      expect(second.encounterCount, 2);
      expect(second.updatedAt, clock.current);
      // The original source context is kept: the first encounter is the memory.
      expect(second.sourceId, 'manual');
      // A second review card is never created for the same word.
      expect(reviews.cards, hasLength(1));
    });

    test(
      'a re-save fills in dictionary details but keeps manual ones',
      () async {
        await build();

        await notifier().saveWord(
          word: '猫',
          reading: 'ねこ',
          meaning: 'my own note',
          sourceType: SourceType.manual,
          sourceId: 'manual',
        );
        await notifier().saveWord(
          word: '猫',
          reading: 'nyanko',
          meaning: 'cat (animal)',
          pos: 'noun',
          sourceType: SourceType.manual,
          sourceId: 'manual',
        );

        final word = vocabulary.words.single;
        expect(word.reading, 'ねこ');
        expect(word.meaning, 'my own note');
        expect(word.pos, 'noun');
      },
    );

    test('setState persists an explicit learning state', () async {
      await build();
      final saved = await notifier().saveWord(
        word: '猫',
        sourceType: SourceType.manual,
        sourceId: 'manual',
      );

      clock.current = DateTime(2026, 3, 20, 8);
      await notifier().setState(saved!.id, VocabState.mastered);

      expect(vocabulary.words.single.state, VocabState.mastered);
      expect(vocabulary.words.single.updatedAt, clock.current);
      expect(
        container.read(vocabularyViewModelProvider).value!.single.state,
        VocabState.mastered,
      );
    });

    test('setState on an unknown id does nothing', () async {
      await build();

      await notifier().setState('missing', VocabState.known);

      expect(vocabulary.words, isEmpty);
    });

    test('deleting a word also deletes its review card', () async {
      await build();
      final saved = await notifier().saveWord(
        word: '猫',
        meaning: 'cat (animal)',
        sourceType: SourceType.manual,
        sourceId: 'manual',
      );

      await notifier().deleteWord(saved!.id);

      expect(vocabulary.words, isEmpty);
      expect(reviews.cards, isEmpty);
      expect(container.read(vocabularyViewModelProvider).value, isEmpty);
    });

    test('answerFor falls back to the context sentence', () async {
      final withDetails = VocabularyItem(
        id: 'w1',
        uid: 'uid-1',
        word: '猫',
        reading: 'ねこ',
        sourceType: SourceType.manual,
        sourceId: 'manual',
        contextSentence: '猫が好きです。',
        createdAt: DateTime(2026, 3, 15),
        updatedAt: DateTime(2026, 3, 15),
      );
      expect(VocabularyViewModel.answerFor(withDetails), 'ねこ');

      final bare = withDetails.copyWith(reading: () => null);
      expect(VocabularyViewModel.answerFor(bare), '猫が好きです。');

      final neither = bare.copyWith(contextSentence: () => null);
      expect(VocabularyViewModel.answerFor(neither), isNull);
    });
  });
}
