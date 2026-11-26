import 'package:ingrain/features/catalog/domain/catalog_video.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';

/// Maps the API's camelCase content and daily-picks JSON. The same shape is
/// written to the on-device cache, so a cached copy parses like a fresh one.
abstract final class CatalogVideoDto {
  static CatalogVideo fromJson(Map<String, dynamic> json) => CatalogVideo(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    level: JlptLevel.fromCode(json['level']),
    categories: [
      for (final code in json['categories'] as List? ?? const [])
        ?ContentInterest.fromCode(code),
    ],
    videoUrl: json['videoUrl'] as String,
    youtubeId: json['youtubeId'] as String?,
    thumbnailUrl:
        json['resolvedThumbnailUrl'] as String? ??
        json['thumbnailUrl'] as String?,
    durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
    channelTitle: json['channelTitle'] as String?,
    reason: PickReason.fromCode(json['reason']),
  );

  /// The same shape [fromJson] reads, for the on-device copy.
  static Map<String, dynamic> toJson(CatalogVideo video) => {
    'id': video.id,
    'title': video.title,
    'description': video.description,
    'level': video.level?.code,
    'categories': [for (final c in video.categories) c.code],
    'videoUrl': video.videoUrl,
    'youtubeId': video.youtubeId,
    'thumbnailUrl': video.thumbnailUrl,
    'durationSeconds': video.durationSeconds,
    'channelTitle': video.channelTitle,
    'reason': video.reason?.code,
  };

  static DailyPicks picksFromJson(
    Map<String, dynamic> json, {
    bool isCached = false,
  }) => DailyPicks(
    date: _utcDay(json['date'] as String),
    validUntil: DateTime.parse(json['validUntil'] as String),
    level: JlptLevel.fromCode(json['level']) ?? JlptLevel.fallback,
    videos: [
      for (final item in json['items'] as List? ?? const [])
        fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    isCached: isCached,
  );

  /// `2026-10-07` as that UTC calendar day. A bare date would otherwise parse
  /// as local midnight.
  static DateTime _utcDay(String day) {
    final parsed = DateTime.parse(day);
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }
}
