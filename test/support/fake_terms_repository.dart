import 'package:ingrain/features/auth/domain/terms_repository.dart';

/// Terms the learner has already accepted, unless a test says otherwise.
class FakeTermsRepository implements TermsRepository {
  FakeTermsRepository({this.accepted = true});

  bool accepted;
  String version = 'test-terms';
  Object? error;
  final List<String> acceptCalls = [];

  @override
  Future<TermsStatus> status() async {
    final error = this.error;
    if (error != null) throw error;
    return TermsStatus(version: version, accepted: accepted);
  }

  @override
  Future<TermsStatus> accept(String version) async {
    final error = this.error;
    if (error != null) throw error;
    acceptCalls.add(version);
    accepted = true;
    return TermsStatus(version: version, accepted: true);
  }
}
