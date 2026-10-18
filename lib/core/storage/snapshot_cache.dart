import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The last copy of what a screen showed, kept on the device so the next
/// launch can paint it at once while fresh data loads behind it
/// (stale-while-revalidate).
///
/// For small, display-only data: the library list, the progress summary,
/// today's picks. Never the source of truth, so a corrupt or outdated entry is
/// simply dropped. Keys should include the uid, so accounts never see each
/// other's copies.
class SnapshotCache {
  final SharedPreferences _prefs;

  SnapshotCache(this._prefs);

  /// Bump to drop every snapshot after a format change.
  static const _prefix = 'snapshot_v1_';

  /// The stored copy decoded by [decode], or null when there is none or it no
  /// longer decodes.
  T? read<T>(String key, T Function(Object? json) decode) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return decode(jsonDecode(raw));
    } catch (error) {
      debugPrint('Dropping unreadable snapshot $key: $error');
      _prefs.remove('$_prefix$key');
      return null;
    }
  }

  /// Stores [json] (anything `jsonEncode` accepts). Failures are ignored: a
  /// missing snapshot only costs a slower next launch.
  Future<void> write(String key, Object? json) async {
    try {
      await _prefs.setString('$_prefix$key', jsonEncode(json));
    } catch (error) {
      debugPrint('Snapshot $key not stored: $error');
    }
  }

  Future<void> remove(String key) => _prefs.remove('$_prefix$key');
}

final snapshotCacheProvider = Provider<SnapshotCache>(
  (ref) => SnapshotCache(ref.watch(sharedPreferencesProvider)),
);
