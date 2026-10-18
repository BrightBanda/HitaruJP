import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:ingrain/features/dialogue/data/dialogue_dto.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';

/// Reads the dialogues bundled in `assets/data/sample_dialogues.json`.
///
/// They are the last resort when the API is unreachable and nothing is cached,
/// so the Library and the reader are usable without running the backend.
class SampleDialogueLoader {
  SampleDialogueLoader({this.assetBundle});

  static const assetPath = 'assets/data/sample_dialogues.json';

  final AssetBundle? assetBundle;

  /// Shared, so callers arriving together parse the file once.
  Future<List<Dialogue>>? _loaded;

  Future<List<Dialogue>> load() =>
      _loaded ??= _load().catchError((Object error) {
        // Let a later call try again.
        _loaded = null;
        throw error;
      });

  Future<List<Dialogue>> _load() async {
    final raw = await (assetBundle ?? rootBundle).loadString(assetPath);
    // A couple of hundred kilobytes of JSON: decoded off the UI thread so the
    // first frames of the home page do not stutter.
    return compute(parse, raw, debugLabel: 'sample dialogues');
  }

  static List<Dialogue> parse(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is Map ? decoded['dialogues'] : null;
    if (list is! List) return const [];
    return list
        .map(
          (value) =>
              DialogueDto.fromMap(Map<String, dynamic>.from(value as Map))
                  .toDomain(),
        )
        .toList();
  }
}
