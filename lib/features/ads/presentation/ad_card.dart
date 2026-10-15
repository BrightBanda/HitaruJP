import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/features/ads/domain/ad_creative.dart';
import 'package:ingrain/features/ads/presentation/ad_providers.dart';
import 'package:ingrain/shared/widgets/colorful.dart';

/// An ad for the free tier; draws nothing for paying learners.
///
/// [compact] is the small card for the Immerse page's shelves. The default is
/// a row that matches the video rows it sits between in the player.
class AdCard extends ConsumerWidget {
  final AdPlacement placement;
  final bool compact;
  final int seed;

  const AdCard({
    super.key,
    required this.placement,
    this.compact = false,
    this.seed = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showAdsProvider)) return const SizedBox.shrink();
    final ad = ref.watch(adSourceProvider).next(placement, seed: seed);
    final theme = Theme.of(context);

    void open() {
      final route = ad.route;
      if (route == null) return;
      // Tabs are switched to; pages open on top.
      route.startsWith('/content') ? context.push(route) : context.go(route);
    }

    final label = Pill(label: 'Ad', color: ad.color);
    if (compact) {
      return SizedBox(
        width: 196,
        child: Card(
          color: ad.color.withValues(alpha: 0.12),
          child: InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(
                        color: ad.color,
                        icon: ad.icon,
                        size: 30,
                        solid: true,
                      ),
                      const Spacer(),
                      label,
                    ],
                  ),
                  const Spacer(),
                  Text(
                    ad.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(height: 1.25),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ad.callToAction,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ad.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      color: ad.color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconBadge(color: ad.color, icon: ad.icon, size: 44, solid: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        label,
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ad.headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ad.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ad.callToAction,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: ad.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
