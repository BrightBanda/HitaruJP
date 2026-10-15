import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/theme/app_colors.dart';
import 'package:ingrain/features/ads/domain/ad_creative.dart';
import 'package:ingrain/features/ads/presentation/ad_card.dart';
import 'package:ingrain/features/ads/presentation/ad_providers.dart';
import 'package:ingrain/core/utils/duration_format.dart';
import 'package:ingrain/features/catalog/domain/catalog_video.dart';
import 'package:ingrain/features/catalog/presentation/viewmodel/catalog_providers.dart';
import 'package:ingrain/features/profile/presentation/widgets/learner_preference_style.dart';
import 'package:ingrain/shared/widgets/colorful.dart';
import 'package:ingrain/shared/widgets/web_transcript_notice.dart';

/// Opens [video] in the player, telling the learner what is going on.
///
/// [replace] swaps the current page for the player instead of stacking another
/// on top, for videos opened from inside the player.
Future<void> openCatalogVideo(
  BuildContext context,
  WidgetRef ref,
  CatalogVideo video, {
  bool replace = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    final opened = await ref.read(catalogOpenerProvider.notifier).open(video);
    final route = '/content/${opened.contentId}';
    replace ? router.pushReplacement(route) : router.push(route);
    if (!opened.hasTranscript) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            WebTranscriptNotice.applies
                ? WebTranscriptNotice.missingTranscript
                : 'No Japanese subtitles on this one. Enjoy it as listening '
                      'practice.',
          ),
        ),
      );
    }
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open this video. Try again.\n$error')),
    );
  }
}

/// "Today's picks": the three videos the server chose for this learner today.
class DailyPicksSection extends ConsumerWidget {
  /// Shown instead when the picks cannot be loaded at all.
  final Widget fallback;

  const DailyPicksSection({super.key, required this.fallback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(dailyPicksProvider);
    final theme = Theme.of(context);

    final level = picks.value?.level;
    final subtitle = switch (picks) {
      AsyncData(:final value) when value.isCached =>
        'Offline · showing your last picks',
      AsyncData(:final value) =>
        '${value.level.code} · ${_freshIn(value.validUntil)}',
      _ => 'Chosen for your level and interests',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
          child: Row(
            children: [
              IconBadge(
                color: level?.color ?? AppColors.video,
                icon: Icons.auto_awesome,
                size: 34,
                solid: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Today's picks", style: theme.textTheme.titleMedium),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        switch (picks) {
          AsyncData(:final value) when value.videos.isNotEmpty => LayoutBuilder(
            builder: (context, constraints) {
              // Wide: all of today's picks side by side, as equals.
              if (constraints.maxWidth >= _sideBySideMinWidth) {
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (index, video) in value.videos.indexed) ...[
                          if (index > 0) const SizedBox(width: 14),
                          Expanded(
                            child: _PickHeroCard(video: video, compact: true),
                          ),
                        ],
                      ],
                    ),
                    const _SpacedAd(placement: AdPlacement.homePicks),
                  ],
                );
              }
              return Column(
                children: [
                  _PickHeroCard(video: value.videos.first),
                  for (final video in value.videos.skip(1)) ...[
                    const SizedBox(height: 10),
                    CatalogVideoRow(video: video),
                  ],
                  const _SpacedAd(placement: AdPlacement.homePicks),
                ],
              );
            },
          ),
          AsyncData() || AsyncError() => fallback,
          _ => const _PicksLoading(),
        },
      ],
    );
  }

  /// From this width the picks sit in one row instead of a stack.
  static const _sideBySideMinWidth = 640.0;

  static String _freshIn(DateTime validUntil) {
    final left = validUntil.difference(DateTime.now().toUtc());
    if (left.inHours >= 1) return 'new picks in ${left.inHours}h';
    if (left.inMinutes >= 1) return 'new picks in ${left.inMinutes}m';
    return 'new picks soon';
  }
}

/// Published videos at the learner's level, as a horizontal shelf.
class LevelShelf extends ConsumerWidget {
  const LevelShelf({super.key});

  /// Where the ad card goes among the videos.
  static const _shelfAdIndex = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videos = ref.watch(levelVideosProvider).value;
    final picks = ref.watch(dailyPicksProvider).value;
    final showAds = ref.watch(showAdsProvider);
    if (videos == null) return const SizedBox.shrink();
    // Today's picks are already on screen; do not show them twice.
    final shown = {for (final video in picks?.videos ?? const []) video.id};
    final rest = videos.where((video) => !shown.contains(video.id)).toList();
    if (rest.isEmpty) return const SizedBox.shrink();

    final level = rest.first.level;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          level == null ? 'More to watch' : 'More at ${level.code}',
        ),
        SizedBox(
          height: 178,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Free tier: a small ad card sits among the videos.
            itemCount: rest.length + (showAds ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (showAds && index == _shelfAdIndex.clamp(0, rest.length)) {
                return const AdCard(
                  placement: AdPlacement.homeShelf,
                  compact: true,
                );
              }
              final at = showAds && index > _shelfAdIndex ? index - 1 : index;
              return _ShelfCard(video: rest[at]);
            },
          ),
        ),
      ],
    );
  }
}

class _PickHeroCard extends ConsumerWidget {
  final CatalogVideo video;

  /// One of several in a row: a smaller play button and less text.
  final bool compact;

  const _PickHeroCard({required this.video, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final opening = ref.watch(catalogOpenerProvider).contains(video.id);
    return Card(
      child: InkWell(
        onTap: opening ? null : () => openCatalogVideo(context, ref, video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CatalogThumbnail(video: video, iconSize: 56),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x99000000)],
                      ),
                    ),
                  ),
                  Center(
                    child: _PlayButton(busy: opening, size: compact ? 44 : 56),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _ReasonChip(video: video),
                  ),
                  if (video.durationSeconds case final seconds?)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _DurationBadge(seconds: seconds),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (video.description.isNotEmpty && !compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      video.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 10),
                  _MetaRow(video: video),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A video as a compact row: thumbnail, title and labels.
class CatalogVideoRow extends ConsumerWidget {
  final CatalogVideo video;

  /// See [openCatalogVideo].
  final bool replaceRoute;

  const CatalogVideoRow({
    super.key,
    required this.video,
    this.replaceRoute = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final opening = ref.watch(catalogOpenerProvider).contains(video.id);
    return Card(
      child: InkWell(
        onTap: opening
            ? null
            : () =>
                  openCatalogVideo(context, ref, video, replace: replaceRoute),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 128,
                  height: 72,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _CatalogThumbnail(video: video, iconSize: 28),
                      Center(child: _PlayButton(busy: opening, size: 30)),
                      if (video.durationSeconds case final seconds?)
                        Positioned(
                          right: 5,
                          bottom: 5,
                          child: _DurationBadge(seconds: seconds, small: true),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    _MetaRow(video: video, compact: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfCard extends ConsumerWidget {
  final CatalogVideo video;

  const _ShelfCard({required this.video});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final opening = ref.watch(catalogOpenerProvider).contains(video.id);
    return SizedBox(
      width: 196,
      child: Card(
        child: InkWell(
          onTap: opening ? null : () => openCatalogVideo(context, ref, video),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 108,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CatalogThumbnail(video: video, iconSize: 32),
                    if (opening)
                      const Center(child: _PlayButton(busy: true, size: 34)),
                    if (video.durationSeconds case final seconds?)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: _DurationBadge(seconds: seconds, small: true),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Level, category and channel, as small coloured labels.
class _MetaRow extends StatelessWidget {
  final CatalogVideo video;
  final bool compact;

  const _MetaRow({required this.video, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final level = video.level;
    final category = video.primaryCategory;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (level != null)
          Pill(label: level.code, color: level.color, solid: true),
        if (category != null)
          Pill(
            label: category.label,
            color: category.color,
            icon: category.icon,
          ),
        if (!compact && video.channelTitle != null)
          Text(
            video.channelTitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final CatalogVideo video;

  const _ReasonChip({required this.video});

  @override
  Widget build(BuildContext context) {
    final reason = video.reason;
    if (reason == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            reason == PickReason.curated
                ? Icons.star_rounded
                : Icons.auto_awesome,
            size: 14,
            color: AppColors.primaryMain,
          ),
          const SizedBox(width: 4),
          Text(
            reason.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool busy;
  final double size;

  const _PlayButton({required this.busy, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.video,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 10)],
      ),
      child: busy
          ? Padding(
              padding: EdgeInsets.all(size * 0.28),
              child: const CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            )
          : Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: size * 0.62,
            ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  final int seconds;
  final bool small;

  const _DurationBadge({required this.seconds, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        formatDuration(Duration(seconds: seconds)),
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 10.5 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CatalogThumbnail extends StatelessWidget {
  final CatalogVideo video;
  final double iconSize;

  const _CatalogThumbnail({required this.video, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    final color = video.level?.color ?? AppColors.video;
    final placeholder = ColoredBox(
      color: color.withValues(alpha: 0.16),
      child: Center(
        child: Icon(Icons.smart_display, color: color, size: iconSize),
      ),
    );
    final url = video.thumbnailUrl;
    if (url == null) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

class _PicksLoading extends StatelessWidget {
  const _PicksLoading();

  @override
  Widget build(BuildContext context) {
    final tint = Theme.of(context).colorScheme.primary.withValues(alpha: 0.08);
    Widget block(double height) => Container(
      height: height,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(18),
      ),
    );
    return Column(
      children: [block(250), const SizedBox(height: 10), block(92)],
    );
  }
}

/// A small ad with room above it, which takes no room when there is no ad.
class _SpacedAd extends ConsumerWidget {
  final AdPlacement placement;

  const _SpacedAd({required this.placement});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showAdsProvider)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AdCard(placement: placement),
    );
  }
}
