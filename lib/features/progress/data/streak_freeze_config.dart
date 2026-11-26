import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/network/api_client.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/progress/domain/streaks.dart';

/// Where the streak freeze tiers come from: the server, which an admin edits.
abstract interface class StreakFreezeConfigRepository {
  Future<StreakFreezeRules> fetch();
}

class RemoteStreakFreezeConfigRepository
    implements StreakFreezeConfigRepository {
  final ApiClient _api;

  RemoteStreakFreezeConfigRepository(this._api);

  @override
  Future<StreakFreezeRules> fetch() async =>
      StreakFreezeRules.fromJson(await _api.get('/config/streak-freezes')) ??
      StreakFreezeRules.defaults;
}

final streakFreezeConfigRepositoryProvider =
    Provider<StreakFreezeConfigRepository>(
      (ref) => RemoteStreakFreezeConfigRepository(ref.watch(apiClientProvider)),
    );

/// The streak freeze tiers in force: the last ones fetched (kept on the
/// device) or the defaults, refreshed from the server once a launch.
final streakFreezeRulesProvider =
    NotifierProvider<StreakFreezeRulesNotifier, StreakFreezeRules>(
      StreakFreezeRulesNotifier.new,
    );

class StreakFreezeRulesNotifier extends Notifier<StreakFreezeRules> {
  static const _cacheKey = 'streak_freeze_rules';

  @override
  StreakFreezeRules build() {
    unawaited(Future.microtask(refresh));
    final cached = ref.read(sharedPreferencesProvider).getString(_cacheKey);
    if (cached == null) return StreakFreezeRules.defaults;
    try {
      return StreakFreezeRules.fromJson(jsonDecode(cached)) ??
          StreakFreezeRules.defaults;
    } catch (_) {
      return StreakFreezeRules.defaults;
    }
  }

  Future<void> refresh() async {
    try {
      final rules = await ref
          .read(streakFreezeConfigRepositoryProvider)
          .fetch();
      if (!ref.mounted) return;
      await ref
          .read(sharedPreferencesProvider)
          .setString(_cacheKey, jsonEncode(rules.toJson()));
      if (ref.mounted && !_same(rules, state)) state = rules;
    } catch (_) {
      // Offline: keep the tiers last seen.
    }
  }

  static bool _same(StreakFreezeRules a, StreakFreezeRules b) =>
      a.tiers.length == b.tiers.length &&
      [for (var i = 0; i < a.tiers.length; i++) a.tiers[i] == b.tiers[i]]
          .every((same) => same);
}
