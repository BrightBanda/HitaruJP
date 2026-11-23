// Store screenshots: the real app screens, with mock data, rendered to PNG.
// Run with tool/showcase/run.sh (it fetches the photos and sets the paths
// below). Not part of the normal test suite.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/router.dart';
import 'package:ingrain/app/theme/app_theme.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/catalog/domain/catalog_video.dart';
import 'package:ingrain/features/content/domain/content_item.dart';
import 'package:ingrain/features/content/presentation/viewmodel/content_view_model.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/domain/dialogue_repository.dart';
import 'package:ingrain/features/dialogue/presentation/viewmodel/dialogue_providers.dart';
import 'package:ingrain/features/growth/data/growth_repository.dart';
import 'package:ingrain/features/growth/domain/growth_rules.dart';
import 'package:ingrain/features/quiz/presentation/viewmodel/quiz_providers.dart';
import 'package:ingrain/features/social/domain/social.dart';
import 'package:ingrain/features/immersion/domain/immersion_session.dart';
import 'package:ingrain/features/immersion/presentation/viewmodel/immersion_session_view_model.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';
import 'package:ingrain/features/progress/presentation/viewmodel/progress_view_model.dart';
import 'package:ingrain/features/vocabulary/domain/dictionary_index.dart';
import 'package:ingrain/features/vocabulary/domain/vocabulary_item.dart';
import 'package:ingrain/features/vocabulary/presentation/viewmodel/vocabulary_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/test_overrides.dart';

final _cache = Platform.environment['SHOWCASE_CACHE'] ?? 'build/showcase/cache';
final _out = Platform.environment['SHOWCASE_OUT'] ?? 'build/showcase/raw';
final _fonts = Platform.environment['SHOWCASE_FONTS'];
final _cjk = Platform.environment['SHOWCASE_CJK'];

/// A phone: 412 × 915 points, drawn at 3× (1236 × 2745 pixels).
const _size = Size(412, 915);
const _pixelRatio = 3.0;
const _japanese = 'Noto Sans JP';

const _uid = 'showcase';

// --- Fonts and photos -----------------------------------------------------

/// Real fonts instead of the test font (whose letters are all boxes). The
/// test engine has no font fallback of its own, so Japanese is named as a
/// fallback on the app's theme.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var any = false;
    for (final path in paths) {
      if (!File(path).existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
      );
      any = true;
    }
    if (any) await loader.load();
  }

  final dir = _fonts;
  if (dir != null) {
    await load('MaterialIcons', ['$dir/MaterialIcons-Regular.otf']);
    final roboto = [
      for (final w in ['Light', 'Regular', 'Medium', 'Bold', 'Black'])
        '$dir/Roboto-$w.ttf',
    ];
    await load('Roboto', roboto);
    // Styles that name no family get the platform default, which on a phone
    // is Roboto but in a test is "FlutterTest" (all boxes): make it Roboto.
    await load('FlutterTest', roboto);
  }
  final cjk = _cjk;
  if (cjk != null) await load(_japanese, [cjk]);

  AppTheme.light = _withFonts(AppTheme.light);
}

/// The app's theme with every text style naming its font.
///
/// On a phone a style with no family gets the system font (Roboto); the test
/// engine gives it a box font instead, and has no font fallback of its own.
/// So the component themes that set their own styles get Roboto named, and
/// everything gets Japanese as a fallback.
ThemeData _withFonts(ThemeData theme) {
  TextStyle? named(TextStyle? style) => style?.copyWith(
    fontFamily: style.fontFamily ?? 'Roboto',
    fontFamilyFallback: const [_japanese],
  );
  WidgetStateProperty<TextStyle?>? namedAll(
    WidgetStateProperty<TextStyle?>? style,
  ) => style == null
      ? null
      : WidgetStateProperty.resolveWith(
          (states) => named(style.resolve(states)),
        );
  ButtonStyle? button(ButtonStyle? style) =>
      style?.copyWith(textStyle: namedAll(style.textStyle));

  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamilyFallback: const [_japanese]),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamilyFallback: const [_japanese],
    ),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: named(theme.appBarTheme.titleTextStyle),
    ),
    navigationBarTheme: theme.navigationBarTheme.copyWith(
      labelTextStyle: namedAll(theme.navigationBarTheme.labelTextStyle),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: named(theme.chipTheme.labelStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button(theme.filledButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button(theme.elevatedButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button(theme.textButtonTheme.style),
    ),
  );
}

/// Mock thumbnails: each video id shows one stock photo.
const _photos = {
  'sc-tea': 'p225.jpg',
  'sc-cook': 'p292.jpg',
  'sc-town': 'p164.jpg',
  'sc-cafe': 'p431.jpg',
  'sc-falls': 'p1043.jpg',
  'sc-alley': 'p1047.jpg',
  'sc-city': 'p1067.jpg',
  'sc-coffee': 'p1060.jpg',
};

String _thumb(String id) => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

/// Puts every mock photo in Flutter's image cache under the keys the app's
/// thumbnails look up, at every decode width they may ask for, so they show
/// without a network.
Future<void> _loadPhotos(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final MapEntry(key: id, value: file) in _photos.entries) {
      final bytes = File('$_cache/photos/$file').readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      ImageStreamCompleter completer() => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: frame.image.clone())),
      );
      // Every decode width is its own entry; keep them all.
      final cache = PaintingBinding.instance.imageCache
        ..maximumSize = 100000
        ..maximumSizeBytes = 1 << 34;
      final provider = CachedNetworkImageProvider(_thumb(id));
      cache.putIfAbsent(provider, completer);
      cache.putIfAbsent(NetworkImage(_thumb(id)), completer);
      for (var width = 160; width <= 3840; width += 160) {
        final key = await ResizeImage(
          provider,
          width: width,
        ).obtainKey(ImageConfiguration.empty);
        cache.putIfAbsent(key, completer);
      }
    }
  });
}

// --- Mock data --------------------------------------------------------------

const _picks = [
  CatalogVideo(
    id: 'sc-tea',
    title: 'Morning tea, in easy Japanese',
    description: 'A slow morning routine, narrated simply.',
    level: JlptLevel.n5,
    categories: [ContentInterest.culture],
    videoUrl: 'https://www.youtube.com/watch?v=sc-tea',
    youtubeId: 'sc-tea',
    thumbnailUrl: 'https://i.ytimg.com/vi/sc-tea/hqdefault.jpg',
    durationSeconds: 412,
    channelTitle: 'Slow Japanese',
    reason: PickReason.level,
  ),
  CatalogVideo(
    id: 'sc-cook',
    title: 'Cooking curry at home',
    description: 'Ingredients and steps, said clearly.',
    level: JlptLevel.n5,
    categories: [ContentInterest.youtube],
    videoUrl: 'https://www.youtube.com/watch?v=sc-cook',
    youtubeId: 'sc-cook',
    thumbnailUrl: 'https://i.ytimg.com/vi/sc-cook/hqdefault.jpg',
    durationSeconds: 538,
    channelTitle: 'Kitchen Kotoba',
    reason: PickReason.interest,
  ),
  CatalogVideo(
    id: 'sc-town',
    title: 'A walk through an old canal town',
    description: 'Street sounds and simple narration.',
    level: JlptLevel.n4,
    categories: [ContentInterest.travel],
    videoUrl: 'https://www.youtube.com/watch?v=sc-town',
    youtubeId: 'sc-town',
    thumbnailUrl: 'https://i.ytimg.com/vi/sc-town/hqdefault.jpg',
    durationSeconds: 721,
    channelTitle: 'Walk & Talk',
    reason: PickReason.level,
  ),
];

/// A short café scene, every word tappable.
final _cafe = Dialogue(
  id: 'sc-cafe-talk',
  title: 'At the café',
  level: 'N5',
  speakers: const ['店員', 'ゆき'],
  lines: [
    _line(0, '店員', [('いらっしゃいませ', null), ('。', null)], 'Welcome!'),
    _line(1, 'ゆき', [
      ('コーヒー', 'こーひー'),
      ('を', null),
      ('一つ', 'ひとつ'),
      ('ください', null),
      ('。', null),
    ], 'One coffee, please.'),
    _line(2, '店員', [
      ('温かい', 'あたたかい'),
      ('の', null),
      ('で', null),
      ('よろしい', null),
      ('です', null),
      ('か', null),
      ('？', null),
    ], 'Would you like it hot?'),
    _line(3, 'ゆき', [
      ('はい', null),
      ('、', null),
      ('お願い', 'おねがい'),
      ('します', null),
      ('。', null),
    ], 'Yes, please.'),
    _line(4, '店員', [
      ('五百円', 'ごひゃくえん'),
      ('です', null),
      ('。', null),
    ], "That's 500 yen."),
    _line(5, 'ゆき', [
      ('ありがとう', null),
      ('ございます', null),
      ('！', null),
    ], 'Thank you!'),
  ],
);

DialogueLine _line(
  int index,
  String speaker,
  List<(String, String?)> tokens,
  String translation,
) => DialogueLine(
  index: index,
  speaker: speaker,
  tokens: [
    for (final (surface, reading) in tokens)
      DialogueToken(surface: surface, reading: reading ?? surface),
  ],
  translation: translation,
);

class _ShowcaseDialogues implements DialogueRepository {
  @override
  bool isShowingCachedCopy = false;

  @override
  Future<List<DialogueSummary>> listSummaries() async => [_cafe];

  @override
  Future<List<DialogueSummary>> listCachedSummaries() => listSummaries();

  @override
  Future<Dialogue> getDialogue(String id) async => _cafe;

  @override
  Future<Dialogue?> getCachedDialogue(String id) async => _cafe;

  @override
  Future<void> cacheDialogue(Dialogue dialogue) async {}
}

const _dictionary = [
  DictionaryEntry(
    surface: '温かい',
    reading: 'あたたかい',
    meanings: ['warm', 'hot (food, drinks)', 'kind, warm-hearted'],
  ),
  DictionaryEntry(surface: 'コーヒー', reading: 'こーひー', meanings: ['coffee']),
  DictionaryEntry(surface: '一つ', reading: 'ひとつ', meanings: ['one (thing)']),
  DictionaryEntry(
    surface: 'お願い',
    reading: 'おねがい',
    meanings: ['request', 'please'],
  ),
  DictionaryEntry(surface: '五百円', reading: 'ごひゃくえん', meanings: ['500 yen']),
];

/// Words already saved, so flashcards and progress have something to show.
const _words = [
  ('駅', 'えき', 'station'),
  ('電車', 'でんしゃ', 'train'),
  ('美味しい', 'おいしい', 'delicious'),
  ('友達', 'ともだち', 'friend'),
  ('今日', 'きょう', 'today'),
  ('天気', 'てんき', 'weather'),
  ('散歩', 'さんぽ', 'a walk, a stroll'),
  ('料理', 'りょうり', 'cooking; a dish'),
  ('お茶', 'おちゃ', 'tea'),
  ('朝ご飯', 'あさごはん', 'breakfast'),
  ('映画', 'えいが', 'movie'),
  ('買い物', 'かいもの', 'shopping'),
  ('写真', 'しゃしん', 'photo'),
  ('楽しい', 'たのしい', 'fun, enjoyable'),
  ('静か', 'しずか', 'quiet'),
  ('川', 'かわ', 'river'),
  ('町', 'まち', 'town'),
];

/// Library videos the learner has added.
const _library = [
  ('sc-cafe', 'Ordering at a café', 'Everyday Nihongo'),
  ('sc-falls', 'Hiking to a waterfall', 'Mountain Diaries'),
  ('sc-alley', 'Old streets at dusk', 'Walk & Talk'),
  ('sc-city', 'A day in the city', 'City Vlog JP'),
  ('sc-coffee', 'How a barista makes pour-over', 'Kitchen Kotoba'),
];

/// Friends for the social screens: a mix of companions, levels and streaks.
const _ken = Person(
  username: 'ken_studies',
  displayName: 'Ken',
  avatarId: 'shiba',
  stats: PublicStats(level: 9, stage: GrowthStage.teen, streak: 6),
  relation: Relation.friends,
  todayQuiz: (correct: 10, total: 12),
);
const _mio = Person(
  username: 'mio',
  displayName: 'Mio',
  avatarId: 'usagi',
  stats: PublicStats(level: 21, stage: GrowthStage.adult, streak: 32),
  relation: Relation.friends,
  todayQuiz: (correct: 12, total: 12),
);
const _yuto = Person(
  username: 'yuto.jp',
  displayName: 'Yuto',
  avatarId: 'tanuki',
  stats: PublicStats(level: 4, stage: GrowthStage.child, streak: 2),
  relation: Relation.friends,
);

class _ShowcaseSocial extends FakeSocialRepository {
  _ShowcaseSocial() : super(username: 'aiko') {
    friendsList.addAll([_ken, _mio, _yuto]);
    received.add(
      ReceivedPing(
        id: 1,
        kind: PingKind.cheer,
        sender: _mio,
        createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
        seen: false,
      ),
    );
  }

  @override
  Future<Leaderboard> leaderboard({
    required DateTime today,
    LeaderboardScope scope = LeaderboardScope.friends,
  }) async {
    const me = Person(
      username: 'aiko',
      displayName: 'Aiko',
      avatarId: 'kitsune',
      stats: PublicStats(level: 12, stage: GrowthStage.teen, streak: 14),
      todayQuiz: (correct: 11, total: 12),
    );
    Person stranger(String username, String avatar, int level) => Person(
      username: username,
      avatarId: avatar,
      stats: PublicStats(
        level: level,
        stage: level >= 20 ? GrowthStage.adult : GrowthStage.teen,
      ),
    );
    final rows = scope == LeaderboardScope.friends
        ? [
            (_mio, 245, 3, 47),
            (me, 190, 3, 38),
            (_ken, 150, 3, 30),
            (_yuto, 55, 1, 11),
          ]
        : [
            (stranger('sakura_nihongo', 'neko', 34), 350, 5, 68),
            (stranger('kanji_hunter', 'oni', 27), 330, 5, 64),
            (_mio, 245, 3, 47),
            (stranger('daily_ramen', 'onigiri', 12), 230, 4, 44),
            (me, 190, 3, 38),
            (stranger('hana.learns', 'panda', 9), 175, 3, 33),
            (_ken, 150, 3, 30),
          ];
    return Leaderboard(
      scope: scope,
      participants: scope == LeaderboardScope.everyone ? 1284 : 0,
      weekStart: today,
      entries: [
        for (final (i, (person, xp, quizzes, correct)) in rows.indexed)
          LeaderboardEntry(
            rank: i + 1,
            person: person,
            isMe: identical(person, me),
            weekXp: xp,
            quizzes: quizzes,
            correct: correct,
          ),
      ],
    );
  }
}

/// The real dictionary, for the quiz: thousands of words at each level.
DictionaryIndex _fullDictionary() => DictionaryIndex.fromJson(
  jsonDecode(File('assets/data/dictionary.json').readAsStringSync())
      as Map<String, dynamic>,
);

bool _useFullDictionary = false;

ProviderContainer _container(SharedPreferences prefs) {
  final session = FakeAuthSession(uid: _uid, name: 'Aiko')
    ..profileFields.addAll({
      'avatarId': 'kitsune',
      'level': JlptLevel.n5.name,
      'interests': [
        ContentInterest.youtube.name,
        ContentInterest.travel.name,
        ContentInterest.culture.name,
      ],
    });
  return ProviderContainer(
    overrides: [
      ...appTestOverrides(
        prefs,
        session: session,
        catalog: FakeCatalogRepository(picks: _picks),
        social: _ShowcaseSocial(),
      ),
      dialogueRepositoryProvider.overrideWithValue(_ShowcaseDialogues()),
      dictionaryProvider.overrideWith(
        (ref) async => _useFullDictionary
            ? _fullDictionary()
            : DictionaryIndex(_dictionary),
      ),
    ],
  );
}

/// Fills the learner's history: a library, saved words, two weeks of
/// immersion and enough XP for a grown companion.
Future<void> _seed(ProviderContainer c) async {
  final content = c.read(contentRepositoryProvider);
  for (final (id, title, channel) in _library) {
    await content.create(
      sourceUrl: 'https://www.youtube.com/watch?v=$id',
      title: title,
      channelTitle: channel,
      thumbnailUrl: _thumb(id),
    );
  }

  final vocab = c.read(vocabularyViewModelProvider.notifier);
  for (final (word, reading, meaning) in _words) {
    await vocab.saveWord(
      word: word,
      reading: reading,
      meaning: meaning,
      sourceType: SourceType.youtube,
      sourceId: 'sc-tea',
      sourceTitle: 'Morning tea, in easy Japanese',
      vocabState: VocabState.learning,
    );
  }

  final immersion = c.read(immersionRepositoryProvider);
  final now = DateTime.now();
  for (var day = 13; day >= 0; day--) {
    final start = DateTime(now.year, now.month, now.day - day, 8, 30);
    final session = await immersion.startSession(
      sourceId: 'sc-tea',
      sourceTitle: 'Morning tea, in easy Japanese',
      activityType: ActivityType.watching,
      startedAt: start,
    );
    final minutes = day == 0 ? 11 : 12 + (day * 7) % 14;
    await immersion.updateDuration(session.id, minutes * 60);
    await immersion.stopSession(
      session.id,
      start.add(Duration(minutes: minutes)),
    );
  }

  // The XP floor the companion page reads: well into the adult stage.
  final rules = c.read(growthRulesProvider);
  await c.read(documentStoreProvider).setDoc(
    _uid,
    GrowthRepository.collection,
    GrowthRepository.docId,
    {'xp': rules.xpForLevel(12) + 40},
  );
}

// --- The phone --------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF1B1F26);
    return const SizedBox(
      height: 28,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Text(
              '9:41',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
            Spacer(),
            Icon(Icons.signal_cellular_alt, size: 16, color: color),
            SizedBox(width: 4),
            Icon(Icons.wifi, size: 16, color: color),
            SizedBox(width: 4),
            Icon(Icons.battery_full, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

/// Lets futures, pictures and providers settle between pumps.
Future<void> _settle(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  await _settle(tester);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Opens the app at [location] for a seeded learner and returns its
/// container and router.
Future<(ProviderContainer, GoRouter)> _open(
  WidgetTester tester,
  GlobalKey key,
  String location,
) async {
  tester.view.physicalSize = _size * _pixelRatio;
  tester.view.devicePixelRatio = _pixelRatio;
  tester.view.padding = const FakeViewPadding(
    top: 28 * _pixelRatio,
    bottom: 12 * _pixelRatio,
  );
  addTearDown(tester.view.reset);

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    FirstRunViewModel.welcomeKey: true,
    // The companion has been met already: no reveal over the screen.
    'growth_seen_stage_$_uid': 'adult',
    'growth_seen_level_$_uid': 12,
  });
  final prefs = await SharedPreferences.getInstance();
  final c = _container(prefs);
  addTearDown(c.dispose);
  await _loadPhotos(tester);
  await tester.runAsync(() async {
    c.read(authViewModelProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _seed(c);
  });

  final router = c.read(appRouterProvider);
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: UncontrolledProviderScope(
        container: c,
        child: Stack(
          textDirection: TextDirection.ltr,
          children: [
            MaterialApp.router(
              title: 'HitaruJP',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              routerConfig: router,
            ),
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: _StatusBar(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await _settle(tester);
  router.go(location);
  await _settle(tester);
  return (c, router);
}

/// The image disk cache wants folders; give it one, so a picture that is not
/// mocked shows its placeholder instead of failing the run.
void _fakePathProvider() {
  final dir = Directory.systemTemp.createTempSync('showcase');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => dir.path,
      );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _fakePathProvider();
    await _loadFonts();
  });

  testWidgets('home', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/immerse');
    await _shoot(tester, key, '01_home');
  });

  testWidgets('a dialogue, with a word tapped', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/dialogues/${_cafe.id}');
    await tester.tap(find.text('温かい').first);
    await _settle(tester);
    await _shoot(tester, key, '02_dialogue');
  });

  testWidgets('flashcards', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/flashcards/study');
    await tester.tap(find.text('Show answer'));
    await _settle(tester);
    await _shoot(tester, key, '03_flashcards');
  });

  testWidgets('companion', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/companion');
    await _shoot(tester, key, '04_companion');
  });

  testWidgets('library', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/library');
    await _shoot(tester, key, '05_library');
  });

  testWidgets('profile', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/profile');
    await _shoot(tester, key, '06_profile');
  });

  testWidgets('daily quiz, one answered', (tester) async {
    _useFullDictionary = true;
    addTearDown(() => _useFullDictionary = false);
    final key = GlobalKey();
    final (c, _) = await _open(tester, key, '/quiz');
    final quiz = await tester.runAsync(() => c.read(dailyQuizProvider.future));
    await tester.tap(find.text(quiz!.questions.first.answer));
    await _settle(tester);
    await _shoot(tester, key, '07_quiz');
  });

  testWidgets('friends', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/profile?tab=friends');
    await _shoot(tester, key, '08_friends');
  });

  testWidgets('the More menu', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/immerse');
    await tester.tap(find.text('More'));
    await _settle(tester);
    await _shoot(tester, key, 'x_more');
  });

  testWidgets('settings', (tester) async {
    final key = GlobalKey();
    final (_, router) = await _open(tester, key, '/profile');
    router.push('/settings');
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Sign out'), 400);
    await _settle(tester);
    await _shoot(tester, key, 'x_settings');
  });

  testWidgets('leaderboard', (tester) async {
    final key = GlobalKey();
    await _open(tester, key, '/leaderboard');
    await _shoot(tester, key, '09_leaderboard');
  });
}
