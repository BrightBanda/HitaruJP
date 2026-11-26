import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/notifications/presentation/viewmodel/notification_view_model.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/settings/presentation/view/settings_panel.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// Settings, opened from Profile, with signing out at the very bottom.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final container = ref.container;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your vocabulary, decks and progress stay saved to your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // While still signed in, so the server stops pushing to this phone.
    await container.read(notificationViewModelProvider.notifier).unregister();
    await container.read(authViewModelProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SettingsPanel(
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PrivacySection(),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: OutlinedButton.icon(
                onPressed: () => _signOut(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.5),
                  ),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who may see the learner's profile stats: their join date, streaks, XP
/// and leaderboard places. Kept on the server, which enforces it.
class PrivacySection extends ConsumerStatefulWidget {
  const PrivacySection({super.key});

  @override
  ConsumerState<PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends ConsumerState<PrivacySection> {
  ProfileVisibility? _saving;

  Future<void> _set(ProfileVisibility visibility) async {
    setState(() => _saving = visibility);
    final messenger = ScaffoldMessenger.of(context);
    final container = ref.container;
    try {
      await container.read(socialRepositoryProvider).setPrivacy(visibility);
      container.invalidate(privacyProvider);
      await container.read(privacyProvider.future);
    } on SocialException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Check your connection.')),
      );
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(privacyProvider);
    final selected = _saving ?? current.value;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'PRIVACY',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.primaryMain,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const IconBadge(
                        color: AppColors.primaryMain,
                        icon: Icons.visibility_outlined,
                        size: 38,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Who can see my profile stats',
                              style: theme.textTheme.bodyLarge,
                            ),
                            Text(
                              'Join date, streaks, XP and leaderboard places. '
                              'Your username and companion always show.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (current.hasError && selected == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Choose a username in Profile → Friends to set this.',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  else
                    RadioGroup<ProfileVisibility>(
                      groupValue: selected,
                      onChanged: (value) {
                        if (value != null && _saving == null) _set(value);
                      },
                      child: Column(
                        children: [
                          for (final option in ProfileVisibility.values)
                            RadioListTile<ProfileVisibility>(
                              value: option,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(option.label),
                              secondary: _saving == option
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
