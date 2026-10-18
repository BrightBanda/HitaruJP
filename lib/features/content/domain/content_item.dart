enum SourceType { youtube, podcast, manual, dialogue }

class ContentItem {
  final String id;
  final SourceType sourceType;
  final String sourceUrl;
  final String title;
  final String? channelTitle;
  final String? thumbnailUrl;
  final int lastPositionSeconds;
  final int totalImmersionSeconds;
  final DateTime lastOpenedAt;
  final int? durationSeconds;

  /// When it joined the library. Null for videos added before this was kept.
  final DateTime? addedAt;

  /// When it joined the library, or the last time it was opened for videos
  /// from before that was recorded. Newest first in the Library.
  DateTime get addedOrOpenedAt => addedAt ?? lastOpenedAt;

  const ContentItem({
    required this.id,
    required this.sourceType,
    required this.sourceUrl,
    required this.title,
    this.channelTitle,
    this.thumbnailUrl,
    this.lastPositionSeconds = 0,
    this.totalImmersionSeconds = 0,
    required this.lastOpenedAt,
    this.durationSeconds,
    this.addedAt,
  });

  ContentItem copyWith({
    String? id,
    SourceType? sourceType,
    String? sourceUrl,
    String? title,
    String? channelTitle,
    String? thumbnailUrl,
    int? lastPositionSeconds,
    int? totalImmersionSeconds,
    DateTime? lastOpenedAt,
    int? durationSeconds,
    DateTime? addedAt,
  }) {
    return ContentItem(
      id: id ?? this.id,
      sourceType: sourceType ?? this.sourceType,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      title: title ?? this.title,
      channelTitle: channelTitle ?? this.channelTitle,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      lastPositionSeconds: lastPositionSeconds ?? this.lastPositionSeconds,
      totalImmersionSeconds:
          totalImmersionSeconds ?? this.totalImmersionSeconds,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}
