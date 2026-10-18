import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/content/data/fallback_transcript_fetcher.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';

extension TranscriptFetchStageText on TranscriptFetchStage {
  String get message => switch (this) {
    TranscriptFetchStage.fetching => 'Fetching Japanese subtitles…',
    TranscriptFetchStage.retrying => 'YouTube did not answer. Retrying…',
    TranscriptFetchStage.server => 'Trying the HitaruJP server…',
    TranscriptFetchStage.officialApi => "Checking with YouTube's official API…",
  };
}

/// One line under a loading video card saying how the transcript fetch is
/// going. Nothing while no fetch runs for [videoId].
class TranscriptFetchStatusLine extends ConsumerWidget {
  final String? videoId;

  /// For text drawn over a thumbnail.
  final Color? color;

  const TranscriptFetchStatusLine({super.key, this.videoId, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = videoId;
    final stage = id == null
        ? null
        : ref.watch(transcriptFetchStatusProvider.select((all) => all[id]));
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topLeft,
      child: stage == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        stage.message,
                        key: ValueKey(stage),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Tells the learner every source failed for [contentId]'s transcript, with a
/// Retry that runs the whole chain again.
void showTranscriptFailedSnackBar(
  ScaffoldMessengerState messenger,
  WidgetRef ref, {
  required String contentId,
  required String error,
}) {
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: Text("Couldn't load the subtitles. $error"),
      action: SnackBarAction(
        label: 'Retry',
        onPressed: () async {
          messenger.showSnackBar(
            const SnackBar(content: Text('Fetching the subtitles again…')),
          );
          final result = await ref
              .read(contentViewModelProvider.notifier)
              .refetchTranscript(contentId);
          messenger.hideCurrentSnackBar();
          if (result.hasTranscript) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Subtitles loaded.')),
            );
          } else if (result.transcriptError case final error?) {
            showTranscriptFailedSnackBar(
              messenger,
              ref,
              contentId: contentId,
              error: error,
            );
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('This video has no Japanese subtitles.'),
              ),
            );
          }
        },
      ),
    ),
  );
}
