import 'package:flutter/material.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/shared/widgets/network_thumbnail.dart';

/// YouTube serves a still for every video id; other sources have none.
String? thumbnailUrlFor(ContentItem item) {
  final stored = item.thumbnailUrl;
  if (stored != null && stored.isNotEmpty) return stored;
  if (item.sourceType != SourceType.youtube) return null;
  return 'https://i.ytimg.com/vi/${item.id}/hqdefault.jpg';
}

/// A video's thumbnail, or a coloured stand-in when there is none or it
/// fails to load.
class VideoThumbnail extends StatelessWidget {
  final ContentItem item;
  final double iconSize;

  const VideoThumbnail({super.key, required this.item, this.iconSize = 40});

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.video.withValues(alpha: 0.16),
      child: Center(
        child: Icon(
          Icons.play_circle_fill,
          color: AppColors.video,
          size: iconSize,
        ),
      ),
    );
    final url = thumbnailUrlFor(item);
    if (url == null) return placeholder;
    return NetworkThumbnail(url: url, placeholder: placeholder);
  }
}
