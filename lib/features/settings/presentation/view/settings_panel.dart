import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/notifications/presentation/viewmodel/notification_view_model.dart';
import 'package:ingrain/features/settings/domain/app_settings.dart';
import 'package:ingrain/features/settings/presentation/viewmodel/settings_view_model.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// App settings, shown on the Profile tab.
class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return builderForState(ref.watch(settingsViewModelProvider), context, ref);
  }

  Widget builderForState(
    SettingsUiState uiState,
    BuildContext context,
    WidgetRef ref,
  ) {
    if (uiState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (uiState.error != null) {
      return Center(child: Text('Error: ${uiState.error}'));
    }
    final settings = uiState.settings;
    if (settings == null) {
      return const Center(child: Text('No settings available'));
    }
    return _buildContent(context, ref, settings);
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final vm = ref.read(settingsViewModelProvider.notifier);
    final theme = Theme.of(context);
    const appearance = AppColors.primaryMain;
    const playback = appearance;
    const goals = appearance;
    const about = appearance;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Section(
          title: 'Appearance',
          color: appearance,
          children: [
            const ListTile(
              leading: IconBadge(
                color: appearance,
                icon: Icons.brightness_6_outlined,
                size: 38,
              ),
              title: Text('Theme'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<ThemeSetting>(
                style: SegmentedButton.styleFrom(
                  side: BorderSide.none,
                  backgroundColor: appearance.withValues(alpha: 0.1),
                  foregroundColor: appearance,
                  selectedBackgroundColor: appearance,
                  selectedForegroundColor: Colors.white,
                ),
                segments: const [
                  ButtonSegment(
                    value: ThemeSetting.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeSetting.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeSetting.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selection) =>
                    vm.setThemeMode(selection.first),
                showSelectedIcon: false,
              ),
            ),
            _SliderTile(
              color: appearance,
              icon: Icons.format_size_outlined,
              label: 'Subtitle font size',
              value: settings.subtitleFontSize,
              min: 10,
              max: 30,
              divisions: 20,
              onChanged: (v) => vm.setSubtitleFontSize(v),
              valueFormatter: (v) => '${v.toStringAsFixed(0)} pt',
            ),
            SwitchListTile(
              secondary: const IconBadge(
                color: appearance,
                icon: Icons.translate_outlined,
                size: 38,
              ),
              activeTrackColor: appearance,
              title: const Text('Show romaji in dialogues'),
              value: settings.showRomaji,
              onChanged: vm.setShowRomaji,
            ),
          ],
        ),
        _Section(
          title: 'Playback',
          color: playback,
          children: [
            _SliderTile(
              color: playback,
              icon: Icons.speed_outlined,
              label: 'Playback speed',
              value: settings.playbackSpeed,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              onChanged: (v) => vm.setPlaybackSpeed(v),
              valueFormatter: (v) => '${v.toStringAsFixed(1)}x',
            ),
          ],
        ),
        _Section(
          title: 'Goals',
          color: goals,
          children: [
            ListTile(
              leading: const IconBadge(
                color: goals,
                icon: Icons.flag_outlined,
                size: 38,
              ),
              title: const Text('Daily goal'),
              trailing: Pill(
                label: '${settings.dailyGoalMinutes} min',
                color: goals,
                solid: true,
              ),
              onTap: () =>
                  _showGoalDialog(context, ref, settings.dailyGoalMinutes),
            ),
          ],
        ),
        _Section(
          title: 'Flashcards',
          color: goals,
          children: [
            ListTile(
              leading: const IconBadge(
                color: goals,
                icon: Icons.tune,
                size: 38,
              ),
              title: const Text('Flashcard settings'),
              subtitle: const Text(
                'Daily limits, learning steps, intervals and ease',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/flashcards/settings'),
            ),
          ],
        ),
        if (ref.watch(pushGatewayProvider).isSupported)
          _Section(
            title: 'Reminders',
            color: about,
            children: [
              ListTile(
                leading: const IconBadge(
                  color: about,
                  icon: Icons.notifications_outlined,
                  size: 38,
                ),
                title: const Text('Notifications'),
                subtitle: const Text('Streak warnings and study reminders'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/notifications'),
              ),
            ],
          ),
        _Section(
          title: 'About',
          color: about,
          children: [
            ListTile(
              leading: const IconBadge(
                color: about,
                icon: Icons.menu_book_outlined,
                size: 38,
              ),
              title: const Text('Dictionary attribution'),
              subtitle: const Text('JMdict/EDICT (CC BY-SA 4.0)'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Dictionary Data'),
                    content: const Text(
                      'This app uses JMdict dictionary data licensed under '
                      'CC BY-SA 4.0. Source: '
                      'https://www.jdic.org/codedoc JMdict',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const IconBadge(
                color: about,
                icon: Icons.verified_outlined,
                size: 38,
              ),
              title: const Text('Version'),
              trailing: Text('1.0.0+1', style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ],
    );
  }

  void _showGoalDialog(BuildContext context, WidgetRef ref, int current) {
    final controller = TextEditingController(text: current.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily goal (minutes)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '30'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n > 0) {
                ref
                    .read(settingsViewModelProvider.notifier)
                    .setDailyGoalMinutes(n);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// A grouped settings card with a caption header in the section's colour.
class _Section extends StatelessWidget {
  final String title;
  final Color color;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 12,
                color: color,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String Function(double) valueFormatter;

  const _SliderTile({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(color: color, icon: icon, size: 38),
              const SizedBox(width: 16),
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text(
                valueFormatter(value),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            activeColor: color,
            inactiveColor: color.withValues(alpha: 0.18),
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueFormatter(value),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
