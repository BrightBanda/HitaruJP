import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/lifecycle.dart';
import 'package:ingrain/core/platform/picture_in_picture.dart';
import 'package:ingrain/core/platform/video_overlay.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/view/player/immersion_player_view.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Tells the player screen when another full page covers it (a dialog or sheet
/// does not count), so the video can step aside for the page.
final playerRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// What the app-wide video player is doing.
class PlayerHostState {
  /// The video loaded in the player; null when there is none.
  final String? contentId;

  /// True while the video is a small window over the rest of the app.
  final bool minimized;

  /// Where the player screen wants the video drawn, in global coordinates.
  /// Null while that screen is covered or has not been laid out yet.
  final Rect? slot;

  /// Top-left of the small window once the learner has dragged it.
  final Offset? miniPosition;

  final bool playing;

  /// True while the video plays in the window over other apps
  /// ([VideoOverlay]); the app's own player waits, paused and out of sight.
  final bool floating;

  const PlayerHostState({
    this.contentId,
    this.minimized = false,
    this.slot,
    this.miniPosition,
    this.playing = false,
    this.floating = false,
  });

  PlayerHostState copyWith({
    bool? minimized,
    bool? playing,
    bool? floating,
    Rect? Function()? slot,
    Offset? miniPosition,
  }) => PlayerHostState(
    contentId: contentId,
    minimized: minimized ?? this.minimized,
    slot: slot != null ? slot() : this.slot,
    miniPosition: miniPosition ?? this.miniPosition,
    playing: playing ?? this.playing,
    floating: floating ?? this.floating,
  );
}

/// What [PlayerHost.floatOverApps] managed.
enum FloatResult {
  floating,

  /// The video has not loaded far enough to know where to start it.
  notReady,

  /// "Display over other apps" was not allowed.
  noPermission,

  /// Not Android, or nothing is loaded.
  unavailable,
}

final playerHostProvider = NotifierProvider<PlayerHost, PlayerHostState>(
  PlayerHost.new,
);

/// Owns the one YouTube player, so it outlives the screen that opened it.
///
/// The video keeps playing, and the immersion session keeps counting, when the
/// learner leaves the player screen: the player turns into a small window that
/// the app-level overlay draws over whatever page they browse to.
class PlayerHost extends Notifier<PlayerHostState> {
  YoutubePlayerController? _controller;
  String? _contentId;
  StreamSubscription<YoutubeVideoState>? _positionSubscription;
  StreamSubscription<YoutubePlayerValue>? _playerSubscription;
  Timer? _positionPoll;
  DateTime _lastPositionAt = DateTime.now();
  bool _polling = false;

  /// Mirrors [PlayerHostState.floating] for [_disposeController], which may
  /// run while the provider is being disposed and cannot read its state.
  bool _floating = false;

  /// Where each video got to this run, by content id: fresher than the
  /// library's copy, which is only re-read on the next fetch.
  final Map<String, Duration> _positions = {};

  /// Nothing saved yet this run.
  static const _unsaved = Duration(seconds: -1);
  Duration _lastSavedPosition = _unsaved;
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Saves while playing are at most this often; pausing, closing and
  /// leaving the app save at once.
  static const _saveInterval = Duration(seconds: 15);

  /// Whether YouTube's captions are on, and the speed chosen, kept here so
  /// the controls still show them when the player screen is reopened.
  bool captionsOn = false;
  double playbackRate = 1.0;

  /// The YouTube id that was loaded into the controller, so a screen opened
  /// on the same video does not load it a second time.
  String? loadedVideoId;

  /// Set by the open player screen, to show a network failure.
  void Function(YoutubeWebResourceError error)? onResourceError;

  @override
  PlayerHostState build() {
    final overlayEvents = VideoOverlay.instance.events.listen(_onOverlayEvent);
    ref.onDispose(overlayEvents.cancel);
    // The app may be killed in the background, so leaving it saves.
    ref.listen(appLifecycleProvider, (_, next) {
      if (next == AppLifecycleState.paused ||
          next == AppLifecycleState.hidden) {
        _savePosition(force: true);
      }
    });
    ref.onDispose(_disposeController);
    return const PlayerHostState();
  }

  YoutubePlayerController? get controller => _controller;

  /// The controller for [contentId]: the running one when that video is
  /// already loaded, otherwise a fresh one (closing any other video).
  ///
  /// Safe to call while a screen is building: provider state is changed on
  /// the next microtask.
  YoutubePlayerController acquire(String contentId) {
    final existing = _controller;
    if (existing != null && _contentId == contentId) {
      Future.microtask(() {
        if (ref.mounted && _contentId == contentId) {
          state = state.copyWith(minimized: false);
          _hideYoutubeControls(existing, false);
        }
      });
      return existing;
    }

    _disposeController();
    final controller = YoutubePlayerController(
      params: YoutubePlayerParams(
        showFullscreenButton: false,
        enableKeyboard: false,
        // YouTube's own controls, progress bar included.
        showControls: true,
        // Off until the learner turns them on from the controls row.
        enableCaption: false,
        captionLanguage: 'ja',
        origin: 'https://www.youtube-nocookie.com',
        strictRelatedVideos: true,
        // How often the iframe reports the position over the WebView bridge.
        // The default 100ms sent ten messages a second, each one waking the
        // UI thread; the transcript only needs a few.
        videoStateUpdateInterval: 250,
      ),
      onWebResourceError: (error) => onResourceError?.call(error),
    );
    _controller = controller;
    _contentId = contentId;
    _lastSavedPosition = _unsaved;
    _lastSavedAt = DateTime.now();
    loadedVideoId = null;
    captionsOn = false;
    playbackRate = 1.0;

    _lastPositionAt = DateTime.now();
    _positionSubscription = controller.videoStateStream.listen((video) {
      _lastPositionAt = DateTime.now();
      _reportPosition(contentId, video.position);
    });
    // The page's own position updates sometimes stall (a throttled WebView)
    // while the video plays on, which froze the seek bar and the transcript.
    // When they go quiet, ask the player for its position directly.
    _positionPoll = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollPosition(controller, contentId),
    );
    _playerSubscription = controller.stream.listen(
      (value) => _onPlayerValue(contentId, value),
    );

    Future.microtask(() {
      if (!ref.mounted || !identical(_controller, controller)) return;
      state = PlayerHostState(contentId: contentId);
      ref.read(playerControllerProvider.notifier).setController(controller);
    });
    return controller;
  }

  /// Where to start [item] so the learner continues where they left off;
  /// null to start at the beginning (never watched, barely started, or
  /// finished).
  Duration? resumePositionFor(ContentItem item) {
    final position =
        _positions[item.id] ?? Duration(seconds: item.lastPositionSeconds);
    if (position < const Duration(seconds: 5)) return null;
    final length = item.durationSeconds;
    if (length != null &&
        length > 0 &&
        position > Duration(seconds: length) - const Duration(seconds: 10)) {
      return null;
    }
    return position;
  }

  /// Stores the current position in the library, so the next play of this
  /// video continues from it. Unless [force]d, only once enough time and
  /// video have passed since the last save.
  void _savePosition({bool force = false, Duration? position}) {
    final contentId = _contentId;
    if (contentId == null) return;
    final at = position ?? _positions[contentId];
    if (at == null) return;
    final now = DateTime.now();
    if (!force &&
        (now.difference(_lastSavedAt) < _saveInterval ||
            (at - _lastSavedPosition).abs() < const Duration(seconds: 5))) {
      return;
    }
    if (at == _lastSavedPosition) return;
    _lastSavedAt = now;
    _lastSavedPosition = at;
    unawaited(
      ref
          .read(contentRepositoryProvider)
          .updateLastPosition(contentId, at.inSeconds)
          .catchError(
            (Object error) => debugPrint('Position not saved: $error'),
          ),
    );
  }

  void _reportPosition(String contentId, Duration position) {
    _positions[contentId] = position;
    if (state.playing) _savePosition();
    ref.read(playbackPositionProvider.notifier).setPosition(position);
    ref
        .read(immersionSessionViewModelProvider(contentId).notifier)
        .updatePosition(position.inSeconds);
  }

  Future<void> _pollPosition(
    YoutubePlayerController controller,
    String contentId,
  ) async {
    if (!state.playing || _polling || !identical(controller, _controller)) {
      return;
    }
    final quiet = DateTime.now().difference(_lastPositionAt);
    if (quiet < const Duration(milliseconds: 900)) return;
    _polling = true;
    try {
      final seconds = await controller.currentTime.timeout(
        const Duration(seconds: 1),
      );
      if (ref.mounted && identical(controller, _controller)) {
        _reportPosition(
          contentId,
          Duration(milliseconds: (seconds * 1000).round()),
        );
      }
    } catch (_) {
      // The bridge did not answer; the next tick tries again.
    } finally {
      _polling = false;
    }
  }

  /// The session follows the player whichever screen (or window) shows it.
  void _onPlayerValue(String contentId, YoutubePlayerValue value) {
    // The floating window is the one playing; this player only waits.
    if (state.floating) return;
    final isPlaying = value.playerState == PlayerState.playing;
    final stopped =
        value.playerState == PlayerState.paused ||
        value.playerState == PlayerState.ended;
    if ((isPlaying || stopped) && isPlaying != state.playing) {
      state = state.copyWith(playing: isPlaying);
      // Leaving the app while a video plays shrinks it into the system's
      // picture-in-picture window, on phones that have one.
      PictureInPicture.instance.setAutoEnter(isPlaying);
    }
    if (value.playerState == PlayerState.ended) {
      // Watched to the end: next time starts from the beginning.
      _positions[contentId] = Duration.zero;
      _savePosition(force: true, position: Duration.zero);
    } else if (stopped) {
      _savePosition(force: true);
    }
    _syncSession(contentId, isPlaying: isPlaying, stopped: stopped);
  }

  void _syncSession(
    String contentId, {
    required bool isPlaying,
    required bool stopped,
  }) {
    final session = ref.read(immersionSessionViewModelProvider(contentId));
    final sessionVm = ref.read(
      immersionSessionViewModelProvider(contentId).notifier,
    );
    if (isPlaying) {
      if (!session.hasActiveSession) {
        final title =
            ref.read(contentItemProvider(contentId)).asData?.value.title ??
            'Video';
        sessionVm.startSession(sourceTitle: title);
      } else if (session.isPaused) {
        sessionVm.resumeSession();
      }
    } else if (stopped && session.isRunning && !session.isPaused) {
      sessionVm.pauseSession();
    }
  }

  /// Shrinks the video into the small window, playing, with YouTube's own
  /// controls out of sight (the window has its own).
  void minimize() {
    final controller = _controller;
    if (controller == null) return;
    state = state.copyWith(minimized: true, slot: () => null);
    _savePosition(force: true);
    _hideYoutubeControls(controller, true);
    // After the move into the window: a WebView that was briefly off screen
    // can come back paused.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (ref.mounted &&
          identical(controller, _controller) &&
          state.minimized) {
        controller.playVideo();
      }
    });
  }

  /// Crops YouTube's title bar and control bar out of view by making the
  /// embedded player taller than its window: the video stays exactly where
  /// it was, centred, and only YouTube's chrome above and below it is cut.
  /// The package cannot turn YouTube's controls off without reloading (and
  /// rebuffering) the video.
  void _hideYoutubeControls(YoutubePlayerController controller, bool hide) {
    const crop = 64;
    final js = hide
        ? '''
(function () {
  document.documentElement.style.overflow = 'hidden';
  var f = document.querySelector('.embed-container iframe');
  if (!f) return;
  f.style.setProperty('top', '-${crop}px', 'important');
  f.style.setProperty('height', 'calc(100% + ${crop * 2}px)', 'important');
})();'''
        : '''
(function () {
  var f = document.querySelector('.embed-container iframe');
  if (!f) return;
  f.style.removeProperty('top');
  f.style.setProperty('height', '100%', 'important');
})();''';
    controller.webViewController.runJavaScript(js).catchError((Object _) {
      // The page is not ready; YouTube hides its controls while playing
      // anyway.
    });
  }

  /// What leaving the player screen does: a playing video carries on in the
  /// small window, one that is paused or finished is closed.
  void leave() {
    if (_controller == null) return;
    state.playing ? minimize() : close();
  }

  /// [leave], but only if [controller] is still the one on show and the
  /// screen has not already handled it.
  void leaveIfExpanded(YoutubePlayerController controller) {
    if (!identical(_controller, controller) || state.minimized) return;
    leave();
  }

  /// Stops the video and removes the window.
  void close() {
    final contentId = _contentId;
    final controller = _controller;
    if (controller == null || contentId == null) return;
    _savePosition(force: true);
    controller.pauseVideo();
    final session = ref.read(immersionSessionViewModelProvider(contentId));
    if (session.isRunning && !session.isPaused) {
      ref
          .read(immersionSessionViewModelProvider(contentId).notifier)
          .pauseSession();
    }
    _disposeController();
    state = const PlayerHostState();
    ref.read(playerControllerProvider.notifier).setController(null);
  }

  void setSlot(Rect? slot) {
    if (_controller == null || state.slot == slot) return;
    state = state.copyWith(slot: () => slot);
  }

  void moveMini(Offset position) {
    if (_controller == null) return;
    state = state.copyWith(miniPosition: position);
  }

  /// Moves the video into a window over other apps and sends the app to the
  /// background, saying what stopped it when it could not.
  Future<FloatResult> floatOverApps() async {
    final controller = _controller;
    final contentId = _contentId;
    if (!VideoOverlay.isSupported || controller == null || contentId == null) {
      return FloatResult.unavailable;
    }
    if (state.floating) return FloatResult.floating;
    final videoId = loadedVideoId;
    final playerState = controller.value.playerState;
    if (videoId == null ||
        playerState == PlayerState.unknown ||
        playerState == PlayerState.unStarted) {
      return FloatResult.notReady;
    }

    Duration position;
    try {
      final seconds = await controller.currentTime.timeout(
        const Duration(seconds: 1),
      );
      position = Duration(milliseconds: (seconds * 1000).round());
    } catch (_) {
      position = ref.read(playbackPositionProvider);
    }
    final shown = await VideoOverlay.instance.show(
      videoId: videoId,
      position: position,
      title: ref.read(contentItemProvider(contentId)).asData?.value.title,
    );
    if (!ref.mounted || !identical(controller, _controller)) {
      return FloatResult.unavailable;
    }
    if (!shown) return FloatResult.noPermission;
    // Set first, so the pause below is not taken for the learner stopping.
    _floating = true;
    state = state.copyWith(floating: true, playing: true);
    controller.pauseVideo();
    return FloatResult.floating;
  }

  /// Follows the floating window: its position drives the transcript and the
  /// session, and when it closes this player carries on from where it got.
  void _onOverlayEvent(VideoOverlayEvent event) {
    final controller = _controller;
    final contentId = _contentId;
    if (controller == null ||
        contentId == null ||
        !state.floating ||
        event.videoId != loadedVideoId) {
      return;
    }
    _reportPosition(contentId, event.position);

    if (!event.closed) {
      if (event.playing != state.playing) {
        state = state.copyWith(playing: event.playing);
      }
      _syncSession(
        contentId,
        isPlaying: event.playing,
        stopped: !event.playing,
      );
      return;
    }

    _floating = false;
    state = state.copyWith(floating: false, playing: false);
    _savePosition(force: true, position: event.position);
    controller.seekTo(
      seconds: event.position.inMilliseconds / 1000,
      allowSeekAhead: true,
    );
    if (event.expanded && event.playing) {
      // Reported back through _onPlayerValue like any other play.
      controller.playVideo();
    } else {
      _syncSession(contentId, isPlaying: false, stopped: true);
    }
  }

  void togglePlayback() {
    final controller = _controller;
    if (controller == null) return;
    state.playing ? controller.pauseVideo() : controller.playVideo();
  }

  void _disposeController() {
    _positionSubscription?.cancel();
    _playerSubscription?.cancel();
    _positionSubscription = null;
    _playerSubscription = null;
    _positionPoll?.cancel();
    _positionPoll = null;
    _controller?.close();
    _controller = null;
    _contentId = null;
    loadedVideoId = null;
    PictureInPicture.instance.setAutoEnter(false);
    // A floating window belongs to this video; another one replaces it.
    if (_floating) VideoOverlay.instance.hide();
    _floating = false;
  }
}
