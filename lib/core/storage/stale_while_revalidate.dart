import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/storage/snapshot_cache.dart';

/// For a `StreamProvider`: the copy kept on the device first, at once, then
/// the server's, which replaces it and is kept for next time.
///
/// A screen built on it opens with what it showed last time instead of a
/// spinner, even while a sleeping server wakes. When the fetch fails the
/// copy stays on screen; only with no copy does the error show.
///
/// [key] must include the uid, so accounts never see each other's copies.
Stream<T> staleWhileRevalidate<T>(
  Ref ref, {
  required String key,
  required Future<T> Function() fetch,
  required Object? Function(T value) toJson,
  required T Function(Object? json) fromJson,
}) async* {
  final cache = ref.read(snapshotCacheProvider);
  final cached = cache.read(key, fromJson);
  if (cached != null) yield cached;
  try {
    final fresh = await fetch();
    unawaited(cache.write(key, toJson(fresh)));
    yield fresh;
  } catch (_) {
    if (cached == null) rethrow;
  }
}
