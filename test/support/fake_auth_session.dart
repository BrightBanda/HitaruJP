import 'dart:async';

import 'package:ingrain/features/auth/domain/auth_repository.dart';

/// In-memory [AuthSession] whose sign-in surface a test can drive directly.
///
/// Firebase cannot initialise in a unit or widget test, so every test that pumps a
/// real screen needs one of these in place of `authRepositoryProvider`.
class FakeAuthSession implements AuthSession {
  FakeAuthSession({
    this.uid = 'test-uid',
    this.name = 'Tester',
    this.onboarded = true,
  });

  /// Whether a stored [name] comes with a completed onboarding. False models a
  /// learner who signed up before the onboarding flow existed.
  bool onboarded;

  /// Everything written with [updateProfile], merged over the seeded document.
  final Map<String, dynamic> profileFields = {};

  /// Empty means signed out, which is what sends the router to `/onboarding`.
  String uid;
  String? name;
  String? profileError;

  final _controller = StreamController<String>.broadcast();

  /// Set to make the next sign-in throw.
  Object? signInError;

  int ensureProfileCalls = 0;
  int signOutCalls = 0;
  bool googleCancelled = false;
  final List<String> setDisplayNameCalls = [];

  /// Fixed, so a test can prove a caller returns the *stored* timestamp rather than
  /// stamping "now" on every read.
  final DateTime createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);

  @override
  Stream<String> authStateChanges() => _controller.stream;

  @override
  String? get currentUid => uid.isEmpty ? null : uid;

  /// Simulates a Firebase session change. Silent if nothing is listening yet, which
  /// is why tests must build the provider before emitting.
  void emit(String nextUid) {
    uid = nextUid;
    _controller.add(nextUid);
  }

  Future<void> dispose() => _controller.close();

  @override
  Future<String> ensureUid() async {
    if (uid.isEmpty) throw StateError('signed out');
    return uid;
  }

  @override
  Future<String?> get displayName async => name;

  @override
  Future<void> setDisplayName(String value) async {
    setDisplayNameCalls.add(value);
    name = value;
  }

  @override
  Future<String?> profileDisplayName() async => name;

  @override
  Future<Map<String, dynamic>> profileDocument() async {
    if (name == null && profileFields.isEmpty) return <String, dynamic>{};
    return {
      'uid': uid,
      'createdAt': createdAt.toIso8601String(),
      if (name != null && onboarded)
        'onboardingCompletedAt': createdAt.toIso8601String(),
      ...profileFields,
      if (name != null) 'displayName': name,
    };
  }

  @override
  Future<void> updateProfile(Map<String, dynamic> fields) async {
    profileFields.addAll(fields);
    final newName = fields['displayName'];
    if (newName is String) name = newName;
  }

  @override
  Future<void> ensureProfile() async => ensureProfileCalls++;

  @override
  Future<bool> signInWithGoogle() async {
    final error = signInError;
    if (error != null) throw error;
    if (googleCancelled) return false;
    emit('google-uid');
    return true;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    final error = signInError;
    if (error != null) throw error;
    emit('email-uid');
  }

  @override
  Future<void> createAccount(String email, String password) async {
    final error = signInError;
    if (error != null) throw error;
    emit('new-uid');
  }

  final List<String> passwordResetCalls = [];

  /// Set to model an email account that has not been verified yet.
  bool unverified = false;
  int verificationEmailsSent = 0;

  @override
  bool get needsEmailVerification => unverified && uid.isNotEmpty;

  @override
  String? get email => uid.isEmpty ? null : 'tester@example.com';

  @override
  Future<void> sendEmailVerification() async => verificationEmailsSent++;

  @override
  Future<bool> reloadNeedsEmailVerification() async => needsEmailVerification;

  @override
  Future<void> sendPasswordReset(String email) async {
    final error = signInError;
    if (error != null) throw error;
    passwordResetCalls.add(email);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emit('');
  }
}
