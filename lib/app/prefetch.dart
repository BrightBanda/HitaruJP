import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/catalog/presentation/viewmodel/catalog_providers.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/social/presentation/viewmodel/social_providers.dart';

/// How long after launch the warm-up starts: long enough for the home page
/// to load first, which matters most.
const _prefetchDelay = Duration(seconds: 2);

/// Starts loading what the learner is likely to open next, a moment after
/// launch, so those pages are ready (and the server awake) when they get
/// there. Each is kept in memory for the session once loaded.
final prefetchProvider = Provider<void>((ref) {
  final onboarded = ref.watch(
    authViewModelProvider.select((auth) => auth.isOnboarded),
  );
  if (!onboarded) return;
  final timer = Timer(_prefetchDelay, () {
    if (!ref.mounted) return;
    ref
      ..read(socialSummaryProvider)
      ..read(leaderboardProvider(LeaderboardScope.everyone))
      ..read(levelVideosProvider);
  });
  ref.onDispose(timer.cancel);
});
