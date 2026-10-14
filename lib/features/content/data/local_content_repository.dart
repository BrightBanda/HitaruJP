import 'package:flutter/foundation.dart';
import 'package:ingrain/core/storage/document_store.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';
import 'package:ingrain/features/content/data/content_item_dto.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/domain/content_repository.dart';
import 'package:ingrain/features/content/domain/transcript_sentence.dart';
import 'package:ingrain/features/content/data/youtube_url_parser.dart';

class LocalContentRepository implements ContentRepository {
  final DocumentStore _store;
  final AuthRepository _auth;

  LocalContentRepository(this._store, this._auth);

  static const String collection = 'contentHistory';

  @override
  Future<ContentItem> getContent(String id) async {
    final uid = await _auth.ensureUid();
    final doc = await _store.getDoc(uid, collection, id);
    if (doc.isEmpty) {
      throw Exception('Content not found: $id');
    }
    return ContentItemDto.fromMap(doc).toDomain();
  }

  @override
  Stream<List<ContentItem>> watchAll() async* {
    final uid = await _auth.ensureUid();
    final docs = await _store.listDocs(uid, collection);
    yield docs
        .where(isContentDocument)
        .map((d) => ContentItemDto.fromMap(d).toDomain())
        .toList();
  }

  /// `contentHistory` also holds the `<contentId>__transcript` siblings, and
  /// `listDocs` returns data without ids. A transcript document has no `id`
  /// field, so that is what tells the two shapes apart.
  @visibleForTesting
  static bool isContentDocument(Map<String, dynamic> doc) =>
      doc['id'] is String && !doc.containsKey('sentences');

  @override
  Future<void> save(ContentItem item) async {
    final uid = await _auth.ensureUid();
    await _store.setDoc(
      uid,
      collection,
      item.id,
      ContentItemDto(
        id: item.id,
        sourceType: item.sourceType,
        sourceUrl: item.sourceUrl,
        title: item.title,
        channelTitle: item.channelTitle,
        thumbnailUrl: item.thumbnailUrl,
        lastPositionSeconds: item.lastPositionSeconds,
        totalImmersionSeconds: item.totalImmersionSeconds,
        lastOpenedAt: item.lastOpenedAt,
        durationSeconds: item.durationSeconds,
      ).map,
    );
  }

  @override
  Future<ContentItem> create({
    required String sourceUrl,
    required String title,
    String? channelTitle,
    String? thumbnailUrl,
    SourceType sourceType = SourceType.youtube,
  }) async {
    final id = sourceType == SourceType.youtube
        ? _extractVideoId(sourceUrl)
        : _generateId();
    final item = ContentItem(
      id: id,
      sourceType: sourceType,
      sourceUrl: sourceUrl,
      title: title,
      channelTitle: channelTitle,
      thumbnailUrl: thumbnailUrl,
      lastOpenedAt: DateTime.now(),
    );
    await save(item);
    return item;
  }

  @override
  Future<void> updateLastPosition(String id, int seconds) async {
    final uid = await _auth.ensureUid();
    final existing = await _store.getDoc(uid, collection, id);
    existing['lastPositionSeconds'] = seconds;
    existing['lastOpenedAt'] = DateTime.now().toIso8601String();
    await _store.setDoc(uid, collection, id, existing);
  }

  @override
  Future<void> delete(String id) async {
    final uid = await _auth.ensureUid();
    // The transcript is a sibling document; leaving it would orphan it.
    await _store.deleteDocs(uid, collection, [id, transcriptDocId(id)]);
  }

  @override
  Future<List<TranscriptSentence>> getTranscript(String contentId) async {
    final uid = await _auth.ensureUid();
    final doc = await _store.getDoc(
      uid,
      collection,
      transcriptDocId(contentId),
    );
    final data = doc['sentences'];
    if (data == null || data is! List) return [];
    return data.asMap().entries.map((entry) {
      final m = Map<String, dynamic>.from(entry.value as Map);
      return TranscriptSentence(
        index: entry.key,
        text: m['text'] as String,
        startSeconds: (m['startSeconds'] as num).toInt(),
        endSeconds: (m['endSeconds'] as num).toInt(),
      );
    }).toList();
  }

  @override
  Future<void> saveTranscript(
    String contentId,
    List<TranscriptSentence> sentences,
  ) async {
    final uid = await _auth.ensureUid();
    final data = sentences
        .map(
          (s) => {
            'index': s.index,
            'text': s.text,
            'startSeconds': s.startSeconds,
            'endSeconds': s.endSeconds,
          },
        )
        .toList();
    await _store.setDoc(uid, collection, transcriptDocId(contentId), {
      'sentences': data,
    });
  }

  /// Firestore cannot address a subcollection by embedding a `/` in a collection
  /// name, so a content item's transcript is a sibling document in `contentHistory`
  /// keyed by a composite id. Keeps `contentHistory` one flat, listable collection.
  @visibleForTesting
  static String transcriptDocId(String contentId) => '${contentId}__transcript';

  static String _extractVideoId(String url) {
    final parsed = YoutubeUrlParser.tryParse(url);
    if (parsed != null) return parsed;
    return _generateId();
  }

  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  }
}
