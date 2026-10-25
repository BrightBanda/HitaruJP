import 'package:flutter/material.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/router.dart';
import 'package:ingrain/features/auth/domain/auth_state.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/content/data/youtube_transcript_fetcher.dart';
import 'package:ingrain/features/content/domain/video_search.dart';
import 'package:ingrain/features/content/presentation/view/youtube_search_results.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/dialogue/data/user_dialogue_repository.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/domain/dialogue_repository.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:ingrain/shared/widgets/double_back_to_exit.dart';

import '../support/test_overrides.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// Skips the onboarding bootstrap so the router settles straight on the shell.
class OnboardedAuthViewModel extends AuthViewModel {
  @override
  AuthState build() =>
      const AuthState.ready(uid: 'uid-1', displayName: 'Tester');
}

class NavigationDialogueRepository implements DialogueRepository {
  final dialogue = Dialogue(
    id: 'lesson-1',
    title: 'At the station',
    level: 'N5',
    lines: [
      DialogueLine(
        index: 0,
        tokens: [DialogueToken(surface: '駅', reading: 'えき', romaji: 'eki')],
      ),
    ],
  );

  final book = Dialogue(
    id: 'book-1',
    title: 'Night at the Inn',
    level: 'N4',
    kind: DialogueKind.book,
    source: const DialogueSource(
      attribution: 'Adapted from a public-domain essay.',
      url: 'https://example.org/original',
    ),
    book: const BookInfo(
      author: '中谷宇吉郎',
      originalYear: 1946,
      summary: 'A traveller finds a room on a snowy night.',
    ),
    lines: const [
      DialogueLine(
        index: 0,
        tokens: [DialogueToken(surface: '雪', reading: 'ゆき')],
        translation: 'It was snowing.',
      ),
    ],
  );

  @override
  bool isShowingCachedCopy = false;

  @override
  Future<List<DialogueSummary>> listSummaries() async => [dialogue, book];

  @override
  Future<List<DialogueSummary>> listCachedSummaries() => listSummaries();

  @override
  Future<Dialogue> getDialogue(String id) async =>
      id == book.id ? book : dialogue;

  @override
  Future<Dialogue?> getCachedDialogue(String id) async => getDialogue(id);

  @override
  Future<void> cacheDialogue(Dialogue dialogue) async {}
}

class FakeVideoSearch implements VideoSearchRepository {
  static const video = VideoSearchResult(
    videoId: 'tokyoVlog01',
    title: '東京 vlog',
    channelTitle: 'Yuka',
    thumbnailUrl: 'https://i.ytimg.com/vi/tokyoVlog01/mqdefault.jpg',
    duration: Duration(minutes: 3),
  );

  /// Seven results: one page of five plus two behind "Show more".
  @override
  Future<List<VideoSearchResult>> search(String query) async => [
    video,
    for (var i = 2; i <= 7; i++)
      VideoSearchResult(
        videoId: 'otherVideo$i',
        title: 'Other video $i',
        thumbnailUrl: 'https://i.ytimg.com/vi/otherVideo$i/mqdefault.jpg',
      ),
  ];

  @override
  Future<VideoSearchResult?> lookup(String videoId) async => null;
}

class FakeTranscriptFetcher extends YoutubeTranscriptFetcher {
  @override
  Future<YoutubeTranscriptResult> fetch(String videoId) async =>
      const YoutubeTranscriptResult(
        durationSeconds: 180,
        transcriptText: '00:00:01,000 --> 00:00:03,000\nこんにちは',
      );
}

void main() {
  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Iterable<MethodCall> exitCalls() =>
      platformCalls.where((call) => call.method == 'SystemNavigator.pop');

  /// Mirrors the Android back button reaching the running app.
  Future<void> pressSystemBack(WidgetTester tester) async {
    final message = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('popRoute'),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      message,
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    List extraOverrides = const [],
    FakeCatalogRepository? catalog,
    Map<String, Object> storedPrefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(storedPrefs);
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        ...appTestOverrides(prefs, catalog: catalog),
        authViewModelProvider.overrideWith(OnboardedAuthViewModel.new),
        dialogueRepositoryProvider.overrideWithValue(
          NavigationDialogueRepository(),
        ),
        // The real asset is decoded on a background isolate, which never
        // completes under the widget tester's fake async.
        ...extraOverrides,
        dictionaryProvider.overrideWith(
          (ref) async => DictionaryIndex(const [
            DictionaryEntry(
              surface: 'おはよう',
              reading: 'おはよう',
              meanings: ['good morning'],
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: container.read(appRouterProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder learnMenuItem(String label) =>
      find.widgetWithText(PopupMenuItem<LearnDestination>, label);

  Future<void> openLearn(WidgetTester tester, String destination) async {
    await tapTab(tester, 'Learn');
    await tester.tap(learnMenuItem(destination));
    await tester.pumpAndSettle();
  }

  Future<void> openLibrary(WidgetTester tester) async {
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
  }

  group('home', () {
    testWidgets('a learner fresh from the first lesson gets a home tour', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        storedPrefs: {FirstRunViewModel.tipsKey('uid-1'): true},
      );
      // The tour waits a moment for the page to settle.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Your daily goal'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Today’s picks'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Your library'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        find.text('コーヒー is already waiting for you here!'),
        findsOneWidget,
      );
      await tester.tap(find.text('Got it!'));
      await tester.pumpAndSettle();

      expect(find.text('Your library'), findsNothing);
      expect(container.read(firstRunProvider).homeTipsPending, isFalse);
    });

    testWidgets('no tour for a learner who has not just onboarded', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Your daily goal'), findsNothing);
    });

    testWidgets('shows start, recommendations and no back button', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.text('HitaruJP'), findsOneWidget);
      expect(find.text('Start immersing'), findsOneWidget);
      expect(find.text("Today's goal"), findsOneWidget);
      expect(find.text('Flashcards'), findsWidgets);
      expect(find.text('YouTube video'), findsNothing);
      expect(find.byType(BackButton), findsNothing);

      // Today's picks come from the (fake) catalogue, not the user's library.
      expect(find.text("Today's picks"), findsOneWidget);
      expect(find.text('Nihongo con Teppei #1'), findsOneWidget);
      expect(find.text('For your interests'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('At the station'), 200);
      expect(find.text('Japanese in the park'), findsOneWidget);
      expect(find.text('Curry, in easy Japanese'), findsOneWidget);
      expect(find.text('Add your first YouTube video'), findsNothing);
      expect(find.text('Dialogue of the day'), findsOneWidget);
    });

    testWidgets('falls back to the library prompt when picks cannot load', (
      tester,
    ) async {
      final offline = FakeCatalogRepository()..error = StateError('offline');
      await pumpApp(tester, catalog: offline);

      expect(find.text("Today's picks"), findsOneWidget);
      expect(find.text('Add your first YouTube video'), findsOneWidget);
    });

    testWidgets('does not overflow on a phone viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpApp(tester);
      await openLibrary(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('start immersing opens the dialogue when there is no video', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.text('Read · At the station'), findsOneWidget);
      await tester.tap(find.text('Start immersing'));
      await tester.pumpAndSettle();

      expect(find.text('駅'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  group('bottom navigation', () {
    testWidgets('Learn opens a menu above the bar with Vocab and Kana', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapTab(tester, 'Learn');
      expect(learnMenuItem('Vocab'), findsOneWidget);
      expect(learnMenuItem('Kana'), findsOneWidget);
      final menuBottom = tester.getBottomLeft(learnMenuItem('Kana')).dy;
      final barTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(menuBottom, lessThan(barTop));

      await tester.tap(learnMenuItem('Kana'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Kana'), findsOneWidget);
      expect(find.text('あ'), findsOneWidget);
      expect(find.text('shi'), findsWidgets);

      await tester.tap(find.textContaining('Katakana'));
      await tester.pumpAndSettle();
      expect(find.text('ア'), findsOneWidget);

      await openLearn(tester, 'Vocab');
      expect(find.widgetWithText(AppBar, 'Vocabulary'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('Profile shows progress and settings tabs', (tester) async {
      await pumpApp(tester);

      await tapTab(tester, 'Profile');
      expect(find.text('Tester'), findsOneWidget);
      // The character hero sits above the tabs; the dashboard is below it.
      await tester.scrollUntilVisible(
        find.text('Today'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Today'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Daily goal'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Daily goal'), findsOneWidget);
    });

    testWidgets('Flashcards: built-in deck, new deck, add a card, study it', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapTab(tester, 'Flashcards');
      expect(find.text('Mined phrases'), findsOneWidget);

      expect(find.byTooltip('Import Anki deck'), findsOneWidget);

      await tester.tap(find.byTooltip('Flashcard settings'));
      await tester.pumpAndSettle();
      expect(find.text('New cards per day'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New deck'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Deck name'),
        'Verbs',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Verbs'), findsOneWidget);

      await tester.tap(find.text('Verbs'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Verbs'), findsOneWidget);

      await tester.tap(find.text('Add card'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Front'), '食べる');
      await tester.enterText(
        find.widgetWithText(TextField, 'Back (optional)'),
        'to eat',
      );
      await tester.tap(find.text('Save card'));
      await tester.pumpAndSettle();
      expect(find.text('食べる'), findsOneWidget);

      await tester.tap(find.text('Study 1 now'));
      await tester.pumpAndSettle();
      expect(find.text('食べる'), findsOneWidget);
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Easy'));
      await tester.pumpAndSettle();
      expect(find.text('Session complete'), findsOneWidget);
    });
  });

  testWidgets('every tab and study page fits a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);
    for (final tab in ['Library', 'Flashcards', 'Profile']) {
      await tapTab(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }

    for (final destination in LearnDestination.values) {
      await openLearn(tester, destination.label);
      expect(tester.takeException(), isNull, reason: destination.label);
    }

    for (final route in [
      '/dialogues/lesson-1',
      '/flashcards/deck/mined-phrases',
    ]) {
      GoRouter.of(tester.element(find.byType(NavigationBar))).push(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: route);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
  });

  group('youtube search', () {
    testWidgets('search finds videos that can be added, then edited', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        extraOverrides: [
          videoSearchRepositoryProvider.overrideWithValue(FakeVideoSearch()),
          youtubeTranscriptFetcherProvider.overrideWithValue(
            FakeTranscriptFetcher(),
          ),
        ],
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YouTube video'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'vlog');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('東京 vlog'), findsOneWidget);
      expect(find.text('Watch'), findsNWidgets(5));
      expect(find.text('Other video 6'), findsNothing);

      final page = find
          .ancestor(
            of: find.byType(YoutubeSearchResults),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Show more (2 left)'),
        300,
        scrollable: page,
      );
      await tester.tap(find.text('Show more (2 left)'));
      await tester.pumpAndSettle();
      expect(find.text('Watch'), findsNWidgets(7));
      expect(find.textContaining('Show more'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('東京 vlog'),
        -300,
        scrollable: page,
      );

      await tester.tap(find.text('Add to library').first);
      await tester.pumpAndSettle();
      expect(find.text('In library'), findsOneWidget);
      final library = container.read(contentViewModelProvider).value!;
      expect(library.single.title, '東京 vlog');

      // Let the confirmation snack bar go before moving on.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      GoRouter.of(tester.element(find.byType(Scaffold).last))
          .push('/content/${library.single.id}/transcript');
      await tester.pumpAndSettle();
      expect(find.text('Lines (1)'), findsOneWidget);
      expect(find.text('こんにちは'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  testWidgets('reading a dialogue is recorded as immersion', (tester) async {
    final container = await pumpApp(tester);
    await openLibrary(tester);
    await tester.tap(find.text('Dialogues and stories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('At the station'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final sessions = await container
        .read(immersionRepositoryProvider)
        .watchRecentSessions()
        .first;
    expect(sessions.single.activityType, ActivityType.reading);
    expect(sessions.single.sourceTitle, 'At the station');
    expect(sessions.single.endedAt, isNotNull);
  });

  group('add content', () {
    testWidgets('the home Add dropdown lists the types you can add', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('YouTube video'), findsOneWidget);
      expect(find.text('Dialogue'), findsOneWidget);
      expect(find.text('Podcast'), findsNothing);
      expect(find.text('Soon'), findsNothing);

      await tester.tap(find.text('YouTube video'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add Content'), findsOneWidget);
      expect(find.text('Search YouTube or paste a link'), findsOneWidget);
    });

    testWidgets('a pasted dialogue is saved and opens in the reader', (
      tester,
    ) async {
      final container = await pumpApp(tester);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dialogue'));
      await tester.pumpAndSettle();

      expect(find.text('Search YouTube or paste a link'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'My morning',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Japanese text'),
        'Aiko: おはよう\nKen: こんにちは',
      );
      await tester.ensureVisible(find.text('Save dialogue'));
      await tester.tap(find.text('Save dialogue'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'My morning'), findsOneWidget);
      expect(find.text('Aiko'), findsWidgets);

      final listed = await container.read(dialogueListViewModelProvider.future);
      expect(listed.first.title, 'My morning');
      expect(listed.map((d) => d.title), contains('At the station'));
    });
  });

  group('library', () {
    testWidgets('category cards switch between videos, books, dialogues', (
      tester,
    ) async {
      await pumpApp(tester);
      await openLibrary(tester);

      expect(find.text('YouTube video'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('Dialogues and stories'), findsOneWidget);
      expect(find.text('Your library is empty'), findsOneWidget);

      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      expect(find.text('Night at the Inn'), findsOneWidget);
      expect(find.text('At the station'), findsNothing);

      // A book opens on its details, with the story below them.
      await tester.tap(find.text('Night at the Inn'));
      await tester.pumpAndSettle();
      expect(find.text('中谷宇吉郎  ·  1946'), findsOneWidget);
      expect(
        find.text('A traveller finds a room on a snowy night.'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('中谷宇吉郎  ·  1946')).dy,
        lessThan(tester.getTopLeft(find.text('雪')).dy),
      );
      expect(
        find.widgetWithText(TextButton, 'View the original'),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dialogues and stories'));
      await tester.pumpAndSettle();
      expect(find.text('At the station'), findsOneWidget);
      expect(find.text('Night at the Inn'), findsNothing);

      await tester.tap(find.text('At the station'));
      await tester.pumpAndSettle();
      expect(find.text('駅'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('long press enters edit mode to select, rename and delete', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      final repository = container.read(contentRepositoryProvider);
      await repository.create(
        sourceUrl: 'https://www.youtube.com/watch?v=aaaaaaaaaa1',
        title: 'First video',
      );
      await repository.create(
        sourceUrl: 'https://www.youtube.com/watch?v=bbbbbbbbbb2',
        title: 'Second video',
      );
      container.invalidate(contentViewModelProvider);
      await openLibrary(tester);
      expect(find.text('First video'), findsOneWidget);

      await tester.longPress(find.text('First video'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      // Back leaves edit mode without the exit warning.
      await pressSystemBack(tester);
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
      expect(find.text(DoubleBackToExit.message), findsNothing);

      await tester.longPress(find.text('First video'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      // Renaming needs exactly one video.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.edit_outlined),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Second video'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Renamed video');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed video'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);

      await tester.longPress(find.text('Renamed video'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed video'), findsNothing);
      expect(find.text('Second video'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
    });

    testWidgets('dialogues you wrote can be renamed and deleted', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await container
          .read(userDialogueRepositoryProvider)
          .save(
            Dialogue(
              id: '${UserDialogueRepository.idPrefix}mine',
              title: 'My dialogue',
              level: 'N5',
              updatedAt: DateTime(2026),
              lines: const [
                DialogueLine(
                  index: 0,
                  tokens: [DialogueToken(surface: 'こんにちは')],
                ),
              ],
            ),
          );
      container.invalidate(dialogueListViewModelProvider);
      await openLibrary(tester);
      await tester.tap(find.text('Dialogues and stories'));
      await tester.pumpAndSettle();

      // Catalogue dialogues stay locked.
      await tester.longPress(find.text('At the station'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
      expect(find.textContaining('Only dialogues you wrote'), findsOneWidget);

      await tester.longPress(find.text('My dialogue'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      // Tapping a locked card does nothing in edit mode.
      await tester.tap(find.text('At the station'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Rename dialogue'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Renamed dialogue');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed dialogue'), findsOneWidget);

      await tester.longPress(find.text('Renamed dialogue'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed dialogue'), findsNothing);
      expect(find.text('At the station'), findsOneWidget);
    });

    testWidgets('Add Content has a back button that returns to Library', (
      tester,
    ) async {
      await pumpApp(tester);
      await openLibrary(tester);

      await tester.tap(find.text('Add content'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add Content'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('system back from Add Content returns to Library', (
      tester,
    ) async {
      await pumpApp(tester);
      await openLibrary(tester);

      await tester.tap(find.text('Add content'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add Content'), findsOneWidget);

      await pressSystemBack(tester);

      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
      expect(exitCalls(), isEmpty);
      expect(find.text(DoubleBackToExit.message), findsNothing);
    });
  });

  group('double back to exit', () {
    testWidgets('the first back press on a root tab only warns', (
      tester,
    ) async {
      await pumpApp(tester);

      await pressSystemBack(tester);

      expect(find.text(DoubleBackToExit.message), findsOneWidget);
      expect(find.text('HitaruJP'), findsOneWidget);
      expect(exitCalls(), isEmpty);
    });

    testWidgets('the second back press leaves the app', (tester) async {
      await pumpApp(tester);

      await pressSystemBack(tester);
      await pressSystemBack(tester);

      expect(exitCalls(), hasLength(1));
    });

    testWidgets('the warning lapses, so a later press only warns again', (
      tester,
    ) async {
      await pumpApp(tester);

      await pressSystemBack(tester);
      await tester.pump(
        DoubleBackToExit.promptDuration + const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();

      await pressSystemBack(tester);

      expect(find.text(DoubleBackToExit.message), findsOneWidget);
      expect(exitCalls(), isEmpty);
    });
  });
}
