import 'package:ingrain/features/content/domain/content_item.dart';

class ContentItemDto {
  final Map<String, dynamic> map;

  ContentItemDto({
    required String id,
    required SourceType sourceType,
    required String sourceUrl,
    required String title,
    String? channelTitle,
    String? thumbnailUrl,
    int lastPositionSeconds = 0,
    int totalImmersionSeconds = 0,
    DateTime? lastOpenedAt,
    int? durationSeconds,
    DateTime? addedAt,
  }) : map = {
         'id': id,
         'sourceType': sourceType.name,
         'sourceUrl': sourceUrl,
         'title': title,
         'channelTitle': channelTitle,
         'thumbnailUrl': thumbnailUrl,
         'lastPositionSeconds': lastPositionSeconds,
         'totalImmersionSeconds': totalImmersionSeconds,
         if (lastOpenedAt != null)
           'lastOpenedAt': lastOpenedAt.toIso8601String(),
         if (durationSeconds != null) 'durationSeconds': durationSeconds,
         if (addedAt != null) 'addedAt': addedAt.toIso8601String(),
       };

  ContentItemDto.fromMap(Map<String, dynamic> data) : map = Map.from(data);

  ContentItemDto.fromDomain(ContentItem item)
    : this(
        id: item.id,
        sourceType: item.sourceType,
        sourceUrl: item.sourceUrl,
        title: item.title,
        channelTitle: item.channelTitle,
        thumbnailUrl: item.thumbnailUrl,
        lastPositionSeconds: item.lastPositionSeconds,
        totalImmersionSeconds: item.totalImmersionSeconds,
        lastOpenedAt: item.lastOpenedAt,
        durationSeconds: item.durationSeconds,
        addedAt: item.addedAt,
      );

  ContentItem toDomain() {
    return ContentItem(
      id: map['id'] as String,
      sourceType: SourceType.values.firstWhere(
        (e) => e.name == map['sourceType'],
        orElse: () => SourceType.manual,
      ),
      sourceUrl: map['sourceUrl'] as String,
      title: map['title'] as String,
      channelTitle: map['channelTitle'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      lastPositionSeconds: (map['lastPositionSeconds'] as num?)?.toInt() ?? 0,
      totalImmersionSeconds:
          (map['totalImmersionSeconds'] as num?)?.toInt() ?? 0,
      lastOpenedAt: () {
        final str = map['lastOpenedAt'] as String?;
        return str != null ? DateTime.parse(str) : DateTime.now();
      }(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      addedAt: DateTime.tryParse(map['addedAt'] as String? ?? ''),
    );
  }
}
