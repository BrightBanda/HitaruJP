import 'package:ingrain/features/auth/domain/user_profile.dart';
import 'package:ingrain/features/catalog/domain/catalog_repository.dart';
import 'package:ingrain/features/catalog/domain/catalog_video.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';
import 'package:ingrain/features/profile/domain/profile_sync_repository.dart';

/// Records what would have been sent to the API.
class FakeProfileSyncRepository implements ProfileSyncRepository {
  final List<UserProfile> pushed = [];
  int visits = 0;
  final List<String> watched = [];
  SubscriptionTier tier = SubscriptionTier.free;

  @override
  Future<SubscriptionTier> push(UserProfile profile) async {
    pushed.add(profile);
    return tier;
  }

  @override
  Future<void> recordVisit() async => visits++;

  @override
  Future<void> recordWatched(String contentId) async => watched.add(contentId);
}

/// Serves fixed daily picks, or throws [error] when set.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({List<CatalogVideo>? picks})
    : picks = picks ?? samplePicks;

  static const samplePicks = [
    CatalogVideo(
      id: 'teppei-001',
      title: 'Nihongo con Teppei #1',
      description: 'A short beginner podcast episode.',
      level: JlptLevel.n5,
      categories: [ContentInterest.podcasts],
      videoUrl: 'https://www.youtube.com/watch?v=drTGtJEvRCA',
      youtubeId: 'drTGtJEvRCA',
      durationSeconds: 235,
      reason: PickReason.interest,
    ),
    CatalogVideo(
      id: 'cj-park',
      title: 'Japanese in the park',
      level: JlptLevel.n5,
      categories: [ContentInterest.youtube],
      videoUrl: 'https://www.youtube.com/watch?v=rjmKQ-fjnyQ',
      youtubeId: 'rjmKQ-fjnyQ',
      reason: PickReason.level,
    ),
    CatalogVideo(
      id: 'nij-curry',
      title: 'Curry, in easy Japanese',
      level: JlptLevel.n5,
      categories: [ContentInterest.culture],
      videoUrl: 'https://www.youtube.com/watch?v=h8aHI9R4p0I',
      youtubeId: 'h8aHI9R4p0I',
      reason: PickReason.level,
    ),
  ];

  List<CatalogVideo> picks;
  Object? error;
  int dailyCalls = 0;

  @override
  Future<DailyPicks> dailyPicks() async {
    dailyCalls++;
    final error = this.error;
    if (error != null) throw error;
    final today = DateTime.now().toUtc();
    final day = DateTime.utc(today.year, today.month, today.day);
    return DailyPicks(
      date: day,
      validUntil: day.add(const Duration(days: 1)),
      level: JlptLevel.n5,
      videos: picks,
    );
  }

  @override
  Future<DailyPicks?> cachedDailyPicks() async => null;

  @override
  Future<List<CatalogVideo>> videosAtLevel(
    JlptLevel level, {
    int limit = 10,
  }) async => const [];
}
