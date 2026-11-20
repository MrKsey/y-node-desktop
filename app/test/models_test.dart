import 'package:flutter_test/flutter_test.dart';
import 'package:y_node_desktop/models.dart';

void main() {
  group('TunnelState', () {
    test('reads every counter of the core', () {
      final state = TunnelState.fromJson({
        'running': true,
        'address': '201:2df4:1e5a:7a1f:9e42:6f39:1b23:4c56',
        'subnet': '300:2df4:1e5a:7a1f::/64',
        'publicKey': 'abcdef',
        'peersUp': 2,
        'peersTotal': 3,
        'rxBytes': 1024,
        'txBytes': 2048,
        'openConnections': 4,
        'totalConnections': 9,
        'exitEnabled': true,
        'exitName': 'exit-1',
        'exitState': 'connected',
        'proxyHttp': '127.0.0.1:7890',
        'proxySocks': '127.0.0.1:7891',
        'systemProxy': true,
        'systemProxyAddress': '127.0.0.1:7890',
        'uptimeSeconds': 61,
      });
      expect(state.running, isTrue);
      expect(state.address, startsWith('201:'));
      expect(state.peersUp, 2);
      expect(state.peersTotal, 3);
      expect(state.rxBytes, 1024);
      expect(state.openConnections, 4);
      expect(state.exitEnabled, isTrue);
      expect(state.exitName, 'exit-1');
      expect(state.systemProxy, isTrue);
      expect(state.uptimeSeconds, 61);
    });

    test('falls back to the disconnected defaults', () {
      final state = TunnelState.fromJson(const {});
      expect(state.running, isFalse);
      expect(state.address, isEmpty);
      expect(state.peersTotal, 0);
    });
  });

  group('PeerStatus', () {
    test('parses the live peer list', () {
      final peer = PeerStatus.fromJson({
        'uri': 'tls://ralsei.ru:12345',
        'up': true,
        'inbound': false,
        'latencyMs': 42.5,
        'rxBytes': 10,
        'txBytes': 20,
      });
      expect(peer.up, isTrue);
      expect(peer.latencyMs, 42.5);
      expect(peer.rxBytes, 10);
    });
  });

  group('ExitProfile', () {
    test('keeps the default ports of an X-Node link', () {
      final profile = ExitProfile.fromJson({
        'id': 'abc',
        'name': 'Exit',
        'address': '202:cbff:1e5a:7a1f::1',
      });
      expect(profile.socksPort, 1080);
      expect(profile.apiPort, 1080);
      expect(profile.dnsPort, 53);
    });
  });

  group('CoreConfig', () {
    test('serialises the edited fields back to the core shape', () {
      final config = CoreConfig(
        bind: '127.0.0.1',
        httpPort: '7890',
        socksPort: '7891',
        mtu: '1420',
        yggDns: '308:84:68:55::, 308:25:40:bd::',
        systemDns: '',
        exitDns: '',
        fallbackDirect: false,
        localDns: true,
        systemProxy: true,
        autoConnect: true,
      );
      final json = config.toJson(
        privateKey: 'key',
        peers: const ['tls://example.com:12345'],
        exits: const [],
        activeId: '',
        exitEnabled: false,
      );
      expect(json['privateKey'], 'key');
      expect(json['mtu'], 1420);
      expect(json['httpPort'], 7890);
      expect(json['systemProxy'], isTrue);
      expect(json['exitFallbackDirect'], isFalse);
      expect(json['yggDns'], hasLength(2));
    });

    test('reads lists of DNS servers as a comma separated string', () {
      final config = CoreConfig.fromJson({
        'yggDns': ['308:84:68:55::', '308:25:40:bd::'],
        'httpPort': 7890,
        'socksPort': 7891,
        'mtu': 1280,
      });
      expect(config.yggDns, '308:84:68:55::, 308:25:40:bd::');
      expect(config.httpPort, '7890');
    });

    test('a fresh install uses Frankfurt, Amsterdam and the system proxy', () {
      final config = CoreConfig();
      expect(splitList(config.yggDns), ['308:84:68:55::', '308:62:45:62::']);
      expect(config.systemProxy, isTrue);
      // A file written before the switch existed keeps the app default too.
      expect(CoreConfig.fromJson(const {}).systemProxy, isTrue);
    });

    test('reads the built-in catalogue of the Services page', () {
      final config = CoreConfig.fromJson({
        'services': [
          {
            'id': 'builtin:directory',
            'title': 'Yggdrasil Web directory',
            'url': 'http://[21e:a51c:885b:7db0:166e:927:98cd:d186]/',
            'builtIn': true,
          },
          {'id': 'user:mine', 'title': 'Mine', 'url': 'http://[200::1]/'},
        ],
      });
      expect(config.services, hasLength(2));
      expect(config.services.first.id, 'builtin:directory');
      expect(config.services.first.builtIn, isTrue);
      expect(config.services.last.builtIn, isFalse);
    });

    test('carries the peer, DNS and exit switches of the Android client', () {
      final config = CoreConfig.fromJson({
        'peerCount': 5,
        'peerAutoReplace': false,
        'peerDeadTimeout': '2m',
        'peerCheckInterval': '45s',
        'dnsMode': 'custom',
        'exitDnsEnabled': false,
        'exitUdp': false,
        'ipv6': 'prefer',
      });
      expect(config.peerCount, '5');
      expect(config.peerAutoReplace, isFalse);
      expect(config.peerDeadTimeoutSec, '120');
      expect(config.peerCheckIntervalSec, '45');
      expect(config.dnsMode, 'custom');
      expect(config.exitDnsEnabled, isFalse);
      expect(config.exitUdp, isFalse);
      expect(config.ipv6, 'prefer');

      final json = config.toJson(
        privateKey: 'key',
        peers: const [],
        exits: const [],
        activeId: '',
        exitEnabled: false,
      );
      expect(json['peerCount'], 5);
      expect(json['peerDeadTimeout'], '120s');
      expect(json['peerCheckInterval'], '45s');
      expect(json['dnsMode'], 'custom');
      expect(json['exitDnsEnabled'], isFalse);
      expect(json['exitUdp'], isFalse);
      expect(json['ipv6'], 'prefer');
    });
  });

  group('ExitStatus', () {
    test('reads the active profile, quota and UDP state', () {
      final status = ExitStatus.fromJson({
        'enabled': true,
        'state': 'online',
        'activeId': 'e',
        'profiles': [
          {
            'id': 'e',
            'name': 'Finland',
            'state': 'online',
            'latencyMs': 38.5,
            'connections': 1,
            'maxConns': 128,
            'dnsAddress': '201:bd5a::1',
            'dnsPort': 53,
            'ipv6State': 'ok',
            'quota': {
              'monthlyBytes': 1000,
              'monthUsed': 250,
              'dailyBytes': 100,
              'dayUsed': 50,
              'downKbps': 1000,
            },
          },
        ],
        'udp': {
          'enabled': true,
          'state': 'idle',
          'bytesIn': 10,
          'bytesOut': 20,
        },
      });
      expect(status.active?.name, 'Finland');
      expect(status.active?.latencyMs, 38.5);
      expect(status.active?.quota?.monthUsed, 250);
      expect(status.active?.quota?.hasLimit, isTrue);
      expect(status.active?.quota?.hasSpeed, isTrue);
      expect(status.udp.enabled, isTrue);
      expect(status.udp.bytesOut, 20);
    });
  });

  group('formatting', () {
    test('splits comma and whitespace separated lists', () {
      expect(splitList('a, b;c  d'), ['a', 'b', 'c', 'd']);
      expect(splitList('  '), isEmpty);
    });

    test('formats bytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1024 * 1024 * 3), '3.0 MB');
    });

    test('formats uptime', () {
      expect(formatUptime(0), '—');
      expect(formatUptime(45), '45s');
      expect(formatUptime(125), '2m 5s');
      expect(formatUptime(7300), '2h 1m');
    });
  });
}
