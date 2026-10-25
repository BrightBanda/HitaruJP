import 'package:ingrain/core/storage/document_store.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';

/// The most XP each learner has ever been shown, kept in their account.
///
/// XP is worked out from history, and history can shrink (a deleted word, a
/// removed session); this floor makes sure the companion never does. It also
/// carries the level and stage to other devices before their history loads.
class GrowthRepository {
  final DocumentStore _store;
  final AuthRepository _auth;

  GrowthRepository(this._store, this._auth);

  static const collection = 'growth';
  static const docId = 'self';

  Future<int> bestXp() async {
    final uid = await _auth.ensureUid();
    final doc = await _store.getDoc(uid, collection, docId);
    return (doc['xp'] as num?)?.toInt() ?? 0;
  }

  Future<void> recordBest(Growth growth) async {
    final uid = await _auth.ensureUid();
    await _store.setDoc(uid, collection, docId, {
      'xp': growth.xp,
      'level': growth.level,
      'stage': growth.stage.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }, merge: true);
  }
}
