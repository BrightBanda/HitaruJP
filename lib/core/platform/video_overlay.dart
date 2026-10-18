import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the floating window reports about its video.
class VideoOverlayEvent {
  /// The YouTube id of the video in the window.
  final String videoId;
  final Duration position;
  final bool playing;

  /// The window closed. [expanded] says whether the learner asked for the
  /// video back in the app (as opposed to closing it).
  final bool closed;
  final bool expanded;

  const VideoOverlayEvent({
    required this.videoId,
    required this.position,
    required this.playing,
    this.closed = false,
    this.expanded = false,
  });
}

/// A video window drawn over other apps (Android's "display over other
/// apps"), like the floating players of video apps. Unlike picture-in-picture
/// it can be dragged anywhere and resized, and it stays up while the learner
/// uses any app.
///
/// The window plays the video in its own player; the app's player waits,
/// paused, and picks up from the reported position when the window closes.
class VideoOverlay {
  VideoOverlay._() {
    if (isSupported) _channel.setMethodCallHandler(_onCall);
  }

  static final instance = VideoOverlay._();

  static const _channel = MethodChannel('hitarujp/overlay');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final _events = StreamController<VideoOverlayEvent>.broadcast();

  /// Progress about once a second while the window is up, then one `closed`
  /// event.
  Stream<VideoOverlayEvent> get events => _events.stream;

  Future<dynamic> _onCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return;
    final closed = call.method == 'overlayClosed';
    if (!closed && call.method != 'overlayProgress') return;
    _events.add(
      VideoOverlayEvent(
        videoId: args['videoId'] as String? ?? '',
        position: Duration(
          milliseconds: ((args['position'] as num? ?? 0) * 1000).round(),
        ),
        playing: args['playing'] == true,
        closed: closed,
        expanded: args['expanded'] == true,
      ),
    );
  }

  /// Floats [videoId] from [position] and sends the app to the background.
  /// Asks for the "display over other apps" permission first when needed;
  /// false when it was not given.
  Future<bool> show({
    required String videoId,
    required Duration position,
    String? title,
  }) async {
    if (!isSupported) return false;
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'videoId': videoId,
        'position': position.inMilliseconds / 1000,
        'title': title,
      });
      return shown ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Closes the window, if one is up.
  Future<void> hide() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException {
      // Nothing to close.
    } on MissingPluginException {
      // Same.
    }
  }
}
