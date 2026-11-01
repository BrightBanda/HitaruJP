import 'package:ingrain/core/storage/document_store.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';
import 'package:ingrain/features/playlists/domain/playlist.dart';

/// Playlists at `users/{uid}/playlists/{id}`, one document each.
class PlaylistRepository {
  final DocumentStore _store;
  final AuthRepository _auth;

  PlaylistRepository(this._store, this._auth);

  static const collection = 'playlists';

  /// Oldest first, so a new playlist lands at the bottom of the list.
  Future<List<Playlist>> listAll() async {
    final uid = await _auth.ensureUid();
    final docs = await _store.listDocs(uid, collection);
    return docs.map(Playlist.fromMap).whereType<Playlist>().toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> save(Playlist playlist) async {
    final uid = await _auth.ensureUid();
    await _store.setDoc(uid, collection, playlist.id, playlist.toMap());
  }

  Future<void> delete(String id) async {
    final uid = await _auth.ensureUid();
    await _store.deleteDoc(uid, collection, id);
  }
}
