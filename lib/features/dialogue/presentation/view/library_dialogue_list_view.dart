import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/content/presentation/view/add_content_type.dart';
import 'package:ingrain/features/dialogue/data/user_dialogue_repository.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:url_launcher/url_launcher.dart';

const nhkEasyJapaneseUrl =
    'https://www3.nhk.or.jp/nhkworld/en/shows/easyjapanese';

class LibraryDialogueListView extends ConsumerWidget {
  /// Ids picked in the Library's edit mode, or null outside it.
  final Set<String>? selectedIds;
  final ValueChanged<String>? onToggle;

  /// A long press on one of the learner's own dialogues starts edit mode.
  final ValueChanged<String>? onStartEditing;

  const LibraryDialogueListView({
    super.key,
    this.selectedIds,
    this.onToggle,
    this.onStartEditing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dialogues = ref.watch(dialogueListViewModelProvider);
    final isCached = ref.read(dialogueRepositoryProvider).isShowingCachedCopy;

    return dialogues.when(
      data: (items) => Column(
        children: [
          if (isCached) const _CachedCopyBanner(),
          Expanded(
            child: items.isEmpty
                ? _EmptyDialogues(onBrowse: () => _openNhk(context))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 136,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final dialogue = items[index];
                      final own = UserDialogueRepository.isUserDialogueId(
                        dialogue.id,
                      );
                      final selected = selectedIds;
                      return DialogueSummaryCard(
                        dialogue: dialogue,
                        editing: selected != null,
                        editable: own,
                        selected: selected?.contains(dialogue.id) ?? false,
                        onToggle: () => onToggle?.call(dialogue.id),
                        onLongPress: () => own
                            ? onStartEditing?.call(dialogue.id)
                            : _explainLocked(context),
                      );
                    },
                  ),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _DialogueLoadError(
        onRetry: () =>
            ref.read(dialogueListViewModelProvider.notifier).refresh(),
        onBrowse: () => _openNhk(context),
        message: error.toString(),
      ),
    );
  }

  static void _explainLocked(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Only dialogues you wrote can be edited or deleted'),
        ),
      );
  }

  static Future<void> _openNhk(BuildContext context) async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(nhkEasyJapaneseUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open NHK Easy Japanese')),
      );
    }
  }
}

/// A dialogue in the catalogue, sized for a two-column grid.
class DialogueSummaryCard extends StatelessWidget {
  final DialogueSummary dialogue;

  /// In edit mode a tap toggles selection instead of opening the dialogue,
  /// and dialogues that cannot be edited are dimmed.
  final bool editing;
  final bool editable;
  final bool selected;
  final VoidCallback? onToggle;
  final VoidCallback? onLongPress;

  const DialogueSummaryCard({
    super.key,
    required this.dialogue,
    this.editing = false,
    this.editable = false,
    this.selected = false,
    this.onToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStory = dialogue.kind == DialogueKind.story;
    const accent = AppColors.primaryMain;

    final card = Card(
      margin: EdgeInsets.zero,
      color: accent.withValues(alpha: selected ? 0.2 : 0.1),
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: accent, width: 1.5),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: editing
            ? (editable ? onToggle : null)
            : () => context.push('/dialogues/${dialogue.id}'),
        onLongPress: editing ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    editing && editable
                        ? (selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked)
                        : editing
                        ? Icons.lock_outline
                        : isStory
                        ? Icons.menu_book_outlined
                        : Icons.forum_outlined,
                    color: accent,
                    size: 20,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      dialogue.level,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  dialogue.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
                ),
              ),
              Text(
                '${isStory ? 'Story' : 'Dialogue'}  ·  '
                '${dialogue.lineCount} lines',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
    return editing && !editable ? Opacity(opacity: 0.45, child: card) : card;
  }
}

class _EmptyDialogues extends StatelessWidget {
  final VoidCallback onBrowse;

  const _EmptyDialogues({required this.onBrowse});

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.forum,
    color: AppColors.primaryMain,
    title: 'No dialogues available',
    message: 'Write your own, or browse NHK Easy Japanese.',
    action: Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.icon(
          style: accentButtonStyle(AppColors.primaryMain),
          onPressed: () => context.push(AddContentType.dialogue.route),
          icon: const Icon(Icons.edit),
          label: const Text('Write a dialogue'),
        ),
        OutlinedButton.icon(
          onPressed: onBrowse,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Browse NHK dialogues'),
        ),
      ],
    ),
  );
}

class _DialogueLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onBrowse;
  final String message;

  const _DialogueLoadError({
    required this.onRetry,
    required this.onBrowse,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off,
    color: AppColors.primaryMain,
    title: 'Could not load dialogues',
    message: message,
    action: Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
        OutlinedButton.icon(
          onPressed: onBrowse,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Browse NHK'),
        ),
      ],
    ),
  );
}

class _CachedCopyBanner extends StatelessWidget {
  const _CachedCopyBanner();

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: const Text('Showing cached copy'),
    leading: const Icon(Icons.cloud_off_outlined),
    actions: const [SizedBox.shrink()],
  );
}
