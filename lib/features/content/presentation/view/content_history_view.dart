import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/view/add_content_type.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/dialogue/data/user_dialogue_repository.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/presentation/view/library_content_filter.dart';
import 'package:ingrain/features/dialogue/presentation/view/library_dialogue_list_view.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:ingrain/shared/widgets/video_thumbnail.dart';

class ContentHistoryView extends ConsumerStatefulWidget {
  const ContentHistoryView({super.key});

  @override
  ConsumerState<ContentHistoryView> createState() => _ContentHistoryViewState();
}

class _ContentHistoryViewState extends ConsumerState<ContentHistoryView> {
  LibraryContentFilter _filter = LibraryContentFilter.videos;

  /// Ids picked in edit mode, which a long press on a video or one of the
  /// learner's own dialogues starts. Null outside edit mode.
  Set<String>? _selected;

  bool get _editing => _selected != null;

  void _startEditing(String id) => setState(() => _selected = {id});

  void _stopEditing() => setState(() => _selected = null);

  void _toggle(String id) {
    final selected = _selected!;
    setState(() {
      if (!selected.remove(id)) selected.add(id);
    });
  }

  bool get _isDialogues => _filter == LibraryContentFilter.dialogues;

  String get _noun => _isDialogues ? 'dialogue' : 'video';

  /// What edit mode can act on under the current filter. Catalogue dialogues
  /// come from the server, so only the learner's own are listed.
  List<({String id, String title})> _editableEntries() => switch (_filter) {
    LibraryContentFilter.videos => [
      for (final item
          in ref.read(contentViewModelProvider).value ?? const <ContentItem>[])
        (id: item.id, title: item.title),
    ],
    LibraryContentFilter.dialogues => [
      for (final dialogue
          in ref.read(dialogueListViewModelProvider).value ??
              const <DialogueSummary>[])
        if (UserDialogueRepository.isUserDialogueId(dialogue.id))
          (id: dialogue.id, title: dialogue.title),
    ],
    LibraryContentFilter.podcasts => const [],
  };

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final uiState = ref.watch(contentViewModelProvider);
    ref.watch(dialogueListViewModelProvider);
    final entries = _editableEntries();
    // Drops ids whose entries were removed elsewhere.
    _selected?.removeWhere((id) => !entries.any((entry) => entry.id == id));

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!_editing) return false;
        _stopEditing();
        return true;
      },
      child: Scaffold(
        appBar: _editing
            ? _buildEditBar(context, entries)
            : _buildAppBar(context),
        body: _buildBody(context, ref, uiState),
      ),
    );
  }

  PreferredSizeWidget _buildEditBar(
    BuildContext context,
    List<({String id, String title})> entries,
  ) {
    final selected = _selected!;
    final allSelected = entries.isNotEmpty && selected.length == entries.length;
    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Done',
        onPressed: _stopEditing,
      ),
      title: Text(
        selected.isEmpty ? 'Select ${_noun}s' : '${selected.length} selected',
      ),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          onPressed: () => setState(() {
            if (allSelected) {
              selected.clear();
            } else {
              selected.addAll(entries.map((entry) => entry.id));
            }
          }),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Rename',
          onPressed: selected.length == 1
              ? () => _rename(
                  context,
                  entries.firstWhere((entry) => entry.id == selected.single),
                )
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: selected.isEmpty ? null : () => _deleteSelected(context),
        ),
      ],
    );
  }

  Future<void> _rename(
    BuildContext context,
    ({String id, String title}) entry,
  ) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(noun: _noun, initialTitle: entry.title),
    );
    if (title == null || !mounted) return;
    if (_isDialogues) {
      await ref
          .read(dialogueListViewModelProvider.notifier)
          .rename(entry.id, title);
    } else {
      await ref
          .read(contentViewModelProvider.notifier)
          .renameContent(entry.id, title);
    }
    if (mounted) _stopEditing();
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final ids = _selected!.toList();
    final count = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(count == 1 ? 'Delete $_noun?' : 'Delete $count ${_noun}s?'),
        content: Text(
          _isDialogues
              ? 'This cannot be undone. Sentences you mined from them stay '
                    'in your flashcards.'
              : 'They are removed from your library with their transcripts. '
                    'Your flashcards and immersion time are kept.',
        ),
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
    if (confirmed != true || !mounted) return;
    if (_isDialogues) {
      await ref.read(dialogueListViewModelProvider.notifier).deleteMany(ids);
    } else {
      await ref.read(contentViewModelProvider.notifier).deleteContents(ids);
    }
    if (mounted) _stopEditing();
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text('Library'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => context.push('/search'),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add content',
          onPressed: () => context.push('/content/add'),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ContentItem>> uiState,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: LibraryContentFilterControl(
            selected: _filter,
            onChanged: (filter) => setState(() {
              _filter = filter;
              _selected = null;
            }),
          ),
        ),
        Expanded(
          child: switch (_filter) {
            LibraryContentFilter.dialogues => LibraryDialogueListView(
              selectedIds: _selected,
              onToggle: _toggle,
              onStartEditing: _startEditing,
            ),
            LibraryContentFilter.podcasts => const _PodcastsComingSoon(),
            LibraryContentFilter.videos => uiState.when(
              data: (items) => items.isEmpty
                  ? _buildEmpty(context)
                  : _buildList(context, ref, items),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
          },
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return EmptyState(
      icon: Icons.smart_display,
      color: AppColors.primaryMain,
      title: 'Your library is empty',
      message:
          'Every video you add keeps its transcript, progress\nand mined '
          'language here.',
      action: FilledButton.icon(
        style: accentButtonStyle(AppColors.primaryMain),
        onPressed: () => context.push(AddContentType.youtube.route),
        icon: const Icon(Icons.add),
        label: const Text('Add content'),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<ContentItem> items,
  ) {
    final theme = Theme.of(context);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final minutes = item.totalImmersionSeconds ~/ 60;
        final selected = _selected?.contains(item.id) ?? false;

        return Card(
          color: selected
              ? AppColors.primaryMain.withValues(alpha: 0.12)
              : null,
          shape: selected
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(
                    color: AppColors.primaryMain,
                    width: 1.5,
                  ),
                )
              : null,
          child: InkWell(
            onTap: _editing
                ? () => _toggle(item.id)
                : () => context.push('/content/${item.id}'),
            onLongPress: _editing ? null : () => _startEditing(item.id),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 96,
                      height: 54,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoThumbnail(item: item, iconSize: 28),
                          if (_editing)
                            ColoredBox(
                              color: selected
                                  ? AppColors.primaryMain.withValues(alpha: 0.7)
                                  : Colors.black38,
                              child: Icon(
                                selected
                                    ? Icons.check
                                    : Icons.radio_button_unchecked,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.channelTitle ?? item.sourceType.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          minutes > 0 ? '${minutes}m immersed' : 'New',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontSize: 11,
                            color: minutes > 0
                                ? AppColors.primaryMain
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PodcastsComingSoon extends StatelessWidget {
  const _PodcastsComingSoon();

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.headphones,
    color: AppColors.primaryMain,
    title: 'Podcasts are coming soon',
    message: 'Until then, try a YouTube video or a dialogue.',
  );
}

class _RenameDialog extends StatefulWidget {
  final String noun;
  final String initialTitle;

  const _RenameDialog({required this.noun, required this.initialTitle});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isNotEmpty) Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rename ${widget.noun}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Title'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
