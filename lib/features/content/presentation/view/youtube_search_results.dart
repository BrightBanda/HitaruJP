import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/core/utils/duration_format.dart';
import 'package:ingrain/features/content/domain/video_search.dart';
import 'package:ingrain/features/content/presentation/view/transcript_fetch_status.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:ingrain/shared/widgets/network_thumbnail.dart';
import 'package:ingrain/shared/widgets/web_transcript_notice.dart';

enum _ImportState { idle, adding, added }

/// YouTube results for [query], each with "Add to library" and "Watch".
class YoutubeSearchResults extends ConsumerStatefulWidget {
  final String query;

  const YoutubeSearchResults({super.key, required this.query});

  @override
  ConsumerState<YoutubeSearchResults> createState() =>
      _YoutubeSearchResultsState();
}

class _YoutubeSearchResultsState extends ConsumerState<YoutubeSearchResults> {
  /// Results are shown a few at a time; "Show more" reveals the next batch.
  static const pageSize = 5;

  final Map<String, _ImportState> _states = {};
  int _visible = pageSize;

  @override
  void didUpdateWidget(YoutubeSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _visible = pageSize;
  }

  Future<void> _import(VideoSearchResult video, {required bool watch}) async {
    setState(() => _states[video.videoId] = _ImportState.adding);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(contentViewModelProvider.notifier)
          .importYoutubeVideo(video);
      if (!mounted) return;
      setState(() => _states[video.videoId] = _ImportState.added);

      if (result.transcriptError case final error?) {
        showTranscriptFailedSnackBar(
          messenger,
          ref,
          contentId: result.item.id,
          error: error,
        );
      } else if (!result.hasTranscript) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              WebTranscriptNotice.applies
                  ? WebTranscriptNotice.missingTranscript
                  : 'No Japanese subtitles on this video. Add a transcript to '
                        'read along.',
            ),
            action: SnackBarAction(
              label: 'Add',
              onPressed: () =>
                  context.push('/content/${result.item.id}/transcript'),
            ),
          ),
        );
      } else if (!watch) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.wasInLibrary
                  ? 'Already in your library'
                  : 'Added to your library',
            ),
          ),
        );
      }
      if (watch && mounted) context.push('/content/${result.item.id}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _states[video.videoId] = _ImportState.idle);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add this video: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(videoSearchProvider(widget.query));
    final primary = Theme.of(context).colorScheme.primary;

    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: TintedSurface(
          color: Theme.of(context).colorScheme.error,
          child: Row(
            children: [
              const Expanded(
                child: Text('YouTube search failed. Check your connection.'),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(videoSearchProvider(widget.query)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (videos) => videos.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No videos found for "${widget.query.trim()}".',
                textAlign: TextAlign.center,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  'Videos',
                  padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
                ),
                for (final video in videos.take(_visible))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _VideoResultCard(
                      video: video,
                      state: _states[video.videoId] ?? _ImportState.idle,
                      accent: primary,
                      onAdd: () => _import(video, watch: false),
                      onWatch: () => _import(video, watch: true),
                    ),
                  ),
                if (videos.length > _visible)
                  TextButton.icon(
                    onPressed: () => setState(() => _visible += pageSize),
                    icon: const Icon(Icons.expand_more),
                    label: Text('Show more (${videos.length - _visible} left)'),
                  ),
              ],
            ),
    );
  }
}

class _VideoResultCard extends StatelessWidget {
  final VideoSearchResult video;
  final _ImportState state;
  final Color accent;
  final VoidCallback onAdd;
  final VoidCallback onWatch;

  const _VideoResultCard({
    required this.video,
    required this.state,
    required this.accent,
    required this.onAdd,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = video.duration;
    final busy = state == _ImportState.adding;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 128,
                    height: 72,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetworkThumbnail(
                          url: video.thumbnailUrl,
                          placeholder: ColoredBox(
                            color: accent.withValues(alpha: 0.14),
                            child: Icon(Icons.smart_display, color: accent),
                          ),
                        ),
                        if (duration != null)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                formatDuration(duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                        ),
                      ),
                      if (video.channelTitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          video.channelTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy || state == _ImportState.added
                        ? null
                        : onAdd,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            state == _ImportState.added
                                ? Icons.check
                                : Icons.library_add,
                          ),
                    label: Text(
                      state == _ImportState.added
                          ? 'In library'
                          : 'Add to library',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onWatch,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Watch'),
                  ),
                ),
              ],
            ),
            TranscriptFetchStatusLine(videoId: video.videoId),
          ],
        ),
      ),
    );
  }
}
