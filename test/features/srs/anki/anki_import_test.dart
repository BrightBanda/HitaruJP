import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/storage/local_document_store.dart';
import 'package:ingrain/features/srs/data/anki/anki_importer.dart';
import 'package:ingrain/features/srs/data/local_review_repository.dart';
import 'package:ingrain/features/srs/data/srs_settings_repository.dart';
import 'package:ingrain/features/srs/domain/review_card.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/anki_import_view_model.dart';
import 'package:ingrain/features/srs/presentation/viewmodel/review_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/anki_fixture.dart';
import '../../../support/test_overrides.dart';

void main() {
  late Directory dir;
  late ProviderContainer container;
  late String apkg;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('anki-import');
    apkg = buildApkg(dir, 'deck.apkg', {
      'collection.anki2': legacyCollection('${dir.path}/c.db'),
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalDocumentStore(prefs);
    container = ProviderContainer(
      overrides: [
        ...appTestOverrides(prefs),
        importTempDirectoryProvider.overrideWith((ref) async => dir.path),
        srsSettingsRepositoryProvider.overrideWithValue(
          SrsSettingsRepository(store, FakeAuthRepository()),
        ),
      ],
    );
    // Keep the auto-disposing import view model alive across awaits.
    container.listen(ankiImportViewModelProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  AnkiImportViewModel vm() =>
      container.read(ankiImportViewModelProvider.notifier);
  AnkiImportState state() => container.read(ankiImportViewModelProvider);

  test('reads, asks, then saves decks and cards with their progress', () async {
    final progress = <AnkiImportProgress>[];
    container.listen(ankiImportViewModelProvider, (_, next) {
      if (next is AnkiImportSaving) progress.add(next.progress);
    });

    await vm().read(apkg);
    final ready = state();
    expect(ready, isA<AnkiImportReady>());
    expect((ready as AnkiImportReady).plan.cardCount, 4);

    await vm().confirm();
    final done = state();
    expect(done, isA<AnkiImportDone>());
    expect((done as AnkiImportDone).result.cards, 4);
    expect(done.result.skipped, 1);
    expect(progress.last.saved, 4);
    expect(progress.last.fraction, 1.0);

    final decks = await container.read(deckRepositoryProvider).listDecks();
    expect(decks.map((d) => d.name), contains('Japanese › Core'));

    final cards = await container.read(reviewRepositoryProvider).listAllCards();
    expect(cards, hasLength(4));
    final mature = cards.firstWhere((c) => c.id == 'anki-10');
    expect(mature.uid, isNotEmpty);
    expect(
      (mature.state, mature.intervalDays, mature.easeFactor),
      (CardState.review, 10, 2.3),
    );
    expect(cards.where((c) => c.suspended), hasLength(1));
  });

  test(
    'importing the same deck again updates instead of duplicating',
    () async {
      for (var i = 0; i < 2; i++) {
        await vm().read(apkg);
        await vm().confirm();
      }

      final cards = await container
          .read(reviewRepositoryProvider)
          .listAllCards();
      final decks = await container.read(deckRepositoryProvider).listDecks();
      expect(cards, hasLength(4));
      expect(decks.where((d) => d.name == 'Japanese › Core'), hasLength(1));
    },
  );

  test('a broken file ends in a clear failure', () async {
    final broken = File('${dir.path}/broken.apkg')..writeAsStringSync('nope');

    await vm().read(broken.path);

    expect(state(), isA<AnkiImportFailed>());
    expect((state() as AnkiImportFailed).message, contains('.apkg'));
  });

  test('bulk saves report progress chunk by chunk', () async {
    final repository =
        container.read(reviewRepositoryProvider) as LocalReviewRepository;
    final now = DateTime(2026);
    final many = [
      for (var i = 0; i < LocalReviewRepository.saveChunkSize + 20; i++)
        ReviewCard(
          id: 'bulk-$i',
          uid: 'test-uid',
          cardType: CardType.basic,
          sourceItemId: 'bulk-$i',
          promptText: '$i',
          createdAt: now,
          dueAt: now,
        ),
    ];
    final reported = <int>[];

    await repository.saveCards(many, onProgress: reported.add);

    expect(reported, [LocalReviewRepository.saveChunkSize, many.length]);
    expect(await repository.listAllCards(), hasLength(many.length));
  });
}
