import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/features/notifications/data/remote_device_repository.dart';
import 'package:ingrain/features/notifications/domain/notification_settings.dart';
import 'package:ingrain/features/notifications/presentation/viewmodel/notification_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_overrides.dart';

class RecordingDevices implements RemoteDeviceRepository {
  final registered = <({String token, String timezone, int hour})>[];
  final unregistered = <String>[];
  bool failing = false;

  @override
  Future<void> register({
    required String token,
    required String platform,
    required String timezone,
    required NotificationSettings settings,
  }) async {
    if (failing) throw Exception('offline');
    registered.add((
      token: token,
      timezone: timezone,
      hour: settings.reminderHour,
    ));
  }

  @override
  Future<void> unregister(String token) async => unregistered.add(token);
}

void main() {
  late FakePushGateway gateway;
  late RecordingDevices devices;
  late SharedPreferences prefs;

  ProviderContainer make() {
    final container = ProviderContainer(
      overrides: [
        ...appTestOverrides(prefs, pushGateway: gateway),
        deviceRepositoryProvider.overrideWithValue(devices),
        deviceTimezoneProvider.overrideWithValue(() async => 'Asia/Tokyo'),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    gateway = FakePushGateway();
    devices = RecordingDevices();
  });

  test('asks for permission once, then registers the phone', () async {
    final container = make();
    final notifier = container.read(notificationViewModelProvider.notifier);

    await notifier.start();

    expect(gateway.permissionRequests, 1);
    expect(container.read(notificationViewModelProvider).permitted, isTrue);
    expect(devices.registered.single.token, 'fcm-token-1');
    expect(devices.registered.single.timezone, 'Asia/Tokyo');
    expect(devices.registered.single.hour, 19);
  });

  test('a refusal is remembered and not asked again next launch', () async {
    gateway.willGrant = false;
    await make().read(notificationViewModelProvider.notifier).start();
    expect(gateway.permissionRequests, 1);
    expect(devices.registered, isEmpty);

    // A later launch.
    await make().read(notificationViewModelProvider.notifier).start();

    expect(gateway.permissionRequests, 1);
    expect(devices.registered, isEmpty);
  });

  test('already permitted: registers without asking', () async {
    gateway.permitted = true;

    await make().read(notificationViewModelProvider.notifier).start();

    expect(gateway.permissionRequests, 0);
    expect(devices.registered, hasLength(1));
  });

  test('a new token from Firebase is sent to the server', () async {
    gateway.permitted = true;
    await make().read(notificationViewModelProvider.notifier).start();

    gateway.refreshToken('fcm-token-2');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(devices.registered.map((d) => d.token), [
      'fcm-token-1',
      'fcm-token-2',
    ]);
  });

  test('changing a setting is saved and sent', () async {
    gateway.permitted = true;
    final container = make();
    final notifier = container.read(notificationViewModelProvider.notifier);
    await notifier.start();

    await notifier.update(
      container
          .read(notificationViewModelProvider)
          .settings
          .copyWith(reminderHour: 8, streakAlerts: false),
    );

    expect(devices.registered.last.hour, 8);
    expect(prefs.getInt('notifications_reminder_hour'), 8);
    // Remembered by the next launch.
    final next = make().read(notificationViewModelProvider).settings;
    expect((next.reminderHour, next.streakAlerts), (8, false));
  });

  test('settings change without permission are kept but not sent', () async {
    gateway.willGrant = false;
    final container = make();
    final notifier = container.read(notificationViewModelProvider.notifier);
    await notifier.start();

    await notifier.update(const NotificationSettings(reminderHour: 7));

    expect(devices.registered, isEmpty);
    expect(prefs.getInt('notifications_reminder_hour'), 7);
  });

  test('a server that is down does not break the app', () async {
    gateway.permitted = true;
    devices.failing = true;

    await make().read(notificationViewModelProvider.notifier).start();

    expect(devices.registered, isEmpty);
  });

  test('unsupported platforms do nothing', () async {
    gateway = FakePushGateway(supported: false);

    await make().read(notificationViewModelProvider.notifier).start();

    expect(gateway.starts, 0);
    expect(devices.registered, isEmpty);
  });

  test('unregister tells the server to drop this phone', () async {
    gateway.permitted = true;
    final notifier = make().read(notificationViewModelProvider.notifier);
    await notifier.start();

    await notifier.unregister();

    expect(devices.unregistered, ['fcm-token-1']);
  });

  test('enable from settings asks the system and registers', () async {
    gateway.willGrant = false;
    final container = make();
    final notifier = container.read(notificationViewModelProvider.notifier);
    await notifier.start();
    expect(devices.registered, isEmpty);

    gateway.willGrant = true;
    final granted = await notifier.enable();

    expect(granted, isTrue);
    expect(devices.registered, hasLength(1));
  });
}
