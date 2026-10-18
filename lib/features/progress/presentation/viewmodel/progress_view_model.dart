import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/error/app_error.dart';
import 'package:ingrain/core/storage/snapshot_cache.dart';
import 'package:ingrain/core/utils/clock.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/immersion/domain/immersion_repository.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/progress/domain/progress_calculator.dart';
import 'package:ingrain/features/progress/domain/progress_summary.dart';
import 'package:ingrain/features/sentence_mining/domain/sentence_repository.dart';
import 'package:ingrain/features/sentence_mining/presentation/viewmodel/sentence_mining_view_model.dart';
import 'package:ingrain/features/settings/presentation/viewmodel/settings_view_model.dart';
import 'package:ingrain/features/srs/domain/review_repository.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';

class ProgressUiState {
  final bool isLoading;
  final ProgressSummary? summary;
  final AppError? error;

  const ProgressUiState._({required this.isLoading, this.summary, this.error});

  const ProgressUiState.loading() : this._(isLoading: true);

  const ProgressUiState.data(ProgressSummary summary)
    : this._(isLoading: false, summary: summary);

  const ProgressUiState.error(AppError error)
    : this._(isLoading: false, error: error);
}

final progressViewModelProvider =
    NotifierProvider<ProgressViewModel, ProgressUiState>(ProgressViewModel.new);

class ProgressViewModel extends Notifier<ProgressUiState> {
  static const ProgressCalculator _calculator = ProgressCalculator();

  late ImmersionRepository _immersionRepository;
  late SentenceRepository _sentenceRepository;
  late VocabularyRepository _vocabularyRepository;
  late ReviewRepository _reviewRepository;
  late Clock _clock;

  @override
  ProgressUiState build() {
    _immersionRepository = ref.watch(immersionRepositoryProvider);
    _sentenceRepository = ref.watch(sentenceRepositoryProvider);
    _vocabularyRepository = ref.watch(vocabularyRepositoryProvider);
    _reviewRepository = ref.watch(reviewRepositoryProvider);
    _clock = ref.watch(clockProvider);
    _load();
    // Last launch's numbers while today's are worked out; a summary from an
    // earlier day would show yesterday's minutes as today's, so it waits.
    final cached = _readSnapshot();
    return cached == null
        ? const ProgressUiState.loading()
        : ProgressUiState.data(cached);
  }

  String? get _snapshotKey {
    final uid = ref.read(authRepositoryProvider).currentUid;
    return uid == null ? null : 'progress_$uid';
  }

  ProgressSummary? _readSnapshot() {
    final key = _snapshotKey;
    if (key == null) return null;
    final snapshot = ref.read(snapshotCacheProvider).read(key, (json) {
      final map = Map<String, dynamic>.from(json as Map);
      return (
        day: DateTime.parse(map['day'] as String),
        summary: ProgressSummary.fromJson(
          Map<String, dynamic>.from(map['summary'] as Map),
        ),
      );
    });
    if (snapshot == null) return null;
    final now = _clock.now;
    final sameDay =
        snapshot.day.year == now.year &&
        snapshot.day.month == now.month &&
        snapshot.day.day == now.day;
    return sameDay ? snapshot.summary : null;
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    // Watched rather than read so the goal is correct even when settings are
    // still loading on first build: the dependency re-runs this ViewModel.
    final goalMinutes =
        ref.watch(settingsViewModelProvider).settings?.dailyGoalMinutes ?? 30;

    try {
      final now = _clock.now;
      // Independent reads, so they run side by side rather than paying five
      // round trips one after another.
      final sessionsFuture = _immersionRepository.watchRecentSessions().first;
      final sentencesFuture = _sentenceRepository.watchAll().first;
      final vocabularyFuture = _vocabularyRepository.watchAll().first;
      // Today's study queue, within the daily limits, so a freshly imported
      // deck of thousands of new cards does not read as thousands "due".
      final dueCardsFuture = ref
          .read(srsSettingsProvider.future)
          .then((settings) => buildStudyQueue(ref, settings))
          .then((queue) => queue.cards);
      final reviewEventsFuture = _reviewRepository.listReviewHistory();
      final (sessions, sentences, vocabulary, dueCards, reviewEvents) = await (
        sessionsFuture,
        sentencesFuture,
        vocabularyFuture,
        dueCardsFuture,
        reviewEventsFuture,
      ).wait;

      final summary = _calculator.summarize(
        sessions: sessions,
        sentences: sentences,
        vocabulary: vocabulary,
        dueCards: dueCards,
        reviewEvents: reviewEvents,
        today: now,
        dailyGoalMinutes: goalMinutes,
      );
      state = ProgressUiState.data(summary);
      final key = _snapshotKey;
      if (key != null) {
        unawaited(
          ref.read(snapshotCacheProvider).write(key, {
            'day': now.toIso8601String(),
            'summary': summary.toJson(),
          }),
        );
      }
    } catch (e, st) {
      state = ProgressUiState.error(
        AppError.unknown(e, message: st.toString()),
      );
    }
  }
}
