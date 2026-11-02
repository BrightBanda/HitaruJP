import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ingrain/core/config/api_config.dart';
import 'package:ingrain/core/error/app_error.dart';

/// A failed call to the ingrain API, already translated into an [AppError].
class ApiException implements Exception {
  final AppError error;

  const ApiException(this.error);

  @override
  String toString() => 'ApiException(${error.type}: ${error.message})';
}

/// JSON over HTTP to the ingrain API, signed with the learner's Firebase ID token.
///
/// Repositories build on this instead of talking to `http` directly, so timeouts,
/// auth headers and status-to-error mapping are decided in one place.
class ApiClient {
  final http.Client _client;
  final Future<String?> Function() _idToken;
  final Uri _base;
  final Duration _timeout;

  ApiClient({
    required this._client,
    required this._idToken,
    String baseUrl = apiBaseUrl,
    this._timeout = const Duration(seconds: 12),
  }) : _base = Uri.parse(baseUrl);

  Future<Object?> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Object?> put(String path, Object body) =>
      _send('PUT', path, body: body);

  Future<Object?> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<Object?> delete(String path) => _send('DELETE', path);

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final token = await _idToken();
    if (token == null) {
      throw const ApiException(
        AppError(type: AppErrorType.auth, message: 'Sign in to continue.'),
      );
    }

    final uri = _base
        .resolve(path)
        .replace(queryParameters: query?.isEmpty ?? true ? null : query);
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on TimeoutException catch (error) {
      throw ApiException(
        AppError(
          type: AppErrorType.network,
          message: 'The HitaruJP server took too long to answer.',
          exception: error,
        ),
      );
    } catch (error) {
      throw ApiException(
        AppError(
          type: AppErrorType.network,
          message: 'Could not reach the HitaruJP server.',
          exception: error,
        ),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_errorFor(response.statusCode));
    }
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw ApiException(
        AppError.unknown(
          error,
          message: 'The server sent an unreadable answer.',
        ),
      );
    }
  }

  static AppError _errorFor(int status) {
    final (type, message) = switch (status) {
      401 || 403 => (AppErrorType.auth, 'Sign in again to continue.'),
      404 => (AppErrorType.notFound, 'Not found.'),
      422 => (AppErrorType.validation, 'The server rejected that request.'),
      429 => (
        AppErrorType.rateLimited,
        'Too many requests. Try again shortly.',
      ),
      _ => (AppErrorType.unknown, 'The server had a problem ($status).'),
    };
    return AppError(type: type, message: message);
  }
}
