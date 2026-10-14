/// The document storage contract every user-data repository is written against.
///
/// Deliberately narrow: these four methods are the only ones the repositories call
/// (verified across vocabulary, settings, sentence, content, review and immersion).
/// Firestore forbids `/` in collection and document ids, so any implementation that
/// needs a hierarchy must flatten it into the id — see
/// `LocalContentRepository`'s `<contentId>__transcript` documents.
abstract interface class DocumentStore {
  /// Returns `{}` — never null, and never throws — when the document is absent.
  Future<Map<String, dynamic>> getDoc(
    String uid,
    String collection,
    String docId,
  );

  Future<void> setDoc(
    String uid,
    String collection,
    String docId,
    Map<String, dynamic> data, {
    bool merge = false,
  });

  Future<void> deleteDoc(String uid, String collection, String docId);

  /// Deletes many documents of one collection at once.
  Future<void> deleteDocs(String uid, String collection, List<String> docIds);

  /// Writes many documents of one collection at once, replacing each.
  ///
  /// For bulk work such as a deck import: thousands of single writes would
  /// each wait for their own round trip.
  Future<void> setDocs(
    String uid,
    String collection,
    Map<String, Map<String, dynamic>> docs,
  );

  /// Documents in [collection], in unspecified order.
  Future<List<Map<String, dynamic>>> listDocs(String uid, String collection);
}
