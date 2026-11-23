import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/quiz/domain/daily_quiz.dart';
import 'package:ingrain/features/quiz/presentation/viewmodel/quiz_providers.dart';
import 'package:ingrain/features/social/data/remote_social_repository.dart';
import 'package:ingrain/features/social/domain/social.dart';

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => RemoteSocialRepository(ref.watch(apiClientProvider)),
);

DateTime _today(Ref ref) {
  final now = ref.read(clockProvider).now;
  return DateTime(now.year, now.month, now.day);
}

/// The learner's username (null until chosen) and shared stats.
final socialMeProvider = FutureProvider<SocialMe>((ref) {
  ref.watch(authViewModelProvider.select((auth) => auth.uid));
  return ref.read(socialRepositoryProvider).me();
});

final friendsOverviewProvider = FutureProvider<FriendsOverview>((ref) {
  ref.watch(authViewModelProvider.select((auth) => auth.uid));
  return ref.read(socialRepositoryProvider).friends(today: _today(ref));
});

final receivedPingsProvider = FutureProvider<List<ReceivedPing>>((ref) {
  ref.watch(authViewModelProvider.select((auth) => auth.uid));
  return ref.read(socialRepositoryProvider).pings();
});

/// This week's board, public or among friends.
final leaderboardProvider =
    FutureProvider.family<Leaderboard, LeaderboardScope>((ref, scope) {
      ref.watch(authViewModelProvider.select((auth) => auth.uid));
      return ref
          .read(socialRepositoryProvider)
          .leaderboard(today: _today(ref), scope: scope);
    });

/// Friend requests and unseen cheers waiting, for the badge on the Friends
/// button. Zero when the server cannot be reached: it is only a hint.
final socialBadgeProvider = FutureProvider<int>((ref) async {
  try {
    final overview = await ref.watch(friendsOverviewProvider.future);
    final pings = await ref.watch(receivedPingsProvider.future);
    return overview.incoming.length + pings.where((ping) => !ping.seen).length;
  } catch (_) {
    return 0;
  }
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
      ref.invalidate(friendsOverviewProvider);
    } catch (_) {
      // Offline or no username yet: the next visit tries again.
    }
  }

  /// Both, for when the learner opens Friends or finishes a quiz.
  Future<void> syncAll() async {
    await publishStats();
    await submitPendingQuizzes();
  }
}
