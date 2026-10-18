import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/lifecycle.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/catalog/data/remote_catalog_repository.dart';
import 'package:ingrain/features/catalog/domain/catalog_repository.dart';
import 'package:ingrain/features/catalog/domain/catalog_video.dart';
import 'package:ingrain/features/content/domain/video_search.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';
import 'package:ingrain/features/profile/presentation/viewmodel/profile_sync_providers.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => RemoteCatalogRepository(
    ref.watch(apiClientProvider),
    ref.watch(authRepositoryProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);

/// Today's recommended videos.
///
/// Picks already fetched today for the learner's level come from the device,
/// with no server call: the API can take long to wake, and they would not
/// change. Otherwise this waits for the profile sync first, so a learner who
/// just finished onboarding or changed their level gets picks for the level
/// they actually chose. Fetches again when the app returns to the foreground
/// on a new day.
final dailyPicksProvider = FutureProvider<DailyPicks>((ref) async {
  final repository = ref.watch(catalogRepositoryProvider);
  final level = ref.watch(
    authViewModelProvider.select((state) => state.profile?.level),
  );
  final cached = await repository.cachedDailyPicks();
  final DailyPicks picks;
  if (cached != null &&
      !cached.isStale(DateTime.now()) &&
      (level == null || cached.level == level)) {
    picks = cached;
  } else {
    await ref.watch(profileSyncProvider.future);
    picks = await repository.dailyPicks();
  }

  ref.listen(appLifecycleProvider, (_, next) {
    if (next == AppLifecycleState.resumed && picks.isStale(DateTime.now())) {
      ref.invalidateSelf();
    }
  });
  return picks;
}, retry: (_, _) => null);

/// More catalogue videos at the learner's level, for browsing past today's picks.
final levelVideosProvider = FutureProvider<List<CatalogVideo>>((ref) async {
  final level =
      ref.watch(
        authViewModelProvider.select((state) => state.profile?.level),
      ) ??
      JlptLevel.fallback;
  return ref.watch(catalogRepositoryProvider).videosAtLevel(level);
}, retry: (_, _) => null);

/// Opens catalogue videos in the immersion player.
///
/// The player works on library items, so a catalogue video is imported first
/// (with its Japanese transcript, when YouTube has one). The state is the set of
/// video ids currently being opened, so their cards can show progress.
class CatalogOpener extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Returns the library item's id, ready for `/content/<id>`, plus whether a
  /// transcript came with it and, when every source failed, why not.
  Future<({String contentId, bool hasTranscript, String? transcriptError})>
  open(CatalogVideo video) async {
    final youtubeId = video.youtubeId;
    if (youtubeId == null) {
      throw StateError('Only YouTube videos can be opened in the player.');
    }
    state = {...state, video.id};
    try {
      final imported = await ref
          .read(contentViewModelProvider.notifier)
          .importYoutubeVideo(
            VideoSearchResult(
              videoId: youtubeId,
              title: video.title,
              channelTitle: video.channelTitle,
              thumbnailUrl:
                  video.thumbnailUrl ??
                  'https://i.ytimg.com/vi/$youtubeId/hqdefault.jpg',
              duration: video.durationSeconds == null
                  ? null
                  : Duration(seconds: video.durationSeconds!),
            ),
          );
      unawaited(
        ref
            .read(profileSyncRepositoryProvider)
            .recordWatched(video.id)
            .catchError(
              (Object error) => debugPrint('Watch not recorded: $error'),
            ),
      );
      return (
        contentId: imported.item.id,
        hasTranscript: imported.hasTranscript,
        transcriptError: imported.transcriptError,
      );
    } finally {
      if (ref.mounted) state = {...state}..remove(video.id);
    }
  }
}

final catalogOpenerProvider = NotifierProvider<CatalogOpener, Set<String>>(
  CatalogOpener.new,
);
