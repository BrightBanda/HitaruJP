import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:ingrain/app/router.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/notifications/data/push_gateway.dart';
import 'package:ingrain/features/notifications/data/remote_device_repository.dart';
import 'package:ingrain/features/notifications/domain/notification_settings.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

final pushGatewayProvider = Provider<PushGateway>((ref) {
  return FirebasePushGateway();
});

final deviceRepositoryProvider = Provider<RemoteDeviceRepository>((ref) {
  return RemoteDeviceRepository(ref.watch(apiClientProvider));
});

/// The phone's IANA time zone, e.g. `Asia/Tokyo`: what "7pm" means to the
/// learner. A provider so tests can fix it.
final deviceTimezoneProvider = Provider<Future<String> Function()>((ref) {
  return () async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'UTC';
    }
  };
});

class NotificationState {
  final NotificationSettings settings;

  /// Whether the system lets the app show notifications. Null until known.
  final bool? permitted;

  const NotificationState({
    this.settings = const NotificationSettings(),
    this.permitted,
  });

  NotificationState copyWith({
    NotificationSettings? settings,
    bool? permitted,
  }) {
    return NotificationState(
      settings: settings ?? this.settings,
      permitted: permitted ?? this.permitted,
    );
  }
}

final notificationViewModelProvider =
    NotifierProvider<NotificationViewModel, NotificationState>(
      NotificationViewModel.new,
    );

class NotificationViewModel extends Notifier<NotificationState> {
  static const _askedKey = 'notifications_permission_asked';
  static const _hourKey = 'notifications_reminder_hour';
  static const _streakKey = 'notifications_streak_alerts';
  static const _remindersKey = 'notifications_reminders';
  static const _winbackKey = 'notifications_winback';

  late SharedPreferences _prefs;
  late PushGateway _gateway;
  bool _started = false;
  String? _registeredToken;

  @override
  NotificationState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    _gateway = ref.watch(pushGatewayProvider);
    return NotificationState(
      settings: NotificationSettings(
        reminderHour: _prefs.getInt(_hourKey) ?? 19,
        streakAlerts: _prefs.getBool(_streakKey) ?? true,
        reminders: _prefs.getBool(_remindersKey) ?? true,
        winback: _prefs.getBool(_winbackKey) ?? true,
      ),
    );
  }

  bool get isSupported => _gateway.isSupported;

  /// Sets everything up once the learner is past the first lesson: asks for
  /// permission (once), tells the server about this phone, and follows taps.
  Future<void> start() async {
    if (_started || !_gateway.isSupported) return;
    _started = true;

    await _gateway.start();
    ref.onDispose(
      _gateway.tokenRefreshes.listen((_) => unawaited(_register())).cancel,
    );
    ref.onDispose(_gateway.routesOpened.listen(_open).cancel);

    var permitted = await _gateway.isPermitted();
    if (!permitted && !(_prefs.getBool(_askedKey) ?? false)) {
      // Once only: asking again after a "no" is nagging, and the system stops
      // showing the prompt anyway. The settings screen explains the rest.
      await _prefs.setBool(_askedKey, true);
      permitted = await _gateway.requestPermission();
    }
    state = state.copyWith(permitted: permitted);
    if (permitted) await _register();

    final launch = await _gateway.launchRoute();
    if (launch != null) _open(launch);
  }

  void _open(String route) => ref.read(appRouterProvider).go(route);

  /// Turns notifications on from the settings screen. False when the system
  /// refused, in which case only the system settings can allow them.
  Future<bool> enable() async {
    await _gateway.start();
    final permitted = await _gateway.requestPermission();
    await _prefs.setBool(_askedKey, true);
    state = state.copyWith(permitted: permitted);
    if (permitted) await _register();
    return permitted;
  }

  Future<void> update(NotificationSettings settings) async {
    state = state.copyWith(settings: settings);
    await _prefs.setInt(_hourKey, settings.reminderHour);
    await _prefs.setBool(_streakKey, settings.streakAlerts);
    await _prefs.setBool(_remindersKey, settings.reminders);
    await _prefs.setBool(_winbackKey, settings.winback);
    if (state.permitted ?? false) await _register();
  }

  Future<void> _register() async {
    try {
      final token = await _gateway.token();
      if (token == null) return;
      _registeredToken = token;
      await ref
          .read(deviceRepositoryProvider)
          .register(
            token: token,
            platform: defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
            timezone: await ref.read(deviceTimezoneProvider)(),
            settings: state.settings,
          );
    } catch (error) {
      // Offline or the server asleep: the next launch registers again.
      debugPrint('Push registration failed: $error');
    }
  }

  /// Stops pushes to this phone for the signed-in learner. Call before
  /// signing out, while the request can still be authorised.
  Future<void> unregister() async {
    final token = _registeredToken ?? await _gateway.token();
    if (token == null) return;
    try {
      await ref.read(deviceRepositoryProvider).unregister(token);
      _registeredToken = null;
    } catch (error) {
      debugPrint('Push unregistration failed: $error');
    }
  }
}

/// Starts push once an onboarded learner has finished the first lesson.
/// Watched once from the app root.
final notificationBootstrapProvider = Provider<void>((ref) {
  final ready = ref.watch(
    authViewModelProvider.select((auth) => auth.isOnboarded),
  );
  final lessonPending = ref.watch(
    firstRunProvider.select((run) => run.lessonPending),
  );
  if (!ready || lessonPending) return;
  if (!ref.watch(pushGatewayProvider).isSupported) return;
  // Not on the first frame: the home page should be up before a system dialog.
  Future.delayed(const Duration(seconds: 2), () {
    if (ref.mounted) {
      unawaited(ref.read(notificationViewModelProvider.notifier).start());
    }
  });
});
