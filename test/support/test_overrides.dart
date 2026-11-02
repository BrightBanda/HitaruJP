import 'package:ingrain/core/providers.dart';
import 'package:ingrain/core/storage/local_document_store.dart';
import 'package:ingrain/features/auth/presentation/viewmodel/auth_view_model.dart';
import 'package:ingrain/features/catalog/presentation/viewmodel/catalog_providers.dart';
import 'package:ingrain/features/notifications/presentation/viewmodel/notification_view_model.dart';
import 'package:ingrain/features/profile/presentation/viewmodel/profile_sync_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_repositories.dart';
import 'fake_auth_session.dart';
import 'fake_push_gateway.dart';

export 'fake_api_repositories.dart';
export 'fake_auth_repository.dart';
export 'fake_auth_session.dart';
export 'fake_push_gateway.dart';

/// The overrides every test needs now that user data lives in Firestore.
///
/// `documentStoreProvider` is pointed back at the SharedPreferences store, auth is
/// faked, and the API-backed repositories are fakes, so a test never reaches
/// Firebase or the ingrain API — and, more importantly, never silently talks to
/// the real project. Individual screens can still override the repositories they
/// care about on top of this.
///
/// The return type is deliberately unannotated: Riverpod 3 keeps `Override` internal,
/// so there is no public name to write here.
// ignore: strict_top_level_inference
appTestOverrides(
  SharedPreferences prefs, {
  FakeAuthSession? session,
  FakeProfileSyncRepository? profileSync,
  FakeCatalogRepository? catalog,
  FakePushGateway? pushGateway,
}) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  documentStoreProvider.overrideWithValue(LocalDocumentStore(prefs)),
  authRepositoryProvider.overrideWithValue(session ?? FakeAuthSession()),
  profileSyncRepositoryProvider.overrideWithValue(
    profileSync ?? FakeProfileSyncRepository(),
  ),
  pushGatewayProvider.overrideWithValue(
    pushGateway ?? FakePushGateway(supported: false),
  ),
  catalogRepositoryProvider.overrideWithValue(
    catalog ?? FakeCatalogRepository(),
  ),
];
