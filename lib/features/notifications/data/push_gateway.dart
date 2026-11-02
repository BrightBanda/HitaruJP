import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The phone's side of push notifications: permission, the FCM token, and
/// what happens when a notification arrives or is tapped.
///
/// A narrow interface so the logic around it can be tested without Firebase.
abstract interface class PushGateway {
  /// False where push does not apply (web, desktop).
  bool get isSupported;

  /// Sets up channels and foreground display. Safe to call more than once.
  Future<void> start();

  Future<bool> isPermitted();

  /// Asks the system for permission; true when granted.
  Future<bool> requestPermission();

  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// The route to open when a notification is tapped while the app runs.
  Stream<String> get routesOpened;

  /// The route of the notification that launched the app, if one did.
  Future<String?> launchRoute();

  Future<void> deleteToken();
}

class FirebasePushGateway implements PushGateway {
  static const channelId = 'reminders';

  // Looked up when needed: only phones have it, and Firebase must be up.
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  bool _started = false;

  @override
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> start() async {
    if (!isSupported || _started) return;
    _started = true;

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null && route.isNotEmpty) _taps.add(route);
      },
    );
    // The channel FCM messages are sent to (the server names it), made here so
    // it exists with a proper name before the first one arrives.
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            'Reminders',
            description: 'Study reminders and streak warnings',
            importance: Importance.defaultImportance,
          ),
        );

    // While the app is open the system shows nothing by itself.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      unawaited(
        _local.show(
          id: message.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              'Reminders',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
          payload: message.data['route'] as String?,
        ),
      );
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = message.data['route'] as String?;
      if (route != null && route.isNotEmpty) _taps.add(route);
    });
  }

  @override
  Future<bool> isPermitted() async {
    if (!isSupported) return false;
    final settings = await _messaging.getNotificationSettings();
    return _allowed(settings.authorizationStatus);
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    final settings = await _messaging.requestPermission();
    return _allowed(settings.authorizationStatus);
  }

  static bool _allowed(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  @override
  Future<String?> token() =>
      isSupported ? _messaging.getToken() : Future.value();

  @override
  Stream<String> get tokenRefreshes =>
      isSupported ? _messaging.onTokenRefresh : const Stream.empty();

  @override
  Stream<String> get routesOpened => _taps.stream;

  @override
  Future<String?> launchRoute() async {
    if (!isSupported) return null;
    final message = await _messaging.getInitialMessage();
    return message?.data['route'] as String?;
  }

  @override
  Future<void> deleteToken() async {
    if (isSupported) await _messaging.deleteToken();
  }
}
