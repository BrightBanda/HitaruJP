import 'package:ingrain/features/content/domain/content_item.dart';

/// Explicit learning states for a saved word (product spec MVP #13).
///
/// The order is the intended progression, so [index] comparisons express
/// "is at least as far along as".
enum VocabState {
  unknown,
  encountered,
  learning,
  known,
  mastered;

  String get label => switch (this) {
    VocabState.unknown => 'Unknown',
    VocabState.encountered => 'Encountered',
    VocabState.learning => 'Learning',
    VocabState.known => 'Known',
    VocabState.mastered => 'Mastered',
  };

  bool isAtLeast(VocabState other) => index >= other.index;

  static VocabState fromName(String? name) {
    return VocabState.values.firstWhere(
      (state) => state.name == name,
      orElse: () => VocabState.encountered,
    );
  }
}

/// A saved word. Carries the same immersion memory as a mined sentence: where
/// and when it was met, so the item never detaches from its context.
class VocabularyItem {
  final String id;
  final String uid;
  final String word;
  final String? reading;
  final String? meaning;
  final String? pos;
  final SourceType sourceType;
  final String sourceId;
  final String? sourceTitle;
  final int? timestampSeconds;
  final String? contextSentence;
  final String? sessionId;
  final VocabState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int encounterCount;

  const VocabularyItem({
    required this.id,
    required this.uid,
    required this.word,
    this.reading,
    this.meaning,
    this.pos,
    required this.sourceType,
    required this.sourceId,
    this.sourceTitle,
    this.timestampSeconds,
    this.contextSentence,
    this.sessionId,
    this.state = VocabState.encountered,
    required this.createdAt,
    required this.updatedAt,
    this.encounterCount = 1,
  });

  bool get hasReading => reading != null && reading!.trim().isNotEmpty;

  bool get hasMeaning => meaning != null && meaning!.trim().isNotEmpty;

  /// Display form such as `猫 (ねこ)`, falling back to the word alone.
  ///
  /// Readings that repeat the word (plain kana words) are not doubled up.
  String get displayWithReading {
    if (!hasReading) return word;
    final kana = reading!.trim();
    if (kana.isEmpty || kana == word) return word;
    return '$word ($kana)';
  }

  VocabularyItem copyWith({
    String? id,
    String? uid,
    String? word,
    String? Function()? reading,
    String? Function()? meaning,
    String? Function()? pos,
    SourceType? sourceType,
    String? sourceId,
    String? Function()? sourceTitle,
    int? Function()? timestampSeconds,
    String? Function()? contextSentence,
    String? Function()? sessionId,
    VocabState? state,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? encounterCount,
  }) {
    return VocabularyItem(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      word: word ?? this.word,
      reading: reading != null ? reading() : this.reading,
      meaning: meaning != null ? meaning() : this.meaning,
      pos: pos != null ? pos() : this.pos,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      sourceTitle: sourceTitle != null ? sourceTitle() : this.sourceTitle,
      timestampSeconds: timestampSeconds != null
          ? timestampSeconds()
          : this.timestampSeconds,
      contextSentence: contextSentence != null
          ? contextSentence()
          : this.contextSentence,
      sessionId: sessionId != null ? sessionId() : this.sessionId,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      encounterCount: encounterCount ?? this.encounterCount,
    );
  }
}
