import 'package:ingrain/core/network/api_client.dart';
import 'package:ingrain/features/auth/domain/terms_repository.dart';

/// `GET` and `POST /me/terms` on the HitaruJP API.
class RemoteTermsRepository implements TermsRepository {
  final ApiClient _api;

  RemoteTermsRepository(this._api);

  @override
  Future<TermsStatus> status() async => parse(await _api.get('/me/terms'));

  @override
  Future<TermsStatus> accept(String version) async =>
      parse(await _api.post('/me/terms', {'version': version}));

  /// Public for tests.
  static TermsStatus parse(Object? body) {
    final json = Map<String, dynamic>.from(body! as Map);
    return TermsStatus(
      version: json['version'] as String,
      accepted: json['accepted'] as bool,
      termsUrl: json['termsUrl'] as String? ?? termsOfServiceUrl,
      privacyUrl: json['privacyUrl'] as String? ?? privacyPolicyUrl,
    );
  }
}
