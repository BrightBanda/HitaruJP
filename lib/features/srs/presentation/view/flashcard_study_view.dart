import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/immersion/presentation/view/immersion_session_scope.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// Studies the due cards of one deck, or of every deck when [deckId] is null.
class FlashcardStudyView extends ConsumerStatefulWidget {
  final String? deckId;
  final String? title;

  const FlashcardStudyView({super.key, this.deckId, this.title});

  @override
  ConsumerState<FlashcardStudyView> createState() => _FlashcardStudyViewState();
}

class _FlashcardStudyViewState extends ConsumerState<FlashcardStudyView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(reviewViewModelProvider.notifier)
          .startSession(deckId: widget.deckId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(reviewViewModelProvider);
    final remaining = session.isLoading
        ? 0
        : session.total - session.currentIndex;

    // Studying cards counts as immersion time too.
    return ImmersionSessionScope(
      sourceId: 'flashcards:${widget.deckId ?? 'all'}',
      sourceTitle: widget.title ?? 'Flashcards',
      activityType: ActivityType.reviewing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? 'Study'),
          actions: [
            if (remaining > 0)
              Center(
                child: Pill(
                  label: '$remaining due',
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.style,
                  solid: true,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh due cards',
              onPressed: () =>
                  ref.read(reviewViewModelProvider.notifier).refreshDue(),
            ),
          ],
        ),
        body: _buildBody(session),
      ),
    );
  }

  Widget _buildBody(ReviewSessionState session) {
    if (session.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (session.isEmpty) return _buildEmpty();
    if (session.isComplete) return _buildComplete(session);

    final card = session.currentCard!;
    return Column(
      children: [
        _ProgressHeader(
          index: session.currentIndex + 1,
          total: session.total,
          progress: session.progress,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PromptCard(card: card),
                const SizedBox(height: 20),
                if (session.answerShown)
                  _AnswerPanel(answerText: card.answerText, card: card)
                else
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(reviewViewModelProvider.notifier).showAnswer(),
                    icon: const Icon(Icons.visibility),
                    label: const Text('Show answer'),
                  ),
              ],
            ),
          ),
        ),
        if (session.answerShown)
          _RatingBar(
            onRate: (rating) => _submit(rating),
            delayFor: (rating) =>
                ref.read(reviewViewModelProvider.notifier).previewDelay(rating),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _submit(Rating rating) async {
    await ref.read(reviewViewModelProvider.notifier).submitAnswer(rating);
    ref.invalidate(dueCountProvider);
    ref.invalidate(deckSummariesProvider);
    ref.invalidate(deckDetailProvider);
    ref.invalidate(progressViewModelProvider);
  }

  Widget _buildEmpty() {
    return EmptyState(
      icon: Icons.check_rounded,
      color: Theme.of(context).colorScheme.primary,
      title: 'All caught up',
      message:
          'Nothing is due right now. Save lines while you immerse, or add '
          'cards to a deck, and they will queue up here.',
    );
  }

  Widget _buildComplete(ReviewSessionState session) {
    return EmptyState(
      icon: Icons.celebration,
      color: Theme.of(context).colorScheme.primary,
      title: 'Session complete',
      message: '${session.reviewedThisSession} reviewed',
      action: Column(
        children: [
          FilledButton.icon(
            onPressed: () =>
                ref.read(reviewViewModelProvider.notifier).refreshDue(),
            icon: const Icon(Icons.refresh),
            label: const Text('Check for more'),
          ),
          if (Navigator.of(context).canPop()) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to decks'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The flashcard face: what to recall, on the hero gradient.
class _PromptCard extends ConsumerWidget {
  final ReviewCard card;

  const _PromptCard({required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (label, icon) = switch (card.cardType) {
      CardType.vocabulary => ('Word', Icons.translate),
      CardType.sentence => ('Sentence', Icons.format_quote),
      CardType.basic => ('Card', Icons.style),
    };
    // Vocabulary cards recall a word together with its reading (`猫 (ねこ)`);
    // the saved word is resolved so older cards that only stored the kanji
    // still show the hiragana.
    final prompt = switch (card.cardType) {
      CardType.vocabulary =>
        ref
                .watch(vocabularyItemProvider(card.sourceItemId))
                .value
                ?.displayWithReading ??
            card.promptText,
      CardType.sentence => card.promptText,
      CardType.basic => card.promptText,
    };
    return GradientPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Pill(label: label, icon: icon, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            prompt,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 26,
              height: 1.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int index;
  final int total;
  final double progress;

  const _ProgressHeader({
    required this.index,
    required this.total,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: primary.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$index / $total', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AnswerPanel extends StatelessWidget {
  final String? answerText;
  final ReviewCard card;

  const _AnswerPanel({required this.answerText, required this.card});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TintedSurface(
      color: theme.colorScheme.primary,
      alpha: 0.1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (answerText != null)
            Text(
              answerText!,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Text(
              'No answer saved for this card. Recall the meaning, then '
              'rate yourself.',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 12),
          Text(
            'Interval ${card.intervalDays}d • '
            'ease ${card.easeFactor.toStringAsFixed(2)} • '
            'seen ${card.reviewCount}x',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RatingBar extends StatelessWidget {
  final ValueChanged<Rating> onRate;
  final Duration Function(Rating) delayFor;

  const _RatingBar({required this.onRate, required this.delayFor});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Only "Again" stands out; the rest share the brand colour, strongest for
    // the answer that pushes the card furthest away.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _RatingButton(
            label: 'Again',
            color: scheme.error,
            alpha: 0.14,
            onPressed: () => onRate(Rating.again),
            intervalLabel: _label(Rating.again),
          ),
          _RatingButton(
            label: 'Hard',
            color: scheme.primary,
            alpha: 0.1,
            onPressed: () => onRate(Rating.hard),
            intervalLabel: _label(Rating.hard),
          ),
          _RatingButton(
            label: 'Good',
            color: scheme.primary,
            alpha: 0.18,
            onPressed: () => onRate(Rating.good),
            intervalLabel: _label(Rating.good),
          ),
          _RatingButton(
            label: 'Easy',
            color: scheme.primary,
            alpha: 0.26,
            onPressed: () => onRate(Rating.easy),
            intervalLabel: _label(Rating.easy),
          ),
        ],
      ),
    );
  }

  String _label(Rating rating) => formatInterval(delayFor(rating));
}

class _RatingButton extends StatelessWidget {
  final String label;
  final String intervalLabel;
  final Color color;
  final double alpha;
  final VoidCallback onPressed;

  const _RatingButton({
    required this.label,
    required this.intervalLabel,
    required this.color,
    required this.alpha,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide.none,
            backgroundColor: color.withValues(alpha: alpha),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                intervalLabel,
                style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Anki's compact interval labels: 45s, 10m, 3h, 4d, 1.5mo, 2.1y.
String formatInterval(Duration delay) {
  final seconds = delay.inSeconds;
  if (seconds < 60) return '${seconds < 1 ? 1 : seconds}s';
  if (delay.inMinutes < 60) return '${delay.inMinutes}m';
  if (delay.inHours < 24) return '${delay.inHours}h';
  final days = delay.inHours / 24;
  if (days < 30) return '${days.round()}d';
  String oneDecimal(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  if (days < 365) return '${oneDecimal(days / 30)}mo';
  return '${oneDecimal(days / 365)}y';
}
