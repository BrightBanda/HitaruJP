import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/notifications/presentation/viewmodel/notification_view_model.dart';

/// Which reminders the learner gets, and at what time of day.
class NotificationSettingsView extends ConsumerWidget {
  const NotificationSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationViewModelProvider);
    final notifier = ref.read(notificationViewModelProvider.notifier);
    final settings = state.settings;
    final blocked = state.permitted == false;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (blocked)
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: const Text('Notifications are off for this app'),
                subtitle: const Text(
                  'Allow them to get streak warnings and study reminders.',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final granted = await notifier.enable();
                    if (!granted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Turn them on in your phone\'s settings under '
                            'Apps → HitaruJP → Notifications.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Allow'),
                ),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.local_fire_department_outlined),
            title: const Text('Streak warnings'),
            subtitle: const Text(
              'When a streak of 3+ days is about to end. At most once a day.',
            ),
            value: settings.streakAlerts,
            onChanged: (value) =>
                notifier.update(settings.copyWith(streakAlerts: value)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.style_outlined),
            title: const Text('Daily reminder'),
            subtitle: const Text(
              'A nudge to review flashcards and immerse, only on days you '
              'have not opened the app.',
            ),
            value: settings.reminders,
            onChanged: (value) =>
                notifier.update(settings.copyWith(reminders: value)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.waving_hand_outlined),
            title: const Text('We miss you'),
            subtitle: const Text('One message after 3 days and after 7 away.'),
            value: settings.winback,
            onChanged: (value) =>
                notifier.update(settings.copyWith(winback: value)),
          ),
          ListTile(
            enabled: settings.anyOn,
            leading: const Icon(Icons.schedule),
            title: const Text('Reminder time'),
            subtitle: const Text('Messages go out around this time.'),
            trailing: Text(
              TimeOfDay(hour: settings.reminderHour, minute: 0).format(context),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: !settings.anyOn
                ? null
                : () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: settings.reminderHour,
                        minute: 0,
                      ),
                    );
                    if (picked != null) {
                      await notifier.update(
                        settings.copyWith(reminderHour: picked.hour),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }
}
