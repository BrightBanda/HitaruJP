import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/content/domain/video_search.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/playlists/presentation/viewmodel/playlist_view_model.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';

/// Opens a playlist or deck someone shared by code and adds a copy of it.
class ImportShareView extends ConsumerStatefulWidget {
  final String? initialCode;

  const ImportShareView({super.key, this.initialCode});

  @override
  ConsumerState<ImportShareView> createState() => _ImportShareViewState();
}

class _ImportShareViewState extends ConsumerState<ImportShareView> {
  late final _controller = TextEditingController(text: widget.initialCode);
  SharedCollection? _shared;
  String? _error;
  bool _looking = false;

  /// While importing: how many items are in so far.
  int? _imported;

  @override
  void initState() {
    super.initState();
    if ((widget.initialCode ?? '').isNotEmpty) _lookUp();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _looking = true;
      _error = null;
      _shared = null;
    });
    try {
      final shared = await ref.read(socialRepositoryProvider).share(code);
      if (mounted) setState(() => _shared = shared);
    } on SocialException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reach the HitaruJP server.');
      }
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _import(SharedCollection shared) async {
    setState(() => _imported = 0);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (shared.kind == ShareKind.playlist) {
        final content = ref.read(contentViewModelProvider.notifier);
        final ids = <String>[];
        for (final video in shared.videos) {
          final imported = await content.importYoutubeVideo(
            VideoSearchResult(
              videoId: video.videoId,
              title: video.title,
              channelTitle: video.channelTitle,
              thumbnailUrl:
                  video.thumbnailUrl ??
                  'https://i.ytimg.com/vi/${video.videoId}/hqdefault.jpg',
            ),
          );
          ids.add(imported.item.id);
          if (mounted) setState(() => _imported = ids.length);
        }
        final playlist = await ref
            .read(playlistsProvider.notifier)
            .create(shared.title, videoIds: ids);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Added "${shared.title}" to your library')),
        );
        if (playlist != null) {
          context.pushReplacement('/playlists/${playlist.id}');
        }
      } else {
        final decks = ref.read(deckRepositoryProvider);
        final deck = await decks.createDeck(shared.title);
        for (final (i, card) in shared.cards.indexed) {
          await decks.addCard(
            deckId: deck.id,
            front: card.front,
            back: card.back,
          );
          if (mounted && i % 10 == 0) setState(() => _imported = i + 1);
        }
        ref.invalidate(deckSummariesProvider);
        ref.invalidate(dueCountProvider);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Added the deck "${shared.title}"')),
        );
        context.pushReplacement('/flashcards/deck/${deck.id}');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _imported = null);
        messenger.showSnackBar(
          SnackBar(content: Text('Could not import it: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shared = _shared;
    final imported = _imported;
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Enter the code a friend sent you to add their playlist or '
            'flashcard deck.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Code',
              hintText: 'ABCD2345',
              errorText: _error,
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: 'Look it up',
                onPressed: _looking ? null : _lookUp,
              ),
            ),
            onSubmitted: (_) => _lookUp(),
          ),
          if (_looking) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (shared != null) ...[
            const SizedBox(height: 24),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          shared.kind == ShareKind.playlist
                              ? Icons.playlist_play
                              : Icons.style,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            shared.title,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${shared.itemCount} '
                      '${shared.kind == ShareKind.playlist ? 'videos' : 'cards'}'
                      '${shared.owner == null ? '' : ' · from @${shared.owner}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final line
                        in shared.kind == ShareKind.playlist
                            ? shared.videos.take(5).map((v) => v.title)
                            : shared.cards
                                  .take(5)
                                  .map(
                                    (c) => c.back == null
                                        ? c.front
                                        : '${c.front} · ${c.back}',
                                  ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $line',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (shared.itemCount > 5)
                      Text(
                        'and ${shared.itemCount - 5} more',
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: imported == null
                          ? () => _import(shared)
                          : null,
                      icon: imported == null
                          ? const Icon(Icons.download)
                          : const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            ),
                      label: Text(
                        imported == null
                            ? shared.kind == ShareKind.playlist
                                  ? 'Add to my library'
                                  : 'Add to my flashcards'
                            : 'Adding $imported of ${shared.itemCount}…',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
