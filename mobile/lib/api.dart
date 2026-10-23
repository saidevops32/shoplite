import 'dart:convert';

import 'package:http/http.dart' as http;

// Set when building: flutter build apk --dart-define=API_BASE=http://<gateway-ip>
const String kBaseUrl = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2');

class ApiException implements Exception {
  final String message;
  final int status;

  ApiException(this.message, this.status);

  @override
  String toString() => message;
}

class Api {
  String? token;

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$kBaseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };


  dynamic _decode(http.Response r) {
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final message = (body is Map && body['error'] is String)
        ? body['error'] as String
        : 'Request failed (${r.statusCode})';
    throw ApiException(message, r.statusCode);
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) async {
    final r = await http.get(_uri(path, query), headers: _headers).timeout(const Duration(seconds: 15));
    return _decode(r);
  }

  Future<dynamic> post(String path, Object body) async {
    final r = await http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _decode(r);
  }
}
