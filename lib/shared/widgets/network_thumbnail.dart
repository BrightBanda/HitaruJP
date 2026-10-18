import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A thumbnail from the web, kept in a disk cache so a relaunch shows it
/// without downloading it again, and decoded at the size it is drawn rather
/// than at full resolution (less memory, less work on the UI thread while a
/// list scrolls in).
///
/// [placeholder] shows while it loads and when it fails.
class NetworkThumbnail extends StatelessWidget {
  final String url;
  final Widget placeholder;
  final BoxFit fit;

  const NetworkThumbnail({
    super.key,
    required this.url,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  /// Decode widths are rounded up to a step, so the same picture drawn at
  /// slightly different sizes shares one decoded copy in memory.
  static const _widthStep = 160;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        int? cacheWidth;
        if (constraints.hasBoundedWidth) {
          final pixels = (constraints.maxWidth * pixelRatio).ceil();
          cacheWidth = math.max(
            _widthStep,
            (pixels / _widthStep).ceil() * _widthStep,
          );
        }
        return CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          memCacheWidth: cacheWidth,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, _) => placeholder,
          errorWidget: (_, _, _) => placeholder,
        );
      },
    );
  }
}
