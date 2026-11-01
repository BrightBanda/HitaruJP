import 'dart:math';

import 'package:ingrain/core/storage/document_store.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';
import 'package:ingrain/features/srs/data/review_card_dto.dart';
import 'package:ingrain/features/srs/data/review_event_dto.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_event.dart';
import 'package:ingrain/features/srs/domain/review_repository.dart';

class LocalReviewRepository implements ReviewRepository {
  final DocumentStore _store;
  final AuthRepository _auth;

  LocalReviewRepository(this._store, this._auth);

  /// Every card of [_cacheUid], loaded once and kept in step with each write.
  /// Screens list all cards often; an imported Anki deck can hold thousands,
  /// and re-reading them each time would burn through Firestore's daily read
  /// quota. Keyed by user so a different sign-in never sees stale cards.
  List<ReviewCard>? _cache;
  String? _cacheUid;
  Future<List<ReviewCard>>? _loading;
  String? _loadingUid;

  /// Bulk saves go out in chunks this size, so progress can be reported.
  static const saveChunkSize = 500;

  void _remember(Iterable<ReviewCard> cards) {
    final cache = _cache;
    if (cache == null) return;
    final byId = {for (final card in cards) card.id: card};
    cache.removeWhere((card) => byId.containsKey(card.id));
    cache.addAll(byId.values);
  }

  static const String cardCollection = 'reviewCards';
  static const String historyCollection = 'reviewHistory';

  static String generateId(String prefix) {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final rand = Random.secure().nextInt(0xFFFFFF);
    return '$prefix-${ms.toRadixString(36)}-$rand';
  }

  @override
  Future<ReviewCard> createCard({
    required CardType cardType,
    required String sourceItemId,
    required String promptText,
    String? answerText,
    DateTime? createdAt,
    DateTime? dueAt,
  }) async {
    final uid = await _auth.ensureUid();
    final created = createdAt ?? DateTime.now();
    final card = ReviewCard(
      id: generateId('card'),
      uid: uid,
      cardType: cardType,
      sourceItemId: sourceItemId,
      promptText: promptText,
      answerText: _normalize(answerText),
      createdAt: created,
      dueAt: dueAt ?? created,
    );
    await _store.setDoc(uid, cardCollection, card.id, _toMap(card));
    _remember([card]);
    return card;
  }

  @override
  Future<void> saveCard(ReviewCard card) async {
    final uid = await _auth.ensureUid();
    // Remembered before the write is acknowledged, so the next read (the
    // study queue, the due badge) already sees it while the cloud catches up.
    _remember([card]);
    await _store.setDoc(uid, cardCollection, card.id, _toMap(card));
  }

  @override
  Future<void> saveCards(
    List<ReviewCard> cards, {
    void Function(int saved)? onProgress,
  }) async {
    final uid = await _auth.ensureUid();
    for (var start = 0; start < cards.length; start += saveChunkSize) {
      final chunk = cards.skip(start).take(saveChunkSize).toList();
      await _store.setDocs(uid, cardCollection, {
        for (final card in chunk) card.id: _toMap(card),
      });
      _remember(chunk);
      onProgress?.call(start + chunk.length);
    }
  }

  @override
  Future<List<ReviewCard>> listDue({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final cards = await listAllCards();
    final due = cards.where((c) => c.isDueAt(at)).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return due;
  }

  @override
  Future<List<ReviewCard>> listAllCards() async {
    final uid = await _auth.ensureUid();
    final cached = _cache;
    if (cached != null && _cacheUid == uid) return List.of(cached);
    // Callers that start a load early (to warm the cache) and callers that
    // need the cards a moment later share one read.
    final loading = _loading;
    if (loading != null && _loadingUid == uid) return List.of(await loading);
    final load = _load(uid);
    _loading = load;
    _loadingUid = uid;
    try {
      return List.of(await load);
    } finally {
      if (identical(_loading, load)) _loading = null;
    }
  }

  Future<List<ReviewCard>> _load(String uid) async {
    final docs = await _store.listDocs(uid, cardCollection);
    final cards = docs
        .map(ReviewCardDto.fromMapSafe)
        .whereType<ReviewCard>()
        .toList();
    _cache = cards;
    _cacheUid = uid;
    return cards;
  }

  @override
  Future<ReviewEvent> recordReview({
    required String cardId,
    required CardType cardType,
    required Rating rating,
    required DateTime reviewedAt,
    required int intervalDaysAfter,
  }) async {
    final uid = await _auth.ensureUid();
    final event = ReviewEvent(
      id: generateId('review'),
      uid: uid,
      cardId: cardId,
      cardType: cardType,
      rating: rating,
      reviewedAt: reviewedAt,
      intervalDaysAfter: intervalDaysAfter,
    );
    final dto = ReviewEventDto(
      id: event.id,
      uid: event.uid,
      cardId: event.cardId,
      cardType: event.cardType,
      rating: event.rating,
      reviewedAt: event.reviewedAt,
      intervalDaysAfter: event.intervalDaysAfter,
    );
    await _store.setDoc(uid, historyCollection, event.id, dto.map);
    return event;
  }

  @override
  Future<List<ReviewEvent>> listReviewHistory({int limit = 200}) async {
    final uid = await _auth.ensureUid();
    final docs = await _store.listDocs(uid, historyCollection);
    final events =
        docs.map(ReviewEventDto.fromMapSafe).whereType<ReviewEvent>().toList()
          ..sort((a, b) => b.reviewedAt.compareTo(a.reviewedAt));
    if (events.length > limit) {
      return events.sublist(0, limit);
    }
    return events;
  }

  @override
  Future<void> deleteReviewEvent(String eventId) async {
    final uid = await _auth.ensureUid();
    await _store.deleteDoc(uid, historyCollection, eventId);
  }

  @override
  Future<void> deleteCardsForSource(String sourceItemId) async {
    final ids = [
      for (final card in await listAllCards())
        if (card.sourceItemId == sourceItemId) card.id,
    ];
    await deleteCards(ids);
  }

  @override
  Future<void> deleteCards(List<String> cardIds) async {
    if (cardIds.isEmpty) return;
    final uid = await _auth.ensureUid();
    await _store.deleteDocs(uid, cardCollection, cardIds);
    final gone = cardIds.toSet();
    _cache?.removeWhere((card) => gone.contains(card.id));
  }

  @override
  Future<int> countDue({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final cards = await listAllCards();
    return cards.where((c) => c.isDueAt(at)).length;
  }

  static Map<String, dynamic> _toMap(ReviewCard card) =>
      ReviewCardDto.fromDomain(card).map;

  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
