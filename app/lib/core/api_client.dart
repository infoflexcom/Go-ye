import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'session_store.dart';

class ApiException implements Exception {
  const ApiException(this.message, {required this.statusCode});

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

/// Talks only to the single Go-Ye Nest API. API_BASE_URL is deliberately a
/// launch-time setting so Android and Windows can point to the same server.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required SessionStore sessionStore,
    http.Client? httpClient,
  })  : _baseUri = _normaliseBaseUri(baseUrl),
        _sessionStore = sessionStore,
        _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final SessionStore _sessionStore;
  final http.Client _http;

  Future<Map<String, Object?>> get(String path, {Map<String, String>? query}) {
    return _request('GET', path, query: query);
  }

  Future<List<Map<String, Object?>>> getList(String path, {Map<String, String>? query}) async {
    var response = await _rawRequest('GET', path, query: query, authenticated: true);
    if (response.statusCode == 401 && await _refreshSession()) {
      response = await _rawRequest('GET', path, query: query, authenticated: true);
    }
    return _decodeListResponse(response);
  }

  Future<Map<String, Object?>> post(String path, Map<String, Object?> body) {
    return _request('POST', path, body: body);
  }

  Future<Map<String, Object?>> patch(String path, Map<String, Object?> body) {
    return _request('PATCH', path, body: body);
  }

  Future<Map<String, Object?>> postPublic(String path, Map<String, Object?> body) async {
    final response = await _rawRequest('POST', path, body: body, authenticated: false);
    return _decodeObjectResponse(response);
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    var response = await _rawRequest(method, path, body: body, query: query, authenticated: true);
    if (response.statusCode == 401 && await _refreshSession()) {
      response = await _rawRequest(method, path, body: body, query: query, authenticated: true);
    }
    return _decodeObjectResponse(response);
  }

  Future<http.Response> _rawRequest(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    required bool authenticated,
  }) async {
    final headers = <String, String>{'accept': 'application/json'};
    if (body != null) {
      headers['content-type'] = 'application/json';
    }
    if (authenticated) {
      final session = await _sessionStore.readSession();
      if (session == null) {
        throw const ApiException('Your session has ended. Please sign in again.', statusCode: 401);
      }
      headers['authorization'] = 'Bearer ${session.accessToken}';
    }
    final uri = _baseUri.resolve(path).replace(queryParameters: query);
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: encoded);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: encoded);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
  }

  Future<bool> _refreshSession() async {
    final session = await _sessionStore.readSession();
    if (session == null) {
      return false;
    }
    final response = await _rawRequest(
      'POST',
      'auth/refresh',
      body: <String, Object?>{'refreshToken': session.refreshToken},
      authenticated: false,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _sessionStore.clearSession();
      return false;
    }
    try {
      await _sessionStore.writeSession(Session.fromApi(objectFromJson(response.body)));
      return true;
    } on FormatException {
      await _sessionStore.clearSession();
      return false;
    }
  }

  Map<String, Object?> _decodeObjectResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return const <String, Object?>{};
      }
      return objectFromJson(response.body);
    }
    throw _exceptionFor(response);
  }

  List<Map<String, Object?>> _decodeListResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return objectListFromJson(response.body);
    }
    throw _exceptionFor(response);
  }

  ApiException _exceptionFor(http.Response response) {
    var message = 'The server could not complete this request.';
    try {
      final payload = objectFromJson(response.body);
      final value = payload['message'];
      if (value is String) {
        message = value;
      } else if (value is List) {
        final messages = value.whereType<String>();
        if (messages.isNotEmpty) {
          message = messages.join('\n');
        }
      }
    } on FormatException {
      // Keep a safe generic error; server error pages are not shown to users.
    }
    return ApiException(message, statusCode: response.statusCode);
  }

  static Uri _normaliseBaseUri(String value) {
    final uri = Uri.parse(value.trim());
    if (!uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError.value(value, 'baseUrl', 'API_BASE_URL must be an absolute URL.');
    }
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }
}
