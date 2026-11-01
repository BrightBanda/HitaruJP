import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/storage/local_document_store.dart';
import 'package:ingrain/features/content/data/local_content_repository.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/playlists/data/playlist_repository.dart';
import 'package:ingrain/features/playlists/domain/playlist.dart';
import 'package:ingrain/features/playlists/presentation/viewmodel/playlist_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

void main() {
  builtInPlaylists();

  late ProviderContainer container;
  late LocalDocumentStore store;

  PlaylistsNotifier notifier() => container.read(playlistsProvider.notifier);
  List<String> ids(String id) => container.read(playlistProvider(id))!.videoIds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = LocalDocumentStore(await SharedPreferences.getInstance());
    container = ProviderContainer(
      overrides: [
        playlistRepositoryProvider.overrideWithValue(
          PlaylistRepository(store, FakeAuthRepository()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(playlistsProvider.future);
  });

  test('a new playlist is listed and saved', () async {
    final created = await notifier().create('  Anime  ', videoIds: ['a']);

    expect(created!.name, 'Anime');
    expect(container.read(playlistsProvider).value!.single.videoIds, ['a']);

    final reloaded = await PlaylistRepository(
      store,
      FakeAuthRepository(),
    ).listAll();
    expect(reloaded.single.name, 'Anime');
    expect(reloaded.single.videoIds, ['a']);
  });

  test('a blank name makes no playlist', () async {
    expect(await notifier().create('   '), isNull);
    expect(container.read(playlistsProvider).value, isEmpty);
  });

  test('adding skips videos already in the playlist', () async {
    final id = (await notifier().create('News', videoIds: ['a']))!.id;

    await notifier().addVideos(id, ['a', 'b', 'b', 'c']);

    expect(ids(id), ['a', 'b', 'c']);
  });

  test('removing and reordering keep the rest in order', () async {
    final id = (await notifier().create('Mix', videoIds: ['a', 'b', 'c']))!.id;

    await notifier().removeVideo(id, 'b');
    expect(ids(id), ['a', 'c']);

    await notifier().setOrder(id, ['c', 'a']);
    expect(ids(id), ['c', 'a']);
  });

  test('reordering what is on screen keeps videos hidden from view', () async {
    final id = (await notifier().create(
      'Mix',
      videoIds: ['a', 'gone', 'b'],
    ))!.id;

    await notifier().setOrder(id, ['b', 'a']);

    expect(ids(id), ['b', 'a', 'gone']);
  });

  test('rename and delete are saved', () async {
    final id = (await notifier().create('Old'))!.id;
    await notifier().rename(id, 'New');
    expect(container.read(playlistProvider(id))!.name, 'New');

    await notifier().delete(id);

    expect(container.read(playlistProvider(id)), isNull);
    final repository = PlaylistRepository(store, FakeAuthRepository());
    expect(await repository.listAll(), isEmpty);
  });
}

// Recents and Favorites, against the app's usual test storage.
void builtInPlaylists() {
  group('built-in playlists', () {
    late ProviderContainer container;
    late LocalContentRepository content;

    PlaylistsNotifier notifier() => container.read(playlistsProvider.notifier);

    /// Returns the id the library gave the video.
    Future<String> addVideo(String name, DateTime lastOpened) async {
      final item = await content.create(
        sourceUrl: 'https://www.youtube.com/watch?v=$name',
        title: name,
      );
      await content.save(item.copyWith(lastOpenedAt: lastOpened));
      return item.id;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: appTestOverrides(prefs));
      addTearDown(container.dispose);
      content =
          container.read(contentRepositoryProvider) as LocalContentRepository;
    });

    Future<void> load() async {
      await container.read(contentViewModelProvider.future);
      await container.read(playlistsProvider.future);
    }

    test('Recents and Favorites are always the first two', () async {
      await load();

      final all = container.read(allPlaylistsProvider);

      expect(all.map((p) => p.id), [Playlist.recentsId, Playlist.favoritesId]);
      expect(all.every((p) => p.isBuiltIn), isTrue);
    });

    test('Recents lists the latest watched first, up to the limit', () async {
      String? newest;
      for (var i = 0; i < Playlist.recentsLimit + 3; i++) {
        newest = await addVideo(
          'video$i',
          DateTime(2026, 1, 1).add(Duration(days: i)),
        );
      }
      await load();

      final recents = container.read(playlistProvider(Playlist.recentsId))!;

      expect(recents.videoIds, hasLength(Playlist.recentsLimit));
      expect(recents.videoIds.first, newest);
    });

    test('Recents cannot be changed', () async {
      final id = await addVideo('a', DateTime(2026, 1, 1));
      await load();

      await notifier().addVideos(Playlist.recentsId, ['b']);
      await notifier().removeVideo(Playlist.recentsId, id);

      expect(container.read(playlistProvider(Playlist.recentsId))!.videoIds, [
        id,
      ]);
      expect(container.read(playlistsProvider).value, isEmpty);
    });

    test('toggling a favorite adds then removes it', () async {
      await load();

      await notifier().toggleFavorite('a');
      expect(container.read(isFavoriteProvider('a')), isTrue);

      await notifier().toggleFavorite('a');
      expect(container.read(isFavoriteProvider('a')), isFalse);
    });

    test('Favorites cannot be renamed or deleted', () async {
      await load();
      await notifier().toggleFavorite('a');

      await notifier().rename(Playlist.favoritesId, 'Mine');
      await notifier().delete(Playlist.favoritesId);

      final favorites = container.read(playlistProvider(Playlist.favoritesId))!;
      expect(favorites.name, 'Favorites');
      expect(favorites.videoIds, ['a']);
    });

    test('your own playlists follow the built-in ones', () async {
      await load();
      await notifier().create('Anime');

      expect(container.read(allPlaylistsProvider).map((p) => p.name), [
        'Recents',
        'Favorites',
        'Anime',
      ]);
    });
  });
}
