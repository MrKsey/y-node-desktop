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

  Future<dynamic> put(String path, [Object? body]) =>
      _send('PUT', path, body, null);

  Future<dynamic> delete(String path) => _send('DELETE', path, null, null);

  Future<dynamic> _send(
    String method,
    String path,
    Object? body,
    Duration? timeout,
  ) async {
    // The core closes idle keep-alive connections while it restarts a node, so
    // a request can fail with "Connection closed before full header was
    // received" even though the action itself is fine. One retry on a fresh
    // connection is enough, but only for a request that can be applied twice:
    // repeating "import this invite" or "add this service" after a lost answer
    // would leave a second copy behind.
    for (var attempt = 0; ; attempt++) {
      try {
        return await _sendOnce(method, path, body, timeout);
      } on http.ClientException catch (error) {
        if (attempt >= 1 || !_canRepeat(method, path, error)) rethrow;
      }
    }
  }

  /// The POST calls the window sends again after a dropped connection. Every
  /// entry is an action whose second run changes nothing: connect, disconnect,
  /// save a setting, run a measurement or read a list.
  static const _repeatablePosts = <String>[
    '/v1/connect',
    '/v1/disconnect',
    '/v1/system-proxy',
    '/v1/country',
    '/v1/peers/probe',
    '/v1/peers/find',
    '/v1/peers/settings',
    '/v1/exit/active',
    '/v1/exit/enabled',
    '/v1/exit/profile',
    '/v1/exit/check',
    '/v1/exit/udp-test',
    '/v1/exit/ipv6-test',
    '/v1/dns/check',
    '/v1/ip',
    '/v1/directory',
  ];

  static bool _canRepeat(
    String method,
    String path,
    http.ClientException error,
  ) {
    if (!_isConnectionDrop(error)) return false;
    if (method != 'POST') return true;
    return _repeatablePosts.any(path.startsWith);
  }

  static bool _isConnectionDrop(http.ClientException error) {
    final text = error.message.toLowerCase();
    return text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('broken pipe');
  }

  Future<dynamic> _sendOnce(
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
    // The timeout covers the whole exchange, headers and body. Waiting only for
    // the headers left a core that stalled mid-answer with a request that never
    // completed: the caller then never polled again, and the Logs page froze on
    // its old snapshot.
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout ?? const Duration(seconds: 30));
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
