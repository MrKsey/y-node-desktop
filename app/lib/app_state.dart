import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'core_process.dart';
import 'models.dart';
import 'update_service.dart';

/// The single source of truth of the window. It polls the core once per second
/// for the tunnel counters and every few seconds for the slower lists.
class AppState extends ChangeNotifier {
  AppState(this.core);

  final CoreProcess core;
  CoreClient? _client;

  TunnelState state = const TunnelState();
  List<PeerStatus> peers = const [];
  List<String> configuredPeers = const [];
  List<String> pool = const [];
  List<ExitProfile> exits = const [];
  List<LogLine> logs = const [];
  CoreConfig config = CoreConfig();
  ExitStatus exitStatus = const ExitStatus();
  String privateKey = '';
  String activeExitId = '';
  bool exitEnabled = false;

  /// The user removed the pinned peer of the exit node from the active list
  /// while the exit was off. Switching the exit on clears both flags.
  bool exitPeerHidden = false;
  bool exitDnsHidden = false;

  /// The public peer list with every transport, the countries it contains and
  /// the detected location, exactly what the Peers page and its browser show.
  List<CatalogPeer> candidates = const [];
  List<CountryCount> countries = const [];
  GeoLocation detected = const GeoLocation();
  DateTime? peersUpdatedAt;
  String countrySlug = '';

  /// The rows of the last latency test. The Peers page keeps them until the
  /// next run and the browser reads the same map.
  List<ProbeResult> probeResults = const [];

  /// The in-network resolvers of the wiki, listed under "Available servers".
  List<DnsPreset> dnsPresets = const [];

  /// The Services list: the built-in catalogue and the entries the user added.
  List<ServiceEntry> resources = const [];
  List<ServiceEntry> directoryResources = const [];

  /// The result of the last check of each resolver, keyed by its address.
  Map<String, DnsCheck> dnsChecks = const {};

  bool ready = false;
  bool busy = false;
  bool probing = false;

  /// The release check of the Update section. [availableUpdate] keeps the last
  /// answer, so the card can offer the release page after the dialog is closed.
  final UpdateService _updates = UpdateService();
  bool updateCheckInFlight = false;
  UpdateInfo? availableUpdate;

  /// The peers of the running latency test. The catalogue marks exactly these
  /// rows, the way the Android client's `probingUris` does.
  Set<String> probingUris = const {};
  bool loadingPeers = false;
  bool loadingDirectory = false;
  bool dnsChecking = false;
  String? error;
  String? notice;

  /// The result of the last directory read, kept apart from [error] so a
  /// failed import is reported on the Services page instead of the tunnel
  /// card.
  String? directoryError;

  /// Bumped by [cancelProbe]: a result of an older run is dropped.
  int _probeGeneration = 0;

  /// The automatic DNS check of the Android client: a check is scheduled once
  /// the tunnel can really carry queries, retried while the stack warms up and
  /// remembered per connection so a failure does not turn into a loop.
  bool _dnsVerified = false;
  bool _dnsScheduled = false;
  bool _dnsAttempted = false;
  DateTime? _dnsReadySince;
  int _dnsGeneration = 0;

  /// The last automatic DNS retry that followed the exit resolver becoming
  /// ready. Keeps the retry from running on every status poll.
  DateTime _lastExitDnsRetry = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _fast;
  Timer? _slow;
  Timer? _noticeTimer;
  Timer? _catalogRetry;

  /// Guards of the two polls. The timers fire on a fixed schedule, so a request
  /// that is still in flight must skip the next tick instead of piling another
  /// connection on top of it.
  bool _stateBusy = false;
  bool _logsBusy = false;

  /// Consecutive failed polls of `/v1/state`, and whether the window is showing
  /// the error of that run.
  int _stateFailures = 0;
  bool _stateErrorShown = false;

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
      unawaited(_startupPeers());
    } catch (e) {
      error = _message(e);
      notifyListeners();
    }
  }

  /// The launch sequence of the window: fill an empty peer list first and
  /// then honour "Connect on launch". The core reads the same switch when it
  /// starts, but a first launch has no peers yet, so its attempt fails before
  /// the discovery has anything to add.
  Future<void> _startupPeers() async {
    await _bootstrapPeers();
    if (!config.autoConnect || state.running || noPeers) return;
    await connect();
  }

  /// The very first launch has neither a result list nor a replacement pool.
  /// With "Replace dropped peers" on, the window runs the same discovery the
  /// "Find peers" button runs, so both lists exist from the first minute. The
  /// empty tunnel list is then filled with the fastest answers: a first launch
  /// has no peers to connect to at all, and waiting for the user to press "Add
  /// the best" left the client offline. The rows are kept by the core in
  /// `lastProbe` and the pool in `pool`, so the next launch reads them back
  /// instead of starting empty.
  ///
  /// Only a launch without any stored discovery fills the tunnel list: a list
  /// the user edited by hand, or cleared on purpose, is never touched here.
  Future<void> _bootstrapPeers() async {
    if (!config.peerAutoReplace) return;
    if (probeResults.isNotEmpty || pool.isNotEmpty) return;
    // The window keeps its banner and the locked Connect button while
    // `probing` is on, so the first launch explains itself.
    await probePeers();
    if (configuredPeers.isEmpty && probeResults.isNotEmpty) {
      await addBestPeers();
    }
  }

  CoreClient get client {
    final client = _client;
    if (client == null) throw CoreException('The core is not running yet');
    return client;
  }

  Future<void> refresh() async {
    if (_client == null || _stateBusy) return;
    _stateBusy = true;
    // A snapshot that did not change must not rebuild the window: the poll runs
    // every second, and repainting the whole page for the same answer kept an
    // idle client at several percent of CPU.
    var changed = false;
    try {
      final data = await client.get(
        '/v1/state',
        timeout: const Duration(seconds: 5),
      );
      if (data is Map<String, dynamic>) {
        final next = TunnelState.fromJson(data);
        changed = !next.sameAs(state);
        state = next;
      }
      _stateFailures = 0;
      if (_stateErrorShown) {
        _stateErrorShown = false;
        error = null;
        changed = true;
      }
    } catch (e) {
      // The poll runs every second and the core is allowed to be busy for a
      // moment: a single missed answer is not a failure. Only a run of them
      // means the core stopped answering, and only that run is reported: a
      // one-off timeout used to leave an error in the window until the next
      // action cleared it.
      _stateFailures++;
      if (_stateFailures >= 5 && state.running) {
        _stateErrorShown = true;
        error = _message(e);
      }
    } finally {
      _stateBusy = false;
    }
    _syncDns();
    if (changed) notifyListeners();
  }

  /// The answer of the last successful `/v1/peers`, `/v1/exit` and
  /// `/v1/exit/status` run. The slow poll runs every four seconds and most of
  /// its answers are identical; comparing them keeps the page from rebuilding
  /// for nothing.
  String _listsSignature = '';

  Future<void> refreshLists() async {
    if (_client == null) return;
    var signature = '';
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
        pool = [
          for (final item in (peersJson['pool'] as List? ?? const [])) '$item',
        ];
        final stored = peersJson['probe'];
        if (probeResults.isEmpty && stored is List) {
          probeResults = [
            for (final item in stored)
              if (item is Map<String, dynamic>) ProbeResult.fromJson(item),
          ];
        }
      }
      final exitJson = await client.get('/v1/exit');
      if (exitJson is Map) {
        exits = [
          for (final item in (exitJson['profiles'] as List? ?? const []))
            ExitProfile.fromJson(item as Map<String, dynamic>),
        ];
        activeExitId = exitJson['activeId'] as String? ?? '';
        exitEnabled = exitJson['enabled'] as bool? ?? false;
        exitPeerHidden = exitJson['peerHidden'] as bool? ?? false;
        exitDnsHidden = exitJson['dnsHidden'] as bool? ?? false;
      }
      final statusJson = await client.get('/v1/exit/status');
      if (statusJson is Map<String, dynamic>) {
        exitStatus = ExitStatus.fromJson(statusJson);
      }
      // A resolver that was still loading its chain when the last check ran
      // is not dead. Once the exit reports it ready, the check is repeated by
      // itself, at most every half a minute: the user must not press
      // "Check now" to see a working DNS.
      final activeExit = exitStatus.active;
      final resolver = exitDnsServer;
      if (activeExit != null &&
          activeExit.dnsState == 'ready' &&
          resolver.isNotEmpty &&
          dnsChecks[resolver]?.ok == false &&
          DateTime.now().difference(_lastExitDnsRetry) >
              const Duration(seconds: 30)) {
        _lastExitDnsRetry = DateTime.now();
        _restartDnsCheck();
      }
      signature = jsonEncode([peersJson, exitJson, statusJson]);
    } catch (_) {
      // The fast loop reports the connection errors; lists are best effort.
    }
    if (signature.isEmpty || signature == _listsSignature) return;
    _listsSignature = signature;
    notifyListeners();
  }

  Future<void> refreshLogs() async {
    if (_logsBusy) return;
    _logsBusy = true;
    try {
      // The page polls every two seconds, so a request that never returns must
      // not freeze it: the timeout releases the next poll. Without it a stuck
      // answer left the list on the old snapshot for the rest of the session.
      final data = await client.get(
        '/v1/logs',
        timeout: const Duration(seconds: 5),
      );
      if (data is List) {
        final next = [
          for (final item in data)
            LogLine.fromJson(item as Map<String, dynamic>),
        ].reversed.toList();
        // A snapshot that did not change must not rebuild the whole window.
        if (!_sameLogs(logs, next)) {
          logs = next;
          notifyListeners();
        }
      }
    } catch (_) {
      // The log page shows the last successful snapshot.
    } finally {
      _logsBusy = false;
    }
  }

  /// The log grows at the top: an unchanged newest line with the same length
  /// means the snapshot is the same one.
  static bool _sameLogs(List<LogLine> current, List<LogLine> next) {
    if (current.length != next.length) return false;
    if (current.isEmpty) return true;
    final a = current.first;
    final b = next.first;
    return a.time == b.time && a.level == b.level && a.message == b.message;
  }

  Future<void> loadConfig() async {
    final data = await client.get('/v1/config');
    if (data is! Map<String, dynamic>) return;
    config = CoreConfig.fromJson(data);
    privateKey = data['privateKey'] as String? ?? '';
    resources = config.services;
    // A configuration that lost the catalogue (an older core, a file edited by
    // hand) would leave the page empty: the services endpoint owns the list,
    // so it is asked once more before the page shows nothing.
    if (resources.isEmpty) {
      try {
        final list = await client.get('/v1/services');
        if (list is Map && list['services'] is List) {
          resources = _servicesOf(list['services']);
          config.services = resources;
        }
      } catch (_) {
        // The page shows its empty state.
      }
    }
    countrySlug = config.countrySlug;
    notifyListeners();
  }

  Future<void> saveConfig(CoreConfig next, {String? key}) async {
    final before = _dnsSignature();
    await _run(() async {
      final data = await client.put('/v1/config', {
        ...next.toJson(
          privateKey: key ?? privateKey,
          peers: configuredPeers,
          pool: pool,
          exits: exits,
          activeId: activeExitId,
          exitEnabled: exitEnabled,
        ),
        'privateKey': key ?? privateKey,
      });
      if (data is Map<String, dynamic>) {
        config = CoreConfig.fromJson(data);
        privateKey = data['privateKey'] as String? ?? privateKey;
        resources = config.services;
      }
      _publishNotice('Settings saved');
    });
    // A new mode or a new list invalidates the automatic check the Android
    // client runs after the tunnel comes up: its results belong to the old
    // settings, so the round is scheduled again.
    if (before != _dnsSignature()) _restartDnsCheck();
    // Switching "Replace dropped peers" on while nothing was ever discovered
    // would leave the Results and the Replacement pool empty, so the round the
    // "Find peers" button runs starts here too.
    unawaited(_bootstrapPeers());
  }

  /// Persists the automatic update-check preference in the core configuration.
  Future<void> saveUpdateCheck(bool enabled) async {
    config.updateCheck = enabled;
    notifyListeners();
    await _saveUpdateSettings();
  }

  /// Runs a release check. Throws [UpdateCheckException] when it fails. On
  /// success [availableUpdate] holds the newer release, or null when the build
  /// is up to date.
  Future<UpdateInfo?> checkForUpdate() async {
    if (updateCheckInFlight) return availableUpdate;
    updateCheckInFlight = true;
    notifyListeners();
    try {
      final update = await _updates.checkForUpdate(
        currentVersion: state.version,
      );
      availableUpdate = update;
      return update;
    } finally {
      updateCheckInFlight = false;
      notifyListeners();
    }
  }

  /// The launch check. A release is announced once per version, and only when
  /// the user turned the automatic check on.
  Future<UpdateInfo?> checkForUpdateOnStart() async {
    if (!config.updateCheck) return null;
    try {
      final update = await checkForUpdate();
      if (update == null || update.version == config.updateNotified) {
        return null;
      }
      return update;
    } on UpdateCheckException {
      // The manual "Check for updates now" reports the error instead.
      return null;
    }
  }

  /// Remembers that this release was already announced.
  Future<void> markUpdateNotified(UpdateInfo info) async {
    if (config.updateNotified == info.version) return;
    config.updateNotified = info.version;
    await _saveUpdateSettings();
  }

  Future<void> _saveUpdateSettings() async {
    try {
      await client.put('/v1/config', {
        ...config.toJson(
          privateKey: privateKey,
          peers: configuredPeers,
          pool: pool,
          exits: exits,
          activeId: activeExitId,
          exitEnabled: exitEnabled,
        ),
        'privateKey': privateKey,
      });
    } catch (e) {
      error = _message(e);
      notifyListeners();
    }
  }

  /// The DNS settings the automatic check depends on. The resolver the exit
  /// publishes is part of them: adding a profile by an invite, or switching to
  /// another one, changes the list the check has to measure.
  String _dnsSignature() => [
    config.dnsMode,
    config.exitDnsEnabled,
    config.systemDns,
    config.yggDns,
    exitDnsServer,
  ].join('|');

  Future<void> connect() => _run(() => client.post('/v1/connect'));

  Future<void> disconnect() => _run(() => client.post('/v1/disconnect'));

  /// Turns the per-user system proxy on or off. The stored switch is updated
  /// here as well: `/v1/state` only reports what the operating system holds,
  /// and the tray and the Proxy page read the intent from the configuration.
  Future<void> setSystemProxy(bool enabled) => _run(() async {
    await client.post('/v1/system-proxy', {'enabled': enabled});
    config.systemProxy = enabled;
  });

  // ---------------------------------------------------------------- peers

  Future<void> addPeer(String uri) => _run(() async {
    await client.post('/v1/peers', {'uri': uri.trim()});
    // The core raises PeerCount when the list grows, so the Settings slider
    // has to read the configuration again: the peer list alone does not carry
    // the new target.
    await loadConfig();
    _publishNotice('Peer added');
  }, refreshAfter: true);

  Future<void> removePeer(String uri) => _run(() async {
    await client.delete('/v1/peers?uri=${Uri.encodeQueryComponent(uri)}');
    _publishNotice('Peer removed');
  }, refreshAfter: true);

  Future<void> removePoolPeer(String uri) => _run(() async {
    await client.delete(
      '/v1/peers?pool=1&uri=${Uri.encodeQueryComponent(uri)}',
    );
    _publishNotice('Peer removed');
  }, refreshAfter: true);

  /// Replaces the tunnel list and the replacement pool in one request.
  Future<void> setPeers(List<String> uris, {List<String>? nextPool}) =>
      _run(() async {
        await client.put('/v1/peers', {'uris': uris, 'pool': nextPool ?? pool});
        _publishNotice('Peers saved');
      }, refreshAfter: true);

  Future<void> clearPeers() => setPeers(const []);

  /// Downloads the public list and keeps it, without measuring anything.
  Future<void> loadCatalog() async {
    if (loadingPeers) return;
    loadingPeers = true;
    error = null;
    notifyListeners();
    try {
      final data = await client.get(
        '/v1/peers/catalog',
        timeout: const Duration(seconds: 90),
      );
      if (data is Map<String, dynamic>) {
        final catalog = PeerCatalog.fromJson(data);
        candidates = catalog.peers;
        countries = catalog.countries;
        detected = catalog.detected;
        countrySlug = catalog.country;
        peersUpdatedAt = catalog.updated;
      }
      if (candidates.isEmpty) error = 'No peer matches these filters';
    } catch (e) {
      error = _message(e);
      // The flags of the peers and of the exit node come from this list. A
      // start without a working network used to leave every icon without a
      // flag until the Peers page was opened, so the download is retried.
      _scheduleCatalogRetry();
    } finally {
      loadingPeers = false;
      notifyListeners();
    }
  }

  void _scheduleCatalogRetry() {
    // Without a running core the request cannot succeed and the window owns no
    // timer to cancel, so the retry waits for the next real load.
    if (_client == null) return;
    if (_catalogRetry?.isActive ?? false) return;
    _catalogRetry = Timer(const Duration(seconds: 20), () {
      if (candidates.isEmpty && !loadingPeers) loadCatalog();
    });
  }

  /// Picks the country the list is ranked around. An empty slug means "detect
  /// automatically".
  Future<void> setCountry(String slug) async {
    await _run(() async {
      await client.post('/v1/country', {'slug': slug});
      countrySlug = slug;
    });
    await loadCatalog();
  }

  /// Measures the given peers and keeps the rows for the results and the
  /// browser. The tunnel list is not changed.
  Future<void> probeUris(List<String> uris) async {
    if (uris.isEmpty || probing) return;
    probing = true;
    probingUris = {for (final uri in uris) uri};
    error = null;
    notifyListeners();
    try {
      final data = await client.post('/v1/peers/probe', {
        'uris': uris,
      }, const Duration(seconds: 120));
      final rows = _resultsOf(data);
      if (rows.isNotEmpty) probeResults = _mergeResults(probeResults, rows);
    } catch (e) {
      error = _message(e);
    } finally {
      probing = false;
      probingUris = const {};
      notifyListeners();
    }
  }

  /// The discovery of the Peers page: download the list, measure the most
  /// promising part and refill the replacement pool with the spares.
  Future<void> probePeers() async {
    if (probing) return;
    final generation = ++_probeGeneration;
    probing = true;
    error = null;
    notifyListeners();
    try {
      if (candidates.isEmpty) {
        await loadCatalog();
      }
      if (candidates.isEmpty) {
        error = 'No live node was found. Try again later.';
        return;
      }
      // The core picks the round: the servers of the home country first, then
      // the closest countries, one URI per server. The home country keeps most
      // of the window but never all of it, so a faster neighbour across the
      // border is measured too. The window used to send the first sixty
      // catalogue rows, which were mostly transports of the same machines and
      // left half of the local servers out.
      final data = await client.post('/v1/peers/find', {
        'limit': 120,
      }, const Duration(seconds: 180));
      if (generation != _probeGeneration) return;
      probeResults = _resultsOf(data);
      peersUpdatedAt = DateTime.now();
      final alive = _fastest(probeResults.where((row) => row.up).toList());
      if (alive.isEmpty) {
        error = 'No live node was found. Try again later.';
        return;
      }
      final activeUris = {for (final uri in configuredPeers) uri};
      final activeHosts = {for (final uri in configuredPeers) uriHost(uri)};
      final spare = [
        for (final row in alive)
          if (!activeUris.contains(row.uri) &&
              !activeHosts.contains(uriHost(row.uri)))
            row.uri,
      ].take(_poolLimit).toList();
      if (spare.isNotEmpty) {
        pool = spare;
        await setPeers(configuredPeers, nextPool: spare);
      }
    } catch (e) {
      if (generation == _probeGeneration) error = _message(e);
    } finally {
      if (generation == _probeGeneration) probing = false;
      notifyListeners();
    }
  }

  /// Stops the discovery from the window: the request keeps running in the
  /// core, but its answer is dropped.
  void cancelProbe() {
    _probeGeneration++;
    probing = false;
    notifyListeners();
  }

  /// Fills the tunnel up to the configured size with the fastest answers and
  /// puts the rest into the replacement pool.
  Future<int> addBestPeers() async {
    final alive = _fastest(probeResults.where((row) => row.up).toList());
    if (alive.isEmpty) return 0;
    final wanted = _peerTarget;
    final active = <String>[...configuredPeers];
    final hosts = {for (final uri in active) uriHost(uri)};
    var changed = 0;
    for (final row in alive) {
      if (active.length >= wanted) break;
      if (hosts.contains(uriHost(row.uri))) continue;
      active.add(row.uri);
      hosts.add(uriHost(row.uri));
      changed++;
    }
    final activeHosts = {for (final uri in active) uriHost(uri)};
    final spare = [
      for (final row in alive)
        if (!activeHosts.contains(uriHost(row.uri))) row.uri,
    ].take(_poolLimit).toList();
    await setPeers(active, nextPool: spare);
    return changed;
  }

  /// Keeps the configured number of links, replacing the slowest with a faster
  /// answer. The rows are ranked by the latency the Results card shows, so the
  /// three links the button promises are the three rows at the top of that
  /// card. A link with no numbers at all is the worst, but a candidate added by
  /// this very call already carries the latency of its probe row: without that
  /// it looked infinitely slow and was replaced by the next row on every
  /// iteration, which ended with a peer from the bottom of the list.
  Future<int> applyBestPeers() async {
    final alive = probeResults.where((row) => row.up).toList()
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    if (alive.isEmpty) return 0;
    final wanted = _peerTarget;
    final active = <String>[...configuredPeers];
    final latency = <String, double>{
      for (final row in probeResults) row.uri: row.latencyMs,
    };
    for (final peer in peers) {
      latency[peer.uri] = peer.latencyMs;
    }
    double qualityOf(String uri) {
      final value = latency[uri];
      if (value == null || value <= 0) return double.infinity;
      return value;
    }

    var changes = 0;
    for (final row in alive) {
      if (active.any((uri) => uriHost(uri) == uriHost(row.uri))) continue;
      if (active.length < wanted) {
        active.add(row.uri);
        latency[row.uri] = row.latencyMs;
        changes++;
        continue;
      }
      var worst = -1;
      var worstValue = 0.0;
      for (var index = 0; index < active.length; index++) {
        final value = qualityOf(active[index]);
        if (value <= row.latencyMs) continue;
        if (worst < 0 || value > worstValue) {
          worst = index;
          worstValue = value;
        }
      }
      if (worst < 0) continue;
      active[worst] = row.uri;
      latency[row.uri] = row.latencyMs;
      changes++;
    }
    final activeHosts = {for (final uri in active) uriHost(uri)};
    final spare = [
      for (final row in alive)
        if (!activeHosts.contains(uriHost(row.uri))) row.uri,
    ].take(_poolLimit).toList();
    await setPeers(active, nextPool: spare);
    return changes;
  }

  /// The discovery of the tunnel screen: the catalogue, the best nodes and the
  /// tunnel list in one go.
  Future<bool> findAndAddPeers() async {
    await probePeers();
    if (error != null || probeResults.where((row) => row.up).isEmpty) {
      return false;
    }
    await addBestPeers();
    return configuredPeers.isNotEmpty;
  }

  /// The pinned peer of the active exit profile: it is a link of the tunnel
  /// even though it never appears in the configured list.
  String get _activeExitPeer {
    for (final profile in exits) {
      if (profile.id == activeExitId) return profile.peer.trim();
    }
    return exits.isEmpty ? '' : exits.first.peer.trim();
  }

  /// True when the tunnel has not a single link to start with: no configured
  /// peer and no pinned peer of the active exit node.
  bool get noPeers => configuredPeers.isEmpty && _activeExitPeer.isEmpty;

  /// A launch without peers runs the discovery by itself, so the Connect
  /// button waits for it instead of starting a node without a single link.
  bool get searchingPeers => noPeers && probing;

  int get _peerTarget =>
      (int.tryParse(config.peerCount.trim()) ?? 3).clamp(1, 20);

  /// The replacement pool holds spares for the supervisor, not a second copy of
  /// the whole catalogue.
  static const int _poolLimit = 20;

  /// Orders the answers by the measured access time: the fastest first. The
  /// country is not a tie-breaker, because the nearest peers may sit across the
  /// border: a server in Finland can answer quicker than one in Vladivostok.
  List<ProbeResult> _fastest(List<ProbeResult> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final byLatency = a.latencyMs.compareTo(b.latencyMs);
      if (byLatency != 0) return byLatency;
      return a.uri.compareTo(b.uri);
    });
    return sorted;
  }

  static List<ProbeResult> _resultsOf(Object? data) {
    final list = data is List ? data : const [];
    return [
      for (final item in list)
        if (item is Map<String, dynamic>) ProbeResult.fromJson(item),
    ]..sort((a, b) {
      if (a.up != b.up) return a.up ? -1 : 1;
      return a.latencyMs.compareTo(b.latencyMs);
    });
  }

  /// Folds fresh rows into the list: the measured peers get their new numbers
  /// and every other row stays. Testing one node from the browser used to
  /// replace the whole discovery result with that single row.
  static List<ProbeResult> _mergeResults(
    List<ProbeResult> current,
    List<ProbeResult> fresh,
  ) {
    final merged = <String, ProbeResult>{
      for (final row in current) row.uri: row,
    };
    for (final row in fresh) {
      if (row.uri.isNotEmpty) merged[row.uri] = row;
    }
    return merged.values.toList()..sort((a, b) {
      if (a.up != b.up) return a.up ? -1 : 1;
      return a.latencyMs.compareTo(b.latencyMs);
    });
  }

  /// The probe answers keyed by URI, for the browser rows.
  Map<String, ProbeResult> get resultsByUri => {
    for (final row in probeResults) row.uri: row,
  };

  /// The address a remote service sees, through the exit or directly.
  Future<PublicIpResult> publicIp({required bool viaExit}) async {
    try {
      final data = await client.post(
        '/v1/ip?via=${viaExit ? 'exit' : 'direct'}',
        null,
        const Duration(seconds: 30),
      );
      if (data is Map<String, dynamic>) return PublicIpResult.fromJson(data);
      return const PublicIpResult(error: 'bad answer');
    } catch (e) {
      return PublicIpResult(error: _message(e));
    }
  }

  // --------------------------------------------------------------- exits

  Future<void> addExitLink(String link) async {
    await _run(() async {
      await client.post('/v1/exit/link', {'link': link.trim()});
      _publishNotice('Exit node added');
    }, refreshAfter: true);
    _restartDnsCheck();
  }

  Future<void> setActiveExit(String id) async {
    await _run(
      () => client.post('/v1/exit/active', {'id': id}),
      refreshAfter: true,
    );
    _restartDnsCheck();
  }

  Future<void> setExitEnabled(bool enabled) async {
    await _run(
      () => client.post('/v1/exit/enabled', {'enabled': enabled}),
      refreshAfter: true,
    );
    _restartDnsCheck();
  }

  /// Takes the pinned peer of the exit node out of the active list. The exit
  /// must be off; switching it on brings the peer back.
  Future<void> hideExitPeer() async {
    await _run(
      () => client.post('/v1/exit/hide-peer', const {}),
      refreshAfter: true,
    );
  }

  /// Takes the resolver the exit publishes out of the tunnel list. The "DNS
  /// exit node" switch keeps its value, so switching the exit on adds the
  /// resolver back.
  Future<void> hideExitDns() async {
    await _run(
      () => client.post('/v1/exit/hide-dns', const {}),
      refreshAfter: true,
    );
    _restartDnsCheck();
  }

  Future<void> removeExit(String id) async {
    await _run(
      () => client.delete('/v1/exit?id=${Uri.encodeQueryComponent(id)}'),
      refreshAfter: true,
    );
    _restartDnsCheck();
  }

  /// Adds a profile or replaces one by its id. The invite and the token are
  /// kept by the core when the form leaves them empty.
  Future<void> saveExit(ExitProfile profile) async {
    await _run(() async {
      await client.post('/v1/exit/profile', profile.toJson());
      _publishNotice('Exit node saved');
    }, refreshAfter: true);
    _restartDnsCheck();
  }

  Future<void> reorderExits(List<String> ids) async {
    final byId = {for (final item in exits) item.id: item};
    exits = [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
      for (final item in exits)
        if (!ids.contains(item.id)) item,
    ];
    notifyListeners();
    try {
      await client.put('/v1/exit/order', {'ids': ids});
      await refreshLists();
    } catch (e) {
      error = _message(e);
      notifyListeners();
    }
  }

  /// Loads the wiki resolvers for the "Available servers" block.
  Future<void> loadDnsPresets() async {
    if (dnsPresets.isNotEmpty) return;
    try {
      final data = await client.get('/v1/dns/presets');
      final list = data is Map ? data['servers'] as List? : null;
      dnsPresets = [
        for (final item in (list ?? const []))
          if (item is Map<String, dynamic>) DnsPreset.fromJson(item),
      ];
      notifyListeners();
    } catch (_) {
      // The block stays hidden; the form keeps working.
    }
  }

  Future<String> checkExit() async {
    try {
      final data = await client.post(
        '/v1/exit/check',
        null,
        const Duration(seconds: 90),
      );
      if (data is Map) {
        final message = data['message'];
        if (message is String && message.isNotEmpty) return message;
        if (data['ok'] == true) {
          return 'Exit node answered: ${data['dnsAddress']}:${data['dnsPort']}';
        }
        return '${data['error'] ?? 'The exit node did not answer'}';
      }
      return 'The exit node did not answer';
    } catch (e) {
      return _message(e);
    }
  }

  /// Checks the UDP relay and the QUIC handshake of the active exit.
  Future<ExitUdpProbe?> testExitUdp() async {
    try {
      final data = await client.post(
        '/v1/exit/udp-test',
        null,
        const Duration(seconds: 40),
      );
      if (data is Map<String, dynamic>) return ExitUdpProbe.fromJson(data);
      return null;
    } catch (e) {
      error = _message(e);
      return null;
    }
  }

  /// Checks the IPv6 path through the active exit.
  Future<ExitIpv6Probe?> testExitIpv6() async {
    try {
      final data = await client.post(
        '/v1/exit/ipv6-test',
        null,
        const Duration(seconds: 40),
      );
      if (data is Map<String, dynamic>) return ExitIpv6Probe.fromJson(data);
      return null;
    } catch (e) {
      error = _message(e);
      return null;
    }
  }

  /// Saves the exit-node behaviour switches of the Exit page. They apply to the
  /// running tunnel at once, the way the Android client does it.
  Future<void> setExitOptions({
    bool? fallbackDirect,
    bool? localDns,
    bool? exitDnsEnabled,
    bool? exitUdp,
    String? ipv6,
  }) async {
    final next = config;
    if (fallbackDirect != null) next.fallbackDirect = fallbackDirect;
    if (localDns != null) next.localDns = localDns;
    if (exitDnsEnabled != null) next.exitDnsEnabled = exitDnsEnabled;
    if (exitUdp != null) next.exitUdp = exitUdp;
    if (ipv6 != null) next.ipv6 = ipv6;
    await saveConfig(next);
  }

  /// Selects the resolver mode: yggdrasil, system or custom.
  Future<void> setDnsMode(String mode) async {
    final next = config;
    next.dnsMode = mode;
    await saveConfig(next);
  }

  /// Switches the colour scheme from the rail: auto, light or dark.
  Future<void> setTheme(String theme) async {
    if (config.theme == theme) return;
    final next = _copyConfig();
    next.theme = theme;
    await saveConfig(next);
  }

  /// Turns the in-memory log of the core on or off.
  Future<void> setLogging(bool enabled) async {
    final next = _copyConfig();
    next.loggingDisabled = !enabled;
    await saveConfig(next);
    if (!enabled) logs = const [];
  }

  /// A detached copy of the configuration, safe to edit before saving.
  CoreConfig _copyConfig() => CoreConfig.fromJson(
    config.toJson(
      privateKey: privateKey,
      peers: configuredPeers,
      pool: pool,
      exits: exits,
      activeId: activeExitId,
      exitEnabled: exitEnabled,
    ),
  );

  /// The name the exit node shows in its client list. An empty name sends the
  /// device name, exactly like the Android switch.
  Future<void> setExitLabel({
    required bool enabled,
    required String name,
  }) async {
    final next = config;
    next.exitLabelEnabled = enabled;
    next.exitLabel = name.trim();
    await saveConfig(next);
  }

  /// Stores the automatic peer count and the replacement switch, then asks the
  /// core to top the list up right away.
  Future<void> setPeerSettings(int count, bool autoReplace) => _run(() async {
    await client.post('/v1/peers/settings', {
      'count': count,
      'autoReplace': autoReplace,
    });
    await loadConfig();
    _publishNotice('Peer settings saved');
  }, refreshAfter: true);

  // ----------------------------------------------------------------- dns

  /// True when the node can really carry DNS queries. "Connected" only means
  /// that the core finished its start: an in-network resolver stays unreachable
  /// until the first peer has finished its handshake, and a check started
  /// before that marks every server dead. This is the same rule the Android
  /// client uses before it runs its automatic check.
  bool get dnsReady => state.running && state.peersUp > 0;

  /// Schedules the automatic check the Android client runs after the tunnel
  /// comes up. A check that failed is not remembered as done: the next
  /// connection schedules another round.
  void _syncDns() {
    if (!dnsReady) {
      // The link dropped for a moment. The running round stops, but a check
      // that already succeeded stays valid: the servers did not change, and a
      // peer that reconnects must not trigger the whole measurement again.
      // A round that never succeeded may start over on the next connection.
      _dnsScheduled = false;
      _dnsAttempted = false;
      _dnsReadySince = null;
      _dnsGeneration++;
      return;
    }
    _dnsReadySince ??= DateTime.now();
    if (_dnsVerified || _dnsScheduled || _dnsAttempted) return;
    _dnsScheduled = true;
    _dnsAttempted = true;
    final generation = ++_dnsGeneration;
    unawaited(_afterTunnelUp(generation));
  }

  /// Drops the remembered result of the automatic check and schedules a new
  /// round. The list it measures depends on the active exit node, so adding a
  /// profile by an invite or switching to another one invalidates the previous
  /// result exactly like a change of the DNS settings does.
  void _restartDnsCheck() {
    _dnsVerified = false;
    _dnsScheduled = false;
    _dnsAttempted = false;
    _dnsReadySince = dnsReady ? DateTime.now() : null;
    _dnsGeneration++;
    _syncDns();
  }

  /// Waits until the link has been stable for a few seconds and then checks the
  /// DNS servers, retrying while the stack is still warming up. Mirrors
  /// `_afterTunnelUp` of the Android client.
  ///
  /// The peer count is not the whole story: the exit resolver answers as soon
  /// as the exit path works, while the other in-network resolvers need a route
  /// to their own nodes, and the spanning tree converges for a while after the
  /// first handshake. A first round therefore leaves those rows red even though
  /// the servers are fine. A round that is not fully green is repeated for
  /// about a minute and then left alone: the automatic check is a one-off per
  /// connection and per change of the DNS settings, not a poll.
  Future<void> _afterTunnelUp(int generation) async {
    try {
      if (config.dnsMode == 'system') {
        // Nothing is resolved through the node: the system resolver is used.
        _dnsVerified = true;
        return;
      }
      while (true) {
        if (generation != _dnsGeneration || !dnsReady) return;
        final since = _dnsReadySince;
        if (since == null) return;
        if (DateTime.now().difference(since) >= const Duration(seconds: 6)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      // The delay grows so a server that is really dead is not hammered; a
      // fully green round ends the loop at once.
      const delays = [
        Duration(seconds: 4),
        Duration(seconds: 6),
        Duration(seconds: 9),
        Duration(seconds: 12),
        Duration(seconds: 15),
        Duration(seconds: 20),
      ];
      for (var attempt = 0; ; attempt++) {
        if (generation != _dnsGeneration || !dnsReady) return;
        final checks = await _dnsRound(quiet: true);
        if (checks.isNotEmpty && checks.every((check) => check.ok)) {
          _dnsVerified = true;
          return;
        }
        if (attempt >= delays.length) {
          // The round gave what it could. The servers that answered stay
          // green; the automatic check does not repeat until the tunnel
          // reconnects or the DNS settings change, and a red row is
          // re-measured by "Check now" only. Without this the exhausted loop
          // started over on the next poll, so the resolvers were probed again
          // and again for the whole session.
          return;
        }
        await Future<void>.delayed(delays[attempt]);
      }
    } finally {
      if (generation == _dnsGeneration) _dnsScheduled = false;
    }
  }

  /// One round of the automatic check: the servers of the active mode, asked
  /// the way the traffic of that mode is resolved.
  Future<List<DnsCheck>> _dnsRound({bool quiet = false}) async {
    if (config.dnsMode == 'system') {
      return checkDns(splitList(config.systemDns), direct: true, quiet: quiet);
    }
    final servers = [
      if (exitDnsServer.isNotEmpty) exitDnsServer,
      ...splitList(config.yggDns),
    ];
    if (servers.isEmpty) return const [];
    return checkDns(servers, direct: false, quiet: quiet);
  }

  /// Checks every server of one list. In-network resolvers are asked through
  /// the node for a real .ygg name, ordinary ones directly for example.com.
  Future<List<DnsCheck>> checkDns(
    List<String> servers, {
    required bool direct,
    bool quiet = false,
  }) async {
    if (servers.isEmpty) return const [];
    dnsChecking = true;
    notifyListeners();
    try {
      final data = await client.post('/v1/dns/check', {
        'servers': servers,
        'direct': direct,
      }, const Duration(seconds: 60));
      final list = data is List ? data : const [];
      final checks = [
        for (final item in list)
          if (item is Map<String, dynamic>) DnsCheck.fromJson(item),
      ];
      if (checks.isNotEmpty) {
        dnsChecks = {
          ...dnsChecks,
          for (final check in checks)
            if (check.server.isNotEmpty) check.server: check,
        };
      }
      return checks;
    } catch (e) {
      if (!quiet) error = _message(e);
      return const [];
    } finally {
      dnsChecking = false;
      notifyListeners();
    }
  }

  /// The resolver the active exit node publishes, empty when the switch is off
  /// or the server has none. The stored profile is the source of truth, exactly
  /// like the Android client: the live status is blank for one poll after the
  /// exit settings change, and a row that disappears from "In use" for fifteen
  /// seconds looks like a lost setting. The status only fills a profile that
  /// was imported before the server published its resolver.
  String get exitDnsServer {
    if (!config.exitDnsEnabled || exitDnsHidden) return '';
    for (final profile in exits) {
      if (profile.id == activeExitId && profile.dns.isNotEmpty) {
        return profile.dns;
      }
    }
    return exitStatus.active?.dnsAddress ?? '';
  }

  /// Re-checks the resolver lists the current DNS mode uses. The resolver of
  /// the exit node belongs to the list even though the switch owns it: "Check
  /// now" has to measure it too, or its row keeps no result.
  ///
  /// Returns true when the node answered for the list, even if every server
  /// failed: an empty answer means the stack was not ready yet and the caller
  /// may try again. This is the contract the Android client uses.
  Future<bool> verifyDns({bool quiet = false}) async {
    final checks = await _dnsRound(quiet: quiet);
    return checks.isNotEmpty;
  }

  Future<DnsCheck?> checkDnsServer(String server) async {
    final direct = _isIpv4(server);
    final checks = await checkDns([server], direct: direct);
    return checks.isEmpty ? null : checks.first;
  }

  static bool _isIpv4(String value) =>
      RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(value);

  // ------------------------------------------------------------ services

  Future<void> addService(ServiceEntry entry) => _run(() async {
    final data = await client.post('/v1/services', entry.toJson());
    _applyServices(data);
    _publishNotice('Resource added');
  });

  Future<void> removeService(String id) => _run(() async {
    final data = await client.delete(
      '/v1/services?id=${Uri.encodeQueryComponent(id)}',
    );
    _applyServices(data);
    _publishNotice('Resource deleted');
  });

  Future<int> deleteResources(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return 0;
    final before = resources.length;
    await _run(() async {
      final query = [
        for (final id in list) 'id=${Uri.encodeQueryComponent(id)}',
      ].join('&');
      final data = await client.delete('/v1/services?$query');
      _applyServices(data);
    });
    return before - resources.length;
  }

  Future<void> reorderResources(List<String> ids) async {
    if (ids.length < 2) return;
    final byId = {for (final item in resources) item.id: item};
    resources = [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
      for (final item in resources)
        if (!ids.contains(item.id)) item,
    ];
    notifyListeners();
    try {
      final data = await client.put('/v1/services/order', {'ids': ids});
      _applyServices(data);
      notifyListeners();
    } catch (e) {
      error = _message(e);
      notifyListeners();
    }
  }

  /// Brings back the built-in entries the user deleted. The core keeps the
  /// catalogue, so the window only asks for it.
  Future<void> restoreBuiltIns() => _run(() async {
    final data = await client.post('/v1/services/restore');
    _applyServices(data);
    _publishNotice('Built-in resources restored');
  });

  /// Applies a services answer of the core: the merged list and the built-in
  /// entries the user deleted, which the page uses for the restore action.
  void _applyServices(Object? data) {
    if (data is! Map || data['services'] is! List) return;
    resources = _servicesOf(data['services']);
    config.services = resources;
    final hidden = data['hidden'];
    if (hidden is List) {
      config.hiddenServices = [for (final id in hidden) '$id'];
    }
  }

  /// Reads the web directory through the running node.
  Future<void> loadDirectory() async {
    if (loadingDirectory) return;
    loadingDirectory = true;
    directoryError = null;
    notifyListeners();
    try {
      final data = await client.post(
        '/v1/directory',
        null,
        const Duration(seconds: 40),
      );
      final list = data is Map ? data['resources'] as List? : null;
      final known = {for (final item in resources) item.url};
      directoryResources = [
        for (final item in (list ?? const []))
          if (item is Map<String, dynamic>)
            if (!known.contains(item['url'])) ServiceEntry.fromJson(item),
      ];
      if (directoryResources.isEmpty) directoryError = 'directoryEmpty';
    } catch (e) {
      directoryError = 'directoryFailed';
    } finally {
      loadingDirectory = false;
      notifyListeners();
    }
  }

  Future<int> importResources(List<ServiceEntry> entries) async {
    var added = 0;
    for (final entry in entries) {
      await addService(entry);
      added++;
    }
    directoryResources = const [];
    return added;
  }

  static List<ServiceEntry> _servicesOf(Object? list) => [
    for (final item in (list as List? ?? const []))
      if (item is Map<String, dynamic>) ServiceEntry.fromJson(item),
  ];

  // ------------------------------------------------------------- helpers

  Future<void> _run(
    Future<void> Function() action, {
    bool refreshAfter = false,
  }) async {
    busy = true;
    error = null;
    _clearNotice();
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
    _clearNotice();
    notifyListeners();
  }

  /// Publishes a one-line message in the window banner. The tray uses it for
  /// results it cannot show itself, such as the exit node check.
  void showNotice(String message) {
    error = null;
    _publishNotice(message);
    notifyListeners();
  }

  /// Shows a notification for three seconds, the way the Android snack bar
  /// does. The banner used to stay until the next action, so a "Settings saved"
  /// line from a minute ago was still sitting at the top of the window.
  void _publishNotice(String message) {
    _noticeTimer?.cancel();
    notice = message;
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (notice != message) return;
      notice = null;
      notifyListeners();
    });
  }

  void _clearNotice() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    notice = null;
  }

  String _message(Object e) {
    if (e is CoreException) return e.message;
    // The platform text of a timeout ("The semaphore timeout period has
    // expired", "Превышен таймаут семафора") says nothing to the user.
    if (e is TimeoutException) return 'The core did not answer in time';
    return '$e';
  }

  /// Stops the timers and the core. The tray quit path awaits it, so the core
  /// can restore the system proxy before the process disappears.
  Future<void> shutdown() async {
    _fast?.cancel();
    _slow?.cancel();
    _noticeTimer?.cancel();
    _catalogRetry?.cancel();
    _fast = null;
    _slow = null;
    _noticeTimer = null;
    _catalogRetry = null;
    // Stops a scheduled DNS round that is still waiting for the stack.
    _dnsGeneration++;
    await core.stop();
  }

  @override
  void dispose() {
    _fast?.cancel();
    _slow?.cancel();
    _noticeTimer?.cancel();
    _catalogRetry?.cancel();
    _dnsGeneration++;
    unawaited(core.stop());
    super.dispose();
  }
}
