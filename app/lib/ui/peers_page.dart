import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Peers: the public list, the discovery, the results, the active set and the
/// replacement pool — the same five cards the Android client shows.
class PeersPage extends StatefulWidget {
  const PeersPage({super.key});

  @override
  State<PeersPage> createState() => _PeersPageState();
}

class _PeersPageState extends State<PeersPage> {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final statuses = {for (final peer in app.peers) peer.uri: peer};
    final configured = app.configuredPeers;
    final up = [
      for (final uri in configured)
        if (statuses[uri]?.up == true) uri,
    ].length;
    final alive = app.probeResults.where((row) => row.up).toList();

    return PageScaffold(
      title: 'Peers',
      child: PageScroll(
        children: [
          _CatalogCard(app: app),
          const SizedBox(height: 8),
          _DiscoveryCard(app: app),
          if (alive.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ResultsCard(app: app),
          ],
          const SizedBox(height: 8),
          _ActiveCard(app: app, up: up),
          const SizedBox(height: 8),
          _PoolCard(app: app, statuses: statuses),
        ],
      ),
    );
  }
}

/// Public peers: the way into the whole list and the count of what is loaded.
class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Public peers',
      subtitle:
          'The whole public-peer list with every transport: tls, tcp, '
          'quic, ws and wss. Filter it, test it and add what you need.',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _openBrowser(context),
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: const Text('Browse all public peers'),
                ),
              ),
            ],
          ),
        ),
        if (app.candidates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Peers: ${app.candidates.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openBrowser(BuildContext context) async {
    if (app.candidates.isEmpty) await app.loadCatalog();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: AppScope(state: app, child: const PeerBrowser()),
        ),
      ),
    );
  }
}

/// Peer discovery: the detected location, the progress and the button that
/// fills the results.
class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = [
      if (app.detected.city.isNotEmpty) app.detected.city,
      if (app.detected.countryName.isNotEmpty) app.detected.countryName,
    ].join(', ');
    final selected = app.countrySlug.isEmpty
        ? null
        : app.countries
              .where((item) => item.slug == app.countrySlug)
              .firstOrNull;

    return SectionCard(
      title: 'Peer discovery',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (app.detected.countrySlug.isNotEmpty ||
                  app.countrySlug.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _pickCountry(context),
                    child: Row(
                      children: [
                        FlagBadge(
                          flag: selected?.flag ?? app.detected.flag,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Detected location',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                selected?.name ?? place,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              if (app.probing) ...[
                const LinearProgressIndicator(minHeight: 6),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.loadingPeers
                            ? 'Downloading the public peer list'
                            : 'Measuring Yggdrasil latency',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: app.cancelProbe,
                    child: const Text('Cancel'),
                  ),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: app.loadingPeers ? null : app.probePeers,
                  icon: const Icon(Icons.radar_rounded),
                  label: const Text('Find peers'),
                ),
                const SizedBox(height: 8),
                Text(
                  formatAgo(app.peersUpdatedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickCountry(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pick a country manually'),
        content: SizedBox(
          width: 420,
          height: 460,
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.my_location_rounded),
                title: const Text('Detect automatically'),
                trailing: app.countrySlug.isEmpty
                    ? const Icon(Icons.check_rounded, size: 18)
                    : null,
                onTap: () => Navigator.of(dialogContext).pop(''),
              ),
              const Divider(),
              for (final country in app.countries)
                ListTile(
                  leading: FlagBadge(flag: country.flag, size: 30),
                  title: Text(country.name),
                  subtitle: Text('${country.count} peers'),
                  trailing: app.countrySlug == country.slug
                      ? const Icon(Icons.check_rounded, size: 18)
                      : null,
                  onTap: () => Navigator.of(dialogContext).pop(country.slug),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await app.setCountry(selected);
  }
}

/// The answers of the last test, with the one button that keeps the best.
class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The card shows the rows in the same order the button ranks them: the
    // fastest first. Otherwise the button could keep a peer that the list
    // showed below the fold, which looked like it came from nowhere.
    final alive = app.probeResults.where((row) => row.up).toList()
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    final wanted = int.tryParse(app.config.peerCount.trim()) ?? 3;
    return SectionCard(
      title: 'Results',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: AppColors.online,
              ),
              const SizedBox(width: 6),
              Text(
                '${alive.length} alive',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.online,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        for (final row in alive.take(8))
          ListTile(
            dense: true,
            leading: FlagBadge(flag: _flagOf(app, row.uri), size: 30),
            title: Text(
              uriHost(row.uri),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              shortUri(row.uri),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatLatency(row.latencyMs),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.online,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  tooltip: 'Add',
                  onPressed: app.busy
                      ? null
                      : () async {
                          await app.addPeer(row.uri);
                          if (!context.mounted) return;
                          showSnack(context, app.error ?? 'Peer added');
                        },
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: FilledButton.tonalIcon(
            onPressed: app.busy
                ? null
                : () async {
                    final changed = await app.applyBestPeers();
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      changed == 0
                          ? 'These are already the best peers'
                          : 'Kept the best $wanted peers in the tunnel',
                    );
                  },
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text('Add the best $wanted'),
          ),
        ),
      ],
    );
  }

  static String _flagOf(AppState app, String uri) {
    for (final peer in app.candidates) {
      if (peer.uri == uri) return peer.flag;
    }
    return '';
  }
}

/// The active set: the exit link on top, then the configured public peers.
class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.app, required this.up});

  final AppState app;
  final int up;

  @override
  Widget build(BuildContext context) {
    final statuses = {for (final peer in app.peers) peer.uri: peer};
    final exitPeer = _exitPeer(app);
    // The pinned peer is part of the tunnel only while the exit is on. With the
    // exit off the row shows a cross, and the user may take it out of the
    // list; switching the exit on brings it back.
    final showExit =
        exitPeer.isNotEmpty && (app.exitEnabled || !app.exitPeerHidden);
    final configured = app.configuredPeers;
    final list = [
      if (showExit) exitPeer,
      for (final uri in configured)
        if (uri != exitPeer) uri,
    ];
    return SectionCard(
      title: 'Active peers',
      subtitle: 'Peers in the tunnel: ${configured.length}',
      children: [
        if (list.isEmpty)
          const EmptyHint(
            icon: Icons.hub_outlined,
            title: 'No active peers',
            body: 'No peer has been added yet',
          )
        else
          for (final uri in list)
            PeerTile(
              uri: uri,
              status: _statusOf(statuses, uri),
              pinned: uri == exitPeer,
              locked: uri != exitPeer || app.exitEnabled,
              title: uri == exitPeer ? _exitName(app) : null,
              flag: _flagOf(app, uri, isExit: uri == exitPeer),
              place: _placeOf(app, uri, isExit: uri == exitPeer),
              trailing: uri != exitPeer
                  ? IconButton(
                      tooltip: 'Remove peer',
                      onPressed: app.busy ? null : () => app.removePeer(uri),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    )
                  : app.exitEnabled
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.lock_rounded, size: 18),
                    )
                  : IconButton(
                      tooltip: 'Remove peer',
                      onPressed: app.busy ? null : app.hideExitPeer,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addManually(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add manually'),
                ),
              ),
              if (list.any((uri) => uri != exitPeer)) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear',
                  onPressed: app.busy ? null : () => _clear(context),
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The flag of a row. The exit node never comes from the public catalogue:
  /// its peer link points at the server itself, so the row falls back to the
  /// flag the core resolved for the exit. Without that fallback the pinned peer
  /// of an imported invite showed no flag at all.
  static String _flagOf(AppState app, String uri, {bool isExit = false}) {
    final fromCatalog = catalogPeerOf(app, uri)?.flag ?? '';
    if (fromCatalog.isNotEmpty) return fromCatalog;
    return isExit ? app.state.exitFlag : '';
  }

  /// "City, Country" of a row, taken from the catalogue or, for the exit node,
  /// from the GeoIP place the core reports in the tunnel state.
  static String _placeOf(AppState app, String uri, {bool isExit = false}) {
    final peer = catalogPeerOf(app, uri);
    if (peer != null) return catalogPlace(peer);
    return isExit ? _exitPlace(app) : '';
  }

  static String _exitPeer(AppState app) {
    for (final profile in app.exits) {
      if (profile.id == app.activeExitId && profile.peer.isNotEmpty) {
        return profile.peer;
      }
    }
    return app.exits.isEmpty ? '' : app.exits.first.peer;
  }

  static String _exitName(AppState app) {
    for (final profile in app.exits) {
      if (profile.id == app.activeExitId) return profile.name;
    }
    return app.exits.isEmpty ? '' : app.exits.first.name;
  }

  /// "City, Country" of the exit node. It never comes from the catalogue: the
  /// core places the exit server by GeoIP and reports the result in the state.
  static String _exitPlace(AppState app) {
    final state = app.state;
    return [
      if (state.exitCity.isNotEmpty) state.exitCity,
      if (state.exitCountry.isNotEmpty) state.exitCountry,
    ].join(', ');
  }

  /// The live row of a configured peer. The node may report the same link with
  /// a normalised URI, so the host is the fallback key.
  static PeerStatus? _statusOf(Map<String, PeerStatus> statuses, String uri) {
    final exact = statuses[uri];
    if (exact != null) return exact;
    final host = uriHost(uri);
    for (final peer in statuses.values) {
      if (uriHost(peer.uri) == host) return peer;
    }
    return null;
  }

  Future<void> _addManually(BuildContext context) async {
    final controller = TextEditingController();
    String? error;
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Add manually'),
          content: SizedBox(
            width: 460,
            child: TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Peer address',
                hintText: 'tls://host:port or wss://host:port/path',
                errorText: error,
              ),
              onSubmitted: (_) async {
                final failure = await _add(app, controller.text);
                if (failure != null) {
                  setLocal(() => error = failure);
                  return;
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final failure = await _add(app, controller.text);
                if (failure != null) {
                  setLocal(() => error = failure);
                  return;
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (added == true && context.mounted) {
      showSnack(context, 'Peer added');
    }
  }

  static Future<String?> _add(AppState app, String value) async {
    final uri = value.trim();
    if (uri.isEmpty) {
      return 'Use an address like tcp://host:port or tls://host:port';
    }
    await app.addPeer(uri);
    final failure = app.error;
    if (failure != null) {
      app.clearMessages();
      return failure;
    }
    return null;
  }

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear'),
        content: const Text(
          'All peers except the pinned exit nodes will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await app.clearPeers();
  }
}

/// The replacement pool: live nodes ready to take the place of a peer that
/// drops.
class _PoolCard extends StatelessWidget {
  const _PoolCard({required this.app, required this.statuses});

  final AppState app;
  final Map<String, PeerStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final results = app.resultsByUri;
    return SectionCard(
      title: 'Replacement pool',
      subtitle: 'Live nodes ready to replace a peer that drops',
      children: [
        if (app.pool.isEmpty)
          const EmptyHint(
            icon: Icons.layers_outlined,
            title: 'The pool is empty — run a peer test',
            body: 'Live nodes ready to replace a peer that drops',
          )
        else
          for (final uri in app.pool)
            PeerTile(
              uri: uri,
              status: PeerStatus(
                uri: uri,
                latencyMs: results[uri]?.latencyMs ?? 0,
              ),
              flag: catalogPeerOf(app, uri)?.flag ?? '',
              place: catalogPlace(catalogPeerOf(app, uri)),
              trailing: IconButton(
                tooltip: 'Remove',
                onPressed: () => app.removePoolPeer(uri),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ),
      ],
    );
  }
}

/// The whole public list: every transport, filtered by country, protocol and
/// port, with a measured latency per peer. The layout follows the Android peer
/// browser.
class PeerBrowser extends StatefulWidget {
  const PeerBrowser({super.key});

  @override
  State<PeerBrowser> createState() => _PeerBrowserState();
}

class _PeerBrowserState extends State<PeerBrowser> {
  String _country = '';
  String _scheme = '';
  bool _only443 = false;

  /// Probing the whole catalogue would take minutes, so the button tests the
  /// part the user is looking at.
  static const int _testLimit = 25;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (app.candidates.isEmpty && !app.loadingPeers) {
      app.loadCatalog();
    }
  }

  List<CatalogPeer> _filtered(AppState app) => [
    for (final peer in app.candidates)
      if ((_country.isEmpty || peer.country == _country) &&
          (_scheme.isEmpty || peer.scheme == _scheme) &&
          (!_only443 || peer.port == 443))
        peer,
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final filtered = _filtered(app);
    final results = app.resultsByUri;
    final added = {for (final uri in app.configuredPeers) uriHost(uri)};

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Public peers',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The whole public-peer list with every transport: tls, tcp, quic, '
            'ws and wss. Filter it, test it and add what you need.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _country,
                isDense: true,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All countries'),
                  ),
                  for (final country in app.countries)
                    DropdownMenuItem(
                      value: country.slug,
                      child: Text(
                        '${country.flag} ${country.name} (${country.count})',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _country = value ?? ''),
              ),
              DropdownButton<String>(
                value: _scheme,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: '', child: Text('All protocols')),
                  DropdownMenuItem(value: 'tls', child: Text('tls')),
                  DropdownMenuItem(value: 'tcp', child: Text('tcp')),
                  DropdownMenuItem(value: 'wss', child: Text('wss')),
                  DropdownMenuItem(value: 'ws', child: Text('ws')),
                  DropdownMenuItem(value: 'quic', child: Text('quic')),
                ],
                onChanged: (value) => setState(() => _scheme = value ?? ''),
              ),
              FilterChip(
                label: const Text('Port 443 only'),
                selected: _only443,
                onSelected: (value) => setState(() => _only443 = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Peers: ${filtered.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sorted by distance from your location, peers in your '
                      'country first. The list keeps this order while you '
                      'filter it.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.75,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: filtered.isEmpty || app.probing
                    ? null
                    : () => app.probeUris([
                        for (final peer in filtered.take(_testLimit)) peer.uri,
                      ]),
                icon: app.probing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed_rounded, size: 18),
                label: Text(app.probing ? 'Testing…' : 'Test latency'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tests the first ${filtered.length < _testLimit ? filtered.length : _testLimit} '
            'of ${filtered.length} peers',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: app.loadingPeers
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? EmptyHint(
                    icon: Icons.public_off_rounded,
                    title: 'No peer matches these filters',
                    body:
                        'The whole public-peer list with every transport: '
                        'tls, tcp, quic, ws and wss.',
                    action: FilledButton.tonalIcon(
                      onPressed: app.loadCatalog,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Load the peer list'),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final peer = filtered[index];
                      final result = results[peer.uri];
                      final isAdded = added.contains(uriHost(peer.uri));
                      return _CatalogRow(
                        peer: peer,
                        result: result,
                        added: isAdded,
                        testing: app.probingUris.contains(peer.uri),
                        onTest: () => app.probeUris([peer.uri]),
                        onAdd: () async {
                          await app.addPeer(peer.uri);
                          if (!context.mounted) return;
                          showSnack(context, app.error ?? 'Peer added');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.peer,
    required this.result,
    required this.added,
    required this.testing,
    required this.onTest,
    required this.onAdd,
  });

  final CatalogPeer peer;
  final ProbeResult? result;
  final bool added;

  /// True while this exact peer is being measured.
  final bool testing;
  final VoidCallback onTest;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = [
      if (peer.city.isNotEmpty) peer.city,
      if (peer.countryName.isNotEmpty) peer.countryName,
    ].join(', ');
    final up = result?.up ?? false;
    final color = result == null
        ? theme.colorScheme.onSurfaceVariant
        : up
        ? AppColors.online
        : AppColors.offline;
    final latencyText = testing
        ? 'testing…'
        : result == null
        ? 'not tested'
        : up
        ? formatLatency(result!.latencyMs)
        : 'no handshake';

    return ListTile(
      onTap: added || testing ? null : onTest,
      leading: FlagBadge(flag: peer.flag),
      title: Text(
        place.isEmpty ? peer.host : place,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shortUri(peer.uri),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${peer.scheme}:${peer.port}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
              if (peer.port == 443) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.verified_user_outlined,
                  size: 12,
                  color: AppColors.teal,
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            latencyText,
            style: theme.textTheme.labelLarge?.copyWith(
              color: testing ? theme.colorScheme.secondary : color,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: testing ? 'Testing…' : 'Check this peer',
            onPressed: testing ? null : onTest,
            icon: testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed_rounded, size: 20),
          ),
          IconButton(
            tooltip: added ? 'Already added' : 'Add to the tunnel',
            onPressed: added ? null : onAdd,
            icon: Icon(
              added
                  ? Icons.check_circle_rounded
                  : Icons.add_circle_outline_rounded,
              size: 22,
              color: added ? AppColors.online : theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
