import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/playlists/presentation/viewmodel/playlist_view_model.dart';
import 'package:ingrain/shared/widgets/video_thumbnail.dart';

/// Asks for a playlist name; null when cancelled.
Future<String?> askPlaylistName(
  BuildContext context, {
  String title = 'New playlist',
  String initial = '',
  String action = 'Create',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial, action: action),
  );
}

Future<bool> confirmDeletePlaylist(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete "$name"?'),
      content: const Text('The videos stay in your library.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String action;

  const _NameDialog({
    required this.title,
    required this.initial,
    required this.action,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

/// Puts [videoIds] into a playlist the learner picks, or a new one. Reports
/// the result in a snackbar.
Future<void> addToPlaylist(
  BuildContext context,
  WidgetRef ref,
  List<String> videoIds,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final playlists = [
    for (final playlist in ref.read(allPlaylistsProvider))
      if (playlist.isEditable) playlist,
  ];
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New playlist'),
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
          for (final playlist in playlists)
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text(playlist.name),
              subtitle: Text(_count(playlist.videoIds.length)),
              onTap: () => Navigator.of(sheetContext).pop(playlist.id),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final notifier = ref.read(playlistsProvider.notifier);
  final String name;
  if (choice == true) {
    final newName = await askPlaylistName(context);
    if (newName == null) return;
    final created = await notifier.create(newName, videoIds: videoIds);
    name = created?.name ?? newName;
  } else {
    final id = choice as String;
    await notifier.addVideos(id, videoIds);
    name = ref.read(playlistProvider(id))?.name ?? 'playlist';
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        videoIds.length == 1
            ? 'Added to "$name"'
            : 'Added ${videoIds.length} videos to "$name"',
      ),
    ),
  );
}

/// Library videos not yet in the playlist, to tick and add. Null if dismissed.
Future<List<String>?> pickVideos(
  BuildContext context, {
  required Set<String> exclude,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VideoPicker(exclude: exclude),
  );
}

class _VideoPicker extends ConsumerStatefulWidget {
  final Set<String> exclude;

  const _VideoPicker({required this.exclude});

  @override
  ConsumerState<_VideoPicker> createState() => _VideoPickerState();
}

class _VideoPickerState extends ConsumerState<_VideoPicker> {
  final _picked = <String>[];

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final item
          in ref.watch(contentViewModelProvider).value ?? const <ContentItem>[])
        if (!widget.exclude.contains(item.id)) item,
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add videos',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton(
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_picked),
                    child: Text(
                      _picked.isEmpty ? 'Add' : 'Add ${_picked.length}',
                    ),
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Every video in your library is already here.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final picked = _picked.contains(item.id);
                    return CheckboxListTile(
                      value: picked,
                      onChanged: (_) => setState(
                        () => picked
                            ? _picked.remove(item.id)
                            : _picked.add(item.id),
                      ),
                      secondary: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 72,
                          height: 40,
                          child: VideoThumbnail(item: item, iconSize: 22),
                        ),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: item.channelTitle == null
                          ? null
                          : Text(item.channelTitle!, maxLines: 1),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _count(int n) => n == 1 ? '1 video' : '$n videos';

String videoCountLabel(int n) => _count(n);
