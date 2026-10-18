import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/sentence_mining/presentation/viewmodel/sentence_mining_view_model.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/transcript_word_extractor.dart';
import 'package:ingrain/features/vocabulary/presentation/view/vocabulary_lookup_sheet.dart';
import 'package:ingrain/features/vocabulary/presentation/view/vocabulary_save_sheet.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// The distinct words of one video's transcript. Saved words live in the
/// flashcard decks, so this page is for finding words rather than listing them.
final transcriptWordsProvider =
    FutureProvider.family<
      List<ExtractedWord>,
      ({String contentId, bool includeKanaOnly})
    >((ref, args) async {
      final dictionary = await ref.watch(dictionaryProvider.future);
      final sentences = await ref.watch(
        transcriptProvider(args.contentId).future,
      );
      return TranscriptWordExtractor(dictionary)
          .extract(sentences, includeKanaOnly: args.includeKanaOnly);
    });

enum _Mode { dictionary, transcript }

/// Look words up in the bundled dictionary, or pull every word out of a
/// video's transcript, and save the ones worth studying.
class VocabularyView extends StatefulWidget {
  const VocabularyView({super.key});

  @override
  State<VocabularyView> createState() => _VocabularyViewState();
}

class _VocabularyViewState extends State<VocabularyView> {
  _Mode _mode = _Mode.dictionary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vocabulary')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<_Mode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _Mode.dictionary,
                  icon: Icon(Icons.search),
                  label: Text('Dictionary'),
                ),
                ButtonSegment(
                  value: _Mode.transcript,
                  icon: Icon(Icons.subtitles_outlined),
                  label: Text('From transcript'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.single),
            ),
          ),
          Expanded(
            child: switch (_mode) {
              _Mode.dictionary => const _DictionarySearch(),
              _Mode.transcript => const _TranscriptExtractor(),
            },
          ),
        ],
      ),
    );
  }
}

/// Opens the lookup sheet for [word], then the save form, then saves it for
/// review with the given source.
Future<void> _lookupAndSave(
  BuildContext context,
  WidgetRef ref, {
  required String word,
  DictionaryEntry? entry,
  SourceType sourceType = SourceType.manual,
  String sourceId = 'manual',
  String? sourceTitle,
  int? timestampSeconds,
  String? contextSentence,
}) async {
  final alreadySaved =
      await ref.read(vocabularyRepositoryProvider).findByWord(word) != null;
  if (!context.mounted) return;

  final shouldSave = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => VocabularyLookupSheet(
      word: word,
      entry: entry,
      contextLabel: contextSentence,
      alreadySaved: alreadySaved,
      onSave: () => Navigator.of(sheetContext).pop(true),
    ),
  );
  if (shouldSave != true || !context.mounted) return;

  final request = await showModalBottomSheet<VocabularySaveRequest>(
    context: context,
    isScrollControlled: true,
    builder: (_) => VocabularySaveSheet(
      title: 'Save word',
      word: word,
      reading: entry?.reading,
      meaning: entry?.primaryMeaning,
      pos: entry?.pos,
      contextLabel: contextSentence,
    ),
  );
  if (request == null || !context.mounted) return;

  await ref
      .read(vocabularyViewModelProvider.notifier)
      .saveWord(
        word: request.word,
        reading: request.reading,
        meaning: request.meaning,
        pos: request.pos,
        deckId: request.deckId,
        sourceType: sourceType,
        sourceId: sourceId,
        sourceTitle: sourceTitle,
        timestampSeconds: timestampSeconds,
        contextSentence: contextSentence,
      );
  ref.invalidate(dueCountProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Word saved for review')));
  }
}

class _DictionarySearch extends ConsumerStatefulWidget {
  const _DictionarySearch();

  @override
  ConsumerState<_DictionarySearch> createState() => _DictionarySearchState();
}

class _DictionarySearchState extends ConsumerState<_DictionarySearch> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dictionaryAsync = ref.watch(dictionaryProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Japanese, kana or English',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: dictionaryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Dictionary unavailable: $e')),
            data: (dictionary) {
              if (_query.trim().isEmpty) {
                return const EmptyState(
                  icon: Icons.translate,
                  color: AppColors.primaryMain,
                  title: 'Search the dictionary',
                  message:
                      'Type a word, a reading, or an English meaning.\nIt works '
                      'offline.',
                );
              }
              final results = dictionary.search(_query);
              if (results.isEmpty) {
                return Center(
                  child: Text(
                    'No words found for "${_query.trim()}"',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                itemCount: results.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = results[index];
                  return _WordTile(
                    headword: entry.surface,
                    reading: entry.reading,
                    meaning: entry.meaningLine,
                    onTap: () => _lookupAndSave(
                      context,
                      ref,
                      word: entry.surface,
                      entry: entry,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TranscriptExtractor extends ConsumerStatefulWidget {
  const _TranscriptExtractor();

  @override
  ConsumerState<_TranscriptExtractor> createState() =>
      _TranscriptExtractorState();
}

class _TranscriptExtractorState extends ConsumerState<_TranscriptExtractor> {
  String? _contentId;
  bool _includeKanaOnly = false;
  bool _byFrequency = false;

  @override
  Widget build(BuildContext context) {
    final videosAsync = ref.watch(contentViewModelProvider);

    return videosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        final videos = [
          for (final item in items)
            if (item.sourceType == SourceType.youtube) item,
        ];
        if (videos.isEmpty) {
          return const EmptyState(
            icon: Icons.subtitles_outlined,
            color: AppColors.primaryMain,
            title: 'No transcripts yet',
            message:
                'Add a video with Japanese captions to your library and its '
                'words show up here.',
          );
        }
        final selected = videos.firstWhere(
          (video) => video.id == _contentId,
          orElse: () => videos.first,
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: DropdownButtonFormField<String>(
                initialValue: selected.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Video'),
                items: [
                  for (final video in videos)
                    DropdownMenuItem(
                      value: video.id,
                      child: Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _contentId = id),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Most frequent first'),
                    selected: _byFrequency,
                    onSelected: (v) => setState(() => _byFrequency = v),
                  ),
                  FilterChip(
                    label: const Text('Short kana words'),
                    selected: _includeKanaOnly,
                    onSelected: (v) => setState(() => _includeKanaOnly = v),
                  ),
                ],
              ),
            ),
            Expanded(child: _wordList(selected)),
          ],
        );
      },
    );
  }

  Widget _wordList(ContentItem video) {
    final wordsAsync = ref.watch(
      transcriptWordsProvider((
        contentId: video.id,
        includeKanaOnly: _includeKanaOnly,
      )),
    );
    return wordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not read the transcript: $e')),
      data: (words) {
        if (words.isEmpty) {
          return const EmptyState(
            icon: Icons.subtitles_off_outlined,
            color: AppColors.primaryMain,
            title: 'No words found',
            message: 'This video has no transcript, or none of it is Japanese.',
          );
        }
        final sorted = _byFrequency
            ? ([...words]..sort((a, b) => b.count.compareTo(a.count)))
            : words;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                '${words.length} words',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                itemCount: sorted.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = sorted[index];
                  return _WordTile(
                    headword: item.word,
                    reading: item.entry.reading,
                    meaning: item.entry.meaningLine,
                    trailing: item.count > 1 ? '×${item.count}' : null,
                    onTap: () => _openWord(video, item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openWord(ContentItem video, ExtractedWord item) async {
    final sentences = await ref.read(transcriptProvider(video.id).future);
    if (!mounted) return;
    await _lookupAndSave(
      context,
      ref,
      word: item.word,
      entry: item.entry,
      sourceType: SourceType.youtube,
      sourceId: video.id,
      sourceTitle: video.title,
      timestampSeconds: item.firstSentence.startSeconds,
      contextSentence: SentenceMiningViewModel.contextForTranscript(
        sentences,
        item.firstSentence.index,
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  final String headword;
  final String reading;
  final String meaning;
  final String? trailing;
  final VoidCallback onTap;

  const _WordTile({
    required this.headword,
    required this.reading,
    required this.meaning,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: headword,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                        ),
                        children: [
                          if (reading.isNotEmpty && reading != headword)
                            TextSpan(
                              text: '  $reading',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meaning,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(trailing!, style: theme.textTheme.labelLarge),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
