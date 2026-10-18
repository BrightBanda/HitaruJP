import 'dart:convert';

import 'package:ingrain/core/network/api_client.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';
import 'package:ingrain/features/catalog/data/catalog_video_dto.dart';
import 'package:ingrain/features/catalog/domain/catalog_repository.dart';
import 'package:ingrain/features/catalog/domain/catalog_video.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `GET /recommendations/daily` and `GET /content`, with the last answers
/// cached on the device: daily picks per learner, level videos per level.
class RemoteCatalogRepository implements CatalogRepository {
  final ApiClient _api;
  final AuthRepository _auth;
  final SharedPreferences _prefs;
  final DateTime Function() _now;

  RemoteCatalogRepository(
    this._api,
    this._auth,
    this._prefs, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static String cacheKey(String uid) => 'catalog_daily_picks_$uid';

  static String levelCacheKey(JlptLevel level) =>
      'catalog_level_videos_${level.code}';

  /// How long level videos are used from the cache before asking again.
  /// The catalogue changes when an administrator publishes, not by the minute.
  static const levelCacheTtl = Duration(hours: 6);

  @override
  Future<DailyPicks?> cachedDailyPicks() async {
    final String uid;
    try {
      uid = await _auth.ensureUid();
    } catch (_) {
      return null;
    }
    final cached = _prefs.getString(cacheKey(uid));
    if (cached == null) return null;
    try {
      return CatalogVideoDto.picksFromJson(
        Map<String, dynamic>.from(jsonDecode(cached) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DailyPicks> dailyPicks() async {
    final key = cacheKey(await _auth.ensureUid());
    try {
      final json = await _api.get('/recommendations/daily');
      final map = Map<String, dynamic>.from(json as Map);
      await _prefs.setString(key, jsonEncode(map));
      return CatalogVideoDto.picksFromJson(map);
    } catch (_) {
      // Yesterday's picks beat an empty home screen while offline.
      final cached = _prefs.getString(key);
      if (cached == null) rethrow;
      return CatalogVideoDto.picksFromJson(
        Map<String, dynamic>.from(jsonDecode(cached) as Map),
        isCached: true,
      );
    }
  }

  @override
  Future<List<CatalogVideo>> videosAtLevel(
    JlptLevel level, {
    int limit = 10,
  }) async {
    final key = levelCacheKey(level);
    final cached = _readLevelCache(key);
    if (cached != null && _now().difference(cached.at) < levelCacheTtl) {
      return _videos(cached.items);
    }
    try {
      final json = await _api.get(
        '/content',
        query: {'level': level.code, 'limit': '$limit'},
      );
      final items = (json as Map)['items'] as List? ?? const [];
      await _prefs.setString(
        key,
        jsonEncode({'at': _now().toIso8601String(), 'items': items}),
      );
      return _videos(items);
    } catch (_) {
      // An older list beats an empty shelf while the server is unreachable.
      if (cached == null) rethrow;
      return _videos(cached.items);
    }
  }

  ({DateTime at, List<dynamic> items})? _readLevelCache(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map;
      return (
        at: DateTime.parse(map['at'] as String),
        items: map['items'] as List,
      );
    } catch (_) {
      return null;
    }
  }

  static List<CatalogVideo> _videos(List<dynamic> items) => [
    for (final item in items)
      CatalogVideoDto.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
}
