import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/utils/clock.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/sentence_mining/presentation/viewmodel/sentence_mining_view_model.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/domain/review_repository.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/data/asset_dictionary_loader.dart';
import 'package:ingrain/features/vocabulary/data/local_vocabulary_repository.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/japanese_tokenizer.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_repository.dart';

final vocabularyRepositoryProvider = Provider<VocabularyRepository>((ref) {
  final store = ref.watch(documentStoreProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  return LocalVocabularyRepository(store, authRepo);
});

/// Bundled offline dictionary. A load failure degrades to an empty index so
/// the rest of the feature keeps working without a lookup.
final dictionaryProvider = FutureProvider<DictionaryIndex>((ref) async {
  try {
    return await const AssetDictionaryLoader().load();
  } catch (_) {
    return DictionaryIndex.empty;
  }
});

final vocabularyViewModelProvider =
    AsyncNotifierProvider<VocabularyViewModel, List<VocabularyItem>>(
      VocabularyViewModel.new,
    );

class VocabularyViewModel extends AsyncNotifier<List<VocabularyItem>> {
  late VocabularyRepository _repository;
  late ReviewRepository _reviewRepository;
  late Clock _clock;

  @override
  FutureOr<List<VocabularyItem>> build() async {
    _repository = ref.watch(vocabularyRepositoryProvider);
    _reviewRepository = ref.watch(reviewRepositoryProvider);
    _clock = ref.watch(clockProvider);
    return _repository.watchAll().first;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _repository.watchAll().first);
  }

  /// Saves a word and queues it for review.
  ///
  /// Saving a word that is already in the collection records an encounter on
  /// the existing item instead of creating a second document, and never
  /// duplicates its review card.
  Future<VocabularyItem?> saveWord({
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
    VocabState vocabState = VocabState.encountered,
  }) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return null;

    try {
      final existing = await _repository.findByWord(trimmed);
      final VocabularyItem saved;
      if (existing != null) {
        saved =
            (await _repository.recordEncounter(
              existing.id,
              encounteredAt: _clock.now,
            )) ??
            existing;
        await _enrich(saved.id, reading: reading, meaning: meaning, pos: pos);
      } else {
        saved = await _repository.save(
          word: trimmed,
          reading: reading,
          meaning: meaning,
          pos: pos,
          sourceType: sourceType,
          sourceId: sourceId,
          sourceTitle: sourceTitle,
          timestampSeconds: timestampSeconds,
          contextSentence: contextSentence,
          sessionId: sessionId,
          state: vocabState,
          createdAt: _clock.now,
        );
        await _createReviewCard(saved);
        ref.invalidate(dueCountProvider);
      }
      await refresh();
      return saved;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  /// Saves a word tapped in the transcript, carrying the source title and the
  /// surrounding context so the word keeps its immersion memory.
  Future<VocabularyItem?> saveFromTranscript({
    required String contentId,
    required String word,
    required TranscriptSentence sentence,
    required List<TranscriptSentence> transcript,
    String? contentTitle,
    String? sessionId,
    String? reading,
    String? meaning,
    String? pos,
  }) async {
    return saveWord(
      word: word,
      reading: reading,
      meaning: meaning,
      pos: pos,
      sourceType: SourceType.youtube,
      sourceId: contentId,
      sourceTitle: contentTitle,
      timestampSeconds: sentence.startSeconds,
      contextSentence: SentenceMiningViewModel.contextForTranscript(
        transcript,
        sentence.index,
      ),
      sessionId: sessionId,
    );
  }

  Future<void> setState(String id, VocabState next) async {
    final items = state.value;
    if (items == null) return;
    VocabularyItem? current;
    for (final item in items) {
      if (item.id == id) current = item;
    }
    if (current == null) return;

    await _repository.update(
      current.copyWith(state: next, updatedAt: _clock.now),
    );
    await refresh();
  }

  Future<void> deleteWord(String id) async {
    await _repository.delete(id);
    await _reviewRepository.deleteCardsForSource(id);
    ref.invalidate(dueCountProvider);
    await refresh();
  }

  /// Fills in dictionary details the saved word was missing, without ever
  /// overwriting something the learner already entered.
  Future<void> _enrich(
    String id, {
    String? reading,
    String? meaning,
    String? pos,
  }) async {
    final current = await _repository.get(id);
    if (current == null) return;

    final updates = current.copyWith(
      reading: () => current.reading ?? _normalize(reading),
      meaning: () => current.meaning ?? _normalize(meaning),
      pos: () => current.pos ?? _normalize(pos),
      updatedAt: _clock.now,
    );
    await _repository.update(updates);
  }

  Future<void> _createReviewCard(VocabularyItem item) async {
    await _reviewRepository.createCard(
      cardType: CardType.vocabulary,
      sourceItemId: item.id,
      promptText: item.word,
      answerText: VocabularyViewModel.answerFor(item),
      createdAt: item.createdAt,
    );
  }

  /// Back-of-card text for a vocabulary card: reading and meaning when known,
  /// otherwise the sentence the word was met in.
  static String? answerFor(VocabularyItem item) {
    final parts = [
      if (item.hasReading) item.reading,
      if (item.hasMeaning) item.meaning,
    ];
    if (parts.isNotEmpty) return parts.join(' — ');
    return item.contextSentence;
  }

  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Splits transcript text into tap targets using the bundled dictionary.
final transcriptTokenizerProvider = Provider<JapaneseTokenizer>((ref) {
  final dictionary = ref.watch(dictionaryProvider).value;
  return dictionary == null
      ? JapaneseTokenizer(const {})
      : JapaneseTokenizer.dictionary(dictionary);
});
