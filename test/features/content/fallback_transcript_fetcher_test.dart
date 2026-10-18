import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ingrain/features/content/data/fallback_transcript_fetcher.dart';
import 'package:ingrain/features/content/data/youtube_data_api_captions.dart';
import 'package:ingrain/features/content/data/youtube_transcript_fetcher.dart';

/// Answers from a script: an exception is thrown, anything else returned.
class ScriptedFetcher extends YoutubeTranscriptFetcher {
  final List<Object> answers;
  int calls = 0;

  ScriptedFetcher(this.answers);

  @override
  Future<YoutubeTranscriptResult> fetch(String videoId) async {
    final answer = answers[calls++];
    if (answer is YoutubeTranscriptException) throw answer;
    return answer as YoutubeTranscriptResult;
  }
}

const _fail = YoutubeTranscriptException('blocked');
const _found = YoutubeTranscriptResult(
  durationSeconds: 60,
  transcriptText: '00:00:01,000 --> 00:00:02,000\nはい',
);

YoutubeDataApiCaptions _api(List<Map<String, Object>> items) =>
    YoutubeDataApiCaptions(
      apiKey: 'test-key',
      client: MockClient((request) async {
        expect(request.url.path, '/youtube/v3/captions');
        expect(request.url.queryParameters['videoId'], 'vid');
        return http.Response(jsonEncode({'items': items}), 200);
      }),
    );

void main() {
  late List<TranscriptFetchStage> stages;

  setUp(() => stages = []);

  Future<YoutubeTranscriptResult> run(FallbackTranscriptFetcher fetcher) =>
      fetcher.fetch('vid', onStage: stages.add);

  test('the first answer wins without any fallback', () async {
    final primary = ScriptedFetcher([_found]);
    final server = ScriptedFetcher([]);

    final result = await run(
      FallbackTranscriptFetcher(primary: primary, server: server),
    );

    expect(result.transcriptText, _found.transcriptText);
    expect(stages, [TranscriptFetchStage.fetching]);
    expect(server.calls, 0);
  });

  test('no Japanese captions is an answer, not a failure', () async {
    final primary = ScriptedFetcher([
      const YoutubeTranscriptResult(durationSeconds: 60),
    ]);

    final result = await run(FallbackTranscriptFetcher(primary: primary));

    expect(result.transcriptText, isNull);
    expect(primary.calls, 1);
  });

  test('retries, then falls back to the server', () async {
    final primary = ScriptedFetcher([_fail, _fail]);
    final server = ScriptedFetcher([_found]);

    final result = await run(
      FallbackTranscriptFetcher(
        primary: primary,
        server: server,
        retryDelay: Duration.zero,
      ),
    );

    expect(result.transcriptText, _found.transcriptText);
    expect(stages, [
      TranscriptFetchStage.fetching,
      TranscriptFetchStage.retrying,
      TranscriptFetchStage.server,
    ]);
  });

  test('the official API settling "no Japanese track" means none', () async {
    final result = await run(
      FallbackTranscriptFetcher(
        primary: ScriptedFetcher([_fail, _fail]),
        officialApi: _api([
          {
            'snippet': {'language': 'en', 'trackKind': 'standard'},
          },
        ]),
        retryDelay: Duration.zero,
      ),
    );

    expect(result.transcriptText, isNull);
    expect(stages.last, TranscriptFetchStage.officialApi);
  });

  test('a Japanese track the sources could not fetch is a failure', () async {
    final fetcher = FallbackTranscriptFetcher(
      primary: ScriptedFetcher([_fail, _fail]),
      officialApi: _api([
        {
          'snippet': {'language': 'ja', 'trackKind': 'asr'},
        },
      ]),
      retryDelay: Duration.zero,
    );

    await expectLater(
      run(fetcher),
      throwsA(
        isA<YoutubeTranscriptException>().having(
          (e) => e.message,
          'message',
          contains('has Japanese subtitles'),
        ),
      ),
    );
  });

  test('without an API key the last source error is reported', () async {
    final fetcher = FallbackTranscriptFetcher(
      primary: ScriptedFetcher([_fail, _fail]),
      officialApi: YoutubeDataApiCaptions(apiKey: ''),
      retryDelay: Duration.zero,
    );

    await expectLater(run(fetcher), throwsA(same(_fail)));
    expect(stages, isNot(contains(TranscriptFetchStage.officialApi)));
  });
}
