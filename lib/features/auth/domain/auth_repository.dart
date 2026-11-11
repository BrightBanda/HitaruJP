/// The identity contract every user-data repository depends on.
///
/// Intentionally narrow: repositories only ever need a uid, a display name, and
/// the ability to change it. Sign-in lives on [AuthSession] so the widget tests
/// can substitute a fake without dragging Firebase in.
///
/// There is no `clear()`. The old local implementation's `clear()` deleted the
/// profile document to mean "sign out"; Firebase sign-out is a plain sign-out and
/// must never touch user data.
abstract interface class AuthRepository {
  /// The signed-in user's id, waiting briefly for Firebase to restore a session.
  ///
  /// Throws a descriptive [StateError] if nobody is signed in: every repository
  /// calls this on entry, so a clear failure beats propagating a null uid.
  Future<String> ensureUid();

  /// Best available human-readable name, or null if there is nothing to show.
  Future<String?> get displayName;

  Future<void> setDisplayName(String name);
}

/// [AuthRepository] plus the sign-in surface the auth view model needs.
///
/// Note the absence of any delete operation: signing out cannot reach user data,
/// by construction rather than by convention.
abstract interface class AuthSession implements AuthRepository {
  /// The uid of the already-restored session, or null while signed out.
  ///
  /// Lets a caller settle immediately instead of waiting for the stream's first
  /// event, which would otherwise leave the app on a spinner.
  String? get currentUid;

  /// Emits the signed-in user's uid, or an empty string when signed out.
  Stream<String> authStateChanges();

  /// Only the name the user chose and stored, with no fallbacks.
  Future<String?> profileDisplayName();

  /// The raw `users/{uid}/profile/self` document, or `{}` when there is none.
  Future<Map<String, dynamic>> profileDocument();

  /// Seeds the profile document on first sign-in. Idempotent.
  Future<void> ensureProfile();

  /// Merges [fields] into the profile document, leaving every other field as is.
  Future<void> updateProfile(Map<String, dynamic> fields);

  /// Returns false when the user dismissed the picker, which is not an error.
  Future<bool> signInWithGoogle();

  Future<void> signInWithEmail(String email, String password);

  /// Creates the account and sends it a verification email.
  Future<void> createAccount(String email, String password);

  /// Emails a password-reset link. Succeeds silently for unknown addresses, since
  /// Firebase's email enumeration protection hides whether an account exists.
  Future<void> sendPasswordReset(String email);

  /// True for an email/password account whose address is not verified yet.
  /// Google accounts are verified by Google and never need this.
  bool get needsEmailVerification;

  /// Sends (or re-sends) the verification email to the signed-in user.
  Future<void> sendEmailVerification();

  /// Re-fetches the user from Firebase and returns [needsEmailVerification].
  /// Verifying happens in a browser, so the app only learns of it by asking.
  Future<bool> reloadNeedsEmailVerification();

  /// The signed-in user's email, if any.
  String? get email;

  /// A plain sign-out. User data is left intact.
  Future<void> signOut();
}
