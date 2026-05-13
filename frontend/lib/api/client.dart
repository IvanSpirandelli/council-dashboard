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

  // ── Council builder ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> councils() async {
    final list = await _getList(_u('/councils'));
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> council(String name) =>
      _getJson(_u('/councils/$name'));

  Future<Map<String, dynamic>> putCouncil(
      String name, Map<String, dynamic> body) async {
    final res = await _client.put(
      _u('/councils/$name'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'body': body}),
    );
    if (res.statusCode != 200) {
      throw http.ClientException('PUT /councils/$name → ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> councilPreview(
    String name,
    String agentId, {
    String? extraContext,
  }) {
    return _postJson(
      _u('/councils/$name/agents/$agentId/preview'),
      {'extra_context': extraContext},
    );
  }

  Future<Map<String, dynamic>> councilPreviewFromBody(
    String name,
    String agentId,
    Map<String, dynamic> body, {
    String? extraContext,
  }) {
    return _postJson(
      _u('/councils/$name/agents/$agentId/preview-from-body'),
      {'body': body, 'extra_context': extraContext},
    );
  }

  Future<Map<String, dynamic>> councilResource(
          String name, String resourceName) =>
      _getJson(_u('/councils/$name/resources/$resourceName'));

  Future<Map<String, dynamic>> putCouncilResource(
      String name, String resourceName, String body) async {
    final res = await _client.put(
      _u('/councils/$name/resources/$resourceName'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'body': body}),
    );
    if (res.statusCode != 200) {
      throw http.ClientException(
          'PUT /councils/$name/resources/$resourceName → ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Council-centric session + performance ─────────────────────────

  Future<Map<String, dynamic>> councilSession(String name) =>
      _getJson(_u('/councils/$name/session'));

  Future<Map<String, dynamic>> councilRound(String name, String roundId) =>
      _getJson(_u('/councils/$name/rounds/$roundId'));

  Future<Map<String, dynamic>> councilLlmArtifact(
          String name, String roundId, String filename) =>
      _getJson(_u('/councils/$name/rounds/$roundId/llm/$filename'));

  Future<Map<String, dynamic>> councilRoundOneRoundCommand(
          String name, String roundId) =>
      _getJson(_u('/councils/$name/rounds/$roundId/one-round-command'));

  Future<Map<String, dynamic>> councilTopology(String name) =>
      _getJson(_u('/topology', {'council': name}));

  Future<Map<String, dynamic>> councilNodeSource(
          String name, String nodeId) =>
      _getJson(_u('/councils/$name/nodes/$nodeId/source'));

  Future<Map<String, dynamic>> councilPerformance(
    String name, {
    String sort = 'test_pearson_r_mean',
    bool ascending = false,
    int? limit,
  }) {
    return _getJson(_u('/councils/$name/performance', {
      'sort': sort,
      'ascending': ascending,
      if (limit != null) 'limit': limit,
    }));
  }

  Future<Map<String, dynamic>> councilLaunchConfig(String name) =>
      _getJson(_u('/councils/$name/launch-config'));

  Future<Map<String, dynamic>> setCouncilLaunchConfig(
    String name, {
    required List<String> cmd,
    String? cwd,
    Map<String, String>? env,
  }) =>
      _postJson(_u('/councils/$name/launch-config'), {
        'cmd': cmd,
        if (cwd != null) 'cwd': cwd,
        'env': env ?? <String, String>{},
      });

  Future<Map<String, dynamic>> councilStart(String name) =>
      _postJson(_u('/councils/$name/start'));

  Future<Map<String, dynamic>> councilStop(String name, {bool force = false}) =>
      _postJson(_u('/councils/$name/stop', {'force': force}));

  Future<Map<String, dynamic>> councilClearStop(String name) =>
      _postJson(_u('/councils/$name/clear-stop'));

  void close() => _client.close();
}

@visibleForTesting
String defaultBaseUrlForTests() => _defaultBaseUrl;
