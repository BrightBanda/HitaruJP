/// Where the terms of service and privacy policy live. The server sends its
/// own copy with the status; these are for when it cannot be reached.
const termsOfServiceUrl = 'https://hautek.org/terms/hitarujp/';
const privacyPolicyUrl = 'https://hautek.org/privacy/hitarujp/';

/// The terms in force on the server, and whether this learner accepted them.
class TermsStatus {
  final String version;
  final bool accepted;
  final String termsUrl;
  final String privacyUrl;

  const TermsStatus({
    required this.version,
    required this.accepted,
    this.termsUrl = termsOfServiceUrl,
    this.privacyUrl = privacyPolicyUrl,
  });
}

/// The record of the learner's consent, which the server keeps. The API
/// refuses learners who have not accepted the terms in force.
abstract interface class TermsRepository {
  Future<TermsStatus> status();

  /// Records acceptance of [version], the one [status] reported.
  Future<TermsStatus> accept(String version);
}
