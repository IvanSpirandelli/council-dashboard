import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Default backend address. Override at runtime via
/// `flutter run --dart-define=DASHBOARD_BASE_URL=http://...`.
const String _defaultBaseUrl =
    String.fromEnvironment('DASHBOARD_BASE_URL', defaultValue: 'http://127.0.0.1:8765');

class DashboardApi {
  DashboardApi({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  final String baseUrl;
  final http.Client _client = http.Client();

  Uri _u(String path, [Map<String, dynamic>? query]) {
    final qp = query?.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    return Uri.parse('$baseUrl$path').replace(queryParameters: qp);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('GET $uri → ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> _getList(Uri uri) async {
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('GET $uri → ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, [Object? body]) async {
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw http.ClientException('POST $uri → ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> health() => _getJson(_u('/health'));

  Future<Map<String, dynamic>> topology() => _getJson(_u('/topology'));

  Future<List<Map<String, dynamic>>> sessions() async {
    final list = await _getList(_u('/sessions'));
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> session(String sessionId) =>
      _getJson(_u('/sessions/$sessionId'));

  Future<Map<String, dynamic>> round(String sessionId, String roundId) =>
      _getJson(_u('/sessions/$sessionId/rounds/$roundId'));

  Future<Map<String, dynamic>> llmArtifact(
      String sessionId, String roundId, String filename) {
    return _getJson(_u('/sessions/$sessionId/rounds/$roundId/llm/$filename'));
  }

  Future<Map<String, dynamic>> performanceTable({
    String? session,
    String? roundId,
    String sort = 'cl2',
    bool asc = false,
    bool allVariants = false,
  }) {
    return _getJson(_u('/performance-table', {
      if (session != null) 'session': session,
      if (roundId != null) 'round_id': roundId,
      'sort': sort,
      'asc': asc,
      'all_variants': allVariants,
    }));
  }

  Future<Map<String, dynamic>> stop(String sessionId, {bool force = false}) =>
      _postJson(_u('/sessions/$sessionId/stop', {'force': force}));

  Future<Map<String, dynamic>> start(String sessionId) =>
      _postJson(_u('/sessions/$sessionId/start'));

  Future<Map<String, dynamic>> clearStop(String sessionId) =>
      _postJson(_u('/sessions/$sessionId/clear-stop'));

  void close() => _client.close();
}

@visibleForTesting
String defaultBaseUrlForTests() => _defaultBaseUrl;
