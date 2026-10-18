import 'package:ingrain/features/catalog/domain/catalog_video.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';

/// The server-curated video catalogue. Nothing here is bundled with the app:
/// administrators decide what exists and what is recommended.
abstract interface class CatalogRepository {
  /// Today's picks for the signed-in learner, chosen by the server from their
  /// level, interests and watch history. Falls back to the last picks fetched
  /// when the server is unreachable, and throws only when there are none.
  Future<DailyPicks> dailyPicks();

  /// The last picks fetched on this device, without asking the server; null
  /// when there are none. Still current until [DailyPicks.validUntil].
  Future<DailyPicks?> cachedDailyPicks();

  /// Published videos at [level], newest first. A recent answer cached on
  /// the device is used without asking the server.
  Future<List<CatalogVideo>> videosAtLevel(JlptLevel level, {int limit = 10});
}
