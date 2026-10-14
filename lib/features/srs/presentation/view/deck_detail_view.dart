import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/sentence_mining/presentation/viewmodel/sentence_mining_view_model.dart';
import 'package:ingrain/features/srs/domain/deck.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// One deck: its counts, a study button, and its cards.
class DeckDetailView extends ConsumerWidget {
  final String deckId;

  const DeckDetailView({super.key, required this.deckId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(deckDetailProvider(deckId));
    final summary = detail.value?.$1;

    return Scaffold(
      appBar: AppBar(
        title: Text(summary?.deck.name ?? 'Deck'),
        actions: [
          if (summary != null && !summary.deck.isBuiltIn)
            PopupMenuButton<String>(
              onSelected: (action) => action == 'rename'
                  ? _rename(context, ref, summary.deck)
                  : _delete(context, ref, summary.deck),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename deck')),
                PopupMenuItem(value: 'delete', child: Text('Delete deck')),
              ],
            ),
        ],
      ),
      floatingActionButton: summary == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addCard(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add card'),
            ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load deck: $error')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('This deck no longer exists'));
          }
          final (summary, cards) = data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              _DeckHeader(summary: summary),
              SectionHeader('${cards.length} cards'),
              if (cards.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    summary.deck.isBuiltIn
                        ? 'Bookmark a line in a transcript or dialogue, or '
                              'save a word, and it appears here.'
                        : 'No cards yet. Tap "Add card" to write one.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (final card in cards) ...[
                _CardTile(
                  card: card,
                  onDelete: () => _deleteCard(context, ref, card),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(deckDetailProvider(deckId));
    ref.invalidate(deckSummariesProvider);
    ref.invalidate(dueCountProvider);
  }

  Future<void> _addCard(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddCardSheet(),
    );
    if (result == null) return;
    await ref
        .read(deckRepositoryProvider)
        .addCard(deckId: deckId, front: result.$1, back: result.$2);
    _refresh(ref);
  }

  Future<void> _deleteCard(
    BuildContext context,
    WidgetRef ref,
    ReviewCard card,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete card?',
      message: switch (card.cardType) {
        CardType.basic => 'This cannot be undone.',
        CardType.sentence =>
          'The mined sentence and its card are deleted. This cannot be '
              'undone.',
        CardType.vocabulary =>
          'The saved word and its card are deleted. This cannot be undone.',
      },
    );
    if (!confirmed) return;
    // Mined sentences and saved words live only here now, so deleting their
    // card deletes them too.
    if (card.cardType == CardType.sentence) {
      await ref
          .read(sentenceMiningViewModelProvider.notifier)
          .deleteSentence(card.sourceItemId);
    } else if (card.cardType == CardType.vocabulary) {
      await ref
          .read(vocabularyViewModelProvider.notifier)
          .deleteWord(card.sourceItemId);
    } else {
      await ref.read(deckRepositoryProvider).deleteCard(card);
    }
    _refresh(ref);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Deck deck) async {
    final controller = TextEditingController(text: deck.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename deck'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Deck name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await ref.read(deckRepositoryProvider).renameDeck(deck, name);
    _refresh(ref);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Deck deck) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete "${deck.name}"?',
      message:
          'The deck and all of its cards are deleted. This cannot be '
          'undone.',
    );
    if (!confirmed) return;
    await ref.read(deckRepositoryProvider).deleteDeck(deck);
    ref.invalidate(deckSummariesProvider);
    ref.invalidate(dueCountProvider);
    if (context.mounted) context.pop();
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }
}

class _DeckHeader extends StatelessWidget {
  final DeckSummary summary;

  const _DeckHeader({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deck = summary.deck;
    return GradientPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (deck.description != null)
            Text(
              deck.description!,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: 'New', value: summary.fresh),
              _Stat(label: 'Learning', value: summary.learning),
              _Stat(label: 'Due', value: summary.due),
              _Stat(label: 'Total', value: summary.total),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
              ),
              onPressed: summary.toStudy == 0
                  ? null
                  : () => context.push(
                      Uri(
                        path: '/flashcards/study',
                        queryParameters: {'deck': deck.id, 'title': deck.name},
                      ).toString(),
                    ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                summary.toStudy == 0
                    ? 'Nothing to study today'
                    : 'Study ${summary.toStudy} now',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final ReviewCard card;
  final VoidCallback onDelete;

  const _CardTile({required this.card, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (card.cardType) {
      CardType.vocabulary => Icons.translate,
      CardType.sentence => Icons.format_quote,
      CardType.basic => Icons.style,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          children: [
            IconBadge(color: theme.colorScheme.primary, icon: icon, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.promptText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (card.answerText != null)
                    Text(
                      card.answerText!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete card',
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  final _front = TextEditingController();
  final _back = TextEditingController();

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  void _submit() {
    if (_front.text.trim().isEmpty) return;
    Navigator.of(context).pop((_front.text, _back.text));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add card', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _front,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Front',
              hintText: '猫',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _back,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Back (optional)',
              hintText: 'ねこ — cat',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _submit, child: const Text('Save card')),
        ],
      ),
    );
  }
}
