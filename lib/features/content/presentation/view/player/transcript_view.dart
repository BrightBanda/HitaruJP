import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/utils/duration_format.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/content/presentation/view/player/immersion_player_view.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/sentence_mining/presentation/view/sentence_save_sheet.dart';
import 'package:ingrain/features/sentence_mining/presentation/viewmodel/sentence_mining_view_model.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/japanese_tokenizer.dart';
import 'package:ingrain/features/vocabulary/presentation/view/vocabulary_lookup_sheet.dart';
import 'package:ingrain/features/vocabulary/presentation/view/vocabulary_save_sheet.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/features/vocabulary/presentation/widgets/tappable_transcript_text.dart';

/// The line playing at [second], or -1 between lines.
int currentSentenceIndex(List<TranscriptSentence> sentences, int second) =>
    sentences.indexWhere(
      (sentence) =>
          second >= sentence.startSeconds && second < sentence.endSeconds,
    );

/// The transcript line playing now, or -1.
///
/// The player reports its position several times a second. Deriving the line
/// here means the transcript only rebuilds when playback moves to another line,
/// not on every report: those rebuilds competed with the video for frames.
final currentSentenceIndexProvider = Provider.family<int, String>((
  ref,
  contentId,
) {
  final sentences =
      ref.watch(transcriptProvider(contentId)).value ??
      const <TranscriptSentence>[];
  final second = ref.watch(
    playbackPositionProvider.select((position) => position.inSeconds),
  );
  return currentSentenceIndex(sentences, second);
});

class TranscriptView extends ConsumerStatefulWidget {
  final String? contentId;

  const TranscriptView({super.key, this.contentId});

  static const _fontSize = 14.0;
  static const _lineVerticalPadding = 6.0;
  static const _lineGap = 2.0;
  static const _listVerticalPadding = 4.0;
  static const _mineButtonSize = 28.0;

  /// Height that shows [rows] single-line transcript lines at the current
  /// text size. Lines that wrap simply take more of it.
  static double heightForRows(BuildContext context, int rows) {
    final textHeight = MediaQuery.textScalerOf(context).scale(_fontSize) * 1.5;
    final lineHeight =
        math.max(textHeight, _mineButtonSize) + _lineVerticalPadding * 2;
    return _listVerticalPadding * 2 + rows * lineHeight + (rows - 1) * _lineGap;
  }

  @override
  ConsumerState<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends ConsumerState<TranscriptView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int? _lastScrolledIndex;
  DateTime? _userScrolledAt;

  /// After the learner scrolls by hand, auto-scroll waits this long before
  /// pulling the list back to the current line.
  static const _manualScrollGrace = Duration(seconds: 4);

  /// Only used to reach a line that has not been built yet.
  static const _estimatedLineHeight = 56.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) => _lineKeys.putIfAbsent(index, GlobalKey.new);

  /// Tokens per line, computed once per transcript rather than on every build.
  final Map<int, List<String>> _tokens = {};
  List<TranscriptSentence>? _tokensFrom;
  JapaneseTokenizer? _tokensBy;

  List<String> _tokensFor(
    List<TranscriptSentence> sentences,
    int index,
    JapaneseTokenizer tokenizer,
  ) {
    if (!identical(sentences, _tokensFrom) ||
        !identical(tokenizer, _tokensBy)) {
      _tokens.clear();
      _tokensFrom = sentences;
      _tokensBy = tokenizer;
    }
    return _tokens.putIfAbsent(
      index,
      () => tokenizer.tokenize(sentences[index].text),
    );
  }

  /// Keeps the current line in the middle of the list: the highlight moves
  /// down until it reaches the centre, then the text scrolls under it.
  void _maybeScrollToCurrent(int currentIndex) {
    if (!mounted || !_scrollController.hasClients) return;

    if (currentIndex < 0 || currentIndex == _lastScrolledIndex) return;

    final scrolledAt = _userScrolledAt;
    if (scrolledAt != null &&
        DateTime.now().difference(scrolledAt) < _manualScrollGrace) {
      return;
    }
    _lastScrolledIndex = currentIndex;

    final lineContext = _lineKeys[currentIndex]?.currentContext;
    if (lineContext != null) {
      Scrollable.ensureVisible(
        lineContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // Far off screen, so not built yet: jump near it, then centre it exactly
    // once it exists.
    final estimate = (currentIndex * _estimatedLineHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(estimate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final built = _lineKeys[currentIndex]?.currentContext;
      if (built != null && mounted) {
        Scrollable.ensureVisible(built, alignment: 0.5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(playerControllerProvider);
    final tokenizer = ref.watch(transcriptTokenizerProvider);
    final theme = Theme.of(context);

    if (widget.contentId == null) {
      return const Center(child: Text('No content selected'));
    }

    final transcriptAsync = ref.watch(transcriptProvider(widget.contentId!));
    final currentIndex = ref.watch(
      currentSentenceIndexProvider(widget.contentId!),
    );

    return transcriptAsync.when(
      data: (sentences) {
        if (sentences.isEmpty) {
          return const Center(child: Text('No transcript available'));
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _maybeScrollToCurrent(currentIndex);
          }
        });

        // Half a screen of space below the last line lets even the final
        // lines scroll up to the centre.
        return LayoutBuilder(
          builder: (context, constraints) =>
              NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  if (notification.direction != ScrollDirection.idle) {
                    _userScrolledAt = DateTime.now();
                    _lastScrolledIndex = null;
                  }
                  return false;
                },
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: sentences.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: TranscriptView._lineGap),
                  padding: EdgeInsets.fromLTRB(
                    12,
                    TranscriptView._listVerticalPadding,
                    12,
                    constraints.maxHeight / 2,
                  ),
                  itemBuilder: (context, index) {
                    final sentence = sentences[index];
                    final isCurrent = index == currentIndex;

                    return GestureDetector(
                      key: _keyFor(index),
                      onTap: controller != null
                          ? () => controller.seekTo(
                              seconds: sentence.startSeconds.toDouble(),
                            )
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: TranscriptView._lineVerticalPadding,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppColors.primaryMain.withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 42,
                              child: Text(
                                formatDuration(
                                  Duration(seconds: sentence.startSeconds),
                                ),
                                style: TextStyle(
                                  color: isCurrent
                                      ? AppColors.primaryMain
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                  fontSize: 11,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TappableTranscriptText(
                                tokens: _tokensFor(sentences, index, tokenizer),
                                highlightColor: isCurrent
                                    ? AppColors.primaryMain
                                    : theme.colorScheme.onSurface,
                                style: TextStyle(
                                  color: isCurrent
                                      ? AppColors.primaryMain
                                      : theme.colorScheme.onSurface,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.w400,
                                  fontSize: TranscriptView._fontSize,
                                ),
                                onTokenTap: (token) => _openLookupSheet(
                                  context,
                                  ref,
                                  sentences: sentences,
                                  sentence: sentence,
                                  word: token,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.bookmark_add_outlined),
                              color: AppColors.primaryMain,
                              iconSize: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: TranscriptView._mineButtonSize,
                                minHeight: TranscriptView._mineButtonSize,
                              ),
                              tooltip: 'Mine this sentence',
                              onPressed: () => _openSaveSheet(
                                context,
                                ref,
                                sentences: sentences,
                                sentence: sentence,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Error loading transcript')),
    );
  }

  /// Tap-to-look-up (product spec MVP #4): show the dictionary entry for the
  /// tapped token and let the learner save it with its immersion memory.
  Future<void> _openLookupSheet(
    BuildContext context,
    WidgetRef ref, {
    required List<TranscriptSentence> sentences,
    required TranscriptSentence sentence,
    required String word,
  }) async {
    final contentId = widget.contentId;
    if (contentId == null) return;

    final controller = ref.watch(playerControllerProvider);
    // Awaited rather than read: the dictionary may still be loading, and a
    // lookup must never answer "not in the dictionary" just because of that.
    DictionaryIndex? dictionary;
    try {
      dictionary = await ref.read(dictionaryProvider.future);
    } catch (_) {
      dictionary = null;
    }
    final entry = dictionary?.lookup(word);
    final contextLabel = SentenceMiningViewModel.contextForTranscript(
      sentences,
      sentence.index,
    );
    final saved = await ref.read(vocabularyRepositoryProvider).findByWord(word);
    final alreadySaved = saved != null;
    if (!context.mounted) return;

    if (!context.mounted) return;

    final wantsSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => VocabularyLookupSheet(
        word: entry?.surface ?? word,
        entry: entry,
        contextLabel: contextLabel,
        alreadySaved: alreadySaved,
        onJumpToTimestamp: controller == null
            ? null
            : () =>
                  controller.seekTo(seconds: sentence.startSeconds.toDouble()),
        onSave: () => Navigator.of(sheetContext).pop(true),
      ),
    );
    if (wantsSave != true || !context.mounted) return;

    final request = await showModalBottomSheet<VocabularySaveRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VocabularySaveSheet(
        title: 'Save word',
        word: entry?.surface ?? word,
        reading: entry?.reading,
        meaning: entry?.primaryMeaning,
        pos: entry?.pos,
        contextLabel: contextLabel,
      ),
    );
    if (request == null || !context.mounted) return;

    String? contentTitle;
    try {
      contentTitle = (await ref.read(contentItemProvider(contentId).future))
          .title;
    } catch (_) {
      contentTitle = null;
    }
    final sessionId = ref
        .read(immersionSessionViewModelProvider(contentId))
        .sessionId;

    await ref
        .read(vocabularyViewModelProvider.notifier)
        .saveFromTranscript(
          contentId: contentId,
          word: request.word,
          sentence: sentence,
          transcript: sentences,
          contentTitle: contentTitle,
          sessionId: sessionId,
          reading: request.reading,
          meaning: request.meaning,
          pos: request.pos,
        );
    ref.invalidate(dueCountProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Word saved for review')));
  }

  Future<void> _openSaveSheet(
    BuildContext context,
    WidgetRef ref, {
    required List<TranscriptSentence> sentences,
    required TranscriptSentence sentence,
  }) async {
    final contentId = widget.contentId;
    if (contentId == null) return;

    // Read lazily rather than watching: the player already keeps this provider
    // alive, so watching here would only add a rebuild dependency to the list.
    String? contentTitle;
    try {
      contentTitle = (await ref.read(contentItemProvider(contentId).future))
          .title;
    } catch (_) {
      contentTitle = null;
    }
    final sessionId = ref
        .read(immersionSessionViewModelProvider(contentId))
        .sessionId;
    if (!context.mounted) return;

    final request = await showModalBottomSheet<SentenceSaveRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SentenceSaveSheet(
        title: 'Mine sentence',
        japanese: sentence.text,
        contextLabel: SentenceMiningViewModel.contextForTranscript(
          sentences,
          sentence.index,
        ),
      ),
    );
    if (request == null || !context.mounted) return;

    await ref
        .read(sentenceMiningViewModelProvider.notifier)
        .saveFromTranscript(
          contentId: contentId,
          sentence: sentence,
          transcript: sentences,
          contentTitle: contentTitle,
          sessionId: sessionId,
          translation: request.translation,
          explanation: request.explanation,
        );
    ref.invalidate(dueCountProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sentence saved for review')));
  }
}
