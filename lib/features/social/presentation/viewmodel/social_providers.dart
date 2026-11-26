import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/storage/stale_while_revalidate.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/quiz/presentation/viewmodel/quiz_providers.dart';
import 'package:ingrain/features/social/data/remote_social_repository.dart';
import 'package:ingrain/features/social/data/social_json.dart';
import 'package:ingrain/features/social/domain/social.dart';

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => RemoteSocialRepository(ref.watch(apiClientProvider)),
);

DateTime _today(Ref ref) {
  final now = ref.read(clockProvider).now;
  return DateTime(now.year, now.month, now.day);
}

String _uid(Ref ref) =>
    ref.watch(authViewModelProvider.select((auth) => auth.uid));

/// The learner's username, friends, requests and received pings, in one
/// call. Opens with the copy kept on the device, so Friends and the badge
/// show at once while the server answers.
final socialSummaryProvider = StreamProvider<SocialSummary>((ref) {
  final uid = _uid(ref);
  return staleWhileRevalidate(
    ref,
    key: 'social_summary_$uid',
    fetch: () => ref.read(socialRepositoryProvider).summary(today: _today(ref)),
    toJson: SocialJson.summaryToJson,
    fromJson: SocialJson.summary,
  );
});

/// The learner's username (null until chosen) and shared stats.
final socialMeProvider = Provider<AsyncValue<SocialMe>>(
  (ref) => ref.watch(socialSummaryProvider).whenData((s) => s.me),
);

final friendsOverviewProvider = Provider<AsyncValue<FriendsOverview>>(
  (ref) => ref.watch(socialSummaryProvider).whenData((s) => s.friends),
);

final receivedPingsProvider = Provider<AsyncValue<List<ReceivedPing>>>(
  (ref) => ref.watch(socialSummaryProvider).whenData((s) => s.pings),
);

/// Someone's profile page, by username.
final publicProfileProvider = StreamProvider.family<PublicProfile, String>((
  ref,
  username,
) {
  final uid = _uid(ref);
  return staleWhileRevalidate(
    ref,
    key: 'profile_${uid}_$username',
    fetch: () => ref
        .read(socialRepositoryProvider)
        .profile(username, today: _today(ref)),
    toJson: SocialJson.profileToJson,
    fromJson: SocialJson.profile,
  );
});

/// Who may see the learner's profile stats.
final privacyProvider = FutureProvider<ProfileVisibility>((ref) {
  _uid(ref);
  return ref.read(socialRepositoryProvider).privacy();
});

/// This week's board, public or among friends.
final leaderboardProvider =
    StreamProvider.family<Leaderboard, LeaderboardScope>((ref, scope) {
      final uid = _uid(ref);
      return staleWhileRevalidate(
        ref,
        key: 'leaderboard_${uid}_${scope.name}',
        fetch: () => ref
            .read(socialRepositoryProvider)
            .leaderboard(today: _today(ref), scope: scope),
        toJson: SocialJson.leaderboardToJson,
        fromJson: SocialJson.leaderboard,
      );
    });

/// Friend requests and unseen cheers waiting, for the badge on the Friends
/// button. Zero until known: it is only a hint.
final socialBadgeProvider = Provider<int>((ref) {
  final summary = ref.watch(socialSummaryProvider).value;
  if (summary == null) return 0;
  return summary.friends.incoming.length +
      summary.pings.where((ping) => !ping.seen).length;
});

/// Keeps the server's view of this learner current: the stats friends see
/// and any finished quiz it has not had. Callable from widgets and notifiers.
final socialSyncProvider = NotifierProvider<SocialSync, void>(SocialSync.new);

class SocialSync extends Notifier<void> {
  @override
  void build() {}

  /// The level, stage and streak friends see, from this device's progress.
  PublicStats currentStats() {
    final progress = ref.read(progressViewModelProvider);
    final Growth? growth = progress.growth;
    return PublicStats(
      level: growth?.level ?? 1,
      stage: growth?.stage ?? GrowthStage.egg,
      streak: progress.summary?.currentStreak ?? 0,
      bestStreak: progress.summary?.longestStreak ?? 0,
      xp: growth?.xp ?? 0,
      joined: ref.read(authViewModelProvider).profile?.createdAt,
    );
  }

  /// Tells the server what friends should see. Best effort.
  Future<void> publishStats() async {
    try {
      await ref.read(socialRepositoryProvider).setStats(currentStats());
    } catch (_) {
      // Offline: the next visit to Friends publishes them.
    }
  }

  /// Sends finished quizzes the server has not had yet (offline, say), for
  /// the leaderboard. Only a day either side of today is still accepted.
  Future<void> submitPendingQuizzes() async {
    final repository = ref.read(quizRepositoryProvider);
    final social = ref.read(socialRepositoryProvider);
    final today = _today(ref);
    try {
      for (final result in await repository.all()) {
        if (result.submitted) continue;
        if (result.date.difference(today).inDays.abs() > 1) continue;
        if (result.total != DailyQuiz.length) continue;
        try {
          await social.submitQuiz(
            day: result.day,
            correct: result.correct,
            total: result.total,
          );
        } on SocialException catch (error) {
          if (error.code != 'quiz_done') rethrow;
        }
        await repository.markSubmitted(result.day);
      }
      if (!ref.mounted) return;
      ref.invalidate(leaderboardProvider);
      ref.invalidate(socialSummaryProvider);
    } catch (_) {
      // Offline or no username yet: the next visit tries again.
    }
  }

  /// The last activity sent, so an unchanged week is not sent again.
  String? _lastActivity;

  /// The learner's XP from videos, dialogues and flashcards over the last
  /// eight days, for the leaderboard. Best effort.
  Future<void> publishActivity() async {
    final growth = ref.read(progressViewModelProvider).growth;
    if (growth == null) return;
    final now = ref.read(clockProvider).now;
    final since = DateTime(now.year, now.month, now.day - 8);
    final days = [
      for (final day in growth.days)
        if (!day.day.isBefore(since))
          ActivityDay(
            day: quizDayKey(day.day),
            videos: day.bySource[XpSource.watching] ?? 0,
            dialogues:
                (day.bySource[XpSource.reading] ?? 0) +
                (day.bySource[XpSource.dialogues] ?? 0),
            flashcards: day.bySource[XpSource.reviews] ?? 0,
          ),
    ];
    final key = [
      for (final day in days)
        '${day.day}:${day.videos}:${day.dialogues}:${day.flashcards}',
    ].join(',');
    if (days.isEmpty || key == _lastActivity) return;
    try {
      await ref.read(socialRepositoryProvider).reportActivity(days);
      _lastActivity = key;
      if (ref.mounted) ref.invalidate(leaderboardProvider);
    } catch (_) {
      // Offline: the next progress update sends it.
    }
  }

  /// How often opening Friends or the leaderboard syncs: often enough to
  /// stay current, rarely enough not to refetch on every visit.
  static const syncInterval = Duration(minutes: 2);
  DateTime? _lastSync;

  /// [syncAll], unless it ran in the last [syncInterval]. For screens that
  /// open often; their data shows from the device copy meanwhile.
  Future<void> syncIfStale() async {
    final last = _lastSync;
    if (last != null && DateTime.now().difference(last) < syncInterval) return;
    await syncAll();
  }

  /// Everything, for when the learner finishes a quiz or pulls to refresh.
  Future<void> syncAll() async {
    _lastSync = DateTime.now();
    await publishStats();
    await publishActivity();
    await submitPendingQuizzes();
  }
}
