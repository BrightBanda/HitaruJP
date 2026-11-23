import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/srs/domain/deck.dart';
import 'package:ingrain/features/srs/presentation/view/anki_import.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// The Flashcards tab: every deck, a "study everything due" shortcut, and
/// deck creation.
class FlashcardsView extends ConsumerWidget {
  const FlashcardsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(deckSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Flashcards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Import a shared code',
            onPressed: () => context.push('/import'),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Flashcard settings',
            onPressed: () => context.push('/flashcards/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import Anki deck',
            onPressed: () => startAnkiImport(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createDeck(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New deck'),
      ),
      body: decks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load decks: $error')),
        data: (summaries) {
          final due = summaries.fold<int>(0, (sum, s) => sum + s.toStudy);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(deckSummariesProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                _DueBanner(due: due),
                const SectionHeader('Decks'),
                for (final summary in summaries) ...[
                  _DeckTile(summary: summary),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Asks for a name and creates a deck. Shared with anywhere a deck can be made.
Future<void> createDeck(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => const _NewDeckDialog(),
  );
  if (result == null) return;
  await ref
      .read(deckRepositoryProvider)
      .createDeck(result.$1, description: result.$2);
  ref.invalidate(deckSummariesProvider);
}

class _DueBanner extends StatelessWidget {
  final int due;

  const _DueBanner({required this.due});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientPanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  due == 0 ? 'All caught up' : '$due cards due',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  due == 0
                      ? 'Nothing to review right now'
                      : 'Across all of your decks',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          if (due > 0)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
              ),
              onPressed: () => context.push('/flashcards/study'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Study all'),
            ),
        ],
      ),
    );
  }
}

class _DeckTile extends StatelessWidget {
  final DeckSummary summary;

  const _DeckTile({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final deck = summary.deck;

    return Card(
      child: InkWell(
        onTap: () => context.push('/flashcards/deck/${deck.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(
                color: primary,
                icon: deck.isBuiltIn ? Icons.auto_awesome : Icons.style,
                solid: deck.isBuiltIn,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (deck.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        deck.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(
                          label: '${summary.fresh} new',
                          color: primary,
                          solid: summary.fresh > 0,
                        ),
                        Pill(
                          label: '${summary.learning} learning',
                          color: primary,
                          solid: summary.learning > 0,
                        ),
                        Pill(
                          label: '${summary.due} due',
                          color: primary,
                          solid: summary.due > 0,
                        ),
                        Pill(label: '${summary.total} cards', color: primary),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewDeckDialog extends StatefulWidget {
  const _NewDeckDialog();

  @override
  State<_NewDeckDialog> createState() => _NewDeckDialogState();
}

class _NewDeckDialogState extends State<_NewDeckDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) return;
    Navigator.of(context).pop((_name.text, _description.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New deck'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Deck name'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
