import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:ingrain/core/platform/picture_in_picture.dart';
import 'package:ingrain/core/utils/duration_format.dart';
import 'package:ingrain/features/content/data/youtube_url_parser.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
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

class _ImmersionPlayerViewState extends ConsumerState<ImmersionPlayerView> {
  late YoutubePlayerController _controller;
  StreamSubscription<YoutubeVideoState>? _videoStateSubscription;
  StreamSubscription<YoutubePlayerValue>? _playerStreamSubscription;
  // Saved up front: `ref` must not be used once the screen starts closing.
  late final PlayerControllerNotifier _controllerNotifier;
  final _playerKey = GlobalKey();
  final _transcriptKey = GlobalKey();
  bool _videoLoadStarted = false;
  bool _videoReady = false;
  bool _playerIsPlaying = false;
  String? _videoId;
  String? _playerError;

  @override
  void initState() {
    super.initState();
    _controllerNotifier = ref.read(playerControllerProvider.notifier);
    _controller = YoutubePlayerController(
      params: YoutubePlayerParams(
        showFullscreenButton: false,
        enableKeyboard: false,
        showControls: false,
        // The app shows its own tappable Japanese transcript, so YouTube's
        // burned-in captions would only duplicate (or contradict) it.
        enableCaption: false,
        origin: 'https://www.youtube-nocookie.com',
        strictRelatedVideos: true,
        // How often the iframe reports the position over the WebView bridge.
        // The default 100ms sent ten messages a second, each one waking the
        // UI thread; transcript lines and the seek bar only need a few.
        videoStateUpdateInterval: 250,
        // On web, YouTube's player reacts to the mouse even with its controls
        // off: hovering fades in dark gradient bars over the video. The app
        // has its own controls, so the player is made to ignore the pointer.
        // Mobile keeps the default.
        pointerEvents: kIsWeb ? PointerEvents.none : PointerEvents.initial,
      ),
      onWebResourceError: (error) {
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
      },
    );

    _videoStateSubscription = _controller.videoStateStream.listen((state) {
      ref.read(playbackPositionProvider.notifier).setPosition(state.position);
      ref
          .read(immersionSessionViewModelProvider(widget.contentId).notifier)
          .updatePosition(state.position.inSeconds);
    });

    _playerStreamSubscription = _controller.stream.listen((value) {
      if (!mounted) return;
      if (value.error != YoutubeError.none &&
          value.error != YoutubeError.unknown) {
        setState(() {
          _playerError = _mapYoutubeError(value.error);
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

      final sessionVm = ref.read(
        immersionSessionViewModelProvider(widget.contentId).notifier,
      );
      final sessionState = ref.read(
        immersionSessionViewModelProvider(widget.contentId),
      );

      final isPlaying = value.playerState == PlayerState.playing;
      final stopped =
          value.playerState == PlayerState.paused ||
          value.playerState == PlayerState.ended;
      if ((isPlaying && !_playerIsPlaying) || (stopped && _playerIsPlaying)) {
        setState(() => _playerIsPlaying = isPlaying);
        // Leaving the app while a video plays shrinks it into a floating
        // window instead of stopping the video.
        PictureInPicture.instance.setAutoEnter(isPlaying);
      }

      if (isPlaying) {
        // Whatever started playback — our button, YouTube's own surface, or
        // the player coming back from fullscreen (which pauses and then plays
        // again) — the session clock follows it.
        if (!sessionState.hasActiveSession) {
          final title =
              ref
                  .read(contentItemProvider(widget.contentId))
                  .asData
                  ?.value
                  .title ??
              'Video';
          sessionVm.startSession(sourceTitle: title);
        } else if (sessionState.isPaused) {
          sessionVm.resumeSession();
        }
      } else if (stopped) {
        if (sessionState.isRunning && !sessionState.isPaused) {
          sessionVm.pauseSession();
        }
      }
    });

    // Set controller in provider after first frame to avoid build-phase modification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controllerNotifier.setController(_controller);
      }
    });

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
  void dispose() {
    PictureInPicture.instance.setAutoEnter(false);
    _videoStateSubscription?.cancel();
    _playerStreamSubscription?.cancel();
    _controller.close();
    // Deferred: provider state cannot change while the tree is tearing down.
    final controller = _controller;
    Future.microtask(() => _controllerNotifier.clearIfCurrent(controller));
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
    _videoLoadStarted = true;
    setState(() {
      _playerError = null;
      _videoReady = false;
    });

    try {
      await _controller.loadVideoById(videoId: resolvedId);
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

    if (!mounted) return;
    setState(() => _videoReady = true);
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

    try {
      await _controller.loadVideoById(videoId: videoId);
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

  /// Back while a video plays shrinks it into the floating window; with
  /// nothing playing (or no window support) it leaves the screen as usual.
  Future<void> _onBack(bool didPop, Object? result) async {
    if (didPop) return;
    final playing =
        _playerIsPlaying ||
        _controller.value.playerState == PlayerState.playing;
    if (playing && await PictureInPicture.instance.enter()) return;
    if (mounted) context.pop();
  }

  Future<void> _seekRelative(int deltaSeconds) async {
    final current = await _controller.currentTime;
    final target = (current + deltaSeconds).clamp(0.0, double.infinity);
    await _controller.seekTo(seconds: target);
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
      child: ValueListenableBuilder<bool>(
        valueListenable: PictureInPicture.instance.active,
        builder: (context, inPip, _) => inPip
            ? Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: RepaintBoundary(
                    key: _playerKey,
                    child: _buildPlayer(contentAsync),
                  ),
                ),
              )
            : _buildScreen(contentAsync, sessionLive),
      ),
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
          final player = RepaintBoundary(
            key: _playerKey,
            child: _buildPlayer(contentAsync),
          );
          final seekBar = _SeekBar(
            controller: _controller,
            fallbackDuration: Duration(
              seconds: contentAsync.asData?.value.durationSeconds ?? 0,
            ),
          );
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
                seekBar,
                transcript,
                const Divider(height: 1),
                Expanded(child: SingleChildScrollView(child: controls)),
              ],
            );
          }

          // Wide: the video shrinks to fit the window's height rather than
          // pushing the transcript and controls off screen.
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
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
                seekBar,
                transcript,
                const Divider(height: 1),
                controls,
              ],
            ),
          );
        },
      ),
    );
  }

  /// From this width the video gets padding and rounded corners.
  static const _wideMinWidth = 960.0;

  Widget _buildPlayer(AsyncValue<ContentItem> contentAsync) {
    return contentAsync.when(
      data: (content) {
        if (content.sourceType != SourceType.youtube) {
          return _placeholderPlayer('Only YouTube content is supported');
        }
        // The iframe needs a moment to boot before the first frame renders.
        // Without this the player is an unexplained black box on slow
        // connections, which reads as "the video is not starting".
        return Stack(
          children: [
            YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
            // Not on web: there the player is an <iframe>, and Flutter
            // painting over it (an animating spinner, every frame) makes the
            // engine split each frame around the video, which stutters. The
            // player already shows the video's thumbnail while it loads.
            if (!kIsWeb && !_videoReady && _playerError == null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black12,
                  child: const Center(
                    child: SizedBox(
                      height: 28,
                      width: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => _placeholderPlayer('Loading...'),
      error: (_, _) => _placeholderPlayer('Failed to load content'),
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

  Widget _placeholderPlayer(String message) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black12,
        child: Center(child: Text(message)),
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
          IconButton(
            icon: const Icon(Icons.replay_10),
            onPressed: () => _seekRelative(-10),
          ),
          IconButton(
            icon: const Icon(Icons.forward_10),
            onPressed: () => _seekRelative(10),
          ),
          DropdownButton<double>(
            value: 1.0,
            items: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                .map((v) => DropdownMenuItem(value: v, child: Text('${v}x')))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                _controller.setPlaybackRate(value);
              }
            },
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

/// Position slider with elapsed and total time. Dragging only previews the
/// position; the video seeks once, when the thumb is released.
class _SeekBar extends ConsumerStatefulWidget {
  final YoutubePlayerController controller;
  final Duration fallbackDuration;

  const _SeekBar({required this.controller, required this.fallbackDuration});

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragSeconds;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playbackPositionProvider);
    final reported = widget.controller.value.metaData.duration;
    final duration = reported > Duration.zero
        ? reported
        : widget.fallbackDuration;
    final total = duration.inMilliseconds / 1000;
    final current = (_dragSeconds ?? position.inMilliseconds / 1000).clamp(
      0.0,
      total <= 0 ? 0.0 : total,
    );
    final labelStyle = Theme.of(context).textTheme.labelSmall;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          Text(
            formatDuration(Duration(seconds: current.round())),
            style: labelStyle,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: current.toDouble(),
                max: total <= 0 ? 1 : total,
                onChanged: total <= 0
                    ? null
                    : (value) => setState(() => _dragSeconds = value),
                onChangeEnd: total <= 0
                    ? null
                    : (value) async {
                        await widget.controller.seekTo(seconds: value);
                        if (mounted) setState(() => _dragSeconds = null);
                      },
              ),
            ),
          ),
          Text(formatDuration(duration), style: labelStyle),
        ],
      ),
    );
  }
}
