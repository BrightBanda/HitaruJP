import 'package:ingrain/features/content/data/youtube_data_api_captions.dart';
import 'package:ingrain/features/content/data/youtube_transcript_fetcher.dart';

/// Where a transcript fetch has got to, so the loading card can say so.
enum TranscriptFetchStage {
  /// The first try.
  fetching,

  /// The first try failed; trying the same source once more.
  retrying,

  /// Asking the HitaruJP server, which fetches captions itself.
  server,

  /// Asking the official YouTube Data API whether captions exist at all.
  officialApi,
}

typedef TranscriptStageListener = void Function(TranscriptFetchStage stage);

/// Fetches a transcript, falling back step by step when a source fails.
///
/// 1. [primary]: YouTube directly on mobile, the server on web.
/// 2. [primary] again after a short pause: most failures are a throttled or
///    flaky request.
/// 3. [server], when there is one besides [primary] (mobile).
/// 4. [officialApi], which cannot download captions but can say whether the
///    video has Japanese ones. "None" becomes a normal no-transcript answer;
///    "some" a failure worth retrying later.
///
/// "No Japanese captions" from any source is an answer, not a failure, and
/// ends the chain.
class FallbackTranscriptFetcher {
  final YoutubeTranscriptFetcher primary;
  final YoutubeTranscriptFetcher? server;
  final YoutubeDataApiCaptions? officialApi;
  final Duration retryDelay;

  const FallbackTranscriptFetcher({
    required this.primary,
    this.server,
    this.officialApi,
    this.retryDelay = const Duration(milliseconds: 1500),
  });

  Future<YoutubeTranscriptResult> fetch(
    String videoId, {
    TranscriptStageListener? onStage,
  }) async {
    YoutubeTranscriptException? lastError;

    Future<YoutubeTranscriptResult?> attempt(
      TranscriptFetchStage stage,
      YoutubeTranscriptFetcher fetcher,
    ) async {
      onStage?.call(stage);
      try {
        return await fetcher.fetch(videoId);
      } on YoutubeTranscriptException catch (error) {
        lastError = error;
        return null;
      }
    }

    final first = await attempt(TranscriptFetchStage.fetching, primary);
    if (first != null) return first;

    await Future<void>.delayed(retryDelay);
    final second = await attempt(TranscriptFetchStage.retrying, primary);
    if (second != null) return second;

    if (server case final server?) {
      final fromServer = await attempt(TranscriptFetchStage.server, server);
      if (fromServer != null) return fromServer;
    }

    final api = officialApi;
    if (api != null && api.isConfigured) {
      onStage?.call(TranscriptFetchStage.officialApi);
      try {
        final track = await api.japaneseTrack(videoId);
        if (track == null) {
          return const YoutubeTranscriptResult(durationSeconds: 0);
        }
        throw const YoutubeTranscriptException(
          'This video has Japanese subtitles, but YouTube would not send '
          'them right now. Try again in a few minutes.',
        );
      } on YoutubeTranscriptException catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        const YoutubeTranscriptException('Could not fetch the transcript.');
  }
}
