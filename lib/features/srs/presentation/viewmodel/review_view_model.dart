import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/utils/clock.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/srs/data/deck_repository.dart';
import 'package:ingrain/features/srs/data/local_review_repository.dart';
import 'package:ingrain/features/srs/data/srs_settings_repository.dart';
import 'package:ingrain/features/srs/domain/deck.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_repository.dart';
import 'package:ingrain/features/srs/domain/srs_scheduler.dart';
import 'package:ingrain/features/srs/domain/srs_settings.dart';
import 'package:ingrain/features/srs/domain/study_queue.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  final store = ref.watch(documentStoreProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  return LocalReviewRepository(store, authRepo);
});

final deckRepositoryProvider = Provider<DeckRepository>((ref) {
  return DeckRepository(
    ref.watch(documentStoreProvider),
    ref.watch(authRepositoryProvider),
    ref.watch(reviewRepositoryProvider),
  );
});

final srsSettingsRepositoryProvider = Provider<SrsSettingsRepository>((ref) {
  return SrsSettingsRepository(
    ref.watch(documentStoreProvider),
    ref.watch(authRepositoryProvider),
  );
});

/// The scheduler settings the learner chose (Anki's defaults until then).
final srsSettingsProvider =
    AsyncNotifierProvider<SrsSettingsNotifier, SrsSettings>(
      SrsSettingsNotifier.new,
    );

class SrsSettingsNotifier extends AsyncNotifier<SrsSettings> {
  @override
  Future<SrsSettings> build() async {
    try {
      return await ref.watch(srsSettingsRepositoryProvider).load();
    } catch (_) {
      // Studying must never be blocked by a settings read.
      return const SrsSettings();
    }
  }

  Future<void> save(SrsSettings settings) async {
    state = AsyncData(settings);
    await ref.read(srsSettingsRepositoryProvider).save(settings);
    ref.invalidate(deckSummariesProvider);
    ref.invalidate(deckDetailProvider);
    ref.invalidate(dueCountProvider);
  }

  Future<void> resetToDefaults() => save(const SrsSettings());
}

/// Today's study queue for one deck, or every deck when [deckId] is null.
///
/// Computed on demand rather than cached in a provider, so whoever refreshes
/// after a change (a review, an import, a deletion) always gets fresh counts.
/// Cheap: the card list is cached in memory by the review repository.
///
/// [settings] is passed in rather than read here: a provider must await its
/// settings through `ref.watch(srsSettingsProvider.future)`, or the settings
/// finishing their first load would restart it mid-flight.
Future<StudyQueue> buildStudyQueue(
  Ref ref,
  SrsSettings settings, {
  String? deckId,
}) async {
  final now = ref.read(clockProvider).now;
  final (cards, studied) = await (
    ref.read(reviewRepositoryProvider).listAllCards(),
    _studiedToday(ref, now),
  ).wait;
  return StudyQueue.build(
    cards: cards,
    settings: settings,
    studiedToday: studied,
    now: now,
    deckId: deckId,
  );
}

Future<Map<String, DailyStudyCounts>> _studiedToday(
  Ref ref,
  DateTime now,
) async {
  try {
    return await ref.read(srsSettingsRepositoryProvider).countsFor(now);
  } catch (_) {
    return const {};
  }
}

/// Every deck with its counts, for the Flashcards tab.
final deckSummariesProvider = FutureProvider<List<DeckSummary>>((ref) async {
  final decks = await ref.watch(deckRepositoryProvider).listDecks();
  final cards = await ref.watch(reviewRepositoryProvider).listAllCards();
  final settings = await ref.watch(srsSettingsProvider.future);
  final queue = await buildStudyQueue(ref, settings);
  return [for (final deck in decks) DeckSummary.of(deck, cards, queue)];
});

/// One deck and its cards, newest first. Null when the deck is gone.
final deckDetailProvider =
    FutureProvider.family<(DeckSummary, List<ReviewCard>)?, String>((
      ref,
      deckId,
    ) async {
      final repository = ref.watch(deckRepositoryProvider);
      final deck = await repository.getDeck(deckId);
      if (deck == null) return null;
      final cards = await repository.cardsIn(deckId);
      final settings = await ref.watch(srsSettingsProvider.future);
      final queue = await buildStudyQueue(ref, settings, deckId: deckId);
      return (DeckSummary.of(deck, cards, queue), cards);
    });

class ReviewSessionState {
  final List<ReviewCard> queue;
  final int currentIndex;
  final bool answerShown;
  final bool isLoading;
  final int reviewedThisSession;

  /// The deck being studied, or null for every deck.
  final String? deckId;

  const ReviewSessionState({
    this.deckId,
    this.queue = const [],
    this.currentIndex = 0,
    this.answerShown = false,
    this.isLoading = false,
    this.reviewedThisSession = 0,
  });

  ReviewCard? get currentCard =>
      currentIndex < queue.length ? queue[currentIndex] : null;

  bool get isEmpty => !isLoading && queue.isEmpty;

  bool get isComplete => queue.isNotEmpty && currentIndex >= queue.length;

  int get total => queue.length;

  double get progress =>
      queue.isEmpty ? 0 : (currentIndex / queue.length).clamp(0.0, 1.0);

  ReviewSessionState copyWith({
    List<ReviewCard>? queue,
    int? currentIndex,
    bool? answerShown,
    bool? isLoading,
    int? reviewedThisSession,
  }) {
    return ReviewSessionState(
      deckId: deckId,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      answerShown: answerShown ?? this.answerShown,
      isLoading: isLoading ?? this.isLoading,
      reviewedThisSession: reviewedThisSession ?? this.reviewedThisSession,
    );
  }
}

final reviewViewModelProvider =
    NotifierProvider<ReviewViewModel, ReviewSessionState>(ReviewViewModel.new);

/// What one answer changed, so [ReviewViewModel.undo] can put it back.
class _AnsweredCard {
  _AnsweredCard({
    required this.before,
    required this.at,
    required this.requeued,
  });

  /// The card as it was before the answer.
  final ReviewCard before;
  final DateTime at;

  /// The answer put the card back at the end of the queue (still learning).
  final bool requeued;

  /// Set once the review log entry is saved, so an undo can delete it.
  String? eventId;
}

class ReviewViewModel extends Notifier<ReviewSessionState> {
  late ReviewRepository _repository;
  late Clock _clock;
  SrsScheduler _scheduler = const SrsScheduler();
  final List<_AnsweredCard> _answered = [];

  /// Saves queued behind each other, so an undo can never overtake the answer
  /// it takes back. The screen moves on without waiting for any of them.
  Future<void> _writes = Future.value();

  @override
  ReviewSessionState build() {
    _repository = ref.watch(reviewRepositoryProvider);
    _clock = ref.watch(clockProvider);
    return const ReviewSessionState(isLoading: true);
  }

  /// Loads today's queue for [deckId] (every deck when null) and resets the
  /// session. Settings are read here, not watched: changing them must not
  /// throw away a session in progress.
  Future<void> startSession({String? deckId}) async {
    state = ReviewSessionState(deckId: deckId, isLoading: true);
    _answered.clear();
    // Start the card read now; it runs alongside the settings read instead of
    // after it, and the queue below shares it.
    unawaited(_repository.listAllCards().then((_) {}, onError: (_) {}));
    final settings = await ref.read(srsSettingsProvider.future);
    final queue = await buildStudyQueue(ref, settings, deckId: deckId);
    _scheduler = SrsScheduler(settings);
    state = ReviewSessionState(deckId: deckId, queue: queue.cards);
  }

  /// Reloads the same deck.
  Future<void> refreshDue() => startSession(deckId: state.deckId);

  void showAnswer() {
    if (state.currentCard == null) return;
    state = state.copyWith(answerShown: true);
  }

  bool get canUndo => _answered.isNotEmpty;

  /// Runs [write] after every earlier save, whatever became of those. The
  /// returned future carries this write's own outcome.
  Future<void> _enqueue(Future<void> Function() write) {
    final run = _writes.then((_) => write());
    _writes = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Completes once everything saved so far has reached storage.
  Future<void> get settled => _writes;

  /// Moves to the next card straight away; the answer is saved in the
  /// background. The returned future completes when it has been saved.
  Future<void> submitAnswer(Rating rating) {
    final card = state.currentCard;
    if (card == null) return Future.value();

    final now = _clock.now;
    final updated = _scheduler.schedule(card, rating, now);

    // Like Anki, a card still in its learning steps comes back in this
    // session once its few minutes are up, after the cards already waiting.
    final comesBack =
        updated.state.isLearning &&
        updated.dueAt.isBefore(now.add(StudyQueue.learnAhead));
    final entry = _AnsweredCard(before: card, at: now, requeued: comesBack);
    _answered.add(entry);
    state = state.copyWith(
      queue: comesBack ? [...state.queue, updated] : null,
      currentIndex: state.currentIndex + 1,
      answerShown: false,
      reviewedThisSession: state.reviewedThisSession + 1,
    );

    return _enqueue(() async {
      await _repository.saveCard(updated);
      final event = await _repository.recordReview(
        cardId: updated.id,
        cardType: updated.cardType,
        rating: rating,
        reviewedAt: now,
        intervalDaysAfter: updated.intervalDays,
      );
      entry.eventId = event.id;
      try {
        await ref
            .read(srsSettingsRepositoryProvider)
            .recordStudied(
              now,
              card.deckId,
              wasNew: card.state == CardState.newCard,
              wasReview: card.state == CardState.review,
            );
      } catch (_) {
        // Limits are a convenience; a failed count must not lose the answer.
      }
    });
  }

  /// Goes back to the card answered last, as it was before, and takes that
  /// answer out of the schedule, the review log and today's limits.
  Future<void> undo() {
    if (_answered.isEmpty || state.isLoading) return Future.value();
    final entry = _answered.removeLast();
    final queue = entry.requeued
        ? state.queue.sublist(0, state.queue.length - 1)
        : null;
    state = state.copyWith(
      queue: queue,
      currentIndex: state.currentIndex - 1,
      answerShown: false,
      reviewedThisSession: state.reviewedThisSession - 1,
    );

    final card = entry.before;
    return _enqueue(() async {
      await _repository.saveCard(card);
      final eventId = entry.eventId;
      if (eventId != null) await _repository.deleteReviewEvent(eventId);
      try {
        await ref
            .read(srsSettingsRepositoryProvider)
            .unrecordStudied(
              entry.at,
              card.deckId,
              wasNew: card.state == CardState.newCard,
              wasReview: card.state == CardState.review,
            );
      } catch (_) {}
    });
  }

  /// When the current card would come back for each answer, shown on the
  /// answer buttons so the schedule is never a mystery.
  Duration previewDelay(Rating rating) {
    final card = state.currentCard;
    if (card == null) return Duration.zero;
    return _scheduler.nextDelay(card, rating, _clock.now);
  }
}

/// Badge count for the navigation destination, refreshable from any screen.
final dueCountProvider = FutureProvider<int>((ref) async {
  final settings = await ref.watch(srsSettingsProvider.future);
  return (await buildStudyQueue(ref, settings)).total;
});
