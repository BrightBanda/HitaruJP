import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/utils/clock.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/content/presentation/view/player/transcript_view.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/domain/dialogue_repository.dart';
import 'package:ingrain/features/dialogue/presentation/view/dialogue_reader_view.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/features/immersion/domain/immersion_repository.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/progress/presentation/view/progress_dashboard.dart';
import 'package:ingrain/features/search/presentation/view/search_view.dart';
import 'package:ingrain/features/sentence_mining/domain/sentence_item.dart';
import 'package:ingrain/features/sentence_mining/domain/sentence_repository.dart';
import 'package:ingrain/features/sentence_mining/presentation/viewmodel/sentence_mining_view_model.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_event.dart';
import 'package:ingrain/features/srs/domain/review_repository.dart';
import 'package:ingrain/features/srs/presentation/view/flashcard_study_view.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:ingrain/features/vocabulary/presentation/widgets/tappable_transcript_text.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_overrides.dart';

class FixedTestClock extends Clock {
  @override
  DateTime get now => DateTime(2026, 3, 15, 12);
}

class InMemorySentenceRepository implements SentenceRepository {
  InMemorySentenceRepository([List<SentenceItem>? seed])
    : sentences = [...?seed];

  final List<SentenceItem> sentences;
  int _nextId = 0;

  @override
  Future<SentenceItem> save({
    required String japanese,
    String? translation,
    String? explanation,
    required SourceType sourceType,
    required String sourceId,
    String? sourceTitle,
    int? timestampSeconds,
    String? contextSentence,
    String? sessionId,
    DateTime? createdAt,
  }) async {
    final sentence = SentenceItem(
      id: 'sentence-${_nextId++}',
      uid: 'uid-1',
      japanese: japanese,
      translation: translation,
      explanation: explanation,
      sourceType: sourceType,
      sourceId: sourceId,
      sourceTitle: sourceTitle,
      timestampSeconds: timestampSeconds,
      contextSentence: contextSentence,
      sessionId: sessionId,
      createdAt: createdAt ?? DateTime(2026, 3, 15),
    );
    sentences.add(sentence);
    return sentence;
  }

  @override
  Future<SentenceItem?> get(String id) async {
    for (final sentence in sentences) {
      if (sentence.id == id) return sentence;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    sentences.removeWhere((s) => s.id == id);
  }

  @override
  Stream<List<SentenceItem>> watchAll() async* {
    final sorted = [...sentences]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    yield sorted;
  }

  @override
  Future<int> count() async => sentences.length;

  @override
  Future<int> countCreatedOn(DateTime day) async => sentences.length;
}

class InMemoryReviewRepository implements ReviewRepository {
  InMemoryReviewRepository([List<ReviewCard>? seed]) : cards = [...?seed];

  final List<ReviewCard> cards;
  final List<ReviewEvent> history = [];
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
    final created = createdAt ?? DateTime(2026, 3, 15);
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
    if (index == -1) {
      cards.add(card);
    } else {
      cards[index] = card;
    }
  }

  @override
  Future<List<ReviewCard>> listDue({DateTime? now}) async {
    final at = now ?? DateTime(2026, 3, 15, 12);
    final due = cards.where((c) => c.isDueAt(at)).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return due;
  }

  @override
  Future<List<ReviewCard>> listAllCards() async => List.of(cards);

  @override
  Future<ReviewEvent> recordReview({
    required String cardId,
    required CardType cardType,
    required Rating rating,
    required DateTime reviewedAt,
    required int intervalDaysAfter,
  }) async {
    final event = ReviewEvent(
      id: 'review-${history.length}',
      uid: 'uid-1',
      cardId: cardId,
      cardType: cardType,
      rating: rating,
      reviewedAt: reviewedAt,
      intervalDaysAfter: intervalDaysAfter,
    );
    history.add(event);
    return event;
  }

  @override
  Future<List<ReviewEvent>> listReviewHistory({int limit = 200}) async {
    final events = [...history]
      ..sort((a, b) => b.reviewedAt.compareTo(a.reviewedAt));
    return events.length > limit ? events.sublist(0, limit) : events;
  }

  @override
  Future<void> deleteCardsForSource(String sourceItemId) async {
    cards.removeWhere((c) => c.sourceItemId == sourceItemId);
  }

  @override
  Future<int> countDue({DateTime? now}) async {
    final at = now ?? DateTime(2026, 3, 15, 12);
    return cards.where((c) => c.isDueAt(at)).length;
  }
}

class InMemoryVocabularyRepository implements VocabularyRepository {
  InMemoryVocabularyRepository([List<VocabularyItem>? seed])
    : words = [...?seed];

  final List<VocabularyItem> words;
  int _nextId = 0;

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
    final now = createdAt ?? DateTime(2026, 3, 15);
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
      updatedAt: encounteredAt ?? DateTime(2026, 3, 15),
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

class EmptyImmersionRepository implements ImmersionRepository {
  const EmptyImmersionRepository();

  @override
  Future<ImmersionSession> startSession({
    required String sourceId,
    String? sourceTitle,
    required ActivityType activityType,
    required DateTime startedAt,
  }) async => ImmersionSession(
    id: 'session-1',
    uid: 'uid-1',
    sourceId: sourceId,
    sourceTitle: sourceTitle,
    activityType: activityType,
    startedAt: startedAt,
  );

  @override
  Future<void> updateDuration(String sessionId, int durationSeconds) async {}

  @override
  Future<void> updatePosition(
    String sessionId,
    int lastPositionSeconds,
  ) async {}

  @override
  Future<void> pauseSession(String sessionId, DateTime pausedAt) async {}

  @override
  Future<void> resumeSession(String sessionId, DateTime resumedAt) async {}

  @override
  Future<void> stopSession(String sessionId, DateTime endedAt) async {}

  @override
  Future<ImmersionSession?> getSession(String sessionId) async => null;

  @override
  Stream<List<ImmersionSession>> watchRecentSessions() async* {
    yield const [];
  }

  @override
  Future<void> deleteSession(String sessionId) async {}
}

class InMemoryDialogueRepository implements DialogueRepository {
  InMemoryDialogueRepository(this.dialogue);

  final Dialogue dialogue;

  @override
  bool isShowingCachedCopy = false;

  @override
  Future<List<DialogueSummary>> listSummaries() async => [dialogue];

  @override
  Future<Dialogue> getDialogue(String id) async => dialogue;

  @override
  Future<Dialogue?> getCachedDialogue(String id) async => dialogue;

  @override
  Future<void> cacheDialogue(Dialogue dialogue) async {}
}

SentenceItem sampleSentence() => SentenceItem(
  id: 'sentence-1',
  uid: 'uid-1',
  japanese: 'これはテストです。',
  translation: 'This is a test.',
  sourceType: SourceType.youtube,
  sourceId: 'content-1',
  sourceTitle: 'My Video',
  timestampSeconds: 42,
  createdAt: DateTime(2026, 3, 15, 9),
);

VocabularyItem sampleWord({
  VocabState state = VocabState.learning,
  String text = '猫',
  String? reading = 'ねこ',
}) {
  return VocabularyItem(
    id: 'word-$text',
    uid: 'uid-1',
    word: text,
    reading: reading,
    meaning: 'cat (animal)',
    pos: 'noun',
    sourceType: SourceType.youtube,
    sourceId: 'content-1',
    sourceTitle: 'My Video',
    timestampSeconds: 42,
    contextSentence: '猫が好きです。',
    state: state,
    createdAt: DateTime(2026, 3, 15, 9),
    updatedAt: DateTime(2026, 3, 15, 9),
  );
}

/// One word per line so each tap target can be hit precisely.
List<TranscriptSentence> lookupTranscript() => const [
  TranscriptSentence(index: 0, text: '猫', startSeconds: 0, endSeconds: 5),
  TranscriptSentence(index: 1, text: '犬', startSeconds: 5, endSeconds: 12),
];

DictionaryIndex testDictionary() => DictionaryIndex.fromJson({
  'entries': [
    {
      'surface': '猫',
      'reading': 'ねこ',
      'pos': 'noun',
      'meanings': ['cat (animal)', 'feline'],
    },
    {
      'surface': '好き',
      'reading': 'すき',
      'meanings': ['liking'],
    },
  ],
});

ContentItem sampleContent() => ContentItem(
  id: 'content-1',
  sourceType: SourceType.youtube,
  sourceUrl: 'https://youtu.be/abc',
  title: 'My Video',
  lastOpenedAt: DateTime(2026, 3, 15, 9),
);

List<TranscriptSentence> sampleTranscript() => const [
  TranscriptSentence(index: 0, text: '前の行', startSeconds: 0, endSeconds: 5),
  TranscriptSentence(
    index: 1,
    text: 'これはテストです。',
    startSeconds: 5,
    endSeconds: 12,
  ),
  TranscriptSentence(index: 2, text: '次の行', startSeconds: 12, endSeconds: 20),
];

ReviewCard sampleCard() => ReviewCard(
  id: 'card-1',
  uid: 'uid-1',
  cardType: CardType.sentence,
  sourceItemId: 'sentence-1',
  promptText: 'これはテストです。',
  answerText: 'This is a test.',
  createdAt: DateTime(2026, 3, 15, 9),
  dueAt: DateTime(2026, 3, 15, 9),
);

void main() {
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester,
    Widget child, {
    List<SentenceItem> sentences = const [],
    List<ReviewCard> cards = const [],
    List<VocabularyItem> words = const [],
    DialogueRepository? dialogueRepository,
    DictionaryIndex? dictionary,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        // The progress dashboard reads the daily goal through settings.
        ...appTestOverrides(prefs),
        clockProvider.overrideWithValue(FixedTestClock()),
        sentenceRepositoryProvider.overrideWithValue(
          InMemorySentenceRepository([...sentences]),
        ),
        reviewRepositoryProvider.overrideWithValue(
          InMemoryReviewRepository([...cards]),
        ),
        vocabularyRepositoryProvider.overrideWithValue(
          InMemoryVocabularyRepository([...words]),
        ),
        dictionaryProvider.overrideWith(
          (ref) async => dictionary ?? testDictionary(),
        ),
        immersionRepositoryProvider.overrideWithValue(
          const EmptyImmersionRepository(),
        ),
        if (dialogueRepository != null)
          dialogueRepositoryProvider.overrideWithValue(dialogueRepository),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('FlashcardStudyView', () {
    testWidgets('shows the all caught up state when nothing is due', (
      tester,
    ) async {
      await pumpScreen(tester, const FlashcardStudyView());

      expect(find.text('Study'), findsOneWidget);
      expect(find.text('All caught up'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rates a due card through to the completion summary', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const FlashcardStudyView(),
        cards: [sampleCard()],
      );

      expect(find.text('これはテストです。'), findsOneWidget);
      expect(find.text('Show answer'), findsOneWidget);
      expect(find.text('1 due'), findsOneWidget);

      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();

      expect(find.text('This is a test.'), findsOneWidget);
      expect(find.text('Interval 0d • ease 2.50 • seen 0x'), findsOneWidget);
      for (final label in ['Again', 'Hard', 'Good', 'Easy']) {
        expect(find.text(label), findsOneWidget);
      }
      // Anki-style waits under each answer for a new card.
      for (final wait in ['1m', '5m', '10m', '4d']) {
        expect(find.text(wait), findsOneWidget);
      }

      await tester.tap(find.text('Easy'));
      await tester.pumpAndSettle();

      expect(find.text('Session complete'), findsOneWidget);
      expect(find.text('1 reviewed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('TranscriptView mining', () {
    testWidgets('saving a transcript line stores it and queues a review', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final sentenceRepository = InMemorySentenceRepository();
      final reviewRepository = InMemoryReviewRepository();

      final container = ProviderContainer(
        overrides: [
          ...appTestOverrides(prefs),
          clockProvider.overrideWithValue(FixedTestClock()),
          sentenceRepositoryProvider.overrideWithValue(sentenceRepository),
          reviewRepositoryProvider.overrideWithValue(reviewRepository),
          immersionRepositoryProvider.overrideWithValue(
            const EmptyImmersionRepository(),
          ),
          transcriptProvider('content-1')
              .overrideWith((ref) async => sampleTranscript()),
          contentItemProvider('content-1')
              .overrideWith((ref) async => sampleContent()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TranscriptView(contentId: 'content-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The second transcript line, so the saved context spans both neighbours.
      await tester.tap(find.byIcon(Icons.bookmark_add_outlined).at(1));
      await tester.pumpAndSettle();

      expect(find.text('Mine sentence'), findsOneWidget);
      expect(find.text('これはテストです。'), findsWidgets);
      expect(find.text('前の行 これはテストです。 次の行'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Japanese'), '');
      await tester.enterText(
        find.widgetWithText(TextField, 'Translation (optional)'),
        'This is a test.',
      );
      await tester.tap(find.text('Save sentence'));
      await tester.pumpAndSettle();

      expect(sentenceRepository.sentences, hasLength(1));
      final saved = sentenceRepository.sentences.single;
      expect(saved.japanese, 'これはテストです。');
      expect(saved.translation, 'This is a test.');
      expect(saved.sourceTitle, 'My Video');
      expect(saved.timestampSeconds, 5);
      expect(saved.contextSentence, '前の行 これはテストです。 次の行');

      expect(reviewRepository.cards, hasLength(1));
      expect(reviewRepository.cards.single.promptText, 'これはテストです。');
      expect(reviewRepository.cards.single.answerText, 'This is a test.');
      expect(find.text('Sentence saved for review'), findsOneWidget);

      // Let the confirmation snack bar dismiss so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the empty state when there is no transcript', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          ...appTestOverrides(prefs),
          clockProvider.overrideWithValue(FixedTestClock()),
          transcriptProvider('content-1')
              .overrideWith((ref) async => const <TranscriptSentence>[]),
          contentItemProvider('content-1')
              .overrideWith((ref) async => sampleContent()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TranscriptView(contentId: 'content-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No transcript available'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
    });
  });

  group('ProgressDashboard', () {
    Future<void> scrollDashboardDown(WidgetTester tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    testWidgets('renders the dashboard with no data', (tester) async {
      await pumpScreen(tester, const Scaffold(body: ProgressDashboard()));

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('Learning'), findsOneWidget);
      expect(find.text('Sentences mined'), findsOneWidget);
      expect(find.text('Due for review'), findsOneWidget);
      expect(find.text('Reviewed today'), findsOneWidget);

      await scrollDashboardDown(tester);
      expect(find.text('Browse mined phrases'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('surfaces mined sentences and due reviews', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: ProgressDashboard()),
        sentences: [sampleSentence()],
        cards: [sampleCard()],
      );

      expect(find.text('Sentences mined'), findsOneWidget);
      expect(find.text('Due for review'), findsOneWidget);

      await scrollDashboardDown(tester);
      expect(find.text('Review 1 due now'), findsOneWidget);
      expect(find.text('Browse mined phrases'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('counts saved vocabulary', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: ProgressDashboard()),
        words: [
          sampleWord(),
          sampleWord(state: VocabState.encountered),
        ],
      );

      expect(find.text('Words saved'), findsOneWidget);

      await scrollDashboardDown(tester);
      expect(find.text('Browse saved vocabulary'), findsNothing);
      expect(find.text('Browse mined phrases'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SearchView', () {
    testWidgets('finds a mined sentence by its translation', (tester) async {
      await pumpScreen(
        tester,
        const SearchView(),
        sentences: [sampleSentence()],
        cards: [sampleCard()],
      );

      expect(find.text('Search your learning history'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a test');
      await tester.pumpAndSettle();

      expect(find.text('これはテストです。'), findsOneWidget);
      expect(find.text('My Video · 0:42'), findsOneWidget);
      expect(find.text('Reviewed 0×'), findsNothing);
      expect(find.text('Not reviewed yet'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('TranscriptView word lookup', () {
    Future<ProviderContainer> pumpTranscript(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          ...appTestOverrides(prefs),
          clockProvider.overrideWithValue(FixedTestClock()),
          vocabularyRepositoryProvider.overrideWithValue(
            InMemoryVocabularyRepository(),
          ),
          reviewRepositoryProvider.overrideWithValue(
            InMemoryReviewRepository(),
          ),
          immersionRepositoryProvider.overrideWithValue(
            const EmptyImmersionRepository(),
          ),
          dictionaryProvider.overrideWith((ref) async => testDictionary()),
          transcriptProvider('content-1')
              .overrideWith((ref) async => lookupTranscript()),
          contentItemProvider('content-1')
              .overrideWith((ref) async => sampleContent()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TranscriptView(contentId: 'content-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    /// Tokenised text renders as [RichText], so the tap is aimed at the start
    /// of the glyph rather than matched by string. Each line of
    /// [lookupTranscript] holds a single word.
    Future<void> tapWord(WidgetTester tester, int line) async {
      final text = find
          .descendant(
            of: find.byType(TappableTranscriptText),
            matching: find.byType(RichText),
          )
          .at(line);
      final box = tester.renderObject<RenderBox>(text);
      await tester.tapAt(box.localToGlobal(Offset(6, box.size.height / 2)));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a word shows the dictionary entry', (tester) async {
      await pumpTranscript(tester);

      await tapWord(tester, 0);

      expect(find.text('猫'), findsWidgets);
      expect(find.text('ねこ'), findsOneWidget);
      expect(find.text('noun'), findsOneWidget);
      expect(find.text('cat (animal)'), findsOneWidget);
      expect(find.text('feline'), findsOneWidget);
      expect(find.text('Save word'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving from the lookup sheet stores the word and a card', (
      tester,
    ) async {
      final container = await pumpTranscript(tester);

      await tapWord(tester, 0);
      await tester.tap(find.text('Save word'));
      await tester.pumpAndSettle();

      // The pre-filled save form opens with the dictionary values.
      expect(find.text('猫'), findsWidgets);
      await tester.tap(find.text('Save word').last);
      await tester.pumpAndSettle();

      final repository = container.read(vocabularyRepositoryProvider);
      expect(await repository.count(), 1);
      final saved = (await repository.findByWord('猫'))!;
      expect(saved.reading, 'ねこ');
      expect(saved.meaning, 'cat (animal)');
      expect(saved.sourceId, 'content-1');
      expect(saved.sourceTitle, 'My Video');
      expect(saved.contextSentence, '猫 犬');

      expect(find.text('Word saved for review'), findsOneWidget);

      // Let the confirmation snack bar dismiss so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a word missing from the dictionary can still be saved', (
      tester,
    ) async {
      final container = await pumpTranscript(tester);

      // 犬 is not in the stub dictionary but must still be tappable.
      await tapWord(tester, 1);

      expect(
        find.textContaining('Not in the bundled dictionary'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save word'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Meaning'),
        'dog (animal)',
      );
      await tester.tap(find.text('Save word').last);
      await tester.pumpAndSettle();

      final saved = (await container
          .read(vocabularyRepositoryProvider)
          .findByWord('犬'))!;
      expect(saved.meaning, 'dog (animal)');

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('DialogueReaderView', () {
    final sampleDialogue = Dialogue(
      id: 'dialogue-1',
      title: 'At the station',
      level: 'N5',
      source: const DialogueSource(attribution: 'Test source'),
      lines: const [
        DialogueLine(
          index: 0,
          speaker: 'ミカ',
          tokens: [
            DialogueToken(surface: '猫', reading: 'ねこ', romaji: 'neko'),
            DialogueToken(surface: 'が', reading: 'が', romaji: 'ga'),
            DialogueToken(surface: '好き', reading: 'すき', romaji: 'suki'),
            DialogueToken(surface: 'です。', reading: 'です', romaji: 'desu'),
          ],
        ),
      ],
    );

    Future<ProviderContainer> pumpDialogue(WidgetTester tester) => pumpScreen(
      tester,
      const DialogueReaderView(dialogueId: 'dialogue-1'),
      dialogueRepository: InMemoryDialogueRepository(sampleDialogue),
    );

    testWidgets('romaji is hidden by default and can be toggled on', (
      tester,
    ) async {
      await pumpDialogue(tester);

      expect(find.text('neko'), findsNothing);
      await tester.tap(find.widgetWithText(FilterChip, 'Romaji'));
      await tester.pumpAndSettle();

      expect(find.text('neko'), findsOneWidget);
      expect(find.text('suki'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('token lookup uses backend reading and can save vocabulary', (
      tester,
    ) async {
      final container = await pumpDialogue(tester);

      await tester.tap(find.text('猫'));
      await tester.pumpAndSettle();

      expect(find.text('ねこ'), findsOneWidget);
      expect(find.text('cat (animal)'), findsOneWidget);
      await tester.tap(find.text('Save word'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save word').last);
      await tester.pumpAndSettle();

      final saved = await container
          .read(vocabularyRepositoryProvider)
          .findByWord('猫');
      expect(saved?.reading, 'ねこ');
      expect(saved?.sourceType, SourceType.dialogue);
      expect(saved?.sourceId, 'dialogue-1');
      expect(find.text('Word saved for review'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('backend reading remains visible when dictionary misses', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const DialogueReaderView(dialogueId: 'dialogue-1'),
        dialogueRepository: InMemoryDialogueRepository(sampleDialogue),
        dictionary: DictionaryIndex.empty,
      );

      await tester.tap(find.text('猫'));
      await tester.pumpAndSettle();

      expect(find.text('Not in the bundled dictionary.'), findsOneWidget);
      expect(find.text('ねこ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mining a line creates a dialogue sentence and review card', (
      tester,
    ) async {
      final container = await pumpDialogue(tester);

      await tester.tap(find.byTooltip('Mine sentence'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Translation (optional)'),
        'I like cats.',
      );
      await tester.tap(find.text('Save sentence'));
      await tester.pumpAndSettle();

      final sentenceRepository = container.read(
        sentenceRepositoryProvider,
      ) as InMemorySentenceRepository;
      expect(
        sentenceRepository.sentences.single.sourceType,
        SourceType.dialogue,
      );
      expect(sentenceRepository.sentences.single.sourceId, 'dialogue-1');
      expect(sentenceRepository.sentences.single.japanese, '猫が好きです。');

      final reviewRepository =
          container.read(reviewRepositoryProvider) as InMemoryReviewRepository;
      expect(reviewRepository.cards.single.promptText, '猫が好きです。');
      expect(reviewRepository.cards.single.answerText, 'I like cats.');
      expect(find.text('Sentence saved for review'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
