import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/playlists/domain/playlist.dart';
import 'package:ingrain/features/playlists/presentation/view/playlist_dialogs.dart';
import 'package:ingrain/features/playlists/presentation/viewmodel/playlist_view_model.dart';
import 'package:ingrain/shared/widgets/video_thumbnail.dart';

/// The learner's playlists in a sideways row on the Videos tab: a thumbnail
/// each, and a "Create playlist" tile at the end.
class PlaylistsStrip extends ConsumerWidget {
  const PlaylistsStrip({super.key});

  static const _tileWidth = 150.0;
  static const _thumbnailHeight = 84.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playlists = ref.watch(allPlaylistsProvider);
    final library = {
      for (final item
          in ref.watch(contentViewModelProvider).value ?? const <ContentItem>[])
        item.id: item,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Playlists', style: theme.textTheme.titleMedium),
        ),
        SizedBox(
          height: _thumbnailHeight + 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == playlists.length) {
                return _CreateTile(
                  onTap: () async {
                    final name = await askPlaylistName(context);
                    if (name == null) return;
                    await ref.read(playlistsProvider.notifier).create(name);
                  },
                );
              }
              final playlist = playlists[index];
              return _PlaylistTile(
                playlist: playlist,
                cover: playlist.videoIds
                    .map((id) => library[id])
                    .nonNulls
                    .firstOrNull,
                count: playlist.videoIds.where(library.containsKey).length,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaylistTile extends ConsumerWidget {
  final Playlist playlist;
  final ContentItem? cover;
  final int count;

  const _PlaylistTile({
    required this.playlist,
    required this.cover,
    required this.count,
  });

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.of(sheetContext).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final notifier = ref.read(playlistsProvider.notifier);
    if (action == 'rename') {
      final name = await askPlaylistName(
        context,
        title: 'Rename playlist',
        initial: playlist.name,
        action: 'Save',
      );
      if (name != null) await notifier.rename(playlist.id, name);
    } else if (await confirmDeletePlaylist(context, playlist.name)) {
      await notifier.delete(playlist.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SizedBox(
      width: PlaylistsStrip._tileWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/playlists/${playlist.id}'),
        onLongPress: playlist.isBuiltIn
            ? null
            : () => _showOptions(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: PlaylistsStrip._thumbnailHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cover == null
                        ? ColoredBox(
                            color: AppColors.primaryMain.withValues(
                              alpha: 0.12,
                            ),
                            child: Icon(
                              playlist.isRecents
                                  ? Icons.history
                                  : playlist.isFavorites
                                  ? Icons.favorite_border
                                  : Icons.playlist_play,
                              color: AppColors.primaryMain,
                              size: 32,
                            ),
                          )
                        : VideoThumbnail(item: cover!, iconSize: 28),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(10),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.playlist_play,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return SizedBox(
      width: PlaylistsStrip._tileWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: PlaylistsStrip._thumbnailHeight,
                width: double.infinity,
                child: Icon(Icons.add, color: accent, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create playlist',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}
