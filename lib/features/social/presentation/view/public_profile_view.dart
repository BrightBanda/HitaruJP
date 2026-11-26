import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/growth/presentation/mascot_painter.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/view/friends_panel.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:ingrain/features/social/presentation/widgets/person_avatar.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// Opens [person]'s profile page.
void openProfile(BuildContext context, Person person) =>
    context.push('/people/${Uri.encodeComponent(person.username)}');

/// Someone's public profile: their companion, when they joined, their
/// streaks, XP and leaderboard places this week and last. Their privacy
/// setting decides whether the stats show.
class PublicProfileView extends ConsumerWidget {
  final String username;

  const PublicProfileView({super.key, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(username));
    return Scaffold(
      appBar: AppBar(title: Text('@$username')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SocialProblem(
          message: error is SocialException
              ? error.message
              : 'Could not reach the HitaruJP server.',
          onRetry: () => ref.invalidate(publicProfileProvider(username)),
        ),
        data: (profile) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(publicProfileProvider(username));
            await ref
                .read(publicProfileProvider(username).future)
                .catchError((Object _) => profile);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Header(profile: profile),
              const SizedBox(height: 16),
              if (profile.isMe) ...[
                _OwnProfileNote(visibility: profile.visibility),
                const SizedBox(height: 16),
              ],
              if (profile.visible)
                _Stats(profile: profile)
              else
                _Private(profile: profile),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PublicProfile profile;

  const _Header({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final person = profile.person;
    return GradientPanel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: PersonAvatar(person: person, size: 112),
          ),
          const SizedBox(height: 14),
          Text(
            profile.isMe ? 'You' : person.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (person.displayName != null || profile.isMe)
            Text(
              '@${person.username}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              Pill(
                label: 'Level ${person.stats.level}',
                icon: Icons.bolt,
                color: Colors.white,
              ),
              Pill(
                label: person.stats.stage.label,
                icon: Icons.pets,
                color: Colors.white,
              ),
            ],
          ),
          if (!profile.isMe) ...[
            const SizedBox(height: 16),
            _FriendActions(person: person),
          ],
        ],
      ),
    );
  }
}

/// Add, accept, or (once friends) cheer and nudge.
class _FriendActions extends ConsumerStatefulWidget {
  final Person person;

  const _FriendActions({required this.person});

  @override
  ConsumerState<_FriendActions> createState() => _FriendActionsState();
}

class _FriendActionsState extends ConsumerState<_FriendActions> {
  late Relation _relation = widget.person.relation;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      HapticFeedback.selectionClick();
    } on SocialException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reach the HitaruJP server.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _befriend() => _run(() async {
    final container = ref.container;
    final repository = container.read(socialRepositoryProvider);
    final updated = _relation == Relation.incoming
        ? await repository.acceptFriend(widget.person.username)
        : await repository.addFriend(widget.person.username);
    if (mounted) setState(() => _relation = updated.relation);
    container
      ..invalidate(socialSummaryProvider)
      ..invalidate(leaderboardProvider)
      ..invalidate(publicProfileProvider(widget.person.username));
  });

  Future<void> _ping(PingKind kind) => _run(() async {
    final left = await ref
        .read(socialRepositoryProvider)
        .ping(widget.person.username, kind);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${kind == PingKind.cheer ? 'Cheer' : 'Nudge'} sent! '
          '${left.hourRemaining} left this hour.',
        ),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final onHero = FilledButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.primaryMain,
      minimumSize: const Size(0, 44),
    );
    final outline = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
      minimumSize: const Size(0, 44),
    );
    return switch (_relation) {
      Relation.friends => Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: onHero,
              onPressed: _busy ? null : () => _ping(PingKind.cheer),
              icon: const Text('🎉'),
              label: const Text('Cheer'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: outline,
              onPressed: _busy ? null : () => _ping(PingKind.nudge),
              icon: const Text('👋'),
              label: const Text('Nudge'),
            ),
          ),
        ],
      ),
      Relation.outgoing => OutlinedButton.icon(
        style: outline,
        onPressed: null,
        icon: const Icon(Icons.schedule, color: Colors.white),
        label: const Text(
          'Request sent',
          style: TextStyle(color: Colors.white),
        ),
      ),
      Relation.incoming || Relation.none => FilledButton.icon(
        style: onHero,
        onPressed: _busy ? null : _befriend,
        icon: _busy ? const Spinner() : const Icon(Icons.person_add),
        label: Text(
          _relation == Relation.incoming
              ? 'Accept friend request'
              : 'Add friend',
        ),
      ),
    };
  }
}

/// One colour for every stat, so the page reads as a whole.
const _accent = AppColors.primaryMain;

class _Stats extends StatelessWidget {
  final PublicProfile profile;

  const _Stats({required this.profile});

  @override
  Widget build(BuildContext context) {
    final joined = profile.joined;
    String days(int? n) => n == null ? '–' : '$n ${n == 1 ? 'day' : 'days'}';
    String week(WeekStanding? standing) =>
        standing == null ? 'Not ranked' : '#${standing.rank}';
    String weekDetail(WeekStanding? standing) => standing == null
        ? 'No XP that week'
        : '${standing.xp} XP · of '
              '${NumberFormat.decimalPattern().format(standing.participants)}';
    final tiles = [
      _StatTile(
        icon: Icons.calendar_month,
        color: _accent,
        label: 'Joined',
        value: joined == null ? '–' : DateFormat.yMMM().format(joined),
      ),
      _StatTile(
        icon: Icons.bolt,
        color: _accent,
        label: 'Total XP',
        value: NumberFormat.decimalPattern().format(profile.xp ?? 0),
        detail: profile.level == null ? null : 'Level ${profile.level}',
      ),
      _StatTile(
        icon: Icons.local_fire_department,
        color: _accent,
        label: 'Current streak',
        value: days(profile.currentStreak),
      ),
      _StatTile(
        icon: Icons.emoji_events,
        color: _accent,
        label: 'Best streak',
        value: days(profile.bestStreak),
      ),
      _StatTile(
        icon: Icons.leaderboard,
        color: _accent,
        label: 'This week',
        value: week(profile.thisWeek),
        detail: weekDetail(profile.thisWeek),
      ),
      _StatTile(
        icon: Icons.history,
        color: _accent,
        label: 'Last week',
        value: week(profile.lastWeek),
        detail: weekDetail(profile.lastWeek),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 3 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? detail;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TintedSurface(
      color: color,
      alpha: 0.1,
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(color: color, icon: icon, size: 36),
          const SizedBox(height: 10),
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            detail ?? ' ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Private extends StatelessWidget {
  final PublicProfile profile;

  const _Private({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friendsOnly = profile.visibility == ProfileVisibility.friends;
    return TintedSurface(
      color: AppColors.primaryMain,
      alpha: 0.08,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const IconBadge(
            color: AppColors.primaryMain,
            icon: Icons.lock_outline,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(
            friendsOnly ? 'Friends only' : 'Stats kept private',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            friendsOnly
                ? '${profile.person.name} shares their streaks and rankings '
                      'with friends.'
                : '${profile.person.name} keeps their streaks and rankings '
                      'to themselves.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _OwnProfileNote extends StatelessWidget {
  final ProfileVisibility visibility;

  const _OwnProfileNote({required this.visibility});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TintedSurface(
      color: AppColors.primaryMain,
      alpha: 0.08,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, color: AppColors.primaryMain),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your stats are visible to: ${visibility.label.toLowerCase()}.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => context.push('/settings'),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
