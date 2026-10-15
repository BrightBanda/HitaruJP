import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/ads/domain/ad_creative.dart';
import 'package:ingrain/features/ads/presentation/ad_card.dart';
import 'package:ingrain/features/ads/presentation/ad_providers.dart';
import 'package:ingrain/features/catalog/presentation/viewmodel/catalog_providers.dart';
import 'package:ingrain/features/catalog/presentation/widgets/daily_picks_section.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// "Up next" under the player: videos at the learner's level, with an ad
/// between them on the free tier.
class RecommendedVideos extends ConsumerWidget {
  /// The YouTube id now playing, which is left out of the list.
  final String? currentYoutubeId;

  const RecommendedVideos({super.key, this.currentYoutubeId});

  /// Videos shown at most.
  static const _limit = 8;

  /// An ad goes after this many videos, and again after twice as many.
  static const _adEvery = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(dailyPicksProvider).value?.videos ?? const [];
    final more = ref.watch(levelVideosProvider).value ?? const [];
    final showAds = ref.watch(showAdsProvider);

    // Today's picks first, then the rest of the level, each video once.
    final seen = <String>{};
    final videos = [
      for (final video in [...picks, ...more])
        if (video.youtubeId != null &&
            video.youtubeId != currentYoutubeId &&
            seen.add(video.id))
          video,
    ].take(_limit).toList();
    if (videos.isEmpty && !showAds) return const SizedBox.shrink();

    final children = <Widget>[];
    for (final (index, video) in videos.indexed) {
      if (showAds && index > 0 && index % _adEvery == 0) {
        children.add(
          AdCard(placement: AdPlacement.playerList, seed: index ~/ _adEvery),
        );
      }
      children.add(CatalogVideoRow(video: video, replaceRoute: true));
    }
    // A short list still gets its ad.
    if (showAds && videos.length <= _adEvery) {
      children.add(const AdCard(placement: AdPlacement.playerList));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'Up next',
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index > 0) const SizedBox(height: 10),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
