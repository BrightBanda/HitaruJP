import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';

/// Tells the learner [contentId]'s transcript could not be fetched (as
/// opposed to the video having none), with a Retry.
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
