import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/playlists/presentation/view/playlist_dialogs.dart';
import 'package:ingrain/features/playlists/presentation/viewmodel/playlist_view_model.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:ingrain/shared/widgets/video_thumbnail.dart';

/// One playlist: its videos in order, to play, reorder and remove.
class PlaylistDetailView extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailView({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider(playlistId));
    final playlistsLoading = ref.watch(playlistsProvider).isLoading;
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: playlistsLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('This playlist no longer exists.')),
      );
    }

    final notifier = ref.read(playlistsProvider.notifier);
    final library = {
      for (final item
          in ref.watch(contentViewModelProvider).value ?? const <ContentItem>[])
        item.id: item,
    };
    // A video deleted from the library just drops out of view.
    final videos = [for (final id in playlist.videoIds) ?library[id]];

    Future<void> add() async {
      final picked = await pickVideos(
        context,
        exclude: playlist.videoIds.toSet(),
      );
      if (picked != null && picked.isNotEmpty) {
        await notifier.addVideos(playlist.id, picked);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          if (playlist.isEditable)
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Add videos',
              onPressed: add,
            ),
          if (!playlist.isBuiltIn)
            PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'rename') {
                  final name = await askPlaylistName(
                    context,
                    title: 'Rename playlist',
                    initial: playlist.name,
                    action: 'Save',
                  );
                  if (name != null) await notifier.rename(playlist.id, name);
                } else if (await confirmDeletePlaylist(
                      context,
                      playlist.name,
                    ) &&
                    context.mounted) {
                  context.pop();
                  await notifier.delete(playlist.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
              ],
            ),
        ],
      ),
      body: videos.isEmpty
          ? EmptyState(
              icon: Icons.playlist_add,
              color: Theme.of(context).colorScheme.primary,
              title: 'Nothing here yet',
              message: playlist.isRecents
                  ? 'Videos you watch show up here.'
                  : 'Add videos from your library.',
              action: playlist.isEditable
                  ? FilledButton.icon(
                      onPressed: add,
                      icon: const Icon(Icons.add),
                      label: const Text('Add videos'),
                    )
                  : null,
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: playlist.isEditable,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: videos.length,
              onReorderItem: (oldIndex, newIndex) {
                final order = [for (final video in videos) video.id];
                order.insert(newIndex, order.removeAt(oldIndex));
                notifier.setOrder(playlist.id, order);
              },
              itemBuilder: (context, index) {
                final item = videos[index];
                return ListTile(
                  key: ValueKey(item.id),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => context.push('/content/${item.id}'),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 96,
                      height: 54,
                      child: VideoThumbnail(item: item, iconSize: 28),
                    ),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(item.channelTitle ?? item.sourceType.name),
                  trailing: playlist.isEditable
                      ? IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Remove from playlist',
                          onPressed: () =>
                              notifier.removeVideo(playlist.id, item.id),
                        )
                      : null,
                );
              },
            ),
    );
  }
}
