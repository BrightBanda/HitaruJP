import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:ingrain/core/utils/duration_format.dart';
import 'package:ingrain/features/content/data/youtube_url_parser.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/player_host/player_host.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/content/presentation/view/player/recommended_videos.dart';
import 'package:ingrain/features/content/presentation/view/player/transcript_view.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';

final playbackPositionProvider =
    NotifierProvider<PlaybackPositionNotifier, Duration>(
      PlaybackPositionNotifier.new,
    );

class PlaybackPositionNotifier extends Notifier<Duration> {
  @override
  Duration build() => Duration.zero;

  void setPosition(Duration position) {
    state = position;
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerControllerNotifier, YoutubePlayerController?>(
      PlayerControllerNotifier.new,
    );

class PlayerControllerNotifier extends Notifier<YoutubePlayerController?> {
  @override
  YoutubePlayerController? build() => null;

  void setController(YoutubePlayerController? controller) {
    state = controller;
  }

  /// Clears the controller only if it is still [controller], so a player
  /// closing late never wipes out the one that replaced it.
  void clearIfCurrent(YoutubePlayerController controller) {
    if (identical(state, controller)) state = null;
  }
}

class ImmersionPlayerView extends ConsumerStatefulWidget {
  final String contentId;

  const ImmersionPlayerView({super.key, required this.contentId});

  @override
  ConsumerState<ImmersionPlayerView> createState() =>
      _ImmersionPlayerViewState();
}

class _ImmersionPlayerViewState extends ConsumerState<ImmersionPlayerView>
    with RouteAware {
  // The player itself belongs to the app-wide [PlayerHost], so the video can
  // carry on in a small window after this screen closes.
  late YoutubePlayerController _controller;
  late final PlayerHost _host;
  StreamSubscription<YoutubePlayerValue>? _playerStreamSubscription;
  final _slotKey = GlobalKey();
  final _transcriptKey = GlobalKey();
  bool _videoLoadStarted = false;
  bool _videoReady = false;
  bool _playerIsPlaying = false;
  bool _covered = false;
  bool _trackingSlot = true;
  String? _videoId;
  String? _playerError;
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _host = ref.read(playerHostProvider.notifier);
    _controller = _host.acquire(widget.contentId);
    // A video already loaded (reopened from the small window) is on its way.
    if (_host.loadedVideoId != null) {
      _videoLoadStarted = true;
      _videoReady = true;
      _videoId = _host.loadedVideoId;
      _playerIsPlaying = _controller.value.playerState == PlayerState.playing;
    }
    _host.onResourceError = (error) {
      // The page loads many sub-resources (ads, trackers, thumbnails) and
      // the WebView reports each one that is blocked or fails as
      // net::ERR_FAILED, though the video itself plays fine. Only the page
      // failing to load, before anything has played, is a real error.
      if (!mounted || error.isForMainFrame == false || _videoReady) return;
      setState(() {
        _playerError = 'Network error: ${error.description}';
        _videoReady = false;
        _videoLoadStarted = false;
      });
    };

    // Screen state only: the immersion session follows the player in the host.
    _playerStreamSubscription = _controller.stream.listen((value) {
      if (!mounted) return;
      if (value.error != YoutubeError.none &&
          value.error != YoutubeError.unknown) {
        debugPrint(
          'YouTube error ${value.error.code} (${value.error.name}) '
          'for video "$_videoId" (content ${widget.contentId})',
        );
        setState(() {
          // The code and id make a report from the field traceable.
          _playerError =
              '${_mapYoutubeError(value.error)}\n'
              'YouTube error ${value.error.code} · video $_videoId';
          _videoReady = false;
          _videoLoadStarted = false;
        });
      } else if (value.playerState == PlayerState.playing ||
          value.playerState == PlayerState.paused ||
          value.playerState == PlayerState.buffering ||
          value.playerState == PlayerState.cued) {
        if (!_videoReady) {
          setState(() {
            _videoReady = true;
            _playerError = null;
          });
        }
      }

      final isPlaying = value.playerState == PlayerState.playing;
      final stopped =
          value.playerState == PlayerState.paused ||
          value.playerState == PlayerState.ended;
      if ((isPlaying && !_playerIsPlaying) || (stopped && _playerIsPlaying)) {
        setState(() => _playerIsPlaying = isPlaying);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback(_trackSlot);

    // Load the video once the content item is known, rather than checking on
    // every build of this screen.
    ref.listenManual(contentItemProvider(widget.contentId), (_, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadVideoIfNeeded(next);
      });
    }, fireImmediately: true);
  }

  String _mapYoutubeError(YoutubeError error) {
    return switch (error) {
      YoutubeError.invalidParam => 'Invalid video ID or parameter.',
      YoutubeError.html5Error => 'HTML5 player error. Please try again.',
      YoutubeError.videoNotFound =>
        'This video could not be found or is private.',
      YoutubeError.notEmbeddable ||
      YoutubeError.sameAsNotEmbeddable ||
      YoutubeError.sameAsNotEmbeddable2 =>
        'The owner does not allow this video to be played in embedded players.',
      YoutubeError.cannotFindVideo => 'Could not find the requested video.',
      YoutubeError.none => '',
      YoutubeError.unknown => 'An error occurred while loading this video.',
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      if (_route != null) playerRouteObserver.unsubscribe(this);
      _route = route;
      playerRouteObserver.subscribe(this, route);
    }
  }

  // Another full page opened on top: the video steps aside for it.
  @override
  void didPushNext() => _covered = true;

  @override
  void didPopNext() => _covered = false;

  /// Tells the host where the video belongs on this screen, every frame the
  /// layout changes (including while the page slides in).
  void _trackSlot(Duration _) {
    if (!_trackingSlot || !mounted) return;
    Rect? slot;
    final box = _slotKey.currentContext?.findRenderObject();
    if (!_covered && box is RenderBox && box.attached && box.hasSize) {
      slot = box.localToGlobal(Offset.zero) & box.size;
    }
    if (ref.read(playerHostProvider).slot != slot) _host.setSlot(slot);
    WidgetsBinding.instance.addPostFrameCallback(_trackSlot);
  }

  @override
  void dispose() {
    _trackingSlot = false;
    playerRouteObserver.unsubscribe(this);
    _playerStreamSubscription?.cancel();
    final controller = _controller;
    final host = _host;
    host.onResourceError = null;
    // Deferred: provider state cannot change while the tree is tearing down.
    Future.microtask(() => host.leaveIfExpanded(controller));
    super.dispose();
  }

  Future<void> _loadVideoIfNeeded(AsyncValue<ContentItem> contentAsync) async {
    final content = contentAsync.asData?.value;
    if (content == null || _videoLoadStarted) return;
    if (content.sourceType != SourceType.youtube) return;

    // Self-healing: if content.id was previously saved as a raw tracking param
    // or invalid id, re-extract the real video ID from the source URL.
    final resolvedId =
        YoutubeUrlParser.tryParse(content.sourceUrl) ??
        YoutubeUrlParser.tryParse(content.id) ??
        content.id;

    _videoId = resolvedId;
    // Never hand YouTube something that is not a video id: it answers with
    // a bare "invalid parameter" that says nothing about the cause.
    if (YoutubeUrlParser.tryParse(resolvedId) != resolvedId) {
      setState(
        () => _playerError =
            'This video’s link is broken. Remove it and add it again.\n'
            'Saved as: ${content.sourceUrl}',
      );
      return;
    }
    _videoLoadStarted = true;
    setState(() {
      _playerError = null;
      _videoReady = false;
    });

    // Continue where the learner left off last time.
    final resumeAt = _host.resumePositionFor(content);
    try {
      await _controller.loadVideoById(
        videoId: resolvedId,
        startSeconds: resumeAt?.inSeconds.toDouble(),
      );
    } catch (_) {
      // The bridge waits for the iframe API itself, but it can still time out
      // or fail on weak mobile connections.
      _videoLoadStarted = false;
      if (!mounted) return;
      setState(
        () => _playerError =
            'Could not load this video. Please check your connection.',
      );
      return;
    }

    _host.loadedVideoId = resolvedId;
    if (!mounted) return;
    setState(() => _videoReady = true);
    if (resumeAt != null) _showResumed(resumeAt);
  }

  void _showResumed(Duration at) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Continuing where you left off (${formatDuration(at)})'),
        action: SnackBarAction(
          label: 'Start over',
          onPressed: () => _controller.seekTo(seconds: 0, allowSeekAhead: true),
        ),
      ),
    );
  }

  /// Re-issues the load command after a failure.
  Future<void> _retryLoad() async {
    final videoId = _videoId;
    if (videoId == null) return;
    setState(() {
      _playerError = null;
      _videoReady = false;
      _videoLoadStarted = true;
    });

    final content = ref.read(contentItemProvider(widget.contentId)).value;
    final resumeAt = content == null ? null : _host.resumePositionFor(content);
    try {
      await _controller.loadVideoById(
        videoId: videoId,
        startSeconds: resumeAt?.inSeconds.toDouble(),
      );
    } catch (_) {
      _videoLoadStarted = false;
      if (!mounted) return;
      setState(
        () => _playerError = 'Could not load this video. Please try again.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _videoReady = true);
  }

  /// Back (or the minimise button) leaves the screen. A playing video keeps
  /// going in a small window over the rest of the app; one that is paused or
  /// finished is closed.
  void _onBack(bool didPop, Object? result) {
    if (didPop) return;
    _host.leave();
    context.pop();
  }

  /// YouTube's own captions, in Japanese. The iframe API has no call for this
  /// in the Dart package, so the captions module is driven directly.
  Future<void> _toggleCaptions() async {
    final on = !_host.captionsOn;
    setState(() => _host.captionsOn = on);
    final js = on
        ? "player.loadModule('captions');"
              "player.setOption('captions','track',{languageCode:'ja'});"
        : "player.unloadModule('captions');";
    try {
      await _controller.webViewController.runJavaScript(js);
    } catch (_) {
      // The player is not ready yet: undo the switch so it shows the truth.
      if (mounted) setState(() => _host.captionsOn = !on);
    }
  }

  /// Sends the video to the small window and goes back to browsing, even when
  /// it is paused.
  void _minimize() {
    _host.minimize();
    context.pop();
  }

  Future<void> _togglePlayback() async {
    final sessionVm = ref.read(
      immersionSessionViewModelProvider(widget.contentId).notifier,
    );
    final sessionState = ref.read(
      immersionSessionViewModelProvider(widget.contentId),
    );
    final content = ref
        .read(contentItemProvider(widget.contentId))
        .asData
        ?.value;
    final title = content?.title ?? 'Video';

    if (_playerIsPlaying ||
        _controller.value.playerState == PlayerState.playing) {
      await _controller.pauseVideo();
      if (sessionState.isRunning && !sessionState.isPaused) {
        sessionVm.pauseSession();
      }
      return;
    }

    if (!sessionState.hasActiveSession) {
      sessionVm.startSession(sourceTitle: title);
    } else if (sessionState.isPaused) {
      sessionVm.resumeSession();
    }
    await _controller.playVideo();
  }

  Future<void> _confirmStopSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop session?'),
        content: const Text(
          'This will end the current session, but the elapsed time will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop session'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final sessionVm = ref.read(
      immersionSessionViewModelProvider(widget.contentId).notifier,
    );
    await sessionVm.stopSession();
    await _controller.pauseVideo();
    if (mounted) {
      setState(() => _playerIsPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contentAsync = ref.watch(contentItemProvider(widget.contentId));
    // Only what this screen draws itself. The session's ticking clock and
    // position are watched by the small widgets that show them, so they no
    // longer rebuild the player every second.
    final sessionLive = ref.watch(
      immersionSessionViewModelProvider(widget.contentId)
          .select((session) => session.isRunning && !session.isPaused),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: _buildScreen(contentAsync, sessionLive),
    );
  }

  Widget _buildScreen(AsyncValue<ContentItem> contentAsync, bool sessionLive) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HitaruJP'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Edit transcript',
            onPressed: () =>
                context.push('/content/${widget.contentId}/transcript'),
          ),
          if (sessionLive)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.circle, color: Colors.green, size: 12),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Its own layer: repaints elsewhere on the screen leave the video's
          // platform view untouched. The key keeps it (and the transcript)
          // the same widget when a resize switches layouts, so the video is
          // moved rather than reloaded.
          final player = _buildPlayer(contentAsync);
          // Right under the video, so reading along never means looking away
          // from it. Three lines: the one before, the current one centred,
          // and the next.
          final transcript = SizedBox(
            height: TranscriptView.heightForRows(context, 3),
            child: RepaintBoundary(
              key: _transcriptKey,
              child: TranscriptView(contentId: widget.contentId),
            ),
          );
          final recommended = RecommendedVideos(currentYoutubeId: _videoId);
          final controls = Column(
            children: [
              if (_playerError != null) _buildPlayerError(),
              _buildPlaybackControls(),
              _SessionControls(
                contentId: widget.contentId,
                title: contentAsync.whenOrNull(data: (c) => c.title),
                onStop: _confirmStopSession,
              ),
            ],
          );

          if (constraints.maxWidth < _wideMinWidth) {
            return Column(
              children: [
                player,
                transcript,
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(children: [controls, recommended]),
                  ),
                ),
              ],
            );
          }

          // Wide: the video shrinks to fit the window's height rather than
          // pushing the transcript and controls off screen.
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Flexible(
                        // Rounded corners on mobile only: clipping the web
                        // <iframe> re-applies a CSS clip every frame and
                        // makes playback flicker.
                        child: kIsWeb
                            ? player
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: player,
                              ),
                      ),
                      transcript,
                      const Divider(height: 1),
                      controls,
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Up next beside the video, as on YouTube.
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(child: recommended),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// From this width the video gets padding and rounded corners.
  static const _wideMinWidth = 960.0;

  /// The empty slot where the app-wide player draws the video, over this
  /// screen. [_trackSlot] reports its position.
  Widget _buildPlayer(AsyncValue<ContentItem> contentAsync) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        key: _slotKey,
        color: Colors.black12,
        child: contentAsync.when(
          data: (content) => content.sourceType == SourceType.youtube
              ? const SizedBox.shrink()
              : const Center(child: Text('Only YouTube content is supported')),
          loading: () => const Center(child: Text('Loading...')),
          error: (_, _) => const Center(child: Text('Failed to load content')),
        ),
      ),
    );
  }

  Widget _buildPlayerError() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _playerError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(onPressed: _retryLoad, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls() {
    final isPlaying =
        _playerIsPlaying ||
        _controller.value.playerState == PlayerState.playing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            tooltip: isPlaying ? 'Pause' : 'Play',
            onPressed: _togglePlayback,
          ),
          DropdownButton<double>(
            value: _host.playbackRate,
            items: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                .map((v) => DropdownMenuItem(value: v, child: Text('${v}x')))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _host.playbackRate = value);
                _controller.setPlaybackRate(value);
              }
            },
          ),
          IconButton(
            icon: Icon(
              _host.captionsOn
                  ? Icons.closed_caption
                  : Icons.closed_caption_off,
            ),
            tooltip: _host.captionsOn ? 'Hide captions' : 'Show captions',
            onPressed: _toggleCaptions,
          ),
          IconButton(
            icon: const Icon(Icons.picture_in_picture_alt),
            tooltip: 'Mini player',
            onPressed: _minimize,
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: () => _controller.enterFullScreen(),
          ),
        ],
      ),
    );
  }
}

/// The session clock, title and stop button. Watches the session on its own so
/// the once-a-second clock tick redraws only this row.
class _SessionControls extends ConsumerWidget {
  final String contentId;
  final String? title;
  final VoidCallback onStop;

  const _SessionControls({
    required this.contentId,
    required this.title,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (elapsedSeconds, hasActiveSession) = ref.watch(
      immersionSessionViewModelProvider(
        contentId,
      ).select((session) => (session.elapsedSeconds, session.hasActiveSession)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            formatDuration(Duration(seconds: elapsedSeconds)),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryMain,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title ?? 'Loading...',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          if (hasActiveSession)
            TextButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop session'),
            ),
        ],
      ),
    );
  }
}
