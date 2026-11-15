import 'dart:convert';

import 'package:http/http.dart' as http;

class CoreException implements Exception {
  CoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The HTTP client of the loopback API. Every call is a plain JSON request; the
/// core is the only owner of the node, so the window never keeps a second copy
/// of the state.
class CoreClient {
  CoreClient(this.base);

  final String base;
  final http.Client _client = http.Client();

  Future<dynamic> get(String path, {Duration? timeout}) =>
      _send('GET', path, null, timeout);

  Future<dynamic> post(String path, [Object? body, Duration? timeout]) =>
      _send('POST', path, body, timeout);

  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body, null);

  Future<dynamic> delete(String path) => _send('DELETE', path, null, null);

  Future<dynamic> _send(
    String method,
    String path,
    Object? body,
    Duration? timeout,
  ) async {
    final request = http.Request(method, Uri.parse('$base$path'));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final streamed = await _client
        .send(request)
        .timeout(timeout ?? const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    final text = response.body;
    if (response.statusCode >= 400) {
      var message = text.isEmpty ? 'HTTP ${response.statusCode}' : text;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['error'] is String) {
          message = decoded['error'] as String;
        }
      } catch (_) {
        // The raw body is already a usable message.
      }
      throw CoreException(message);
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }
}
