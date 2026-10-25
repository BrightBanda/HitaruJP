import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/storage/snapshot_cache.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/content/data/content_item_dto.dart';
import 'package:ingrain/features/content/data/local_content_repository.dart';
import 'package:ingrain/features/content/data/remote_video_search_repository.dart';
import 'package:ingrain/features/content/data/remote_youtube_transcript_fetcher.dart';
import 'package:ingrain/features/content/data/transcript_parser.dart';
import 'package:ingrain/features/content/data/youtube_transcript_fetcher.dart';
import 'package:ingrain/features/content/data/youtube_url_parser.dart';
import 'package:ingrain/features/content/data/youtube_video_search_repository.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/domain/content_repository.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/content/domain/video_search.dart';

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  final store = ref.watch(documentStoreProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  return LocalContentRepository(store, authRepo);
});

final youtubeTranscriptFetcherProvider = Provider<YoutubeTranscriptFetcher>((
  ref,
) {
  // Browsers block calls to YouTube (CORS), so web fetches captions through
  // the API; mobile asks YouTube directly.
  if (kIsWeb) {
    return RemoteYoutubeTranscriptFetcher(ref.watch(apiClientProvider));
  }
  return YoutubeTranscriptFetcher();
});

class ContentViewModel extends AsyncNotifier<List<ContentItem>> {
  late ContentRepository _repository;

  /// Paints the library saved on this device at once, then replaces it with
  /// Firestore's copy when that arrives.
  @override
  FutureOr<List<ContentItem>> build() {
    _repository = ref.watch(contentRepositoryProvider);
    final cached = _readSnapshot();
    if (cached == null) return _fetch();
    Future.microtask(() async {
      try {
        final fresh = await _fetch();
        if (ref.mounted) state = AsyncData(fresh);
      } catch (_) {
        // Offline: the saved copy stays up.
      }
    });
    return cached;
  }

  /// Reloads in place: the list on screen stays up until the new one is in,
  /// instead of the page flashing back to its loading state.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  String? get _snapshotKey {
    final uid = ref.read(authRepositoryProvider).currentUid;
    return uid == null ? null : 'content_$uid';
  }

  List<ContentItem>? _readSnapshot() {
    final key = _snapshotKey;
    if (key == null) return null;
    return ref
        .read(snapshotCacheProvider)
        .read(
          key,
          (json) => [
            for (final doc in json as List)
              ContentItemDto.fromMap(Map<String, dynamic>.from(doc as Map))
                  .toDomain(),
          ],
        );
  }

  Future<List<ContentItem>> _fetch() async {
    final items = await _repository.watchAll().first;
    final key = _snapshotKey;
    if (key != null) {
      unawaited(
        ref.read(snapshotCacheProvider).write(key, [
          for (final item in items) ContentItemDto.fromDomain(item).map,
        ]),
      );
    }
    return items;
  }

  Future<ContentItem?> addContent({
    required String sourceUrl,
    required String title,
  }) async {
    try {
      YoutubeUrlParser.parse(sourceUrl);
      final item = await _repository.create(sourceUrl: sourceUrl, title: title);
      await refresh();
      return item;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<ContentItem?> addContentWithTranscript({
    required String sourceUrl,
    required String title,
    required int durationSeconds,
    required String transcriptText,
  }) async {
    try {
      YoutubeUrlParser.parse(sourceUrl);
      final item = await _repository.create(sourceUrl: sourceUrl, title: title);
      final updatedItem = item.copyWith(durationSeconds: durationSeconds);
      await _repository.save(updatedItem);

      final sentences = TranscriptParser.parse(
        transcriptText,
        durationSeconds: durationSeconds,
        format: TranscriptFormat.srt,
      );
      await _repository.saveTranscript(item.id, sentences);

      await refresh();
      return updatedItem;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  /// Puts a YouTube video in the library together with its Japanese
  /// transcript, or returns the entry that is already there. A video without
  /// Japanese captions is still added; [YoutubeImport.hasTranscript] says so.
  Future<YoutubeImport> importYoutubeVideo(VideoSearchResult video) async {
    final library = state.value ?? await _repository.watchAll().first;
    final existing = library.where((i) => i.id == video.videoId).firstOrNull;
    if (existing != null) {
      final transcript = await _repository.getTranscript(existing.id);
      return YoutubeImport(
        existing,
        hasTranscript: transcript.isNotEmpty,
        wasInLibrary: true,
      );
    }

    final (:fetched, :error) = await _fetchTranscript(video.videoId);

    // A fetcher that cannot tell the length (the web one) reports 0; keep the
    // length search already gave us rather than overwrite it.
    final fetchedSeconds = fetched?.durationSeconds ?? 0;
    final duration = fetchedSeconds > 0
        ? fetchedSeconds
        : video.duration?.inSeconds ?? 0;
    final created = await _repository.create(
      sourceUrl: video.url,
      title: video.title,
      channelTitle: video.channelTitle ?? fetched?.channelTitle,
      thumbnailUrl: video.thumbnailUrl,
    );
    final item = created.copyWith(durationSeconds: duration);
    await _repository.save(item);

    final hasTranscript = await _saveFetchedTranscript(item, fetched);
    await refresh();
    return YoutubeImport(
      item,
      hasTranscript: hasTranscript,
      transcriptError: error,
    );
  }

  /// Fetches the transcript again for a library video that came without one,
  /// such as after YouTube refused it. The id of a YouTube item is its video
  /// id.
  Future<YoutubeImport> refetchTranscript(String contentId) async {
    final item = await _repository.getContent(contentId);
    final (:fetched, :error) = await _fetchTranscript(contentId);
    final hasTranscript = await _saveFetchedTranscript(item, fetched);
    await refresh();
    return YoutubeImport(
      item,
      hasTranscript: hasTranscript,
      wasInLibrary: true,
      transcriptError: error,
    );
  }

  /// One fetch, no retries: a slow add is worse than a missing transcript,
  /// which the learner can fetch again or paste. A failure comes back as
  /// [error] rather than thrown: the video is still worth adding without it.
  Future<({YoutubeTranscriptResult? fetched, String? error})> _fetchTranscript(
    String videoId,
  ) async {
    try {
      final fetched = await ref
          .read(youtubeTranscriptFetcherProvider)
          .fetch(videoId);
      return (fetched: fetched, error: null);
    } on YoutubeTranscriptException catch (error) {
      return (fetched: null, error: error.message);
    }
  }

  /// Saves [fetched]'s text as [item]'s transcript; false when there is none.
  Future<bool> _saveFetchedTranscript(
    ContentItem item,
    YoutubeTranscriptResult? fetched,
  ) async {
    final text = fetched?.transcriptText;
    final hasTranscript = text != null && text.trim().isNotEmpty;
    if (hasTranscript) {
      await _repository.saveTranscript(
        item.id,
        TranscriptParser.parse(
          text,
          durationSeconds: item.durationSeconds ?? 0,
          format: TranscriptFormat.srt,
        ),
      );
    }
    ref.invalidate(transcriptProvider(item.id));
    ref.invalidate(contentItemProvider(item.id));
    return hasTranscript;
  }

  Future<void> deleteContent(String id) => deleteContents([id]);

  Future<void> deleteContents(Iterable<String> ids) async {
    for (final id in ids) {
      await _repository.delete(id);
      ref.invalidate(contentItemProvider(id));
      ref.invalidate(transcriptProvider(id));
    }
    await refresh();
  }

  Future<void> renameContent(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final item = await _repository.getContent(id);
    await _repository.save(item.copyWith(title: trimmed));
    ref.invalidate(contentItemProvider(id));
    await refresh();
  }

  Future<void> saveTranscript(
    String contentId,
    List<TranscriptSentence> sentences,
  ) async {
    await _repository.saveTranscript(contentId, sentences);
  }

  Future<List<TranscriptSentence>> getTranscript(String contentId) {
    return _repository.getTranscript(contentId);
  }
}

final contentViewModelProvider =
    AsyncNotifierProvider<ContentViewModel, List<ContentItem>>(
      ContentViewModel.new,
    );

final contentItemProvider = FutureProvider.family<ContentItem, String>((
  ref,
  id,
) {
  return ref.watch(contentRepositoryProvider).getContent(id);
});

final transcriptProvider =
    FutureProvider.family<List<TranscriptSentence>, String>((ref, contentId) {
      return ref.watch(contentRepositoryProvider).getTranscript(contentId);
    });

class YoutubeImport {
  final ContentItem item;
  final bool hasTranscript;

  /// True when the video was already saved and nothing was fetched.
  final bool wasInLibrary;

  /// Why the transcript could not be fetched, when every source failed. Null
  /// when it came, or when the video simply has no Japanese captions.
  final String? transcriptError;

  const YoutubeImport(
    this.item, {
    required this.hasTranscript,
    this.wasInLibrary = false,
    this.transcriptError,
  });
}

final videoSearchRepositoryProvider = Provider<VideoSearchRepository>((ref) {
  // Browsers block calls to youtube.com (CORS), so web searches through the
  // API; mobile asks YouTube directly.
  if (kIsWeb) return RemoteVideoSearchRepository(ref.watch(apiClientProvider));
  final repository = YoutubeVideoSearchRepository();
  ref.onDispose(repository.close);
  return repository;
});

/// The video id in [input] when it is a YouTube link or a bare video id, null
/// when it reads as a search. A bare 11-character word only counts as an id
/// if it has a digit, `-` or `_`, so "programming" is still searched for.
String? videoIdFromInput(String input) {
  final text = input.trim();
  if (text.contains('youtu') || text.contains('://')) {
    return YoutubeUrlParser.tryParse(text);
  }
  final looksLikeId =
      RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(text) &&
      RegExp(r'[0-9_-]').hasMatch(text);
  return looksLikeId ? text : null;
}

/// YouTube results for what was typed: the one video for a link or id,
/// otherwise a search. No automatic retry: YouTube throttles hammering.
final videoSearchProvider = FutureProvider.autoDispose
    .family<List<VideoSearchResult>, String>((ref, input) async {
      final repository = ref.watch(videoSearchRepositoryProvider);
      final videoId = videoIdFromInput(input);
      if (videoId != null) {
        final video = await repository.lookup(videoId);
        if (video != null) return [video];
      }
      return repository.search(input.trim());
    }, retry: (_, _) => null);
