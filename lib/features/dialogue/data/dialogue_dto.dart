import 'package:ingrain/features/dialogue/domain/dialogue.dart';

class DialogueDto {
  final Map<String, dynamic> map;

  DialogueDto.fromMap(Map<String, dynamic> data) : map = Map.from(data);

  Dialogue toDomain() {
    final source = map['source'] is Map
        ? Map<String, dynamic>.from(map['source'] as Map)
        : <String, dynamic>{};
    final lines = (map['lines'] as List? ?? const [])
        .map((value) => _lineFromMap(Map<String, dynamic>.from(value as Map)))
        .toList();

    return Dialogue(
      id: map['id'] as String,
      title: map['title'] as String,
      level: map['level'] as String? ?? 'Unknown',
      kind: _kind(map['kind'] as String?),
      speakers: _strings(map['speakers']),
      source: DialogueSource(
        attribution: (map['attribution'] ?? source['attribution']) as String?,
        url: (map['sourceUrl'] ?? source['url']) as String?,
      ),
      updatedAt: _date(map['updatedAt']),
      book: _book(map),
      lines: lines,
    );
  }

  static DialogueSummary summaryFromMap(Map<String, dynamic> map) {
    final source = map['source'] is Map
        ? Map<String, dynamic>.from(map['source'] as Map)
        : <String, dynamic>{};
    return DialogueSummary(
      id: map['id'] as String,
      title: map['title'] as String,
      level: map['level'] as String? ?? 'Unknown',
      kind: _kind(map['kind'] as String?),
      speakers: _strings(map['speakers']),
      lineCount: (map['lineCount'] as num?)?.toInt() ?? 0,
      source: DialogueSource(
        attribution: (map['attribution'] ?? source['attribution']) as String?,
        url: (map['sourceUrl'] ?? source['url']) as String?,
      ),
      updatedAt: _date(map['updatedAt']),
      book: _book(map),
    );
  }

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(map);

  static DialogueLine _lineFromMap(Map<String, dynamic> map) {
    final tokens = (map['tokens'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .map(
          (token) => DialogueToken(
            surface: token['surface'] as String? ?? '',
            reading: token['reading'] as String?,
            romaji: token['romaji'] as String?,
          ),
        )
        .toList();
    return DialogueLine(
      index: (map['index'] as num?)?.toInt() ?? 0,
      speaker: map['speaker'] as String?,
      tokens: tokens,
      romaji: _text(map['romaji']),
      translation: _text(map['translation']),
    );
  }

  static BookInfo? _book(Map<String, dynamic> map) {
    final author = _text(map['author']);
    if (author == null) return null;
    return BookInfo(
      author: author,
      originalTitle: _text(map['originalTitle']),
      originalYear: (map['originalYear'] as num?)?.toInt(),
      summary: _text(map['description']),
    );
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static DialogueKind _kind(String? value) => DialogueKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => DialogueKind.dialogue,
  );
}

class DialogueSummaryDto {
  final Map<String, dynamic> map;

  DialogueSummaryDto(DialogueSummary summary)
    : map = {
        'id': summary.id,
        'title': summary.title,
        'level': summary.level,
        'kind': summary.kind.name,
        'speakers': summary.speakers,
        'lineCount': summary.lineCount,
        'attribution': summary.source.attribution,
        'sourceUrl': summary.source.url,
        if (summary.updatedAt != null)
          'updatedAt': summary.updatedAt!.toIso8601String(),
        if (summary.book case final book?) ..._bookToMap(book),
      };

  DialogueSummaryDto.fromMap(Map<String, dynamic> data) : map = Map.from(data);

  DialogueSummary toDomain() => DialogueDto.summaryFromMap(map);
}

Map<String, dynamic> dialogueToMap(Dialogue dialogue) => {
  'id': dialogue.id,
  'title': dialogue.title,
  'level': dialogue.level,
  'kind': dialogue.kind.name,
  'speakers': dialogue.speakers,
  'lineCount': dialogue.lineCount,
  'attribution': dialogue.source.attribution,
  'sourceUrl': dialogue.source.url,
  if (dialogue.updatedAt != null)
    'updatedAt': dialogue.updatedAt!.toIso8601String(),
  if (dialogue.book case final book?) ..._bookToMap(book),
  'lines': [
    for (final line in dialogue.lines)
      {
        'index': line.index,
        'speaker': line.speaker,
        if (line.romaji != null) 'romaji': line.romaji,
        if (line.translation != null) 'translation': line.translation,
        'tokens': [
          for (final token in line.tokens)
            {
              'surface': token.surface,
              'reading': token.reading,
              'romaji': token.romaji,
            },
        ],
      },
  ],
};

Map<String, dynamic> _bookToMap(BookInfo book) => {
  'author': book.author,
  if (book.originalTitle != null) 'originalTitle': book.originalTitle,
  if (book.originalYear != null) 'originalYear': book.originalYear,
  if (book.summary != null) 'description': book.summary,
};
