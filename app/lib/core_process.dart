import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api.dart';

/// Owns the lifetime of the `y-node-core` helper.
///
/// The core is shipped next to the application binary (inside
/// `Contents/MacOS` on macOS), so the window can always find it without a
/// configuration file. When an instance is already listening on the port (for
/// example after a restart of the window) the existing one is reused.
class CoreProcess {
  CoreProcess({this.port = 7799});

  final int port;
  Process? _process;
  final List<String> _pending = [];

  String get baseUrl => 'http://127.0.0.1:$port';

  bool get spawned => _process != null;

  /// Recently printed core output, useful for the startup error message.
  List<String> get recentOutput => List.unmodifiable(_pending);

  Future<CoreClient> ensure() async {
    final client = CoreClient(baseUrl);
    if (await _healthy(client)) return client;
    await _start();
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (await _healthy(client)) return client;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final tail = _pending.isEmpty ? '' : '\n${_pending.join('\n')}';
    throw CoreException('The core process did not start$tail');
  }

  Future<bool> _healthy(CoreClient client) async {
    try {
      final data = await client.get(
        '/v1/health',
        timeout: const Duration(seconds: 2),
      );
      return data is Map && data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _start() async {
    final path = corePath();
    if (!File(path).existsSync()) {
      throw CoreException('The core binary is missing: $path');
    }
    _process = await Process.start(path, ['-api-port', '$port']);
    _process!.stdout.transform(utf8.decoder).listen(_record);
    _process!.stderr.transform(utf8.decoder).listen(_record);
    unawaited(
      _process!.exitCode.then((code) {
        _record('core exited with code $code');
        _process = null;
      }),
    );
  }

  void _record(String chunk) {
    for (final line in const LineSplitter().convert(chunk)) {
      final text = line.trim();
      if (text.isEmpty) continue;
      _pending.add(text);
      if (_pending.length > 40) _pending.removeAt(0);
    }
  }

  String corePath() {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows ? 'y-node-core.exe' : 'y-node-core';
    return '$dir${Platform.pathSeparator}$name';
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    // The core treats the end of its stdin pipe as a shutdown request and
    // restores the system proxy on the way out. A hard kill would leave the
    // operating system pointing at a closed port.
    try {
      await process.stdin.close();
    } catch (_) {
      // The pipe is already gone.
    }
    final code = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    if (code == -1) process.kill();
  }
}
