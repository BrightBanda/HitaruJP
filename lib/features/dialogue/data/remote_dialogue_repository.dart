import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ingrain/core/config/api_config.dart';
import 'package:ingrain/features/dialogue/data/dialogue_dto.dart';
import 'package:ingrain/features/dialogue/data/local_dialogue_cache.dart';
import 'package:ingrain/features/dialogue/data/sample_dialogue_loader.dart';
import 'package:ingrain/features/dialogue/domain/dialogue.dart';
import 'package:ingrain/features/dialogue/domain/dialogue_repository.dart';

/// The dialogue catalogue: the API's dialogues plus the samples bundled with
/// the app, with an offline cache for the API's.
class RemoteDialogueRepository implements DialogueRepository {
  final http.Client _client;
  final LocalDialogueCache _cache;
  final SampleDialogueLoader? _samples;
  final Uri _baseUri;
  final Duration _timeout;

  @override
  bool isShowingCachedCopy = false;

  /// `timeout` bounds each request. Without it, an unreachable host (say the
  /// emulator-only `10.0.2.2` on a real phone) leaves the screen loading for
  /// as long as the OS takes to give up on the connection.
  RemoteDialogueRepository({
    required this._client,
    required this._cache,
    this._samples,
    String baseUrl = apiBaseUrl,
    this._timeout = const Duration(seconds: 6),
  }) : _baseUri = Uri.parse(baseUrl);

  @override
  Future<List<DialogueSummary>> listSummaries() async {
    final samples = await _loadSamples();
    List<DialogueSummary> catalogue;
    try {
      final response = await _get('/dialogues');
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = decoded['dialogues'] as List;
      catalogue = raw
          .map(
            (value) => DialogueDto.summaryFromMap(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
      await _cache.cacheSummaries(catalogue);
      isShowingCachedCopy = false;
    } catch (_) {
      catalogue = await _cache.getSummaries();
      if (catalogue.isEmpty && samples.isEmpty) rethrow;
      isShowingCachedCopy = true;
    }
    return _withSamples(catalogue, samples);
  }

  @override
  Future<List<DialogueSummary>> listCachedSummaries() async {
    final (catalogue, samples) = await (
      _cache.getSummaries().catchError((Object _) => <DialogueSummary>[]),
      _loadSamples(),
    ).wait;
    return _withSamples(catalogue, samples);
  }

  static List<DialogueSummary> _withSamples(
    List<DialogueSummary> catalogue,
    List<Dialogue> samples,
  ) {
    final ids = {for (final item in catalogue) item.id};
    return [
      ...catalogue,
      ...samples.where((sample) => !ids.contains(sample.id)),
    ];
  }

  @override
  Future<Dialogue> getDialogue(String id) async {
    // Samples ship with the app: never wait on the network for one.
    final sample = (await _loadSamples()).where((d) => d.id == id).firstOrNull;
    if (sample != null) return sample;

    try {
      final response = await _get('/dialogues/$id');
      final dialogue = DialogueDto.fromMap(
        jsonDecode(response.body) as Map<String, dynamic>,
      ).toDomain();
      await _cache.cacheDialogue(dialogue);
      isShowingCachedCopy = false;
      return dialogue;
    } catch (_) {
      final cached = await getCachedDialogue(id);
      if (cached == null) rethrow;
      isShowingCachedCopy = true;
      return cached;
    }
  }

  @override
  Future<Dialogue?> getCachedDialogue(String id) => _cache.getDialogue(id);

  @override
  Future<void> cacheDialogue(Dialogue dialogue) =>
      _cache.cacheDialogue(dialogue);

  Future<http.Response> _get(String path) async {
    final url = _baseUri.resolve(path);
    final response = await _client
        .get(url)
        .timeout(
          _timeout,
          onTimeout: () => throw http.ClientException(
            'No answer from the dialogue API within ${_timeout.inSeconds}s',
            url,
          ),
        );
    _checkResponse(response);
    return response;
  }

  /// Never throws: a broken sample asset must not mask the original error.
  Future<List<Dialogue>> _loadSamples() async {
    try {
      return await _samples?.load() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static void _checkResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Dialogue API returned ${response.statusCode}',
        response.request?.url,
      );
    }
  }
}
