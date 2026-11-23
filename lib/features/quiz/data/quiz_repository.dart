import 'package:ingrain/core/storage/document_store.dart';
import 'package:ingrain/features/auth/domain/auth_repository.dart';
import 'package:ingrain/features/growth/data/activity_history.dart';

/// A finished daily quiz, as the learner's history keeps it.
class QuizResult {
  /// `2026-11-25`: the learner's own calendar day.
  final String day;
  final int correct;
  final int total;
  final DateTime completedAt;

  /// The words got wrong, to show again on the results screen.
  final List<String> missed;

  /// Sent to the server for the friends leaderboard.
  final bool submitted;

  const QuizResult({
    required this.day,
    required this.correct,
    required this.total,
    required this.completedAt,
    this.missed = const [],
    this.submitted = false,
  });

  bool get isPerfect => correct == total;

  DateTime get date => DateTime.parse(day);

  QuizDay toQuizDay() => QuizDay(day: date, correct: correct, total: total);

  Map<String, dynamic> toMap() => {
    'day': day,
    'correct': correct,
    'total': total,
    'completedAt': completedAt.toUtc().toIso8601String(),
    'missed': missed,
    'submitted': submitted,
  };

  static QuizResult? fromMap(Map<String, dynamic> map) {
    final day = map['day'];
    final correct = map['correct'];
    final total = map['total'];
    if (day is! String || correct is! num || total is! num) return null;
    return QuizResult(
      day: day,
      correct: correct.toInt(),
      total: total.toInt(),
      completedAt:
          DateTime.tryParse(map['completedAt'] as String? ?? '')?.toLocal() ??
          DateTime.parse(day),
      missed: [for (final word in map['missed'] as List? ?? const []) '$word'],
      submitted: map['submitted'] == true,
    );
  }
}

/// Daily quiz results, one document per day under the learner's account.
class QuizRepository {
  static const collection = 'quiz';

  final DocumentStore _store;
  final AuthRepository _auth;

  QuizRepository(this._store, this._auth);

  Future<QuizResult?> result(String day) async {
    final uid = await _auth.ensureUid();
    final doc = await _store.getDoc(uid, collection, day);
    return doc.isEmpty ? null : QuizResult.fromMap(doc);
  }

  Future<List<QuizResult>> all() async {
    final uid = await _auth.ensureUid();
    final docs = await _store.listDocs(uid, collection);
    return [for (final doc in docs) ?QuizResult.fromMap(doc)];
  }

  Future<void> save(QuizResult result) async {
    final uid = await _auth.ensureUid();
    await _store.setDoc(uid, collection, result.day, result.toMap());
  }

  Future<void> markSubmitted(String day) async {
    final uid = await _auth.ensureUid();
    await _store.setDoc(uid, collection, day, {'submitted': true}, merge: true);
  }
}
