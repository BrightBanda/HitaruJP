import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/app/app.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/storage/local_document_store.dart';
import 'package:ingrain/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Independent, so they start together: the first frame waits for the
  // slower of the two rather than both in turn.
  final (_, prefs) = await (
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    SharedPreferences.getInstance(),
  ).wait;
  // Housekeeping; the first frame does not need to wait for it.
  unawaited(_clearLegacyLocalStore(prefs));
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        firebaseAppProvider.overrideWithValue(Firebase.app()),
      ],
      child: const IngrApp(),
    ),
  );
}

/// Pre-Firebase data was keyed by a random local uid, so it is unreachable from a
/// Firebase account and can never be migrated. Delete it once on first launch after
/// the upgrade so the anonymous user's vocabulary and SRS history do not linger on
/// the device.
Future<void> _clearLegacyLocalStore(SharedPreferences prefs) async {
  final legacyKeys = prefs
      .getKeys()
      .where((key) => key.startsWith(LocalDocumentStore.legacyKeyPrefix))
      .toList();
  for (final key in legacyKeys) {
    await prefs.remove(key);
  }
}
