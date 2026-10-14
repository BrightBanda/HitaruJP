import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/dialogue/data/local_dialogue_cache.dart';
import 'package:ingrain/features/dialogue/data/remote_dialogue_repository.dart';
import 'package:ingrain/features/dialogue/data/sample_dialogue_loader.dart';
import 'package:ingrain/features/dialogue/data/user_dialogue_repository.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/domain/dialogue_repository.dart';

final dialogueRepositoryProvider = Provider<DialogueRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return RemoteDialogueRepository(
    client: client,
    cache: LocalDialogueCache(
      ref.watch(localDocumentStoreProvider),
      ref.watch(authRepositoryProvider),
    ),
    samples: SampleDialogueLoader(),
  );
});

final userDialogueRepositoryProvider = Provider<UserDialogueRepository>((ref) {
  return UserDialogueRepository(
    ref.watch(documentStoreProvider),
    ref.watch(authRepositoryProvider),
  );
});

final dialogueListViewModelProvider =
    AsyncNotifierProvider<DialogueListViewModel, List<DialogueSummary>>(
      DialogueListViewModel.new,
    );

/// The user's own dialogues first, then the catalogue.
class DialogueListViewModel extends AsyncNotifier<List<DialogueSummary>> {
  late DialogueRepository _repository;
  late UserDialogueRepository _userRepository;

  @override
  Future<List<DialogueSummary>> build() {
    _repository = ref.watch(dialogueRepositoryProvider);
    _userRepository = ref.watch(userDialogueRepositoryProvider);
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// Renames one of the learner's own dialogues.
  Future<void> rename(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final dialogue = await _userRepository.get(id);
    if (dialogue == null) return;
    await _userRepository.save(
      Dialogue(
        id: dialogue.id,
        title: trimmed,
        level: dialogue.level,
        kind: dialogue.kind,
        speakers: dialogue.speakers,
        source: dialogue.source,
        updatedAt: dialogue.updatedAt,
        lines: dialogue.lines,
      ),
    );
    ref.invalidate(dialogueReaderViewModelProvider(id));
    await refresh();
  }

  /// Deletes the learner's own dialogues; catalogue ids are ignored.
  Future<void> deleteMany(Iterable<String> ids) async {
    for (final id in ids.where(UserDialogueRepository.isUserDialogueId)) {
      await _userRepository.delete(id);
      ref.invalidate(dialogueReaderViewModelProvider(id));
    }
    await refresh();
  }

  /// An unreachable catalogue only fails the list when the user has nothing of
  /// their own to show either.
  Future<List<DialogueSummary>> _load() async {
    List<DialogueSummary> own;
    try {
      own = await _userRepository.listAll();
    } catch (_) {
      own = const [];
    }
    try {
      return [...own, ...await _repository.listSummaries()];
    } catch (_) {
      if (own.isEmpty) rethrow;
      return own;
    }
  }
}

final dialogueReaderViewModelProvider =
    AsyncNotifierProvider.family<DialogueReaderViewModel, Dialogue, String>(
      (dialogueId) => DialogueReaderViewModel(dialogueId),
    );

class DialogueReaderViewModel extends AsyncNotifier<Dialogue> {
  final String dialogueId;

  DialogueReaderViewModel(this.dialogueId);

  late DialogueRepository _repository;
  late UserDialogueRepository _userRepository;

  @override
  Future<Dialogue> build() {
    _repository = ref.watch(dialogueRepositoryProvider);
    _userRepository = ref.watch(userDialogueRepositoryProvider);
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<Dialogue> _load() async {
    if (UserDialogueRepository.isUserDialogueId(dialogueId)) {
      final own = await _userRepository.get(dialogueId);
      if (own != null) return own;
    }
    return _repository.getDialogue(dialogueId);
  }
}
