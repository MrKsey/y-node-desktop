import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'core_process.dart';
import 'models.dart';

/// The single source of truth of the window. It polls the core once per second
/// for the tunnel counters and every few seconds for the slower lists.
class AppState extends ChangeNotifier {
  AppState(this.core);

  final CoreProcess core;
  CoreClient? _client;

  TunnelState state = const TunnelState();
  List<PeerStatus> peers = const [];
  List<String> configuredPeers = const [];
  List<ExitProfile> exits = const [];
  List<LogLine> logs = const [];
  CoreConfig config = CoreConfig();
  String privateKey = '';
  String activeExitId = '';
  bool exitEnabled = false;

  bool ready = false;
  bool busy = false;
  bool probeRunning = false;
  bool autoPeersRunning = false;
  String? error;
  String? notice;

  Timer? _fast;
  Timer? _slow;

  Future<void> start() async {
    try {
      _client = await core.ensure();
      await refresh();
      await refreshLists();
      await loadConfig();
      ready = true;
      _fast = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
      _slow = Timer.periodic(const Duration(seconds: 4), (_) => refreshLists());
      notifyListeners();
    } catch (e) {
      error = _message(e);
      notifyListeners();
    }
  }

  CoreClient get client {
    final client = _client;
    if (client == null) throw CoreException('The core is not running yet');
    return client;
  }

  Future<void> refresh() async {
    if (_client == null) return;
    try {
      final data = await client.get('/v1/state');
      if (data is Map<String, dynamic>) {
        state = TunnelState.fromJson(data);
      }
    } catch (e) {
      if (state.running) error = _message(e);
    }
    notifyListeners();
  }

  Future<void> refreshLists() async {
    if (_client == null) return;
    try {
      final peersJson = await client.get('/v1/peers');
      if (peersJson is Map) {
        peers = [
          for (final item in (peersJson['live'] as List? ?? const []))
            PeerStatus.fromJson(item as Map<String, dynamic>),
        ];
        configuredPeers = [
          for (final item in (peersJson['configured'] as List? ?? const []))
            '$item',
        ];
      }
      final exitJson = await client.get('/v1/exit');
      if (exitJson is Map) {
        exits = [
          for (final item in (exitJson['profiles'] as List? ?? const []))
            ExitProfile.fromJson(item as Map<String, dynamic>),
        ];
        activeExitId = exitJson['activeId'] as String? ?? '';
        exitEnabled = exitJson['enabled'] as bool? ?? false;
      }
    } catch (_) {
      // The fast loop reports the connection errors; lists are best effort.
    }
    notifyListeners();
  }

  Future<void> refreshLogs() async {
    try {
      final data = await client.get('/v1/logs');
      if (data is List) {
        logs = [
          for (final item in data)
            LogLine.fromJson(item as Map<String, dynamic>),
        ].reversed.toList();
      }
    } catch (_) {
      // The log tab shows the last successful snapshot.
    }
    notifyListeners();
  }

  Future<void> loadConfig() async {
    final data = await client.get('/v1/config');
    if (data is! Map<String, dynamic>) return;
    config = CoreConfig.fromJson(data);
    privateKey = data['privateKey'] as String? ?? '';
    notifyListeners();
  }

  Future<void> saveConfig(CoreConfig next, {String? key}) async {
    await _run(() async {
      final data = await client.put('/v1/config', {
        ...next.toJson(
          privateKey: key ?? privateKey,
          peers: configuredPeers,
          exits: exits,
          activeId: activeExitId,
          exitEnabled: exitEnabled,
        ),
        'privateKey': key ?? privateKey,
      });
      if (data is Map<String, dynamic>) {
        config = CoreConfig.fromJson(data);
        privateKey = data['privateKey'] as String? ?? privateKey;
      }
      notice = 'Settings saved';
    });
  }

  Future<void> connect() => _run(() => client.post('/v1/connect'));

  Future<void> disconnect() => _run(() => client.post('/v1/disconnect'));

  Future<void> setSystemProxy(bool enabled) =>
      _run(() => client.post('/v1/system-proxy', {'enabled': enabled}));

  Future<void> addPeer(String uri) => _run(() async {
    await client.post('/v1/peers', {'uri': uri.trim()});
    notice = 'Peer added';
  });

  Future<void> removePeer(String uri) => _run(() async {
    await client.delete('/v1/peers?uri=${Uri.encodeQueryComponent(uri)}');
    notice = 'Peer removed';
  });

  Future<void> autoPeers() async {
    autoPeersRunning = true;
    notifyListeners();
    await _run(() async {
      final data = await client.post(
        '/v1/peers/auto',
        null,
        const Duration(seconds: 120),
      );
      final list = (data is Map ? data['peers'] as List? : null) ?? const [];
      if (list.isEmpty) {
        throw CoreException('No public peers answered');
      }
      for (final item in list) {
        try {
          await client.post('/v1/peers', {'uri': '$item'});
        } catch (_) {
          // A duplicate is fine, the core keeps one copy anyway.
        }
      }
      notice = 'Added ${list.length} public peers';
    }, refreshAfter: true);
    autoPeersRunning = false;
    notifyListeners();
  }

  Future<String> probePeers() async {
    probeRunning = true;
    notifyListeners();
    try {
      final data = await client.post('/v1/peers/probe', {
        'uris': [for (final peer in peers) peer.uri],
      }, const Duration(seconds: 90));
      final list = data is List ? data : const [];
      return [
        for (final item in list)
          if (item is Map)
            '${item['uri']}: ${item['up'] == true ? 'up ${item['latencyMs'] ?? 0} ms' : (item['error'] ?? 'down')}',
      ].join('\n');
    } catch (e) {
      return _message(e);
    } finally {
      probeRunning = false;
      notifyListeners();
    }
  }

  Future<void> addExitLink(String link) => _run(() async {
    await client.post('/v1/exit/link', {'link': link.trim()});
    notice = 'Exit node added';
  });

  Future<void> setActiveExit(String id) => _run(
    () => client.post('/v1/exit/active', {'id': id}),
    refreshAfter: true,
  );

  Future<void> setExitEnabled(bool enabled) => _run(
    () => client.post('/v1/exit/enabled', {'enabled': enabled}),
    refreshAfter: true,
  );

  Future<void> removeExit(String id) => _run(
    () => client.delete('/v1/exit?id=${Uri.encodeQueryComponent(id)}'),
    refreshAfter: true,
  );

  Future<String> checkExit() async {
    try {
      final data = await client.post(
        '/v1/exit/check',
        null,
        const Duration(seconds: 60),
      );
      if (data is Map) {
        if (data['ok'] == true) {
          return 'Exit node answered: ${data['dnsAddress']}:${data['dnsPort']}';
        }
        return '${data['message'] ?? data['error'] ?? 'The exit node did not answer'}';
      }
      return 'The exit node did not answer';
    } catch (e) {
      return _message(e);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool refreshAfter = false,
  }) async {
    busy = true;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      try {
        await refresh();
        if (refreshAfter) await refreshLists();
      } catch (_) {
        // The error above already explains the failure.
      }
      notifyListeners();
    }
  }

  void clearMessages() {
    error = null;
    notice = null;
    notifyListeners();
  }

  String _message(Object e) => e is CoreException ? e.message : '$e';

  @override
  void dispose() {
    _fast?.cancel();
    _slow?.cancel();
    unawaited(core.stop());
    super.dispose();
  }
}
