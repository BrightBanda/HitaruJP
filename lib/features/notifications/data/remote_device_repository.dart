import 'package:ingrain/core/network/api_client.dart';
import 'package:ingrain/features/notifications/domain/notification_settings.dart';

/// Tells the server about this phone, so it can send pushes to it.
class RemoteDeviceRepository {
  final ApiClient _api;

  RemoteDeviceRepository(this._api);

  Future<void> register({
    required String token,
    required String platform,
    required String timezone,
    required NotificationSettings settings,
  }) async {
    await _api.put('/me/device', {
      'token': token,
      'platform': platform,
      'timezone': timezone,
      'reminderHour': settings.reminderHour,
      'streakAlerts': settings.streakAlerts,
      'reminders': settings.reminders,
      'winback': settings.winback,
    });
  }

  Future<void> unregister(String token) async {
    await _api.delete('/me/device/${Uri.encodeComponent(token)}');
  }
}
