import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ingrain/app/main_shell.dart';
import 'package:ingrain/features/auth/presentation/view/onboarding_view.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/content/presentation/view/add_content_type.dart';
import 'package:ingrain/features/content/presentation/view/content_add_view.dart';
import 'package:ingrain/features/content/presentation/view/content_history_view.dart';
import 'package:ingrain/features/content/presentation/view/transcript_editor_view.dart';
import 'package:ingrain/features/content/presentation/view/player/immersion_player_view.dart';
import 'package:ingrain/features/dialogue/presentation/view/dialogue_reader_view.dart';
import 'package:ingrain/features/immersion/presentation/view/immersion_home_view.dart';
import 'package:ingrain/features/kana/presentation/kana_view.dart';
import 'package:ingrain/features/onboarding/presentation/view/first_lesson_view.dart';
import 'package:ingrain/features/onboarding/presentation/viewmodel/first_run_view_model.dart';
import 'package:ingrain/features/profile/presentation/edit_profile_view.dart';
import 'package:ingrain/features/profile/presentation/profile_view.dart';
import 'package:ingrain/features/search/presentation/view/search_view.dart';
import 'package:ingrain/features/srs/presentation/view/deck_detail_view.dart';
import 'package:ingrain/features/srs/presentation/view/flashcard_study_view.dart';
import 'package:ingrain/features/srs/presentation/view/flashcards_view.dart';
import 'package:ingrain/features/content/presentation/player_host/player_host.dart';
import 'package:ingrain/features/srs/presentation/view/srs_settings_view.dart';
import 'package:ingrain/features/vocabulary/presentation/view/vocabulary_view.dart';
import 'package:ingrain/shared/layout/window_size.dart';

export 'package:ingrain/app/main_shell.dart'
    show LearnDestination, MainShellView;

final appRouterProvider = Provider<GoRouter>((ref) {
  // Only what the redirect needs: a new router is built whenever this changes,
  // so watching the whole state would reset navigation on every profile edit.
  final (isLoading, isOnboarded) = ref.watch(
    authViewModelProvider.select((auth) => (auth.isLoading, auth.isOnboarded)),
  );

  return GoRouter(
    initialLocation: '/onboarding',
    observers: [playerRouteObserver],
    redirect: (context, state) {
      if (isLoading) return null;
      final location = state.uri.toString();
      if (!isOnboarded && location != '/onboarding') {
        return '/onboarding';
      }
      if (isOnboarded && location == '/onboarding') {
        // Just finished the questions: the guided first lesson comes next.
        // Read, not watched: finishing the lesson navigates by itself.
        return ref.read(firstRunProvider).lessonPending
            ? '/first-lesson'
            : '/immerse';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShellView(child: child),
        routes: [
          GoRoute(
            path: '/immerse',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ImmersionHomeView()),
          ),
          GoRoute(
            path: '/library',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ContentHistoryView()),
          ),
          GoRoute(
            path: '/flashcards',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: FlashcardsView()),
          ),
          GoRoute(
            path: LearnDestination.vocab.path,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: VocabularyView()),
          ),
          GoRoute(
            path: LearnDestination.kana.path,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: KanaView()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileView()),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingView(),
      ),
      GoRoute(
        path: '/first-lesson',
        builder: (context, state) => const FirstLessonView(),
      ),
      GoRoute(
        path: '/flashcards/study',
        builder: (context, state) => PageFrame(
          child: FlashcardStudyView(
            deckId: state.uri.queryParameters['deck'],
            title: state.uri.queryParameters['title'],
          ),
        ),
      ),
      GoRoute(
        path: '/flashcards/settings',
        builder: (context, state) => const PageFrame(child: SrsSettingsView()),
      ),
      GoRoute(
        path: '/flashcards/deck/:id',
        builder: (context, state) => PageFrame(
          maxWidth: 980,
          child: DeckDetailView(deckId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/content/add',
        builder: (context, state) => PageFrame(
          child: ContentAddView(
            initialType: AddContentType.fromName(
              state.uri.queryParameters['type'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const PageFrame(child: SearchView()),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const PageFrame(child: EditProfileView()),
      ),
      GoRoute(
        path: '/dialogues/:id',
        builder: (context, state) => PageFrame(
          child: DialogueReaderView(dialogueId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/content/:id/transcript',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PageFrame(
            child: TranscriptEditorView(
              contentId: state.pathParameters['id']!,
              initialTranscript: extra?['transcript'] as String?,
              initialDuration: extra?['duration'] as int?,
            ),
          );
        },
      ),
      GoRoute(
        path: '/content/:id',
        builder: (context, state) =>
            ImmersionPlayerView(contentId: state.pathParameters['id']!),
      ),
    ],
  );
});
