import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/auth/domain/user_profile.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/kana/domain/kana_chart.dart';
import 'package:ingrain/features/kana/presentation/kana_progress_view_model.dart';
import 'package:ingrain/features/profile/domain/avatar_character.dart';
import 'package:ingrain/features/profile/presentation/widgets/avatar_painter.dart';
import 'package:ingrain/features/profile/presentation/widgets/learner_avatar.dart';
import 'package:ingrain/features/profile/presentation/widgets/learner_preference_style.dart';
import 'package:ingrain/features/profile/presentation/widgets/preference_pickers.dart';
import 'package:ingrain/features/progress/presentation/view/progress_dashboard.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/notifications/presentation/viewmodel/notification_view_model.dart';
import 'package:ingrain/features/settings/presentation/view/settings_panel.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// The Profile tab: the learner's character and identity up top, then their
/// progress and settings.
class ProfileView extends ConsumerWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Profile'),
          actions: [
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/profile/edit'),
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => _signOut(context, ref),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Wide: the character card stays put in its own column while
            // progress and settings scroll beside it.
            if (constraints.maxWidth >= _sideBySideMinWidth) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: _heroColumnWidth,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(24, 4, 8, 24),
                      child: _ProfileHero(),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _TabBarHeader._tabBar,
                        const Expanded(
                          child: TabBarView(
                            children: [ProgressDashboard(), SettingsPanel()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return NestedScrollView(
              headerSliverBuilder: (context, _) => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _ProfileHero(),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarHeader(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                ),
              ],
              body: const TabBarView(
                children: [ProgressDashboard(), SettingsPanel()],
              ),
            );
          },
        ),
      ),
    );
  }

  static const _sideBySideMinWidth = 900.0;
  static const _heroColumnWidth = 400.0;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
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
    if (confirmed == true) {
      // While still signed in, so the server stops pushing to this phone.
      await ref.read(notificationViewModelProvider.notifier).unregister();
      await ref.read(authViewModelProvider.notifier).signOut();
    }
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  final Color color;

  const _TabBarHeader({required this.color});

  static const _tabBar = TabBar(
    tabs: [
      Tab(icon: Icon(Icons.insights), text: 'Progress'),
      Tab(icon: Icon(Icons.settings), text: 'Settings'),
    ],
  );

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: color, child: _tabBar);

  @override
  bool shouldRebuild(_TabBarHeader oldDelegate) => oldDelegate.color != color;
}

/// The character on its banner, then who the learner is and how they are doing.
class _ProfileHero extends ConsumerWidget {
  const _ProfileHero();

  static const _avatarSize = 116.0;
  static const _bannerHeight = 112.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authViewModelProvider);
    final profile = auth.profile;
    final character = AvatarCharacter.fromId(profile?.avatarId);
    final name = auth.displayName?.trim();
    final displayName = name == null || name.isEmpty ? 'Learner' : name;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _bannerHeight + _avatarSize / 2,
            child: Stack(
              children: [
                _Banner(character: character, height: _bannerHeight),
                Positioned(
                  left: 0,
                  right: 0,
                  top: _bannerHeight - _avatarSize / 2,
                  child: Center(
                    child: _EditableAvatar(
                      size: _avatarSize,
                      onEdit: () => context.push('/profile/edit'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(character, profile),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _Badges(profile: profile),
                const SizedBox(height: 16),
                const _StatsRow(),
                if (profile != null &&
                    (profile.learningReasons.isNotEmpty ||
                        profile.interests.isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  _Goals(profile: profile),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(AvatarCharacter character, UserProfile? profile) {
    final parts = ['${character.name} ${character.kana}'];
    if (profile != null) {
      parts.add('Joined ${DateFormat.yMMMM().format(profile.createdAt)}');
    }
    return parts.join('  ·  ');
  }
}

/// The avatar's colour, with a scatter of soft kana floating in it.
class _Banner extends StatelessWidget {
  final AvatarCharacter character;
  final double height;

  const _Banner({required this.character, required this.height});

  static const _glyphs = [
    ('あ', 0.06, 0.18, 30.0, -0.2),
    ('日', 0.22, 0.58, 22.0, 0.15),
    ('ア', 0.80, 0.14, 28.0, 0.25),
    ('本', 0.90, 0.60, 22.0, -0.1),
    ('語', 0.68, 0.70, 18.0, 0.1),
    ('の', 0.34, 0.10, 18.0, 0.3),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [character.background, character.accent],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            for (final (glyph, x, y, size, angle) in _glyphs)
              Positioned(
                left: constraints.maxWidth * x,
                top: height * y,
                child: Transform.rotate(
                  angle: angle,
                  child: Text(
                    glyph,
                    style: TextStyle(
                      fontSize: size,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditableAvatar extends StatelessWidget {
  final double size;
  final VoidCallback onEdit;

  const _EditableAvatar({required this.size, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onEdit,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: LearnerAvatar(size: size, rounded: true, outlined: true),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Material(
              color: theme.colorScheme.primary,
              shape: CircleBorder(
                side: BorderSide(color: theme.colorScheme.surface, width: 3),
              ),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(Icons.edit, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Level and plan.
class _Badges extends StatelessWidget {
  final UserProfile? profile;

  const _Badges({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = profile?.effectiveLevel;
    final tier = profile?.subscriptionTier ?? SubscriptionTier.free;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (level != null)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LevelBars(level: level, height: 13),
                const SizedBox(width: 6),
                Text(
                  '${level.code} · ${level.title}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: tier.isPaid
                ? const LinearGradient(colors: AppColors.heroGradient)
                : null,
            color: tier.isPaid
                ? null
                : theme.colorScheme.onSurface.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tier.isPaid ? Icons.workspace_premium : Icons.person_outline,
                size: 16,
                color: tier.isPaid
                    ? Colors.white
                    : theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 5),
              Text(
                tier.isPaid ? 'Premium' : 'Free plan',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tier.isPaid ? Colors.white : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  static final _kanaTotal = [
    for (final script in KanaScript.values) ...KanaChart.sections(script),
  ].fold<int>(0, (sum, section) => sum + section.count);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(progressViewModelProvider).summary;
    final kanaKnown = ref.watch(kanaKnownCountProvider);
    String value(int? Function() read) => summary == null ? '—' : '${read()}';

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.local_fire_department,
            value: value(() => summary?.currentStreak),
            label: 'Day streak',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.headphones,
            value: summary == null
                ? '—'
                : _hoursOrMinutes(summary.lifetimeSeconds),
            label: 'Immersed',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.translate,
            value: value(() => summary?.totalWords),
            label: 'Words',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            icon: Icons.font_download_outlined,
            value: '$kanaKnown',
            label: 'Kana / $_kanaTotal',
          ),
        ),
      ],
    );
  }
}

/// "3h" from an hour up, "45m" below.
String _hoursOrMinutes(int seconds) =>
    seconds >= 3600 ? '${seconds ~/ 3600}h' : '${seconds ~/ 60}m';

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// Why they are learning and what they enjoy.
class _Goals extends StatelessWidget {
  final UserProfile profile;

  const _Goals({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    Widget group(String title, List<Widget> pills) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: pills),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile.learningReasons.isNotEmpty)
          group('Learning for', [
            for (final reason in profile.learningReasons)
              Pill(label: reason.label, color: accent, icon: reason.icon),
          ]),
        if (profile.learningReasons.isNotEmpty && profile.interests.isNotEmpty)
          const SizedBox(height: 12),
        if (profile.interests.isNotEmpty)
          group('Interests', [
            for (final interest in profile.interests)
              Pill(label: interest.label, color: accent, icon: interest.icon),
          ]),
      ],
    );
  }
}
