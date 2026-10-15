import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/ads/domain/ad_creative.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';

final adSourceProvider = Provider<AdSource>((ref) => const HouseAdSource());

/// Ads are for the free tier only. A tier the app does not know reads as free.
final showAdsProvider = Provider<bool>((ref) {
  final tier = ref.watch(
    authViewModelProvider.select((auth) => auth.profile?.subscriptionTier),
  );
  return tier == null || !tier.isPaid;
});
