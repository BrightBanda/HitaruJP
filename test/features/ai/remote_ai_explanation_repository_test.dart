import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ingrain/core/error/app_error.dart';
import 'package:ingrain/features/ai/data/remote_ai_explanation_repository.dart';
import 'package:ingrain/features/ai/domain/ai_explanation.dart';

const ExplainRequest request = (
  text: '食べちゃった',
  kind: ExplainKind.sentence,
  context: 'もう食べちゃった',
);

const body = {
  'translation': 'I ended up eating it.',
  'reading': null,
  'meaning': 'Ate it, with a hint of regret.',
  'partOfSpeech': null,
  'grammar': [
    {'point': '〜てしまう', 'explanation': 'completion or regret'},
  ],
  'nuance': 'ちゃう is the casual contraction.',
  'formality': 'casual',
  'alternatives': [
    {'japanese': '食べてしまいました', 'note': 'polite'},
  ],
};

RemoteAiExplanationRepository repository(
  MockClientHandler handler, {
  String? token = 'id-token',
  Duration timeout = const Duration(seconds: 5),
}) => RemoteAiExplanationRepository(
  client: MockClient(handler),
  idToken: () async => token,
  baseUrl: 'https://api.example.test',
  timeout: timeout,
);

Future<AppErrorType> failureType(Future<AiExplanation> future) async {
  try {
    await future;
  } on AiExplanationException catch (error) {
    return error.error.type;
  }
  fail('expected an AiExplanationException');
}

void main() {
  test(
    'posts the request with the bearer token and parses the answer',
    () async {
      late http.Request sent;
      final explanation = await repository((req) async {
        sent = req;
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }).explain(request);

      expect(sent.url.toString(), 'https://api.example.test/ai/explain');
      expect(sent.headers['Authorization'], 'Bearer id-token');
      expect(jsonDecode(sent.body), {
        'text': '食べちゃった',
        'kind': 'sentence',
        'context': 'もう食べちゃった',
      });
      expect(explanation.translation, 'I ended up eating it.');
      expect(explanation.grammar.single.point, '〜てしまう');
      expect(explanation.alternatives.single.japanese, '食べてしまいました');
      expect(explanation.formality, 'casual');
    },
  );

  test('notes combine meaning, grammar and nuance', () {
    final notes = RemoteAiExplanationRepository.parse(body).toNotes();

    expect(notes, contains('Ate it, with a hint of regret.'));
    expect(notes, contains('• 〜てしまう: completion or regret'));
    expect(notes, contains('ちゃう is the casual contraction.'));
  });

  test('refuses without a signed-in user and never calls the server', () async {
    var called = false;
    final type = await failureType(
      repository((_) async {
        called = true;
        return http.Response('{}', 200);
      }, token: null).explain(request),
    );

    expect(type, AppErrorType.auth);
    expect(called, isFalse);
  });

  test('maps server statuses into the app error model', () async {
    Future<AppErrorType> forStatus(int status) => failureType(
      repository((_) async => http.Response('{}', status)).explain(request),
    );

    expect(await forStatus(401), AppErrorType.auth);
    expect(await forStatus(429), AppErrorType.rateLimited);
    expect(await forStatus(422), AppErrorType.validation);
    expect(await forStatus(502), AppErrorType.unknown);
  });

  group('the daily allowance', () {
    String limitBody(int limit, String tier) => jsonEncode({
      'detail': {
        'code': 'daily_limit_reached',
        'limit': limit,
        'tier': tier,
        'message': 'daily limit reached',
      },
    });

    String? messageFor(http.Response response) =>
        RemoteAiExplanationRepository.errorFor(response).error.message;

    test('tells a free learner how many they had, and about premium', () {
      final message = messageFor(http.Response(limitBody(6, 'free'), 429));
      expect(message, contains('6 free AI explanations'));
      expect(message, contains('Premium'));
    });

    test('tells a premium learner to come back tomorrow', () {
      final message = messageFor(http.Response(limitBody(20, 'premium'), 429));
      expect(message, contains('all 20 AI explanations'));
      expect(message, isNot(contains('Premium')));
    });

    test('a plain 429 still means the AI is busy', () {
      expect(
        messageFor(http.Response('{"detail": "busy"}', 429)),
        'The AI is busy. Try again shortly.',
      );
    });
  });

  test('a silent server times out as a network error', () async {
    final type = await failureType(
      repository(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 50),
      ).explain(request),
    );

    expect(type, AppErrorType.network);
  });
}
