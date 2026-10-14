import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/ai/domain/ai_explanation.dart';
import 'package:ingrain/features/ai/presentation/ai_explanation_providers.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/features/dialogue/presentation/widgets/dialogue_token_row.dart';
import 'package:ingrain/features/dialogue/presentation/widgets/speaker_label.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/immersion/presentation/view/immersion_session_scope.dart';
import 'package:ingrain/features/sentence_mining/presentation/view/sentence_save_sheet.dart';
import 'package:ingrain/features/sentence_mining/presentation/viewmodel/sentence_mining_view_model.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/presentation/view/vocabulary_lookup_sheet.dart';
import 'package:ingrain/features/vocabulary/presentation/view/vocabulary_save_sheet.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/features/settings/presentation/viewmodel/settings_view_model.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:url_launcher/url_launcher.dart';

class DialogueReaderView extends ConsumerStatefulWidget {
  final String dialogueId;

  const DialogueReaderView({super.key, required this.dialogueId});

  @override
  ConsumerState<DialogueReaderView> createState() => _DialogueReaderViewState();
}

class _DialogueReaderViewState extends ConsumerState<DialogueReaderView> {
  /// Whether each line shows its English translation. Off by default: a
  /// translation is an AI request, so none are made until the learner asks.
  bool _showTranslation = false;

  String get dialogueId => widget.dialogueId;

  @override
  Widget build(BuildContext context) {
    final dialogueAsync = ref.watch(
      dialogueReaderViewModelProvider(dialogueId),
    );
    final settings = ref.watch(settingsViewModelProvider).settings;
    final showRomaji = settings?.showRomaji ?? false;
    final isCached = ref.read(dialogueRepositoryProvider).isShowingCachedCopy;

    return Scaffold(
      appBar: AppBar(
        title: dialogueAsync.asData == null
            ? const Text('Dialogue')
            : Text(dialogueAsync.asData!.value.title),
        actions: [
          if (dialogueAsync.asData?.value.source.url != null)
            IconButton(
              tooltip: 'Open source',
              icon: const Icon(Icons.open_in_new),
              onPressed: () =>
                  _openSource(context, dialogueAsync.asData!.value.source.url!),
            ),
        ],
      ),
      body: dialogueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load this dialogue'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref
                    .read(dialogueReaderViewModelProvider(dialogueId).notifier)
                    .refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (dialogue) => ImmersionSessionScope(
          // Reading counts as immersion while the dialogue is open.
          sourceId: 'dialogue:${dialogue.id}',
          sourceTitle: dialogue.title,
          activityType: ActivityType.reading,
          child: Column(
            children: [
              if (isCached) const _CachedDialogueNotice(),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: _DialogueHeader(dialogue: dialogue),
                      ),
                    ),
                    // Stays under the app bar while the lines scroll past.
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ReaderOptionsBar(
                        showRomaji: showRomaji,
                        showTranslation: _showTranslation,
                        onRomaji: () => ref
                            .read(settingsViewModelProvider.notifier)
                            .setShowRomaji(!showRomaji),
                        onTranslation: () => setState(
                          () => _showTranslation = !_showTranslation,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      sliver: SliverList.separated(
                        itemCount: dialogue.lines.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final line = dialogue.lines[index];
                          return _DialogueLineCard(
                            dialogue: dialogue,
                            line: line,
                            showRomaji: showRomaji,
                            showTranslation: _showTranslation,
                            onTokenTap: (token) => _openLookup(
                              context,
                              ref,
                              dialogue,
                              line,
                              token,
                            ),
                            onMine: () =>
                                _mineLine(context, ref, dialogue, line),
                          );
                        },
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
  }

  Future<void> _openLookup(
    BuildContext context,
    WidgetRef ref,
    Dialogue dialogue,
    DialogueLine line,
    DialogueToken token,
  ) async {
    final dictionary = await ref.read(dictionaryProvider.future);
    final entry = dictionary.lookup(token.surface);
    final repository = ref.read(vocabularyRepositoryProvider);
    final alreadySaved = await repository.findByWord(token.surface) != null;
    if (!context.mounted) return;

    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => VocabularyLookupSheet(
        word: token.surface,
        entry: entry,
        reading: token.reading,
        contextLabel: SentenceMiningViewModel.contextForDialogue(
          dialogue.lines,
          line.index,
        ),
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
        word: token.surface,
        reading: token.reading ?? entry?.reading,
        meaning: entry?.primaryMeaning,
        pos: entry?.pos,
        contextLabel: SentenceMiningViewModel.contextForDialogue(
          dialogue.lines,
          line.index,
        ),
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
          sourceType: SourceType.dialogue,
          sourceId: dialogue.id,
          sourceTitle: dialogue.title,
          contextSentence: SentenceMiningViewModel.contextForDialogue(
            dialogue.lines,
            line.index,
          ),
        );
    ref.invalidate(dueCountProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Word saved for review')));
    }
  }

  Future<void> _mineLine(
    BuildContext context,
    WidgetRef ref,
    Dialogue dialogue,
    DialogueLine line,
  ) async {
    final contextLabel = SentenceMiningViewModel.contextForDialogue(
      dialogue.lines,
      line.index,
    );
    final request = await showModalBottomSheet<SentenceSaveRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SentenceSaveSheet(
        title: 'Mine sentence',
        japanese: line.text,
        contextLabel: contextLabel,
      ),
    );
    if (request == null || !context.mounted) return;
    final saved = await ref
        .read(sentenceMiningViewModelProvider.notifier)
        .saveFromDialogue(
          dialogueId: dialogue.id,
          dialogueTitle: dialogue.title,
          line: line,
          lines: dialogue.lines,
          translation: request.translation,
          explanation: request.explanation,
        );
    ref.invalidate(dueCountProvider);
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sentence saved for review')),
      );
    }
  }

  static Future<void> _openSource(
    BuildContext context,
    String sourceUrl,
  ) async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(sourceUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open source page')),
      );
    }
  }
}

/// Title, level and cast on the hero gradient.
class _DialogueHeader extends StatelessWidget {
  final Dialogue dialogue;

  const _DialogueHeader({required this.dialogue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStory = dialogue.kind == DialogueKind.story;
    return GradientPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isStory ? Icons.menu_book : Icons.forum,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dialogue.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(label: dialogue.level, color: Colors.white),
              Pill(
                label: '${dialogue.lines.length} lines',
                color: Colors.white,
              ),
              for (final speaker in dialogue.speakers)
                Pill(
                  label: speaker,
                  color: speakerColor(speaker, dialogue.speakers),
                  solid: true,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Tap a word to look it up. Bookmark a line to review it later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line as a chat bubble in its speaker's colour. Speakers alternate
/// sides; a line with no speaker (a story) spans the full width.
class _DialogueLineCard extends StatelessWidget {
  final Dialogue dialogue;
  final DialogueLine line;
  final bool showRomaji;
  final bool showTranslation;
  final ValueChanged<DialogueToken> onTokenTap;
  final VoidCallback onMine;

  const _DialogueLineCard({
    required this.dialogue,
    required this.line,
    required this.showRomaji,
    required this.showTranslation,
    required this.onTokenTap,
    required this.onMine,
  });

  @override
  Widget build(BuildContext context) {
    final speaker = line.speaker;
    final color = speaker == null
        ? AppColors.primaryMain
        : speakerColor(speaker, dialogue.speakers);
    final onRight = speaker != null && dialogue.speakers.indexOf(speaker).isOdd;

    final bubble = TintedSurface(
      color: color,
      alpha: 0.12,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (speaker != null)
            SpeakerLabel(speaker: speaker, speakers: dialogue.speakers),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DialogueTokenRow(
                  line: line,
                  showRomaji: showRomaji,
                  onTokenTap: onTokenTap,
                ),
              ),
              IconButton(
                tooltip: 'Mine sentence',
                icon: const Icon(Icons.bookmark_add_outlined),
                color: color,
                onPressed: onMine,
              ),
            ],
          ),
          if (showTranslation)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: _LineTranslation(text: line.text),
            ),
        ],
      ),
    );

    if (speaker == null) return bubble;
    return Align(
      alignment: onRight ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(widthFactor: 0.88, child: bubble),
    );
  }
}

class _CachedDialogueNotice extends StatelessWidget {
  const _CachedDialogueNotice();

  @override
  Widget build(BuildContext context) => const MaterialBanner(
    content: Text('Showing cached copy'),
    leading: Icon(Icons.cloud_off_outlined),
    actions: [SizedBox.shrink()],
  );
}

/// The romaji and translation switches, pinned under the app bar.
class _ReaderOptionsBar extends SliverPersistentHeaderDelegate {
  final bool showRomaji;
  final bool showTranslation;
  final VoidCallback onRomaji;
  final VoidCallback onTranslation;

  const _ReaderOptionsBar({
    required this.showRomaji,
    required this.showTranslation,
    required this.onRomaji,
    required this.onTranslation,
  });

  static const _height = 52.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      elevation: overlapsContent ? 2 : 0,
      child: SizedBox(
        height: _height,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilterChip(
                avatar: const Icon(Icons.translate, size: 18),
                label: const Text('Romaji'),
                selected: showRomaji,
                onSelected: (_) => onRomaji(),
              ),
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.subtitles_outlined, size: 18),
                label: Text(
                  showTranslation ? 'Hide translation' : 'See translation',
                ),
                selected: showTranslation,
                onSelected: (_) => onTranslation(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_ReaderOptionsBar old) =>
      old.showRomaji != showRomaji || old.showTranslation != showTranslation;
}

/// One line's translation, fetched when it first scrolls into view.
class _LineTranslation extends ConsumerWidget {
  final String text;

  const _LineTranslation({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final request = (text: text, kind: ExplainKind.sentence, context: null);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
    );
    return ref
        .watch(aiExplanationProvider(request))
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, _) => Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref.invalidate(aiExplanationProvider(request)),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Translation failed, retry'),
            ),
          ),
          data: (explanation) => Text(explanation.translation, style: style),
        );
  }
}
