import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ingrain/core/storage/firestore_document_store.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';

/// Escape hatch for the Google Sign-In server client id.
///
/// `FirebaseOptions` only carries `androidClientId`/`iosClientId`, never a web
/// client id, and Google Sign-In on Android wants the *web* one. Supply it at build
/// time when the generated options do not already carry a usable value.
const _serverClientIdOverride = String.fromEnvironment(
  'GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
);

class FirebaseAuthRepository implements AuthSession {
  static const String profileCollection = 'profile';
  static const String profileDocId = 'self';
  static const Duration ensureUidTimeout = Duration(seconds: 10);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  /// `GoogleSignIn` is a process-wide singleton in 7.x and must be initialised
  /// exactly once before any other call.
  Future<void>? _googleSignInReady;

  FirebaseAuthRepository(this._auth, this._firestore, {String? serverClientId})
    : _googleSignIn = GoogleSignIn.instance,
      _serverClientId = _resolveServerClientId(serverClientId);

  final String? _serverClientId;

  User? get currentUser => _auth.currentUser;

  @override
  String? get currentUid => _auth.currentUser?.uid;

  /// Emits the signed-in user's uid, or an empty string when signed out.
  @override
  Stream<String> authStateChanges() =>
      _auth.authStateChanges().map((user) => user?.uid ?? '');

  @override
  Future<String> ensureUid() async {
    final user = _auth.currentUser;
    if (user != null) return user.uid;

    // On a cold start the first frame can run before Firebase has restored its
    // persisted session, so wait for the first real emission rather than failing
    // every repository that touches storage during bootstrap.
    try {
      return await _auth
          .authStateChanges()
          .map((user) => user?.uid ?? '')
          .firstWhere((uid) => uid.isNotEmpty)
          .timeout(ensureUidTimeout);
    } on TimeoutException {
      throw StateError(
        'No signed-in user after ${ensureUidTimeout.inSeconds}s. The router should '
        'have sent the user to /onboarding; reaching this means sign-in did not '
        'complete.',
      );
    }
  }

  @override
  Future<String?> get displayName async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await profileDisplayName() ?? _fallbackName(user);
    } on FirebaseException {
      // Offline or Firestore not connected yet: a best-effort name is still
      // better than an error, since every caller only uses this to prefill.
      return _fallbackName(user);
    }
  }

  /// Only the name the user actually chose and stored.
  ///
  /// Kept separate from [displayName] so onboarding can tell "signed in but never
  /// named" from "has a name" — otherwise the email-local-part fallback would make
  /// every first sign-up look already-onboarded and the name field would never
  /// appear.
  @override
  Future<String?> profileDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final name = (await _profileRef(user.uid).get()).data()?['displayName'];
    return name is String && name.trim().isNotEmpty ? name : null;
  }

  @override
  Future<void> setDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Cannot set a display name while signed out.');
    }
    final trimmed = name.trim();
    await _profileRef(user.uid)
        .set({'displayName': trimmed}, SetOptions(merge: true));
    await user.updateDisplayName(trimmed);
  }

  /// The raw `users/{uid}/profile/self` document, or `{}` when there is none.
  @override
  Future<Map<String, dynamic>> profileDocument() async {
    final user = _auth.currentUser;
    if (user == null) return <String, dynamic>{};
    final data = (await _profileRef(user.uid).get()).data();
    if (data == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(data);
  }

  /// Seeds `users/{uid}/profile/self` on first sign-in. Idempotent.
  @override
  Future<void> ensureProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final ref = _profileRef(user.uid);
    if ((await ref.get()).exists) return;
    await ref.set({
      'uid': user.uid,
      if (user.displayName != null) 'displayName': user.displayName,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Cannot update the profile while signed out.');
    }
    final path = documentPath(user.uid, profileCollection, profileDocId);
    assertFirestoreSafe(fields, path: path);
    await _firestore.doc(path).set(fields, SetOptions(merge: true));
  }

  /// Returns false when the user dismissed the account chooser, which is not an
  /// error worth showing.
  @override
  Future<bool> signInWithGoogle() async {
    // google_sign_in's authenticate() is not supported in browsers; Firebase's
    // own popup is the web equivalent and needs no client id.
    if (kIsWeb) return _signInWithGooglePopup();

    await (_googleSignInReady ??= _googleSignIn.initialize(
      serverClientId: _serverClientId,
    ));

    final GoogleSignInAccount account;
    try {
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError(
        'Google sign-in returned no id token. On Android this usually means the '
        'debug keystore SHA-1/SHA-256 is not registered in the Firebase console.',
      );
    }
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    return true;
  }

  /// Codes Firebase uses when the learner closes or replaces the popup.
  static const _dismissedPopupCodes = {
    'popup-closed-by-user',
    'cancelled-popup-request',
    'user-cancelled',
  };

  Future<bool> _signInWithGooglePopup() async {
    try {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return true;
    } on FirebaseAuthException catch (error) {
      if (_dismissedPopupCodes.contains(error.code)) return false;
      rethrow;
    }
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> createAccount(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    // Best effort: the account exists either way, and a failed send should not
    // read as a failed sign-up.
    try {
      await credential.user?.sendEmailVerification();
    } on FirebaseAuthException {
      // Ignored; the learner can still use the app.
    }
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  @override
  bool get needsEmailVerification => _needsVerification(_auth.currentUser);

  @override
  String? get email => _auth.currentUser?.email;

  @override
  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  @override
  Future<bool> reloadNeedsEmailVerification() async {
    await _auth.currentUser?.reload();
    return _needsVerification(_auth.currentUser);
  }

  static bool _needsVerification(User? user) {
    if (user == null || user.emailVerified) return false;
    // Only password accounts. A Google account linked to the same email is
    // already proven to own it.
    final providers = user.providerData.map((p) => p.providerId).toSet();
    return providers.contains('password') && !providers.contains('google.com');
  }

  /// A plain sign-out. The user's data in Firestore is left alone.
  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleSignInReady != null) {
      try {
        await _googleSignIn.signOut();
      } on Exception {
        // Google may already be signed out; the Firebase session is what matters.
      }
    }
  }

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) =>
      _firestore.doc(documentPath(uid, profileCollection, profileDocId));

  static String? _fallbackName(User user) {
    final fromGoogle = user.displayName;
    if (fromGoogle != null && fromGoogle.trim().isNotEmpty) return fromGoogle;
    final email = user.email;
    if (email == null || email.isEmpty) return null;
    return email.split('@').first;
  }

  static String? _resolveServerClientId(String? provided) {
    final candidate = (provided != null && provided.isNotEmpty)
        ? provided
        : _serverClientIdOverride;
    return candidate.isEmpty ? null : candidate;
  }
}
