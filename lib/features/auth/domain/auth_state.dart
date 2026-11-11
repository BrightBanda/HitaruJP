import 'package:ingrain/features/auth/domain/user_profile.dart';

class AuthState {
  final bool isLoading;
  final String uid;
  final String? displayName;

  /// The stored profile, once loaded. Null while signed out, or when a test
  /// builds the state from a name alone.
  final UserProfile? profile;

  /// Set when the last sign-in attempt failed; cleared on the next attempt.
  final String? error;

  /// Signed in with an email/password account whose address is unverified.
  /// Such a session is held at the verification screen.
  final bool needsEmailVerification;

  const AuthState._({
    required this.isLoading,
    required this.uid,
    this.displayName,
    this.profile,
    this.error,
    this.needsEmailVerification = false,
  });

  const AuthState.loading() : this._(isLoading: true, uid: '');

  /// The pre-Firebase "no user" state: `uid` empty, no name, nothing to show.
  const AuthState.signedOut() : this._(isLoading: false, uid: '');

  const AuthState.ready({
    required String uid,
    String? displayName,
    UserProfile? profile,
    String? error,
    bool needsEmailVerification = false,
  }) : this._(
         isLoading: false,
         uid: uid,
         displayName: displayName,
         profile: profile,
         error: error,
         needsEmailVerification: needsEmailVerification,
       );

  bool get isSignedIn => !isLoading && uid.isNotEmpty;

  /// Signed in *and* through onboarding. With a loaded profile that means the
  /// full flow (see [UserProfile.isOnboarded]); without one, having chosen a name.
  /// The trim guards against a name that is only whitespace.
  bool get isOnboarded {
    if (!isSignedIn || needsEmailVerification) return false;
    final profile = this.profile;
    if (profile != null) return profile.isOnboarded;
    return displayName?.trim().isNotEmpty ?? false;
  }
}
