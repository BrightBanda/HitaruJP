import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which parts of the first-open tour this device still has to show.
class FirstRunState {
  /// The welcome pages before sign-in. Per device: whoever signs in next
  /// has seen what the app is about.
  final bool welcomeSeen;

  /// The guided first lesson, for a learner who just finished onboarding.
  final bool lessonPending;

  /// The pointers over the home page, after the lesson.
  final bool homeTipsPending;

  const FirstRunState({
    this.welcomeSeen = false,
    this.lessonPending = false,
    this.homeTipsPending = false,
  });
}

/// The tour's progress, kept on the device.
///
/// The lesson and the home tips are per learner, and only ever *set* pending
/// by finishing onboarding: someone who onboarded before the tour existed, or
/// on another phone, is never sent back through it.
class FirstRunViewModel extends Notifier<FirstRunState> {
  static const welcomeKey = 'first_run_welcome_seen';
  static String lessonKey(String uid) => 'first_run_lesson_pending_$uid';
  static String tipsKey(String uid) => 'first_run_tips_pending_$uid';

  late SharedPreferences _prefs;

  @override
  FirstRunState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    final signedIn = ref.watch(authViewModelProvider.select((s) => s.uid));
    final uid = signedIn.isEmpty ? null : signedIn;
    return FirstRunState(
      welcomeSeen: _prefs.getBool(welcomeKey) ?? false,
      lessonPending: uid != null && (_prefs.getBool(lessonKey(uid)) ?? false),
      homeTipsPending: uid != null && (_prefs.getBool(tipsKey(uid)) ?? false),
    );
  }

  void markWelcomeSeen() {
    _prefs.setBool(welcomeKey, true);
    state = FirstRunState(
      welcomeSeen: true,
      lessonPending: state.lessonPending,
      homeTipsPending: state.homeTipsPending,
    );
  }

  /// Queues the lesson and the home tips for [uid]. Called just before the
  /// profile is marked onboarded, so the router finds the lesson waiting.
  void startTour(String uid) {
    _prefs.setBool(lessonKey(uid), true);
    _prefs.setBool(tipsKey(uid), true);
    state = FirstRunState(
      welcomeSeen: state.welcomeSeen,
      lessonPending: true,
      homeTipsPending: true,
    );
  }

  void finishLesson(String uid) {
    _prefs.remove(lessonKey(uid));
    state = FirstRunState(
      welcomeSeen: state.welcomeSeen,
      homeTipsPending: state.homeTipsPending,
    );
  }

  void finishHomeTips(String uid) {
    _prefs.remove(tipsKey(uid));
    state = FirstRunState(
      welcomeSeen: state.welcomeSeen,
      lessonPending: state.lessonPending,
    );
  }
}

final firstRunProvider = NotifierProvider<FirstRunViewModel, FirstRunState>(
  FirstRunViewModel.new,
);
