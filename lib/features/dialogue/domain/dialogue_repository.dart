import 'package:ingrain/features/dialogue/domain/dialogue.dart';

abstract interface class DialogueRepository {
  bool get isShowingCachedCopy;

  Future<List<DialogueSummary>> listSummaries();

  /// What [listSummaries] can show without the network (the device's cached
  /// copy and the bundled samples), for painting the list at once.
  Future<List<DialogueSummary>> listCachedSummaries();

  Future<Dialogue> getDialogue(String id);

  Future<Dialogue?> getCachedDialogue(String id);

  Future<void> cacheDialogue(Dialogue dialogue);
}
