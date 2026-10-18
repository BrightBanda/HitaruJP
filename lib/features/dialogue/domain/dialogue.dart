enum DialogueKind { dialogue, story, book }

/// What a book is, shown above its text: who wrote the original and what the
/// adaptation is. Credit and the source link live in [DialogueSource].
class BookInfo {
  final String author;
  final String? originalTitle;
  final int? originalYear;
  final String? summary;

  const BookInfo({
    required this.author,
    this.originalTitle,
    this.originalYear,
    this.summary,
  });
}

class DialogueSource {
  final String? attribution;
  final String? url;

  const DialogueSource({this.attribution, this.url});
}

class DialogueToken {
  final String surface;
  final String? reading;
  final String? romaji;

  const DialogueToken({required this.surface, this.reading, this.romaji});
}

class DialogueLine {
  final int index;
  final String? speaker;
  final List<DialogueToken> tokens;

  /// The whole line in romaji and in English, when the author wrote them.
  final String? romaji;
  final String? translation;

  const DialogueLine({
    required this.index,
    this.speaker,
    required this.tokens,
    this.romaji,
    this.translation,
  });

  String get text => tokens.map((token) => token.surface).join();
}

class DialogueSummary {
  final String id;
  final String title;
  final String level;
  final DialogueKind kind;
  final List<String> speakers;
  final int lineCount;
  final DialogueSource source;
  final DateTime? updatedAt;

  /// Set when [kind] is [DialogueKind.book].
  final BookInfo? book;

  const DialogueSummary({
    required this.id,
    required this.title,
    required this.level,
    this.kind = DialogueKind.dialogue,
    this.speakers = const [],
    this.lineCount = 0,
    this.source = const DialogueSource(),
    this.updatedAt,
    this.book,
  });
}

class Dialogue extends DialogueSummary {
  final List<DialogueLine> lines;

  const Dialogue({
    required super.id,
    required super.title,
    required super.level,
    super.kind,
    super.speakers,
    super.source,
    super.updatedAt,
    super.book,
    required this.lines,
  }) : super(lineCount: lines.length);
}
