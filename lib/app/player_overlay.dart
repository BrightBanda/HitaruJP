import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/app/router.dart';
import 'package:ingrain/core/platform/picture_in_picture.dart';
import 'package:ingrain/core/platform/video_overlay.dart';
import 'package:ingrain/features/content/presentation/player_host/player_host.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Draws the app-wide video player above every page.
///
/// With the player screen open the video sits exactly over that screen's
/// video slot. After the learner leaves the screen it becomes a small window
/// they can drag anywhere; tapping it reopens the full screen.
class PlayerOverlay extends StatefulWidget {
  const PlayerOverlay({super.key});

  @override
  State<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<PlayerOverlay> {
  // The player draws its video through an OverlayPortal, which needs an
  // Overlay above it, and this layer sits outside the app's navigator, so it
  // brings one.
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => const _PlayerLayer(),
  );

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class _PlayerLayer extends ConsumerStatefulWidget {
  const _PlayerLayer();

  @override
  ConsumerState<_PlayerLayer> createState() => _PlayerLayerState();
}

class _PlayerLayerState extends ConsumerState<_PlayerLayer> {
  /// Where the small window is while it is being dragged. Kept here, not in
  /// the host, so a drag moves only the stand-in instead of rebuilding the app.
  final _dragPosition = ValueNotifier<Offset?>(null);
  bool _wasMinimized = false;
  StreamSubscription<VideoOverlayEvent>? _overlayEvents;

  // From the latest build, for the drag handlers.
  Rect _miniRect = Rect.zero;
  MediaQueryData _media = const MediaQueryData();

  static const _miniMaxWidth = 240.0;
  static const _margin = 12.0;

  /// Where the real player waits while the stand-in is dragged: moving an
  /// Android video view every frame is what made dragging heavy.
  static const _parked = -4000.0;

  @override
  void initState() {
    super.initState();
    // "Back to HitaruJP" on the floating window opens the full player.
    _overlayEvents = VideoOverlay.instance.events.listen((event) {
      final contentId = ref.read(playerHostProvider).contentId;
      if (!event.closed || !event.expanded || contentId == null) return;
      ref.read(appRouterProvider).push('/content/$contentId');
    });
  }

  @override
  void dispose() {
    _overlayEvents?.cancel();
    _dragPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(playerHostProvider);
    final notifier = ref.read(playerHostProvider.notifier);
    final controller = notifier.controller;
    if (controller == null || host.contentId == null) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: PictureInPicture.instance.active,
      builder: (context, inPip, _) {
        final player = YoutubePlayer(
          // One slot per player: the package keeps the controller it was
          // first given, so a new video needs a new widget, while the same
          // video keeps its view as it moves between screen and window.
          key: GlobalObjectKey(controller),
          controller: controller,
          aspectRatio: 16 / 9,
          // The window's own drag would otherwise also trigger fullscreen.
          enableFullScreenOnVerticalDrag: !host.minimized,
          // Drawn by the package above the video, which covers anything
          // placed beneath it.
          controlsBuilder: host.minimized
              ? (context, _) => _MiniControls(
                  onClose: notifier.close,
                  onFloat: VideoOverlay.isSupported
                      ? () => _float(context)
                      : null,
                  onTogglePlay: notifier.togglePlayback,
                  onExpand: () => ref
                      .read(appRouterProvider)
                      .push('/content/${host.contentId}'),
                  onDrag: _drag,
                  onDragEnd: _dragEnd,
                )
              : null,
        );
        if (inPip) {
          return Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: AspectRatio(aspectRatio: 16 / 9, child: player),
          );
        }

        _media = MediaQuery.of(context);
        _miniRect = _computeMiniRect(host);
        final rect = host.floating
            // The window over other apps plays it; this one waits unseen.
            ? const Rect.fromLTWH(_parked, 0, 320, 180)
            : host.minimized
            ? _miniRect
            // Off screen while the player screen is covered or not yet laid
            // out: the video keeps playing, it just is not drawn.
            : host.slot ?? const Rect.fromLTWH(_parked, 0, 320, 180);

        final modeChanged = host.minimized != _wasMinimized;
        _wasMinimized = host.minimized;

        return ValueListenableBuilder<Offset?>(
          valueListenable: _dragPosition,
          builder: (context, dragging, _) {
            final at = dragging == null
                ? rect
                : Rect.fromLTWH(_parked, 0, rect.width, rect.height);
            return Stack(
              children: [
                AnimatedPositioned(
                  // Glides between the screen and the small window; every
                  // other move (a sliding page, a drop) is immediate.
                  duration: dragging == null && modeChanged
                      ? const Duration(milliseconds: 220)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  left: at.left,
                  top: at.top,
                  width: at.width,
                  height: at.height,
                  child: player,
                ),
                if (dragging != null)
                  Positioned(
                    left: dragging.dx,
                    top: dragging.dy,
                    width: rect.width,
                    height: rect.height,
                    child: _DragStandIn(playing: host.playing),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _float(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref.read(playerHostProvider.notifier).floatOverApps();
    final message = switch (result) {
      FloatResult.floating => null,
      FloatResult.notReady =>
        'The video is still loading. Try again once it starts playing.',
      FloatResult.noPermission =>
        'Allow "Display over other apps" for HitaruJP to float videos.',
      FloatResult.unavailable => 'This video cannot float right now.',
    };
    if (message != null) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _drag(Offset delta) {
    _dragPosition.value = _clamp(
      (_dragPosition.value ?? _miniRect.topLeft) + delta,
      _miniRect.size,
    );
  }

  void _dragEnd() {
    final end = _dragPosition.value;
    if (end == null) return;
    ref.read(playerHostProvider.notifier).moveMini(end);
    _dragPosition.value = null;
  }

  Rect _computeMiniRect(PlayerHostState host) {
    final width = math.min(_miniMaxWidth, _media.size.width * 0.6);
    final size = Size(width, width * 9 / 16);
    // Above the bottom navigation bar by default, in the bottom-right corner.
    final bottomGap = _media.size.width < 600 ? 96.0 : 24.0;
    final home = Offset(
      _media.size.width - size.width - _margin,
      _media.size.height - size.height - _media.padding.bottom - bottomGap,
    );
    return _clamp(host.miniPosition ?? home, size) & size;
  }

  /// Keeps the window on screen, clear of the status bar and gesture area.
  Offset _clamp(Offset position, Size size) {
    final minX = _media.padding.left;
    final maxX = _media.size.width - size.width - _media.padding.right;
    final minY = _media.padding.top;
    final maxY = _media.size.height - size.height - _media.padding.bottom;
    return Offset(
      position.dx.clamp(minX, math.max(minX, maxX)),
      position.dy.clamp(minY, math.max(minY, maxY)),
    );
  }
}

/// What follows the finger while the small window is dragged.
class _DragStandIn extends StatelessWidget {
  final bool playing;

  const _DragStandIn({required this.playing});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1B2130),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black54)],
      ),
      child: Center(
        child: Icon(
          playing ? Icons.graphic_eq : Icons.pause,
          color: Colors.white70,
          size: 32,
        ),
      ),
    );
  }
}

/// The small window's controls, drawn over the video: close, play/pause, and
/// a surface that drags the window or, on a tap, opens the full player.
class _MiniControls extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  /// Floats the video over other apps; null where that is not possible.
  final VoidCallback? onFloat;
  final VoidCallback onTogglePlay;
  final VoidCallback onExpand;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  const _MiniControls({
    required this.onClose,
    this.onFloat,
    required this.onTogglePlay,
    required this.onExpand,
    required this.onDrag,
    required this.onDragEnd,
  });

  @override
  ConsumerState<_MiniControls> createState() => _MiniControlsState();
}

class _MiniControlsState extends ConsumerState<_MiniControls> {
  /// How far a finger may travel and still count as a tap.
  static const _tapSlop = 6.0;

  double _travelled = 0;

  @override
  Widget build(BuildContext context) {
    final playing = ref.watch(playerHostProvider.select((s) => s.playing));
    return Stack(
      fit: StackFit.expand,
      children: [
        // Raw pointer events rather than a pan gesture: those wait for the
        // finger to move a fixed distance before dragging starts, which made
        // the window feel stuck to the screen.
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _travelled = 0,
          onPointerMove: (event) {
            _travelled += event.delta.distance;
            if (_travelled >= _tapSlop) widget.onDrag(event.delta);
          },
          onPointerUp: (_) {
            final tapped = _travelled < _tapSlop;
            widget.onDragEnd();
            if (tapped) widget.onExpand();
          },
          onPointerCancel: (_) => widget.onDragEnd(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: _MiniButton(icon: Icons.close, onPressed: widget.onClose),
        ),
        if (widget.onFloat case final onFloat?)
          Positioned(
            top: 0,
            left: 0,
            child: _MiniButton(
              icon: Icons.picture_in_picture_alt,
              tooltip: 'Float over other apps',
              onPressed: onFloat,
            ),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          child: _MiniButton(
            icon: playing ? Icons.pause : Icons.play_arrow,
            onPressed: widget.onTogglePlay,
          ),
        ),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const _MiniButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    // The player's overlay has no Material above it.
    return Material(
      type: MaterialType.transparency,
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(backgroundColor: Colors.black45),
        onPressed: onPressed,
      ),
    );
  }
}
