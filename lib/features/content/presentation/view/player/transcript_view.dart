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

  /// Whether the list follows the line being played. Scrolling by hand stops
  /// it, so the learner can read back without being pulled away; the "Now
  /// playing" button (or scrolling the line back into view) resumes it.
  bool _following = true;

  /// The line playing now, or the last one when between lines.
  int _activeIndex = -1;

  /// Set while following is off and the playing line is out of sight: which
  /// way the button points, up or down.
  AxisDirection? _jumpDirection;

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
    if (!_following) {
      // The playing line may just have moved out of view.
      _updateJumpButton();
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

  /// Where the playing line is relative to what is on screen: null when it
  /// can be seen, else the way to scroll to reach it.
  AxisDirection? _offscreenDirection() {
    final index = _activeIndex;
    if (index < 0 || !_scrollController.hasClients) return null;
    final position = _scrollController.position;
    final box = _lineKeys[index]?.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final viewport = RenderAbstractViewport.of(box);
      // The scroll offsets that would put the line at the top, and at the
      // bottom, of the list.
      final atTop = viewport.getOffsetToReveal(box, 0).offset;
      final atBottom = viewport.getOffsetToReveal(box, 1).offset;
      final slack = box.size.height / 2;
      if (position.pixels > atTop + slack) return AxisDirection.up;
      if (position.pixels < atBottom - slack) return AxisDirection.down;
      return null;
    }
    // Not built, so well out of view; which side is all that matters.
    return index * _estimatedLineHeight < position.pixels
        ? AxisDirection.up
        : AxisDirection.down;
  }

  void _updateJumpButton() {
    if (!mounted) return;
    final direction = _following ? null : _offscreenDirection();
    if (direction != _jumpDirection) {
      setState(() => _jumpDirection = direction);
    }
  }

  /// "Now playing": follow the video again, starting with a glide back.
  void _resumeFollowing() {
    setState(() {
      _following = true;
      _jumpDirection = null;
      _lastScrolledIndex = null;
    });
    _maybeScrollToCurrent(_activeIndex);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _following = false;
      _lastScrolledIndex = null;
    }
    if (_following) return false;
    if (notification is ScrollEndNotification &&
        _offscreenDirection() == null) {
      // Scrolled back to the playing line by hand: pick up following.
      _following = true;
    }
    _updateJumpButton();
    return false;
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
    if (currentIndex >= 0) _activeIndex = currentIndex;

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
          builder: (context, constraints) => Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
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
                          ? () {
                              // Playing from here: follow it again.
                              _following = true;
                              _updateJumpButton();
                              controller.seekTo(
                                seconds: sentence.startSeconds.toDouble(),
                              );
                            }
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
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Center(
                  child: _NowPlayingButton(
                    direction: _jumpDirection,
                    onPressed: _resumeFollowing,
                  ),
                ),
              ),
            ],
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
          deckId: request.deckId,
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

/// Brings the transcript back to the line being played. Slides in while that
/// line is out of view, pointing the way to it.
class _NowPlayingButton extends StatelessWidget {
  /// Null hides the button.
  final AxisDirection? direction;
  final VoidCallback onPressed;

  const _NowPlayingButton({required this.direction, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final visible = direction != null;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.6),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(
              direction == AxisDirection.up
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 16,
            ),
            label: const Text('Now playing'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: Theme.of(context).textTheme.labelMedium,
              elevation: 3,
            ),
          ),
        ),
      ),
    );
  }
}
