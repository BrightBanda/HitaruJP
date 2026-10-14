import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/platform/picture_in_picture.dart';
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

  const PlayerHostState({
    this.contentId,
    this.minimized = false,
    this.slot,
    this.miniPosition,
    this.playing = false,
  });

  PlayerHostState copyWith({
    bool? minimized,
    bool? playing,
    Rect? Function()? slot,
    Offset? miniPosition,
  }) => PlayerHostState(
    contentId: contentId,
    minimized: minimized ?? this.minimized,
    slot: slot != null ? slot() : this.slot,
    miniPosition: miniPosition ?? this.miniPosition,
    playing: playing ?? this.playing,
  );
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

  /// The YouTube id that was loaded into the controller, so a screen opened
  /// on the same video does not load it a second time.
  String? loadedVideoId;

  /// Set by the open player screen, to show a network failure.
  void Function(YoutubeWebResourceError error)? onResourceError;

  @override
  PlayerHostState build() {
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
        }
      });
      return existing;
    }

    _disposeController();
    final controller = YoutubePlayerController(
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
        pointerEvents: kIsWeb ? PointerEvents.none : PointerEvents.initial,
      ),
      onWebResourceError: (error) => onResourceError?.call(error),
    );
    _controller = controller;
    _contentId = contentId;
    loadedVideoId = null;

    _positionSubscription = controller.videoStateStream.listen((video) {
      ref.read(playbackPositionProvider.notifier).setPosition(video.position);
      ref
          .read(immersionSessionViewModelProvider(contentId).notifier)
          .updatePosition(video.position.inSeconds);
    });
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

  /// The session follows the player whichever screen (or window) shows it.
  void _onPlayerValue(String contentId, YoutubePlayerValue value) {
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

  /// Shrinks the video into the small window.
  void minimize() {
    if (_controller == null) return;
    state = state.copyWith(minimized: true, slot: () => null);
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
    _controller?.close();
    _controller = null;
    _contentId = null;
    loadedVideoId = null;
    PictureInPicture.instance.setAutoEnter(false);
  }
}
