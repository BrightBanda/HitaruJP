import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/storage/snapshot_cache.dart';
import 'package:ingrain/firebase_options.dart';
import 'package:ingrain/features/auth/data/firebase_auth_repository.dart';
import 'package:ingrain/features/auth/data/user_profile_dto.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';
import 'package:ingrain/features/auth/domain/auth_state.dart';
import 'package:ingrain/features/auth/domain/user_profile.dart';
import 'package:ingrain/features/profile/domain/learner_preferences.dart';

final authRepositoryProvider = Provider<AuthSession>((ref) {
  return FirebaseAuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
    // `FirebaseOptions` exposes only `androidClientId`/`iosClientId`, never a web
    // client id, and Google Sign-In on Android wants the web one. The generated
    // options are the best available guess; the dart-define overrides it.
    serverClientId: DefaultFirebaseOptions.currentPlatform.androidClientId,
  );
});

final authViewModelProvider = NotifierProvider<AuthViewModel, AuthState>(
  AuthViewModel.new,
);

final isOnboardedProvider = Provider<bool>((ref) {
  return ref.watch(authViewModelProvider).isOnboarded;
});

class AuthViewModel extends Notifier<AuthState> {
  late AuthSession _auth;
  StreamSubscription<String>? _subscription;

  @override
  AuthState build() {
    _auth = ref.watch(authRepositoryProvider);
    ref.onDispose(() => _subscription?.cancel());
    _bootstrap();
    // A returning learner starts from the profile saved on this device, so
    // the app opens straight onto the home page instead of waiting for
    // Firestore. _bootstrap refreshes it from the server right after.
    final uid = _auth.currentUid;
    final cached = uid == null ? null : _cachedProfile(uid);
    if (uid != null && cached != null) return _readyFrom(uid, cached);
    return const AuthState.loading();
  }

  static String _profileKey(String uid) => 'profile_$uid';

  Map<String, dynamic>? _cachedProfile(String uid) => ref
      .read(snapshotCacheProvider)
      .read(_profileKey(uid), (json) => Map<String, dynamic>.from(json as Map));

  void _cacheProfile(String uid, Map<String, dynamic> document) {
    unawaited(
      ref.read(snapshotCacheProvider).write(_profileKey(uid), document),
    );
  }

  static AuthState _readyFrom(String uid, Map<String, dynamic> document) {
    final profile = UserProfileDto.fromMapSafe(document);
    final name = profile?.displayName;
    return AuthState.ready(
      uid: uid,
      displayName: name != null && name.trim().isNotEmpty ? name : null,
      profile: profile,
    );
  }

  /// Follows the Firebase session rather than probing it once. This is the single
  /// point every repository's `ensureUid()` flows through, so it has to be right
  /// before anything else is touched.
  void _bootstrap() {
    _subscription = _auth.authStateChanges().listen(
      (uid) => _applySession(uid),
      onError: (_, _) {
        if (ref.mounted) state = const AuthState.signedOut();
      },
    );
    // Settle from the restored session instead of waiting for the stream's first
    // event. Firebase always emits one, but until it does the router sees
    // `isLoading` and the whole app sits behind a spinner. Deferred to a microtask
    // because `build()` has not returned its own state yet at this point.
    final current = _auth.currentUid;
    unawaited(Future<void>.microtask(() => _applySession(current ?? '')));
  }

  Future<void> _applySession(String uid) async {
    if (uid.isEmpty) {
      if (ref.mounted) state = const AuthState.signedOut();
      return;
    }
    try {
      // One read for a returning learner; only a first sign-in, with no
      // profile yet, pays for the seed write and a second read.
      var document = await _auth.profileDocument();
      if (document.isEmpty) {
        await _auth.ensureProfile();
        document = await _auth.profileDocument();
      }
      // The stream outlives any single listener: a sign-out or a provider rebuild
      // can dispose this notifier while the profile read is still in flight.
      if (!ref.mounted) return;
      state = _readyFrom(uid, document);
      if (document.isNotEmpty) _cacheProfile(uid, document);
      // Best effort: "last active" is a statistic, not worth failing over.
      unawaited(
        _auth
            .updateProfile({
              'lastActiveAt': DateTime.now().toUtc().toIso8601String(),
            })
            .catchError((Object _) {}),
      );
    } catch (error) {
      if (!ref.mounted) return;
      // Offline with a saved profile: keep showing it rather than an error.
      if (state.uid == uid && state.profile != null) return;
      state = AuthState.ready(
        uid: uid,
        error: 'Could not load your profile: $error',
      );
    }
  }

  /// Best-effort name for prefilling the onboarding field. Falls back to the Google
  /// name and then the email local part, so the field is rarely empty.
  Future<String?> suggestedDisplayName() => _auth.displayName;

  Future<bool> signInWithGoogle() => _runSignIn(_auth.signInWithGoogle);

  Future<bool> signInWithEmail(String email, String password) =>
      _runSignIn(() async {
        await _auth.signInWithEmail(email, password);
        return true;
      });

  Future<bool> createAccount(String email, String password) =>
      _runSignIn(() async {
        await _auth.createAccount(email, password);
        return true;
      });

  /// Surfaces failures in [AuthState.error] instead of throwing at the UI layer.
  /// Returns whether a session is now active — a dismissed account chooser reports
  /// false without setting an error.
  Future<bool> _runSignIn(Future<bool> Function() action) async {
    state = AuthState.ready(
      uid: state.uid,
      displayName: state.displayName,
      profile: state.profile,
    );
    try {
      return await action();
    } on FirebaseAuthException catch (error) {
      state = AuthState.ready(
        uid: '',
        error: error.message ?? 'Sign-in failed (${error.code}).',
      );
      return false;
    } on GoogleSignInException catch (error) {
      state = AuthState.ready(
        uid: '',
        error: error.description ?? 'Sign-in failed.',
      );
      return false;
    } catch (error) {
      state = AuthState.ready(uid: '', error: '$error');
      return false;
    }
  }

  /// Stores every onboarding answer and marks the learner onboarded.
  ///
  /// Flip the session to onboarded before the writes finish so the router can
  /// leave the onboarding screen even if Firestore is slow or temporarily
  /// unavailable. The writes are still attempted, but the UI must not block on
  /// them.
  Future<void> completeOnboarding({
    required String displayName,
    String? avatarId,
    JlptLevel? level,
    List<LearningReason> learningReasons = const [],
    List<ContentInterest> interests = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final base = state.profile ?? UserProfile(uid: state.uid, createdAt: now);
    await _saveProfile(
      base.copyWith(
        displayName: () => displayName.trim(),
        avatarId: () => avatarId ?? base.avatarId,
        level: () => level ?? base.level,
        learningReasons: learningReasons,
        interests: interests,
        onboardingCompletedAt: () => now,
        onboardingVersion: UserProfile.currentOnboardingVersion,
      ),
    );
  }

  /// Saves an edited profile (name, avatar, level, reasons, interests).
  Future<void> updateProfile(UserProfile profile) => _saveProfile(
    profile.copyWith(displayName: () => profile.displayName?.trim()),
  );

  Future<void> _saveProfile(UserProfile profile) async {
    final name = profile.displayName;
    final nameChanged = name != null && name != state.displayName;
    state = AuthState.ready(
      uid: state.uid,
      displayName: name,
      profile: profile,
    );
    final cached = _cachedProfile(state.uid) ?? {'uid': state.uid};
    _cacheProfile(state.uid, {
      ...cached,
      ...UserProfileDto.learnerFields(profile),
    });
    try {
      if (nameChanged) await _auth.setDisplayName(name);
      await _auth.updateProfile(UserProfileDto.learnerFields(profile));
    } catch (error) {
      if (ref.mounted) {
        state = AuthState.ready(
          uid: state.uid,
          displayName: name,
          profile: profile,
          error: 'Could not save your profile: $error',
        );
      }
      rethrow;
    }
  }

  /// Records the tier the server reported. The app never stores or sets a tier
  /// itself; it only shows what the server says.
  void applySubscriptionTier(SubscriptionTier tier) {
    final profile = state.profile;
    if (profile == null || profile.subscriptionTier == tier) return;
    state = AuthState.ready(
      uid: state.uid,
      displayName: state.displayName,
      profile: profile.copyWith(subscriptionTier: tier),
      error: state.error,
    );
  }

  /// Reads the stored `createdAt` rather than stamping "now" on every read.
  Future<UserProfile?> profile() async {
    if (state.isLoading || !state.isSignedIn) return null;
    return UserProfileDto.fromMapSafe(await _auth.profileDocument());
  }

  Future<void> refresh() async {
    final uid = await _auth.ensureUid();
    state = AuthState.ready(
      uid: uid,
      displayName: await _auth.displayName,
      profile: UserProfileDto.fromMapSafe(await _auth.profileDocument()),
    );
  }

  /// A plain sign-out. User data in Firestore is deliberately left intact.
  Future<void> signOut() async {
    await _auth.signOut();
    state = const AuthState.signedOut();
  }
}
