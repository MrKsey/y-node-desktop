import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y_node_desktop/app_state.dart';
import 'package:y_node_desktop/core_process.dart';
import 'package:y_node_desktop/models.dart';
import 'package:y_node_desktop/theme.dart';
import 'package:y_node_desktop/ui/exit_page.dart';
import 'package:y_node_desktop/ui/logs_page.dart';
import 'package:y_node_desktop/ui/peers_page.dart';
import 'package:y_node_desktop/ui/proxy_page.dart';
import 'package:y_node_desktop/ui/services_page.dart';
import 'package:y_node_desktop/ui/settings_page.dart';
import 'package:y_node_desktop/ui/tunnel_page.dart';
import 'package:y_node_desktop/ui/widgets.dart';

/// Builds a state that never starts the core: the pages only read it, so the
/// smoke test can lay every screen out without a running node.
AppState _state() {
  final state = AppState(CoreProcess());
  state.ready = true;
  state.state = TunnelState.fromJson({
    'running': true,
    'address': '201:2df4:1e5a:7a1f:9e42:6f39:1b23:4c56',
    'subnet': '300:2df4:1e5a:7a1f::/64',
    'publicKey': 'abcdef0123456789abcdef0123456789',
    'peersUp': 2,
    'peersTotal': 3,
    'rxBytes': 1024,
    'txBytes': 4096,
    'openConnections': 4,
    'totalConnections': 9,
    'exitEnabled': true,
    'exitInUse': true,
    'exitName': 'Finland',
    'exitState': 'online',
    'exitDns': '201:bd5a:efe4:92c:284c:bbcd:5b53:ea3b',
    'exitFlag': '🇫🇮',
    'exitCountry': 'Finland',
    'exitCity': 'Helsinki',
    'proxyHttp': '127.0.0.1:7890',
    'proxySocks': '127.0.0.1:7891',
    'systemProxy': true,
    'systemProxyAddress': '127.0.0.1:7890',
    'latencyMs': 12.5,
    'uptimeSeconds': 3700,
    'version': '1.2.0',
    'platform': 'windows',
    'yggVersion': '0.5.12',
  });
  state.peers = [
    PeerStatus.fromJson({
      'uri': 'tls://box.example.org:13338',
      'up': true,
      'latencyMs': 12.5,
    }),
    PeerStatus.fromJson({
      'uri': 'quic://novosibirsk.example.org:9952',
      'up': true,
      'latencyMs': 88,
    }),
  ];
  state.configuredPeers = ['tls://box.example.org:13338'];
  state.exits = [
    ExitProfile.fromJson({
      'id': '201:bd5a::1:1080',
      'name': 'Finland',
      'address': '201:bd5a::1',
      'registered': true,
      'peer': 'quic://novosibirsk.example.org:9952',
    }),
  ];
  state.activeExitId = '201:bd5a::1:1080';
  state.exitEnabled = true;
  state.exitStatus = ExitStatus.fromJson({
    'enabled': true,
    'state': 'online',
    'activeId': '201:bd5a::1:1080',
    'profiles': [
      {
        'id': '201:bd5a::1:1080',
        'name': 'Finland',
        'state': 'online',
        'latencyMs': 45,
        'maxConns': 32,
        'connections': 2,
        'dnsAddress': '201:bd5a::1',
        'dnsPort': 53,
        'quota': {'monthlyBytes': 1000000, 'monthUsed': 250000},
      },
    ],
    'udp': {'enabled': true, 'state': 'online', 'bytesIn': 512},
  });
  state.probeResults = [
    const ProbeResult(
      uri: 'tls://box.example.org:13338',
      up: true,
      latencyMs: 12.5,
    ),
    const ProbeResult(uri: 'tcp://dead.example.org:1', error: 'timeout'),
  ];
  state.dnsChecks = {
    '308:84:68:55::': const DnsCheck(
      server: '308:84:68:55::',
      ok: true,
      ms: 21,
      name: 'example.com',
      address: '93.184.216.34',
    ),
  };
  return state;
}

Widget _wrap(AppState state, Widget page) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Scaffold(
      body: AppScope(state: state, child: page),
    ),
  );
}

void main() {
  testWidgets('the tunnel screen lays out on a wide window', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        _state(),
        TunnelPage(
          onOpenPeers: () {},
          onOpenExit: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ACTIVE PEERS'), findsOneWidget);
    expect(find.text('YOUR ADDRESS'), findsOneWidget);
    // rx is the download of the client and belongs under "Received"; tx is the
    // upload and belongs under "Sent".
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.text('4.0 KB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settings page offers the launch switches', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(_state(), const SettingsPage()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Connect on launch'), findsOneWidget);
    expect(find.text('Start with Windows'), findsOneWidget);
    // The launch switch belongs to the tray block, not to Connection. Section
    // titles are upper-cased by the card itself.
    expect(find.text('TRAY AND LAUNCH'), findsOneWidget);
    expect(find.text('TRAY'), findsNothing);
    final tray = find.ancestor(
      of: find.text('TRAY AND LAUNCH'),
      matching: find.byType(SectionCard),
    );
    expect(
      find.descendant(of: tray, matching: find.text('Connect on launch')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the exit peer keeps its live state after normalisation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = _state();
    // The node reports the pinned link without the key query, so the row has
    // to match by host instead of by the exact URI.
    state.configuredPeers = ['wss://160.20.158.195:443/ygg'];
    state.peers = [
      PeerStatus.fromJson({
        'uri': 'wss://160.20.158.195:443/ygg',
        'up': true,
        'latencyMs': 31,
      }),
    ];
    state.exits = [
      ExitProfile.fromJson({
        'id': 'exit',
        'name': 'Finland',
        'address': '201:bd5a::1',
        'peer': 'wss://160.20.158.195:443/ygg?key=abc',
      }),
    ];
    state.activeExitId = 'exit';
    state.exitEnabled = true;

    await tester.pumpWidget(
      _wrap(
        state,
        TunnelPage(
          onOpenPeers: () {},
          onOpenExit: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Finland'), findsWidgets);
    expect(find.text('waiting'), findsNothing);
    expect(find.text('connected'), findsWidgets);
  });

  testWidgets('the tunnel screen locks Connect while the first search runs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = _state();
    // A fresh install: no tunnel, no configured peer, no exit, discovery on.
    state.state = TunnelState.fromJson(const {});
    state.peers = const [];
    state.configuredPeers = const [];
    state.exits = const [];
    state.activeExitId = '';
    state.exitEnabled = false;
    state.probing = true;

    await tester.pumpWidget(
      _wrap(
        state,
        TunnelPage(
          onOpenPeers: () {},
          onOpenExit: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Searching peers…'), findsOneWidget);
    expect(find.text('Looking for live nodes'), findsOneWidget);
    expect(
      tester.widget<PowerButton>(find.byType(PowerButton)).enabled,
      isFalse,
    );

    // A search that found nothing keeps the button locked: connecting a node
    // without a single link cannot succeed.
    state.probing = false;
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<PowerButton>(find.byType(PowerButton)).enabled,
      isFalse,
    );

    // The discovery filled the list: the same button unlocks.
    final filled = _state();
    filled.state = TunnelState.fromJson(const {});
    filled.peers = const [];
    filled.exits = const [];
    filled.activeExitId = '';
    filled.exitEnabled = false;
    filled.configuredPeers = ['tls://box.example.org:13338'];
    await tester.pumpWidget(
      _wrap(
        filled,
        TunnelPage(
          onOpenPeers: () {},
          onOpenExit: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<PowerButton>(find.byType(PowerButton)).enabled,
      isTrue,
    );
  });

  testWidgets('the peers page flags the pinned exit peer', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = _state();
    // The exit node never comes from the public catalogue: its link points at
    // the server itself, so the row has to take the flag the core resolved for
    // the exit. Without that fallback the pinned row showed no flag at all.
    const exitPeer = 'wss://160.20.158.195:443/ygg?key=abc';
    state.exits = [
      ExitProfile.fromJson({
        'id': 'exit',
        'name': 'Finland',
        'address': '201:bd5a::1',
        'peer': exitPeer,
      }),
    ];
    state.activeExitId = 'exit';
    state.exitEnabled = true;
    state.configuredPeers = ['tls://box.example.org:13338'];

    await tester.pumpWidget(_wrap(state, const PeersPage()));
    await tester.pump(const Duration(milliseconds: 100));

    final tiles = tester.widgetList<PeerTile>(find.byType(PeerTile));
    final exitTile = tiles.firstWhere(
      (tile) => tile.uri == exitPeer,
      orElse: () => throw StateError('the exit peer is not in Active peers'),
    );
    expect(exitTile.pinned, isTrue);
    expect(exitTile.flag, '🇫🇮');
    expect(exitTile.place, 'Helsinki, Finland');
  });

  testWidgets('the services page lists the built-in catalogue', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = _state();
    state.resources = const [
      ServiceEntry(
        id: 'builtin:directory',
        title: 'Yggdrasil Web directory',
        url: 'http://[21e:a51c:885b:7db0:166e:927:98cd:d186]/',
        builtIn: true,
      ),
      ServiceEntry(
        id: 'builtin:myip',
        title: 'Show my IP address',
        url: 'http://[320:9c1:e1fa:a105::ad]/',
        builtIn: true,
      ),
    ];

    await tester.pumpWidget(_wrap(state, const ServicesPage()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Yggdrasil Web directory'), findsOneWidget);
    expect(find.text('Show my IP address'), findsOneWidget);
    expect(find.text('The list is empty'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the services page offers to restore the deleted built-ins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = _state();
    state.resources = const [
      ServiceEntry(
        id: 'builtin:myip',
        title: 'Show my IP address',
        url: 'http://[320:9c1:e1fa:a105::ad]/',
        builtIn: true,
      ),
    ];
    state.config.hiddenServices = ['builtin:directory'];

    await tester.pumpWidget(_wrap(state, const ServicesPage()));
    await tester.pump(const Duration(milliseconds: 100));

    // The deleted default stays gone between restarts; this button is the way
    // back, and it says how many entries it brings.
    expect(find.byTooltip('Restore built-in resources (1)'), findsOneWidget);
    expect(find.text('Yggdrasil Web directory'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a notice appears at the bottom and moves no content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = _state();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppScope(
          state: state,
          child: NoticeHost(
            child: Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 40),
                  const Text('page content'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final before = tester.getTopLeft(find.text('page content'));

    state.showNotice('Settings saved');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The message is a snack bar at the bottom, the way the Exit node screen
    // shows "Name saved"; the page above it does not move.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Settings saved'), findsOneWidget);
    expect(tester.getTopLeft(find.text('page content')), before);
    expect(
      tester.getTopLeft(find.byType(SnackBar)).dy,
      greaterThan(before.dy + 200),
    );
    expect(tester.takeException(), isNull);

    // Let the notice expire: the state keeps a three second timer for it.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('every page builds without an exception', (tester) async {
    tester.view.physicalSize = const Size(1200, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pages = <String, Widget>{
      'peers': const PeersPage(),
      'services': const ServicesPage(),
      'exit': const ExitPage(),
      'proxy': const ProxyPage(),
      'logs': const LogsPage(),
      'settings': const SettingsPage(),
    };

    for (final entry in pages.entries) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap(_state(), entry.value));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.takeException(),
        isNull,
        reason: 'the ${entry.key} page threw while building',
      );
      // The logs page polls the core on a timer; unmount it before the next
      // page so the timer is cancelled and the tree is not updated while dirty.
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
