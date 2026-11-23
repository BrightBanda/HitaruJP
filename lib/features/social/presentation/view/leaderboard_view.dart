import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/quiz/presentation/viewmodel/quiz_providers.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/view/friends_panel.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';
import 'package:ingrain/features/social/presentation/widgets/person_avatar.dart';

/// The Leaderboard tab: this week's daily-quiz XP, for everyone or among
/// friends, with a button to take today's quiz.
class LeaderboardView extends ConsumerStatefulWidget {
  const LeaderboardView({super.key});

  @override
  ConsumerState<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends ConsumerState<LeaderboardView> {
  LeaderboardScope _scope = LeaderboardScope.everyone;

  Future<void> _openQuiz() async {
    await context.push('/quiz');
    ref.invalidate(leaderboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(socialMeProvider);
    final quiz = ref.watch(todayQuizResultProvider).value;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Leaderboard'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'quiz',
        onPressed: _openQuiz,
        icon: Icon(quiz == null ? Icons.play_arrow_rounded : Icons.check),
        label: Text(
          quiz == null
              ? "Start today's quiz"
              : 'Quiz done · ${quiz.correct}/${quiz.total}',
        ),
      ),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SocialProblem(
          message: error is SocialException
              ? error.message
              : 'Could not reach the HitaruJP server.',
          onRetry: () => ref.invalidate(socialMeProvider),
        ),
        data: (me) => me.username == null
            ? const UsernameSetup(
                reason:
                    'Pick a username to appear on the leaderboard. Everyone '
                    'sees your username and companion; your name and email '
                    'stay private.',
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<LeaderboardScope>(
                        segments: const [
                          ButtonSegment(
                            value: LeaderboardScope.everyone,
                            icon: Icon(Icons.public),
                            label: Text('Everyone'),
                          ),
                          ButtonSegment(
                            value: LeaderboardScope.friends,
                            icon: Icon(Icons.people),
                            label: Text('Friends'),
                          ),
                        ],
                        selected: {_scope},
                        onSelectionChanged: (selection) =>
                            setState(() => _scope = selection.first),
                      ),
                    ),
                  ),
                  Expanded(child: _Board(scope: _scope)),
                ],
              ),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  final LeaderboardScope scope;

  const _Board({required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(leaderboardProvider(scope));
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(socialSyncProvider.notifier).syncAll();
        ref.invalidate(leaderboardProvider(scope));
        await ref
            .read(leaderboardProvider(scope).future)
            .catchError(
              (Object _) => Leaderboard(weekStart: DateTime.now(), entries: []),
            );
      },
      child: board.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SocialProblem(
          message: '$error',
          onRetry: () => ref.invalidate(leaderboardProvider(scope)),
        ),
        data: (board) {
          final me = board.me;
          final empty = board.entries.every((entry) => entry.weekXp == 0);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Room under the last row for the quiz button.
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              Text("This week's quiz XP", style: theme.textTheme.titleLarge),
              Text(
                [
                  'Resets every Monday',
                  if (scope == LeaderboardScope.everyone &&
                      board.participants > 0)
                    '${board.participants} '
                        '${board.participants == 1 ? 'learner' : 'learners'}',
                  '5 XP a right answer, 10 more for a perfect quiz',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (empty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    scope == LeaderboardScope.everyone
                        ? 'No quizzes yet this week. Be the first on the board!'
                        : 'No quizzes yet this week. Add friends from your '
                              'profile to race them.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              for (final entry in board.entries)
                if (!empty || entry.isMe) LeaderboardRow(entry: entry),
              if (board.meIsBelow && me != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Center(child: Text('⋯')),
                ),
                LeaderboardRow(entry: me),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One learner's place on the board. Tapping someone else shows them, with
/// a way to add them as a friend.
class LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;

  const LeaderboardRow({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = entry.weekXp == 0
        ? null
        : switch (entry.rank) {
            1 => '🥇',
            2 => '🥈',
            3 => '🥉',
            _ => null,
          };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: entry.isMe ? AppColors.primaryMain.withValues(alpha: 0.08) : null,
      shape: entry.isMe
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.primaryMain, width: 1.5),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: entry.isMe
            ? null
            : () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => _PersonSheet(person: entry.person),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  medal ?? '${entry.rank}',
                  textAlign: TextAlign.center,
                  style: medal == null
                      ? theme.textTheme.titleMedium
                      : const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 6),
              PersonAvatar(person: entry.person, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.isMe ? 'You' : entry.person.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${entry.quizzes} '
                      '${entry.quizzes == 1 ? 'quiz' : 'quizzes'} · '
                      '${entry.correct} right',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '${entry.weekXp} XP',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.primaryMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Someone from the board: their companion and progress, and a friend
/// request a tap away.
class _PersonSheet extends ConsumerStatefulWidget {
  final Person person;

  const _PersonSheet({required this.person});

  @override
  ConsumerState<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends ConsumerState<_PersonSheet> {
  late Relation _relation = widget.person.relation;
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(socialRepositoryProvider);
      final updated = _relation == Relation.incoming
          ? await repository.acceptFriend(widget.person.username)
          : await repository.addFriend(widget.person.username);
      HapticFeedback.selectionClick();
      if (mounted) setState(() => _relation = updated.relation);
      ref
        ..invalidate(friendsOverviewProvider)
        ..invalidate(leaderboardProvider);
    } on SocialException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final person = widget.person;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PersonAvatar(person: person, size: 88),
            const SizedBox(height: 12),
            Text(person.name, style: theme.textTheme.titleLarge),
            if (person.displayName != null)
              Text('@${person.username}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(statsLine(person), style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: switch (_relation) {
                Relation.friends => const OutlinedButton(
                  onPressed: null,
                  child: Text('Friends ✓'),
                ),
                Relation.outgoing => const OutlinedButton(
                  onPressed: null,
                  child: Text('Request sent'),
                ),
                Relation.incoming || Relation.none => FilledButton.icon(
                  onPressed: _busy ? null : _add,
                  icon: _busy ? const Spinner() : const Icon(Icons.person_add),
                  label: Text(
                    _relation == Relation.incoming
                        ? 'Accept friend request'
                        : 'Add friend',
                  ),
                ),
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
