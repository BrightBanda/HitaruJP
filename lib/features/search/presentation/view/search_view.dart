import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/core/utils/duration_format.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/search/domain/learning_search.dart';
import 'package:ingrain/features/search/presentation/viewmodel/search_view_model.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

enum _Filter {
  all('All'),
  words('Words'),
  sentences('Sentences'),
  videos('Videos'),
  cards('Cards');

  const _Filter(this.label);

  final String label;

  bool accepts(SearchHit hit) => switch (this) {
    _Filter.all => true,
    _Filter.words => hit is WordHit,
    _Filter.sentences => hit is SentenceHit,
    _Filter.videos => hit is ContentHit,
    _Filter.cards => hit is CardHit,
  };
}

/// Searches everything the learner has saved: words, sentences, the videos
/// they came from, and hand-written flashcards.
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final _controller = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search words, sentences, videos…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      ref.read(searchQueryProvider.notifier).update('');
                    },
                  ),
          ),
          onChanged: ref.read(searchQueryProvider.notifier).update,
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load your history: $error')),
        data: (hits) {
          if (query.trim().isEmpty) return const _Prompt();
          final visible = hits.where(_filter.accepts).toList();
          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final filter in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: ChoiceChip(
                          label: Text(
                            '${filter.label} '
                            '${hits.where(filter.accepts).length}',
                          ),
                          selected: _filter == filter,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        color: Theme.of(context).colorScheme.primary,
                        title: 'Nothing found',
                        message:
                            'No saved word, sentence, video or card matches '
                            '"${query.trim()}".',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _HitTile(hit: visible[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Prompt extends ConsumerWidget {
  const _Prompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final corpus = ref.watch(searchCorpusProvider).value;
    return EmptyState(
      icon: Icons.manage_search,
      color: Theme.of(context).colorScheme.primary,
      title: 'Search your learning history',
      message: corpus == null
          ? 'Type a word, a reading, a meaning or a video title.'
          : '${corpus.words.length} words, ${corpus.sentences.length} '
                'sentences and ${corpus.contents.length} videos. Japanese or '
                'English, hiragana or katakana.',
    );
  }
}

class _HitTile extends StatelessWidget {
  final SearchHit hit;

  const _HitTile({required this.hit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, kind, title, subtitle, source, route) = _describe(hit);
    final card = switch (hit) {
      WordHit(:final card) || SentenceHit(:final card) => card,
      CardHit(:final card) => card,
      ContentHit() => null,
    };

    return Card(
      child: InkWell(
        onTap: route == null ? null : () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(color: theme.colorScheme.primary, icon: icon, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(label: kind, color: theme.colorScheme.primary),
                        if (source != null)
                          Pill(
                            label: source,
                            icon: Icons.link,
                            color: theme.colorScheme.primary,
                          ),
                        if (card != null)
                          Pill(
                            label: card.reviewCount == 0
                                ? 'Not reviewed yet'
                                : 'Reviewed ${card.reviewCount}×',
                            icon: Icons.style,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// (icon, kind label, title, subtitle, source label, route to open).
  static (IconData, String, String, String?, String?, String?) _describe(
    SearchHit hit,
  ) => switch (hit) {
    WordHit(:final word, :final card) => (
      Icons.translate,
      'Word · ${word.state.label}',
      word.displayWithReading,
      word.meaning,
      _sourceLabel(word.sourceTitle, word.timestampSeconds),
      '/flashcards/deck/${card?.deckId ?? minedPhrasesDeckId}',
    ),
    SentenceHit(:final sentence) => (
      Icons.format_quote,
      'Sentence',
      sentence.japanese,
      sentence.translation,
      _sourceLabel(sentence.sourceTitle, sentence.timestampSeconds),
      _sourceRoute(sentence.sourceType, sentence.sourceId) ??
          '/flashcards/deck/$minedPhrasesDeckId',
    ),
    ContentHit(:final content) => (
      Icons.smart_display,
      'Video',
      content.title,
      content.channelTitle,
      null,
      '/content/${content.id}',
    ),
    CardHit(:final card) => (
      Icons.style,
      'Card',
      card.promptText,
      card.answerText,
      null,
      '/flashcards/deck/${card.deckId}',
    ),
  };

  static String? _sourceLabel(String? title, int? seconds) {
    if (title == null || title.isEmpty) return null;
    if (seconds == null) return title;
    return '$title · ${formatDuration(Duration(seconds: seconds))}';
  }

  /// Opens where the sentence was mined, when that place still exists.
  static String? _sourceRoute(SourceType type, String sourceId) =>
      switch (type) {
        SourceType.youtube || SourceType.podcast => '/content/$sourceId',
        SourceType.dialogue => '/dialogues/$sourceId',
        SourceType.manual => null,
      };
}
