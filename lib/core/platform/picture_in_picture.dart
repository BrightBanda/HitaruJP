import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Picture-in-picture for the video player. Android only: everywhere else
/// [isSupported] is false and every call does nothing.
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

  /// Shrinks the app into the floating window. False when that is not allowed.
  Future<bool> enter() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// While set, leaving the app (home button, gesture) enters the window.
  Future<void> setAutoEnter(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setAutoEnter', enabled);
    } on PlatformException {
      // Not worth surfacing: the learner can still use the back button.
    } on MissingPluginException {
      // Same.
    }
  }
}
