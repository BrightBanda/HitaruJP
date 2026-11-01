import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/storage/local_document_store.dart';
import 'package:ingrain/features/srs/data/srs_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_auth_repository.dart';

import 'package:ingrain/core/utils/clock.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_event.dart';
import 'package:ingrain/features/srs/domain/review_repository.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';

class ManualClock extends Clock {
  DateTime _time;

  ManualClock(this._time);

  @override
  DateTime get now => _time;

  void advance(Duration delta) {
    _time = _time.add(delta);
  }
}

class FakeReviewRepository implements ReviewRepository {
  final List<ReviewCard> cards = [];
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
    final created = createdAt ?? DateTime(2026, 1, 1);
    final card = ReviewCard(
      id: 'card-${_nextId++}',
      uid: 'test-uid',
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
    final at = now ?? DateTime(2026, 1, 1);
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
      uid: 'test-uid',
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
    final events = List.of(history)
      ..sort((a, b) => b.reviewedAt.compareTo(a.reviewedAt));
    return events.length > limit ? events.sublist(0, limit) : events;
  }

  @override
  Future<void> deleteReviewEvent(String eventId) async {
    history.removeWhere((event) => event.id == eventId);
  }

  @override
  Future<void> deleteCardsForSource(String sourceItemId) async {
    cards.removeWhere((c) => c.sourceItemId == sourceItemId);
  }

  @override
  Future<int> countDue({DateTime? now}) async {
    final at = now ?? DateTime(2026, 1, 1);
    return cards.where((c) => c.isDueAt(at)).length;
  }
}

void main() {
  group('ReviewViewModel', () {
    late FakeReviewRepository repository;
    late ManualClock clock;
    late ProviderContainer container;
    final startTime = DateTime(2026, 1, 1, 12, 0, 0);

    ReviewViewModel vm() => container.read(reviewViewModelProvider.notifier);
    ReviewSessionState state() => container.read(reviewViewModelProvider);

    Future<void> seedDueCards(int count) async {
      for (var i = 0; i < count; i++) {
        await repository.createCard(
          cardType: CardType.sentence,
          sourceItemId: 'sentence-$i',
          promptText: '文 $i',
          answerText: 'Sentence $i',
          createdAt: startTime,
          dueAt: startTime,
        );
      }
    }

    setUp(() async {
      repository = FakeReviewRepository();
      clock = ManualClock(startTime);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      container = ProviderContainer(
        overrides: [
          reviewRepositoryProvider.overrideWithValue(repository),
          clockProvider.overrideWithValue(clock),
          // Settings and daily counts live in the local store, as in the app.
          srsSettingsRepositoryProvider.overrideWithValue(
            SrsSettingsRepository(
              LocalDocumentStore(prefs),
              FakeAuthRepository(),
            ),
          ),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is loading with no queue', () {
      expect(state().isLoading, isTrue);
      expect(state().queue, isEmpty);
      expect(state().currentCard, isNull);
    });

    test('startSession loads due cards into the queue', () async {
      await seedDueCards(3);

      await vm().startSession();

      final session = state();
      expect(session.isLoading, isFalse);
      expect(session.total, 3);
      expect(session.currentIndex, 0);
      expect(session.answerShown, isFalse);
      expect(session.isEmpty, isFalse);
      expect(session.currentCard!.promptText, '文 0');
    });

    test('startSession excludes cards that are not due yet', () async {
      await repository.createCard(
        cardType: CardType.sentence,
        sourceItemId: 'due',
        promptText: 'due',
        createdAt: startTime,
        dueAt: startTime,
      );
      // New cards have no due date (only the daily limit), so "not due yet"
      // means a review card scheduled for later.
      final later = await repository.createCard(
        cardType: CardType.sentence,
        sourceItemId: 'later',
        promptText: 'later',
        createdAt: startTime,
        dueAt: startTime.add(const Duration(days: 3)),
      );
      await repository.saveCard(
        later.copyWith(state: CardState.review, intervalDays: 3),
      );

      await vm().startSession();

      expect(state().total, 1);
      expect(state().currentCard!.promptText, 'due');
    });

    test('startSession with nothing due reports the empty state', () async {
      await vm().startSession();

      expect(state().isEmpty, isTrue);
      expect(state().isComplete, isFalse);
      expect(state().total, 0);
    });

    test('showAnswer reveals the answer', () async {
      await seedDueCards(1);
      await vm().startSession();

      expect(state().answerShown, isFalse);

      vm().showAnswer();

      expect(state().answerShown, isTrue);
    });

    test('showAnswer does nothing without a current card', () {
      vm().showAnswer();

      expect(state().answerShown, isFalse);
    });

    test('good on a new card moves it to the next learning step', () async {
      await seedDueCards(1);
      await vm().startSession();

      await vm().submitAnswer(Rating.good);

      final card = repository.cards.single;
      expect(card.state, CardState.learning);
      expect(card.step, 1);
      expect(card.repetitions, 1);
      expect(card.dueAt, startTime.add(const Duration(minutes: 10)));
      expect(repository.history.single.rating, Rating.good);
      expect(repository.history.single.intervalDaysAfter, 0);
      expect(repository.history.single.reviewedAt, startTime);
    });

    test('easy on a new card graduates it straight to review', () async {
      await seedDueCards(1);
      await vm().startSession();

      await vm().submitAnswer(Rating.easy);

      final card = repository.cards.single;
      expect(card.state, CardState.review);
      expect(card.intervalDays, 4);
      expect(card.dueAt, startTime.add(const Duration(days: 4)));
    });

    test('submitAnswer advances to the next card', () async {
      await seedDueCards(2);
      await vm().startSession();

      await vm().submitAnswer(Rating.hard);

      expect(state().currentIndex, 1);
      expect(state().reviewedThisSession, 1);
      expect(state().answerShown, isFalse);
      expect(state().currentCard!.promptText, '文 1');
      expect(state().isComplete, isFalse);
    });

    test('completing the session reports every card reviewed', () async {
      await seedDueCards(2);
      await vm().startSession();

      await vm().submitAnswer(Rating.easy);
      await vm().submitAnswer(Rating.easy);

      expect(state().isComplete, isTrue);
      expect(state().currentCard, isNull);
      expect(state().reviewedThisSession, 2);
      expect(state().progress, 1.0);
      expect(repository.history.length, 2);
    });

    test('a card still learning comes back in the same session', () async {
      await seedDueCards(1);
      await vm().startSession();

      await vm().submitAnswer(Rating.again);

      final card = repository.cards.single;
      expect(card.state, CardState.learning);
      expect(card.step, 0);
      expect(card.dueAt, startTime.add(const Duration(minutes: 1)));
      expect(state().isComplete, isFalse);
      expect(state().currentCard!.id, card.id);
      expect(state().total, 2);
    });

    test('daily new card limit caps the queue', () async {
      await seedDueCards(25);

      await vm().startSession();

      expect(state().total, 20);
    });

    test('a reviewed card leaves the due queue until it comes back', () async {
      await seedDueCards(1);
      await vm().startSession();
      await vm().submitAnswer(Rating.easy);

      await vm().refreshDue();

      expect(state().isEmpty, isTrue);
    });

    test('previewDelay matches what the scheduler will apply', () async {
      await seedDueCards(1);
      await vm().startSession();

      expect(vm().previewDelay(Rating.again), const Duration(minutes: 1));
      expect(vm().previewDelay(Rating.hard), const Duration(seconds: 330));
      expect(vm().previewDelay(Rating.good), const Duration(minutes: 10));
      expect(vm().previewDelay(Rating.easy), const Duration(days: 4));
    });

    test('previewDelay is zero without a current card', () async {
      expect(vm().previewDelay(Rating.good), Duration.zero);
    });

    test('submitAnswer does nothing without a current card', () async {
      await vm().startSession();

      await vm().submitAnswer(Rating.good);

      expect(repository.history, isEmpty);
      expect(state().reviewedThisSession, 0);
    });

    test('the next card shows before the answer is saved', () async {
      await seedDueCards(2);
      await vm().startSession();

      final saved = vm().submitAnswer(Rating.easy);

      expect(state().currentIndex, 1);
      expect(repository.history, isEmpty);
      await saved;
      expect(repository.history.length, 1);
    });

    test('undo returns to the previous card and restores it', () async {
      await seedDueCards(2);
      await vm().startSession();
      final before = repository.cards.first;
      await vm().submitAnswer(Rating.easy);

      await vm().undo();

      expect(state().currentIndex, 0);
      expect(state().currentCard!.id, before.id);
      expect(state().reviewedThisSession, 0);
      expect(state().answerShown, isFalse);
      expect(repository.cards.first.state, CardState.newCard);
      expect(repository.history, isEmpty);
      expect(vm().canUndo, isFalse);
    });

    test('undo takes back a card that was put back in the queue', () async {
      await seedDueCards(1);
      await vm().startSession();
      await vm().submitAnswer(Rating.again);
      expect(state().total, 2);

      await vm().undo();

      expect(state().total, 1);
      expect(state().currentIndex, 0);
    });

    test('undo steps back through several answers', () async {
      await seedDueCards(3);
      await vm().startSession();
      await vm().submitAnswer(Rating.easy);
      await vm().submitAnswer(Rating.easy);

      await vm().undo();
      await vm().undo();

      expect(state().currentIndex, 0);
      expect(vm().canUndo, isFalse);
      await vm().undo();
      expect(state().currentIndex, 0);
    });

    test('the due count follows today\'s queue', () async {
      await seedDueCards(2);

      expect(await container.read(dueCountProvider.future), 2);

      await vm().startSession();
      await vm().submitAnswer(Rating.easy);
      container.invalidate(dueCountProvider);

      expect(await container.read(dueCountProvider.future), 1);
    });
  });

  group('ReviewSessionState', () {
    test('progress is zero for an empty queue', () {
      expect(const ReviewSessionState().progress, 0);
    });

    test('progress tracks the current index', () {
      final epoch = DateTime(2026);
      final state = ReviewSessionState(
        queue: [
          ReviewCard(
            id: 'a',
            uid: 'u',
            cardType: CardType.sentence,
            sourceItemId: 's',
            promptText: 'a',
            createdAt: epoch,
            dueAt: epoch,
          ),
          ReviewCard(
            id: 'b',
            uid: 'u',
            cardType: CardType.sentence,
            sourceItemId: 's',
            promptText: 'b',
            createdAt: epoch,
            dueAt: epoch,
          ),
        ],
      );

      expect(state.progress, 0);
      expect(state.currentCard!.id, 'a');
      expect(state.copyWith(currentIndex: 1).currentCard!.id, 'b');
    });
  });
}
