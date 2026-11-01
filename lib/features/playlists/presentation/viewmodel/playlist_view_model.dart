import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/playlists/data/playlist_repository.dart';
import 'package:ingrain/features/playlists/domain/playlist.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(
    ref.watch(documentStoreProvider),
    ref.watch(authRepositoryProvider),
  );
});

final playlistsProvider =
    AsyncNotifierProvider<PlaylistsNotifier, List<Playlist>>(
      PlaylistsNotifier.new,
    );

/// Recents, Favorites, then the learner's own playlists. The first two are
/// always there, even before anything is in them.
final allPlaylistsProvider = Provider<List<Playlist>>((ref) {
  final saved = ref.watch(playlistsProvider).value ?? const <Playlist>[];
  final library = ref.watch(contentViewModelProvider).value ?? const [];
  final now = ref.watch(clockProvider).now;

  final recent = [...library]
    ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
  final recents = Playlist(
    id: Playlist.recentsId,
    name: 'Recents',
    videoIds: [for (final item in recent.take(Playlist.recentsLimit)) item.id],
    createdAt: now,
    updatedAt: now,
  );
  final favorites =
      saved.where((playlist) => playlist.isFavorites).firstOrNull ??
      Playlist(
        id: Playlist.favoritesId,
        name: 'Favorites',
        createdAt: now,
        updatedAt: now,
      );
  return [
    recents,
    favorites.copyWith(name: 'Favorites'),
    for (final playlist in saved)
      if (!playlist.isFavorites) playlist,
  ];
});

/// One playlist by id; null once it is gone.
final playlistProvider = Provider.family<Playlist?, String>((ref, id) {
  return ref
      .watch(allPlaylistsProvider)
      .where((playlist) => playlist.id == id)
      .firstOrNull;
});

/// Whether a video is in Favorites.
final isFavoriteProvider = Provider.family<bool, String>((ref, videoId) {
  return ref
          .watch(playlistProvider(Playlist.favoritesId))
          ?.videoIds
          .contains(videoId) ??
      false;
});

/// Every change shows on screen first and is saved behind it, so the lists
/// never wait on the cloud.
class PlaylistsNotifier extends AsyncNotifier<List<Playlist>> {
  @override
  Future<List<Playlist>> build() =>
      ref.watch(playlistRepositoryProvider).listAll();

  PlaylistRepository get _repository => ref.read(playlistRepositoryProvider);

  List<Playlist> get _current => state.value ?? const [];

  Future<Playlist?> create(
    String name, {
    List<String> videoIds = const [],
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final now = ref.read(clockProvider).now;
    final playlist = Playlist(
      id:
          'playlist-${now.microsecondsSinceEpoch.toRadixString(36)}'
          '-${Random.secure().nextInt(0xFFFFF).toRadixString(36)}',
      name: trimmed,
      videoIds: videoIds,
      createdAt: now,
      updatedAt: now,
    );
    state = AsyncData([..._current, playlist]);
    await _repository.save(playlist);
    return playlist;
  }

  Future<void> rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _isBuiltIn(id)) return Future.value();
    return _change(id, (playlist) => playlist.copyWith(name: trimmed));
  }

  /// Appends [videoIds] that the playlist does not already hold.
  Future<void> addVideos(String id, Iterable<String> videoIds) {
    return _change(id, (playlist) {
      final held = playlist.videoIds.toSet();
      final added = [
        for (final videoId in videoIds)
          if (held.add(videoId)) videoId,
      ];
      return added.isEmpty
          ? playlist
          : playlist.copyWith(videoIds: [...playlist.videoIds, ...added]);
    });
  }

  Future<void> removeVideo(String id, String videoId) {
    return _change(
      id,
      (playlist) => playlist.copyWith(
        videoIds: [
          for (final held in playlist.videoIds)
            if (held != videoId) held,
        ],
      ),
    );
  }

  /// Puts the videos in [order] first, in that order. Any the playlist holds
  /// that are not named (hidden because they left the library) follow.
  Future<void> setOrder(String id, List<String> order) {
    return _change(id, (playlist) {
      final named = order.toSet();
      return playlist.copyWith(
        videoIds: [
          ...order,
          for (final held in playlist.videoIds)
            if (!named.contains(held)) held,
        ],
      );
    });
  }

  Future<void> delete(String id) async {
    if (_isBuiltIn(id)) return;
    state = AsyncData([
      for (final playlist in _current)
        if (playlist.id != id) playlist,
    ]);
    await _repository.delete(id);
  }

  static bool _isBuiltIn(String id) =>
      id == Playlist.favoritesId || id == Playlist.recentsId;

  /// Adds the video to Favorites, or takes it out when it is already there.
  Future<void> toggleFavorite(String videoId) {
    final held =
        _current
            .where((playlist) => playlist.isFavorites)
            .firstOrNull
            ?.videoIds
            .contains(videoId) ??
        false;
    return held
        ? removeVideo(Playlist.favoritesId, videoId)
        : addVideos(Playlist.favoritesId, [videoId]);
  }

  Future<void> _change(String id, Playlist Function(Playlist) change) async {
    if (id == Playlist.recentsId) return;
    // Favorites exists from the start but is only saved once it is used.
    if (id == Playlist.favoritesId && !_current.any((p) => p.id == id)) {
      final now = ref.read(clockProvider).now;
      state = AsyncData([
        ..._current,
        Playlist(id: id, name: 'Favorites', createdAt: now, updatedAt: now),
      ]);
    }
    Playlist? changed;
    state = AsyncData([
      for (final playlist in _current)
        if (playlist.id == id)
          changed = _stamp(change(playlist), playlist)
        else
          playlist,
    ]);
    if (changed != null) await _repository.save(changed);
  }

  Playlist _stamp(Playlist next, Playlist previous) => identical(next, previous)
      ? previous
      : next.copyWith(updatedAt: ref.read(clockProvider).now);
}
