import 'dart:convert';

import 'package:ingrain/core/storage/document_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed [DocumentStore], plus the dialogue cache's extras.
///
/// This is no longer the store behind user data — that is `FirestoreDocumentStore`.
/// It remains the offline cache for the dialogue catalogue, which needs
/// `registerCollection` and the nested `dialogues/<id>` key shape.
class LocalDocumentStore implements DocumentStore {
  final SharedPreferences _prefs;

  LocalDocumentStore(this._prefs);

  static const _prefix = 'local_store_';
  static const _usersKey = '${_prefix}users';

  /// Key prefix for the pre-Firebase local store, cleared on first launch.
  static const legacyKeyPrefix = _prefix;

  String _collectionKey(String uid, String collection) =>
      '$_prefix$uid/$collection';

  Future<Map<String, dynamic>> _loadCollection(
    String uid,
    String collection,
  ) async {
    final raw = _prefs.getString(_collectionKey(uid, collection));
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCollection(
    String uid,
    String collection,
    Map<String, dynamic> data,
  ) async {
    final raw = jsonEncode(data);
    await _prefs.setString(_collectionKey(uid, collection), raw);
  }

  @override
  Future<Map<String, dynamic>> getDoc(
    String uid,
    String collection,
    String docId,
  ) async {
    final coll = await _loadCollection(uid, collection);
    return Map<String, dynamic>.from(
      (coll[docId] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }

  @override
  Future<void> setDoc(
    String uid,
    String collection,
    String docId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    final coll = await _loadCollection(uid, collection);
    if (merge && coll.containsKey(docId)) {
      final existing = Map<String, dynamic>.from(
        (coll[docId] as Map).cast<String, dynamic>(),
      );
      existing.addAll(data);
      coll[docId] = existing;
    } else {
      coll[docId] = data;
    }
    await _saveCollection(uid, collection, coll);
  }

  @override
  Future<void> setDocs(
    String uid,
    String collection,
    Map<String, Map<String, dynamic>> docs,
  ) async {
    final coll = await _loadCollection(uid, collection);
    coll.addAll(docs);
    await _saveCollection(uid, collection, coll);
  }

  @override
  Future<void> deleteDocs(
    String uid,
    String collection,
    List<String> docIds,
  ) async {
    final coll = await _loadCollection(uid, collection);
    docIds.forEach(coll.remove);
    await _saveCollection(uid, collection, coll);
  }

  @override
  Future<void> deleteDoc(String uid, String collection, String docId) async {
    final coll = await _loadCollection(uid, collection);
    coll.remove(docId);
    await _saveCollection(uid, collection, coll);
  }

  @override
  Future<List<Map<String, dynamic>>> listDocs(
    String uid,
    String collection, {
    String? withField,
  }) async {
    final coll = await _loadCollection(uid, collection);
    return coll.values
        .map(
          (v) => Map<String, dynamic>.from((v as Map).cast<String, dynamic>()),
        )
        .where((doc) => withField == null || doc[withField] != null)
        .toList();
  }

  Future<void> deleteCollection(String uid, String collection) async {
    await _prefs.remove(_collectionKey(uid, collection));
  }

  Future<Map<String, dynamic>> _loadUserMap() async {
    final raw = _prefs.getString(_usersKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Only `LocalDialogueCache` needs this, and only because it writes under
  /// `dialogues/<id>` — a shape Firestore cannot represent. The dialogue cache
  /// stays on this store, so the method does too.
  Future<void> registerCollection(String uid, String collection) async {
    final userMap = await _loadUserMap();
    final existing = Map<String, dynamic>.from(
      (userMap[uid] as Map?)?.cast<String, dynamic>() ?? {},
    );
    existing[collection] = true;
    userMap[uid] = existing;
    await _prefs.setString(_usersKey, jsonEncode(userMap));
  }
}
