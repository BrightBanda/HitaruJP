import 'package:flutter/material.dart';
import 'package:ingrain/app/theme/app_colors.dart';

/// Where an ad is shown, so the same slot can rotate through different ads.
enum AdPlacement { playerList, homePicks, homeShelf }

/// What an ad says and where tapping it goes.
class AdCreative {
  final String id;
  final String headline;
  final String body;
  final String callToAction;
  final IconData icon;
  final Color color;

  /// An in-app route, or null for an ad that only informs.
  final String? route;

  const AdCreative({
    required this.id,
    required this.headline,
    required this.body,
    required this.callToAction,
    required this.icon,
    required this.color,
    this.route,
  });
}

/// Where the ads come from.
///
/// Today these are the app's own promotions. A real ad network plugs in by
/// implementing this and overriding the provider; nothing that shows an ad
/// needs to change.
abstract interface class AdSource {
  AdCreative next(AdPlacement placement, {int seed = 0});
}

class HouseAdSource implements AdSource {
  const HouseAdSource();

  static const creatives = [
    AdCreative(
      id: 'premium',
      headline: 'Go Premium',
      body: 'No ads and unlimited AI explanations.',
      callToAction: 'See plans',
      icon: Icons.workspace_premium,
      color: AppColors.review,
      route: '/profile',
    ),
    AdCreative(
      id: 'mining',
      headline: 'Turn lines into flashcards',
      body: 'Mine any sentence from a video or dialogue.',
      callToAction: 'Open flashcards',
      icon: Icons.style,
      color: AppColors.sentences,
      route: '/flashcards',
    ),
    AdCreative(
      id: 'dialogues',
      headline: 'Write your own dialogue',
      body: 'Add kana, romaji and a translation to any text.',
      callToAction: 'Try it',
      icon: Icons.forum,
      color: AppColors.dialogue,
      route: '/content/add',
    ),
    AdCreative(
      id: 'vocab',
      headline: 'Pull words from a transcript',
      body: 'List every word of a video and save the new ones.',
      callToAction: 'Open vocab',
      icon: Icons.translate,
      color: AppColors.vocabulary,
      route: '/learn/vocab',
    ),
  ];

  @override
  AdCreative next(AdPlacement placement, {int seed = 0}) {
    // Premium first in the player; the others rotate with the seed so the
    // learner does not see the same one everywhere.
    final offset = placement == AdPlacement.playerList ? 0 : 1;
    return creatives[(offset + seed) % creatives.length];
  }
}
