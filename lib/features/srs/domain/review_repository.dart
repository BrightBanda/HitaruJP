import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_event.dart';

abstract interface class ReviewRepository {
  Future<ReviewCard> createCard({
    required CardType cardType,
    required String sourceItemId,
    required String promptText,
    String? answerText,
    DateTime? createdAt,
    DateTime? dueAt,
  });

  Future<void> saveCard(ReviewCard card);

  /// Saves many cards in bulk (a deck import). [onProgress] is told how many
  /// are saved so far.
  Future<void> saveCards(
    List<ReviewCard> cards, {
    void Function(int saved)? onProgress,
  });

  Future<List<ReviewCard>> listDue({DateTime? now});

  Future<List<ReviewCard>> listAllCards();

  Future<ReviewEvent> recordReview({
    required String cardId,
    required CardType cardType,
    required Rating rating,
    required DateTime reviewedAt,
    required int intervalDaysAfter,
  });

  Future<List<ReviewEvent>> listReviewHistory({int limit});

  /// Removes one logged review (undoing an answer).
  Future<void> deleteReviewEvent(String eventId);

  Future<void> deleteCardsForSource(String sourceItemId);

  /// Deletes cards by id in bulk (deleting a whole deck).
  Future<void> deleteCards(List<String> cardIds);

  Future<int> countDue({DateTime? now});
}
