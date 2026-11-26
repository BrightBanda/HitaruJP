import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/view/public_profile_view.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:ingrain/features/social/presentation/widgets/person_avatar.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:share_plus/share_plus.dart';

/// Profile's Friends tab: the learner's @username to share, cheers they
/// got, friend requests, and their friends' progress. Asks for a username
/// the first time.
class FriendsPanel extends ConsumerStatefulWidget {
  const FriendsPanel({super.key});

  @override
  ConsumerState<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends ConsumerState<FriendsPanel> {
  @override
  void initState() {
    super.initState();
    // What friends see and any quiz finished offline, sent on every visit.
    unawaited(
      Future.microtask(() {
        if (mounted) ref.read(socialSyncProvider.notifier).syncAll();
      }),
    );
  }

  Future<void> _refresh() async {
    final container = ref.container;
    await container.read(socialSyncProvider.notifier).syncAll();
    container
      ..invalidate(friendsOverviewProvider)
      ..invalidate(receivedPingsProvider)
      ..invalidate(socialBadgeProvider);
    await container
        .read(friendsOverviewProvider.future)
        .catchError((Object _) => const FriendsOverview());
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(socialMeProvider);
    return me.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => SocialProblem(
        message: error is SocialException
            ? error.message
            : 'Could not reach the HitaruJP server.',
        onRetry: () => ref.invalidate(socialMeProvider),
      ),
      data: (me) => me.username == null
          ? const UsernameSetup()
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _FriendsList(username: me.username!),
            ),
    );
  }
}

/// Shares the learner's @username so friends can add them.
Future<void> shareUsername(BuildContext context, String username) async {
  try {
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Learn Japanese with me on HitaruJP! Add me as a friend: '
            '@$username',
        subject: 'Add me on HitaruJP',
      ),
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: '@$username'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Username copied')));
  }
}

// --- Choosing a username --------------------------------------------------------

/// Claims the learner's @username: what friends search for, and what the
/// leaderboard shows.
class UsernameSetup extends ConsumerStatefulWidget {
  /// Why the username is needed here.
  final String reason;

  const UsernameSetup({
    super.key,
    this.reason =
        'Friends find you by it, and it shows on the leaderboard. Your email '
        'is never shown.',
  });

  @override
  ConsumerState<UsernameSetup> createState() => _UsernameSetupState();
}

class _UsernameSetupState extends ConsumerState<UsernameSetup> {
  static final _valid = RegExp(r'^[a-z0-9_]{3,20}$');

  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _controller.text.trim().toLowerCase();
    if (!_valid.hasMatch(username)) {
      setState(() => _error = 'Use 3 to 20 lowercase letters, numbers or _.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final container = ref.container;
    try {
      await container.read(socialRepositoryProvider).setUsername(username);
      container
        ..invalidate(socialMeProvider)
        ..invalidate(leaderboardProvider);
    } on SocialException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reach the HitaruJP server.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.diversity_3,
                size: 56,
                color: AppColors.primaryMain,
              ),
              const SizedBox(height: 16),
              Text('Choose a username', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                widget.reason,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]')),
                  LengthLimitingTextInputFormatter(20),
                  TextInputFormatter.withFunction(
                    (old, value) =>
                        value.copyWith(text: value.text.toLowerCase()),
                  ),
                ],
                decoration: InputDecoration(
                  prefixText: '@',
                  labelText: 'Username',
                  helperText: '3–20 letters, numbers or _',
                  errorText: _error,
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _busy ? const Spinner() : const Text('Save username'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- The list ---------------------------------------------------------------

class _FriendsList extends ConsumerStatefulWidget {
  final String username;

  const _FriendsList({required this.username});

  @override
  ConsumerState<_FriendsList> createState() => _FriendsListState();
}

class _FriendsListState extends ConsumerState<_FriendsList> {
  bool _markedSeen = false;

  /// Cheers shown once are no longer new: clears the badge.
  void _markSeen(List<ReceivedPing> pings) {
    if (!mounted || _markedSeen || pings.every((ping) => ping.seen)) return;
    _markedSeen = true;
    final container = ref.container;
    unawaited(
      container.read(socialRepositoryProvider).markPingsSeen().then((_) {
        container.invalidate(socialBadgeProvider);
      }, onError: (Object _) {}),
    );
  }

  Future<void> _act(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ref.container;
    try {
      await action();
    } on SocialException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reach the HitaruJP server.')),
      );
    }
    container
      ..invalidate(friendsOverviewProvider)
      ..invalidate(leaderboardProvider)
      ..invalidate(socialBadgeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(friendsOverviewProvider);
    final repository = ref.read(socialRepositoryProvider);
    final pings = ref.watch(receivedPingsProvider).value ?? const [];
    final recent = pings
        .where((ping) => DateTime.now().difference(ping.createdAt).inDays < 2)
        .take(5)
        .toList();
    if (recent.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen(recent));
    }

    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => SocialProblem(
        message: '$error',
        onRetry: () => ref.invalidate(friendsOverviewProvider),
      ),
      data: (overview) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _MyHandle(username: widget.username),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionHeader('For you'),
            for (final ping in recent) _PingTile(ping: ping),
          ],
          if (overview.incoming.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionHeader('Friend requests · ${overview.incoming.length}'),
            for (final person in overview.incoming)
              PersonRow(
                person: person,
                actions: [
                  TextButton(
                    onPressed: () =>
                        _act(() => repository.removeFriend(person.username)),
                    child: const Text('Decline'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        _act(() => repository.acceptFriend(person.username)),
                    child: const Text('Accept'),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 16),
          SectionHeader(
            overview.friends.isEmpty
                ? 'Friends'
                : 'Friends · ${overview.friends.length}',
          ),
          if (overview.friends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.group_add,
                color: AppColors.primaryMain,
                title: 'Study together',
                message:
                    'Add friends to follow their progress, cheer each other '
                    'on and compare quiz scores.',
                action: FilledButton.icon(
                  onPressed: () => context.push('/friends/search'),
                  icon: const Icon(Icons.person_search),
                  label: const Text('Find people'),
                ),
              ),
            )
          else
            for (final friend in overview.friends) _FriendTile(friend: friend),
          if (overview.outgoing.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionHeader('Waiting for them'),
            for (final person in overview.outgoing)
              PersonRow(
                person: person,
                actions: [
                  TextButton(
                    onPressed: () =>
                        _act(() => repository.removeFriend(person.username)),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _MyHandle extends StatelessWidget {
  final String username;

  const _MyHandle({required this.username});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.alternate_email),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@$username',
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Friends find you by this',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Share my username',
              icon: const Icon(Icons.ios_share),
              onPressed: () => shareUsername(context, username),
            ),
            FilledButton.tonalIcon(
              onPressed: () => context.push('/friends/search'),
              icon: const Icon(Icons.person_search, size: 18),
              label: const Text('Find'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PingTile extends StatelessWidget {
  final ReceivedPing ping;

  const _PingTile({required this.ping});

  @override
  Widget build(BuildContext context) {
    final name = ping.sender.name;
    final code = ping.shareCode;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => openProfile(context, ping.sender),
      leading: PersonAvatar(person: ping.sender, size: 40),
      title: Text(switch (ping.kind) {
        PingKind.cheer => '$name cheered you on 🎉',
        PingKind.nudge => '$name nudged you 👋',
        PingKind.share => '$name shared "${ping.shareTitle ?? 'something'}"',
      }),
      subtitle: Text(_ago(ping.createdAt)),
      trailing: ping.kind == PingKind.share && code != null
          ? FilledButton.tonal(
              onPressed: () => context.push('/import?code=$code'),
              child: const Text('Add'),
            )
          : ping.seen
          ? null
          : const Badge(smallSize: 10, backgroundColor: AppColors.streak),
    );
  }
}

/// A friend and their progress, with cheer and nudge buttons.
class _FriendTile extends ConsumerStatefulWidget {
  final Person friend;

  const _FriendTile({required this.friend});

  @override
  ConsumerState<_FriendTile> createState() => _FriendTileState();
}

class _FriendTileState extends ConsumerState<_FriendTile> {
  PingKind? _sending;

  Future<void> _ping(PingKind kind) async {
    if (_sending != null) return;
    setState(() => _sending = kind);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final left = await ref
          .read(socialRepositoryProvider)
          .ping(widget.friend.username, kind);
      HapticFeedback.lightImpact();
      final what = kind == PingKind.cheer ? 'Cheer' : 'Nudge';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$what sent to ${widget.friend.name}! '
            '${left.hourRemaining} left this hour, '
            '${left.dayRemaining} today.',
          ),
        ),
      );
    } on SocialException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reach the HitaruJP server.')),
      );
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${widget.friend.name}?'),
        content: const Text('You will no longer follow each other.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final container = ref.container;
    try {
      await container
          .read(socialRepositoryProvider)
          .removeFriend(widget.friend.username);
    } catch (_) {}
    container
      ..invalidate(friendsOverviewProvider)
      ..invalidate(leaderboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friend = widget.friend;
    final quiz = friend.todayQuiz;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openProfile(context, friend),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              PersonAvatar(person: friend),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${friend.username} · ${statsLine(friend)}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quiz == null
                          ? 'No quiz yet today'
                          : 'Quiz today: ${quiz.correct}/${quiz.total}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: quiz == null
                            ? theme.colorScheme.onSurfaceVariant
                            : AppColors.dialogue,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cheer ${friend.name} on',
                onPressed: _sending == null
                    ? () => _ping(PingKind.cheer)
                    : null,
                icon: _sending == PingKind.cheer
                    ? const Spinner()
                    : const Text('🎉', style: TextStyle(fontSize: 22)),
              ),
              IconButton(
                tooltip: 'Nudge ${friend.name} to study',
                onPressed: _sending == null
                    ? () => _ping(PingKind.nudge)
                    : null,
                icon: _sending == PingKind.nudge
                    ? const Spinner()
                    : const Text('👋', style: TextStyle(fontSize: 22)),
              ),
              PopupMenuButton<String>(
                onSelected: (_) => _remove(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('Remove friend')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Shared pieces -------------------------------------------------------------

/// A learner with action buttons on the right: requests and search results.
class PersonRow extends StatelessWidget {
  final Person person;
  final List<Widget> actions;

  const PersonRow({super.key, required this.person, required this.actions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openProfile(context, person),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            PersonAvatar(person: person, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${person.username} · ${statsLine(person)}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// A failed load with a way to try again.
class SocialProblem extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const SocialProblem({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(32),
    children: [
      const Icon(Icons.cloud_off, size: 48),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Center(
        child: FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ),
    ],
  );
}

class Spinner extends StatelessWidget {
  const Spinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2.4),
  );
}

String _ago(DateTime time) {
  final elapsed = DateTime.now().difference(time);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
  return elapsed.inDays == 1 ? 'Yesterday' : '${elapsed.inDays} days ago';
}
