import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/storage/local_document_store.dart';
import 'package:ingrain/features/auth/data/user_profile_dto.dart';
import 'package:ingrain/features/auth/domain/auth_state.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_session.dart';

class DelayedSetDisplayNameSession extends FakeAuthSession {
  DelayedSetDisplayNameSession({super.uid, super.name});

  final Completer<void> gate = Completer<void>();

  @override
  Future<void> setDisplayName(String value) async {
    setDisplayNameCalls.add(value);
    await gate.future;
    name = value;
  }
}

void main() {
  group('LocalDocumentStore', () {
    late LocalDocumentStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = LocalDocumentStore(prefs);
    });

    test('setDoc and getDoc round-trip', () async {
      await store.setDoc('uid1', 'items', 'doc1', {
        'name': 'test',
        'count': 42,
      });
      final doc = await store.getDoc('uid1', 'items', 'doc1');
      expect(doc['name'], 'test');
      expect(doc['count'], 42);
    });

    test('merge updates existing data without losing other fields', () async {
      await store.setDoc('uid1', 'items', 'doc1', {
        'name': 'test',
        'count': 42,
      });
      await store.setDoc('uid1', 'items', 'doc1', {'count': 99}, merge: true);
      final doc = await store.getDoc('uid1', 'items', 'doc1');
      expect(doc['name'], 'test');
      expect(doc['count'], 99);
    });

    test('deleteDoc removes the document', () async {
      await store.setDoc('uid1', 'items', 'doc1', {'name': 'test'});
      await store.deleteDoc('uid1', 'items', 'doc1');
      expect(await store.getDoc('uid1', 'items', 'doc1'), isEmpty);
    });

    test('listDocs returns all documents', () async {
      await store.setDoc('uid1', 'items', 'doc1', {'name': 'a'});
      await store.setDoc('uid1', 'items', 'doc2', {'name': 'b'});
      expect((await store.listDocs('uid1', 'items')).length, 2);
    });

    test('user-scoping prevents cross-user access', () async {
      await store.setDoc('uid1', 'items', 'doc1', {'name': 'a'});
      await store.setDoc('uid2', 'items', 'doc1', {'name': 'b'});
      expect((await store.getDoc('uid1', 'items', 'doc1'))['name'], 'a');
      expect((await store.getDoc('uid2', 'items', 'doc1'))['name'], 'b');
    });

    test('getDoc returns empty map for non-existent document', () async {
      expect(await store.getDoc('uid1', 'items', 'nonexistent'), isEmpty);
    });

    test('the legacy key prefix is what first launch cleans up', () {
      expect(LocalDocumentStore.legacyKeyPrefix, 'local_store_');
    });
  });

  group('UserProfileDto', () {
    test('toDomain maps correctly', () {
      final profile = UserProfileDto(
        uid: 'test-uid',
        displayName: 'Test User',
        createdAt: DateTime(2024, 1, 1),
      ).toDomain();
      expect(profile.uid, 'test-uid');
      expect(profile.displayName, 'Test User');
      expect(profile.createdAt, DateTime(2024, 1, 1));
    });

    test('fromMapSafe returns null for empty map', () {
      expect(UserProfileDto.fromMapSafe({}), isNull);
    });

    test('fromMapSafe returns null when uid is null', () {
      expect(UserProfileDto.fromMapSafe({'displayName': 'Test'}), isNull);
    });

    test('fromMapSafe parses valid map', () {
      final profile = UserProfileDto.fromMapSafe({
        'uid': 'uid123',
        'displayName': 'Alice',
        'createdAt': '2024-01-01T00:00:00.000',
      });
      expect(profile?.uid, 'uid123');
      expect(profile?.displayName, 'Alice');
      expect(profile?.createdAt, DateTime(2024, 1, 1));
    });
  });

  group('AuthState', () {
    test('loading state is not onboarded', () {
      const state = AuthState.loading();
      expect(state.isLoading, isTrue);
      expect(state.isOnboarded, isFalse);
    });

    test('ready state without displayName is not onboarded', () {
      const state = AuthState.ready(uid: 'uid');
      expect(state.isSignedIn, isTrue);
      expect(state.isOnboarded, isFalse);
    });

    test('ready state with displayName is onboarded', () {
      const state = AuthState.ready(uid: 'uid', displayName: 'Alice');
      expect(state.isOnboarded, isTrue);
    });

    test('signedOut is neither loading nor onboarded', () {
      const state = AuthState.signedOut();
      expect(state.isLoading, isFalse);
      expect(state.isSignedIn, isFalse);
      expect(state.isOnboarded, isFalse);
    });

    test('a blank uid is not signed in even with a name', () {
      const state = AuthState.ready(uid: '', displayName: 'Alice');
      expect(state.isSignedIn, isFalse);
      expect(state.isOnboarded, isFalse);
    });

    test('a whitespace-only name does not count as onboarded', () {
      const state = AuthState.ready(uid: 'uid', displayName: '   ');
      expect(state.isOnboarded, isFalse);
    });
  });

  group('AuthViewModel', () {
    late FakeAuthSession session;
    late ProviderContainer container;

    AuthViewModel build() => container.read(authViewModelProvider.notifier);

    /// A broadcast stream delivers on a microtask, and `_applySession` then awaits
    /// two more futures before it writes state.
    Future<void> pump() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      // Fresh install: nobody is signed in until a test emits a session.
      session = FakeAuthSession(uid: '');
      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(session),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      // ProviderContainer is lazy: force the notifier to build now so it is already
      // subscribed to the auth stream before a test emits a session change.
      container.read(authViewModelProvider);
      addTearDown(() async {
        container.dispose();
        await session.dispose();
      });
    });

    test('settles on signed out without waiting for the stream', () async {
      // A silent stream must not strand the app on a spinner: the initial sync off
      // `currentUid` is what settles it.
      await pump();

      expect(container.read(authViewModelProvider).isLoading, isFalse);
      expect(container.read(authViewModelProvider).isSignedIn, isFalse);
    });

    test('an empty stream emission also lands on signed out', () async {
      session.emit('');
      await pump();
      expect(container.read(authViewModelProvider).isSignedIn, isFalse);
    });

    test(
      'a signed-in session seeds the profile and picks up the name',
      () async {
        session.name = 'Aiko';
        session.emit('user-1');
        await pump();

        final state = container.read(authViewModelProvider);
        expect(state.isSignedIn, isTrue);
        expect(state.isOnboarded, isTrue);
        expect(
          session.ensureProfileCalls,
          0,
          reason: 'the profile already exists, so nothing is seeded',
        );
      },
    );

    test(
      'a signed-in session with no stored name is not onboarded yet',
      () async {
        session.name = null;
        session.emit('user-1');
        await pump();

        expect(container.read(authViewModelProvider).isSignedIn, isTrue);
        expect(container.read(authViewModelProvider).isOnboarded, isFalse);
        expect(
          session.ensureProfileCalls,
          1,
          reason: 'no profile yet: seed it',
        );
      },
    );

    test(
      'a returning learner starts from the profile cached on the device',
      () async {
        session.name = 'Aiko';
        session.emit('user-1');
        await pump();

        // The next launch: same signed-in user, profile not yet read.
        final next = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthSession(uid: 'user-1'),
            ),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
        );
        addTearDown(next.dispose);

        final state = next.read(authViewModelProvider);
        expect(state.isLoading, isFalse);
        expect(state.isOnboarded, isTrue);
        expect(state.displayName, 'Aiko');
      },
    );

    test('completeOnboarding stores the name and flips isOnboarded', () async {
      session.emit('user-1');
      await pump();

      await build().completeOnboarding(displayName: '  Aiko  ');

      final state = container.read(authViewModelProvider);
      expect(state.displayName, 'Aiko');
      expect(state.isOnboarded, isTrue);
    });

    test(
      'completeOnboarding marks the user onboarded before persistence resolves',
      () async {
        final blocked = DelayedSetDisplayNameSession(
          uid: 'user-1',
          name: 'Old',
        );
        final blockedContainer = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(blocked),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
        );
        addTearDown(() async {
          blockedContainer.dispose();
          await blocked.dispose();
        });

        blockedContainer.read(authViewModelProvider);
        blocked.emit('user-1');
        await pump();

        final future = blockedContainer
            .read(authViewModelProvider.notifier)
            .completeOnboarding(displayName: 'Aiko');

        expect(
          blockedContainer.read(authViewModelProvider).isOnboarded,
          isTrue,
        );

        blocked.gate.complete();
        await future;
        expect(
          blockedContainer.read(authViewModelProvider).displayName,
          'Aiko',
        );
      },
    );

    test('a failed sign-in surfaces an error and stays signed out', () async {
      session.signInError = StateError('popup closed');

      final ok = await build().signInWithGoogle();

      expect(ok, isFalse);
      final state = container.read(authViewModelProvider);
      expect(state.isSignedIn, isFalse);
      expect(state.error, contains('popup closed'));
    });

    test('a cancelled Google sign-in is not an error', () async {
      session.googleCancelled = true;

      expect(await build().signInWithGoogle(), isFalse);
      expect(container.read(authViewModelProvider).error, isNull);
    });

    test('email sign-in and account creation both reach the session', () async {
      await build().signInWithEmail('aiko@example.com', 'hunter2');
      await pump();
      expect(container.read(authViewModelProvider).isSignedIn, isTrue);

      await build().createAccount('ken@example.com', 'hunter2');
      await pump();
      expect(container.read(authViewModelProvider).uid, 'new-uid');
    });

    test('signOut is a plain sign-out and never deletes the profile', () async {
      session.name = 'Aiko';
      session.emit('user-1');
      await pump();

      await build().signOut();
      await pump();

      expect(session.signOutCalls, 1);
      final state = container.read(authViewModelProvider);
      expect(state.isSignedIn, isFalse);
      // Nothing in AuthSession can delete, so the stored profile survives intact.
      // The old local implementation's sign-out wiped this document.
      expect(session.name, 'Aiko');
      expect((await session.profileDocument())['displayName'], 'Aiko');
    });

    test('profile reads the stored document, not the clock', () async {
      session.name = 'Aiko';
      session.emit('user-1');
      await pump();

      final profile = await build().profile();
      expect(profile, isNotNull);
      expect(profile!.uid, 'user-1');
      expect(profile.createdAt, session.createdAt);
      expect(
        profile.createdAt,
        isNot(DateTime.now()),
        reason: 'createdAt must come from the stored document',
      );
    });

    test('profile is null while signed out', () async {
      session.emit('');
      await pump();
      expect(await build().profile(), isNull);
    });
  });
}
