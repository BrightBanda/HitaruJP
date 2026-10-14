import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The system's picture-in-picture window, on Android phones that have one.
/// Elsewhere (and on phones without it, such as many Android Go devices) every
/// call does nothing; the in-app mini player covers those.
class PictureInPicture {
  PictureInPicture._() {
    if (isSupported) _channel.setMethodCallHandler(_onCall);
  }

  static final instance = PictureInPicture._();

  static const _channel = MethodChannel('hitarujp/pip');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True while the app is shown in the small floating window.
  final ValueNotifier<bool> active = ValueNotifier(false);

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'pipChanged') active.value = call.arguments == true;
  }

  /// While set, leaving the app (home button, gesture) enters the window.
  Future<void> setAutoEnter(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setAutoEnter', enabled);
    } on PlatformException {
      // Not worth surfacing: the in-app mini player still works.
    } on MissingPluginException {
      // Same.
    }
  }
}
