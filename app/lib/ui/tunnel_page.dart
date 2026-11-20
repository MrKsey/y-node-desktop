import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// The tunnel screen: the hero card with this device on the left, the exit node
/// on the right and the power button between them, then the counters, the
/// active peers, the exit card and the address — the Android layout.
class TunnelPage extends StatefulWidget {
  const TunnelPage({
    super.key,
    required this.onOpenPeers,
    required this.onOpenExit,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenPeers;
  final VoidCallback onOpenExit;
  final VoidCallback onOpenSettings;

  @override
  State<TunnelPage> createState() => _TunnelPageState();
}

class _TunnelPageState extends State<TunnelPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat();
    // The flag on the exit icon and the country of every peer come from the
    // public list, the same background load the Android client runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = AppScope.of(context);
      if (app.candidates.isEmpty && !app.loadingPeers) {
        app.loadCatalog();
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final live = app.state;
    final connected = live.running;
    final busy = app.busy;
    final exitProfile = _activeExit(app);
    final exitPeer = exitProfile?.peer.trim() ?? '';
    final statuses = {for (final peer in app.peers) peer.uri: peer};
    final configured = app.configuredPeers;
    // A launch without peers runs the discovery by itself: the power button is
    // locked until a live node is found, so a click cannot start a node that
    // has nothing to connect to.
    final noPeers = app.noPeers;
    final searching = app.searchingPeers;
    final up = [
      for (final uri in configured)
        if (_statusOf(statuses, uri)?.up == true) uri,
    ].length;
    final exitFlag = _flagOf(app, exitPeer);

    return PageScaffold(
      title: 'Y-Node',
      subtitle: 'A Yggdrasil network client',
      child: PageScroll(
        children: [
          _Hero(
            pulse: _pulse,
            statusLabel: connected
                ? 'Connected'
                : searching
                ? 'Searching peers…'
                : busy
                ? 'Connecting…'
                : 'Disconnected',
            statusColor: connected
                ? AppColors.online
                : searching || busy
                ? AppColors.pending
                : AppColors.offline,
            connected: connected,
            busy: busy,
            searching: searching,
            locked: noPeers,
            stageText: _stageText(app),
            peersUp: up,
            peersTotal: configured.length,
            connectedAt: live.uptimeSeconds,
            exitName: exitProfile?.name ?? live.exitName,
            exitFlag: exitFlag,
            exitOn: app.exitEnabled,
            exitInUse: live.exitInUse,
            exitState: live.exitState,
            onToggle: () => connected ? app.disconnect() : app.connect(),
            onMeTap: () => _showIp(context, app, viaExit: false),
            onExitTap: () => _showIp(context, app, viaExit: true),
            errorText:
                app.error ?? (live.lastError.isEmpty ? null : live.lastError),
          ),
          const SizedBox(height: 16),
          _StatsCard(
            up: live.txBytes,
            down: live.rxBytes,
            latency: live.latencyMs,
            healthCheckSec: _healthCheck(app),
            onLatencyInfo: () => _showLatencyInfo(context, app),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Active peers',
            subtitle: configured.isEmpty
                ? null
                : connected
                ? '$up of ${configured.length} connected'
                : 'Peers in the tunnel: ${configured.length}',
            children: [
              if (configured.isEmpty && exitPeer.isEmpty)
                EmptyHint(
                  icon: searching ? Icons.search_rounded : Icons.hub_outlined,
                  title: searching
                      ? 'Looking for live nodes'
                      : 'No peers selected',
                  body: searching
                      ? 'The Connect button unlocks as soon as a live node '
                            'answers'
                      : 'Open Peers to find nodes',
                  action: searching
                      ? null
                      : FilledButton.tonalIcon(
                          onPressed: app.probing || app.loadingPeers
                              ? null
                              : () async {
                                  final ok = await app.findAndAddPeers();
                                  if (!context.mounted) return;
                                  if (!ok) {
                                    showSnack(
                                      context,
                                      app.error ??
                                          'No live node was found. '
                                              'Try again later.',
                                    );
                                  }
                                },
                          icon: app.probing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search_rounded),
                          label: const Text('Find peers'),
                        ),
                )
              else
                for (final uri in [
                  if (exitPeer.isNotEmpty) exitPeer,
                  for (final item in configured)
                    if (item != exitPeer) item,
                ])
                  PeerTile(
                    uri: uri,
                    status: _statusOf(statuses, uri),
                    pinned: uri == exitPeer,
                    highlight: live.exitInUse && uri == exitPeer,
                    title: uri == exitPeer ? exitProfile?.name : null,
                    flag: uri == exitPeer
                        ? (catalogPeerOf(app, uri)?.flag ?? exitFlag)
                        : (catalogPeerOf(app, uri)?.flag ?? ''),
                    place: catalogPlace(catalogPeerOf(app, uri)),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: widget.onOpenPeers,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Peers'),
                    ),
                    const Spacer(),
                    if (connected)
                      TextButton.icon(
                        // Android's "Re-check now" asks the running supervisor
                        // for the live peer state. It does not probe the public
                        // catalogue: that round takes minutes and is what the
                        // Peers page is for.
                        onPressed: () async {
                          await app.refresh();
                          await app.refreshLists();
                          if (!context.mounted) return;
                          showSnack(
                            context,
                            'Peer state re-read from the node',
                          );
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Re-check now'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ExitCard(
            app: app,
            profile: exitProfile,
            connected: connected,
            onOpenExit: widget.onOpenExit,
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Your address',
            children: [
              ScrollableInfoRow(
                label: 'Node address',
                value: live.address.isEmpty ? '—' : live.address,
                copyHint: 'copy',
                onTap: live.address.isEmpty
                    ? null
                    : () => copyText(context, live.address, 'Address copied'),
              ),
              if (live.subnet.isNotEmpty)
                ScrollableInfoRow(
                  label: 'Subnet',
                  value: live.subnet,
                  copyHint: 'copy',
                  onTap: () => copyText(context, live.subnet, 'Address copied'),
                ),
              InfoRow(
                label: 'Public key',
                value: _shortKey(live.publicKey),
                monospace: true,
                onTap: live.publicKey.isEmpty
                    ? null
                    : () => copyText(context, live.publicKey, 'Address copied'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static int _healthCheck(AppState app) =>
      int.tryParse(app.config.peerCheckIntervalSec) ?? 30;

  static String _shortKey(String key) {
    if (key.length <= 20) return key.isEmpty ? '—' : key;
    return '${key.substring(0, 10)}…${key.substring(key.length - 6)}';
  }

  static String _stageText(AppState app) {
    if (app.searchingPeers) return 'Looking for the best peers';
    if (app.busy && !app.state.running) return 'Preparing the tunnel';
    if (!app.state.running) return 'Connect';
    if (app.state.peersUp == 0) return 'Waiting for the first peer to answer';
    return 'The tunnel is up';
  }

  static ExitProfile? _activeExit(AppState app) {
    for (final profile in app.exits) {
      if (profile.id == app.activeExitId) return profile;
    }
    return app.exits.isEmpty ? null : app.exits.first;
  }

  static PeerStatus? _statusOf(Map<String, PeerStatus> statuses, String uri) {
    final exact = statuses[uri];
    if (exact != null) return exact;
    final host = uriHost(uri);
    for (final peer in statuses.values) {
      if (uriHost(peer.uri) == host) return peer;
    }
    return null;
  }

  static String _flagOf(AppState app, String uri) {
    if (uri.isEmpty) return '';
    final host = uriHost(uri);
    for (final peer in app.candidates) {
      if (peer.uri == uri || peer.host == host) return peer.flag;
    }
    // The exit node is not in the public list: the core places it by GeoIP.
    return app.state.exitFlag;
  }

  Future<void> _showIp(
    BuildContext context,
    AppState app, {
    required bool viaExit,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AppScope(
        state: app,
        child: _IpDialog(viaExit: viaExit),
      ),
    );
  }

  Future<void> _showLatencyInfo(BuildContext context, AppState app) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Latency'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Latency is the round-trip time between the node on this '
                'computer and each connected peer, averaged over the peers '
                'that are up. Yggdrasil sends a signed request over every link '
                'and waits for a valid signed response; the figure shown is an '
                'exponential average of those round trips. It is a protocol '
                'measurement, not an ICMP ping.',
              ),
              const SizedBox(height: 12),
              Text(
                'Refreshed every ${_healthCheck(app)} s · Settings → Connection',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// The hero card: status, the link with the power button and the line under it.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.pulse,
    required this.statusLabel,
    required this.statusColor,
    required this.connected,
    required this.busy,
    required this.searching,
    required this.locked,
    required this.stageText,
    required this.peersUp,
    required this.peersTotal,
    required this.connectedAt,
    required this.exitName,
    required this.exitFlag,
    required this.exitOn,
    required this.exitInUse,
    required this.exitState,
    required this.onToggle,
    required this.onMeTap,
    required this.onExitTap,
    this.errorText,
  });

  final AnimationController pulse;
  final String statusLabel;
  final Color statusColor;
  final bool connected;
  final bool busy;
  final bool searching;
  final bool locked;
  final String stageText;
  final int peersUp;
  final int peersTotal;
  final int connectedAt;
  final String exitName;
  final String exitFlag;
  final bool exitOn;
  final bool exitInUse;
  final String exitState;
  final VoidCallback onToggle;
  final VoidCallback onMeTap;
  final VoidCallback onExitTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkUp = connected || busy;
    final pending = busy || searching;
    final exitLit = exitOn && linkUp;
    final exitColor = exitState == 'denied' || exitState == 'unreachable'
        ? AppColors.pending
        : theme.colorScheme.primary;
    final exitLabel = exitName.isEmpty ? 'Exit node' : _shortExitName(exitName);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          children: [
            StatusPill(label: statusLabel, color: statusColor),
            const SizedBox(height: 6),
            Row(
              children: [
                _HeroEntity(
                  label: 'Me',
                  icon: Icons.person_rounded,
                  color: statusColor,
                  active: linkUp,
                  hint: 'Tap to see the address',
                  onTap: onMeTap,
                ),
                Expanded(
                  child: _FlowLink(
                    animation: pulse,
                    color: statusColor,
                    on: linkUp,
                  ),
                ),
                SizedBox(
                  width: 134,
                  height: 141,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (busy)
                        AnimatedBuilder(
                          animation: pulse,
                          builder: (context, child) {
                            final t = pulse.value;
                            return Opacity(
                              opacity: (1 - t) * 0.5,
                              child: Transform.scale(
                                scale: 1 + 0.16 * t,
                                child: Container(
                                  width: 112,
                                  height: 112,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: statusColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      PowerButton(
                        connected: connected,
                        busy: busy,
                        enabled: !locked,
                        onPressed: onToggle,
                        tooltip: searching
                            ? 'Looking for the best peers…'
                            : locked
                            ? 'No peers yet'
                            : connected
                            ? 'Disconnect'
                            : 'Connect',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _FlowLink(
                    animation: pulse,
                    color: exitColor,
                    on: exitLit,
                    phase: 0.35,
                  ),
                ),
                _HeroEntity(
                  label: exitLabel,
                  icon: Icons.vpn_lock_rounded,
                  flag: exitFlag,
                  color: exitColor,
                  active: exitLit,
                  locked: exitInUse,
                  hint: 'Tap to see the address',
                  onTap: onExitTap,
                ),
              ],
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 64,
              child: Align(
                alignment: Alignment.topCenter,
                child: pending
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            stageText,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 200,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: const LinearProgressIndicator(
                                minHeight: 3,
                              ),
                            ),
                          ),
                          if (peersTotal > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              '$peersUp of $peersTotal connected',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            connected ? 'Disconnect' : 'Connect',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (connected && connectedAt > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 15,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Connected for ${formatUptime(connectedAt)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            if (errorText != null && errorText!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.offline.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.offline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _shortExitName(String name) {
    final trimmed = name.trim();
    if (trimmed.length <= 20) return trimmed;
    return '${trimmed.substring(0, 19)}…';
  }
}

/// One end of the hero link: a tap opens the address balloon.
class _HeroEntity extends StatelessWidget {
  const _HeroEntity({
    required this.label,
    required this.color,
    required this.active,
    required this.hint,
    required this.onTap,
    this.icon,
    this.flag = '',
    this.locked = false,
  });

  final String label;
  final Color color;
  final bool active;
  final String hint;
  final VoidCallback onTap;
  final IconData? icon;
  final String flag;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idle = theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 18),
          Semantics(
            button: true,
            hint: hint,
            child: Tooltip(
              message: hint,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? color.withValues(alpha: 0.14)
                            : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.6),
                        border: Border.all(
                          color: active
                              ? color.withValues(alpha: 0.55)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: flag.isNotEmpty
                          ? FlagPicture(flag: flag, size: 46)
                          : Icon(
                              icon ?? Icons.circle,
                              size: 21,
                              color: active ? color : idle,
                            ),
                    ),
                    if (locked)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            size: 8,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              height: 1.2,
              color: active ? theme.colorScheme.onSurface : idle,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The animated line between an entity and the power button.
class _FlowLink extends StatelessWidget {
  const _FlowLink({
    required this.animation,
    required this.color,
    required this.on,
    this.phase = 0,
  });

  final Animation<double> animation;
  final Color color;
  final bool on;
  final double phase;

  @override
  Widget build(BuildContext context) {
    Widget paint(double t) => CustomPaint(
      size: Size.infinite,
      painter: _FlowPainter(t: t, color: color, flow: on),
    );

    return SizedBox(
      height: 22,
      child: RepaintBoundary(
        child: on
            ? AnimatedBuilder(
                animation: animation,
                builder: (context, _) => paint((animation.value + phase) % 1.0),
              )
            : paint(0),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({required this.t, required this.color, required this.flow});

  final double t;
  final Color color;
  final bool flow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final y = size.height / 2;
    final line = Paint()
      ..color = color.withValues(alpha: flow ? 0.45 : 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 3.0;
    const gap = 4.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      final end = x + dash > size.width ? size.width : x + dash;
      canvas.drawLine(Offset(x, y), Offset(end, y), line);
    }
    if (!flow) return;
    final dot = Paint()..color = color;
    final halo = Paint()..color = color.withValues(alpha: 0.18);
    for (var i = 0; i < 2; i++) {
      final x = size.width * ((t + i * 0.5) % 1.0);
      canvas.drawCircle(Offset(x, y), 4.5, halo);
      canvas.drawCircle(Offset(x, y), 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) =>
      old.t != t || old.color != color || old.flow != flow;
}

/// Received, latency and sent, with the hint line of the Android stats card.
class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.up,
    required this.down,
    required this.latency,
    required this.healthCheckSec,
    required this.onLatencyInfo,
  });

  final int up;
  final int down;
  final double latency;
  final int healthCheckSec;
  final VoidCallback onLatencyInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StatBlock(
                    icon: Icons.download_rounded,
                    label: 'Received',
                    value: formatBytes(down),
                  ),
                ),
                Expanded(
                  child: StatBlock(
                    icon: Icons.speed_rounded,
                    label: 'Latency',
                    value: formatLatency(latency),
                    onTap: onLatencyInfo,
                  ),
                ),
                Expanded(
                  child: StatBlock(
                    icon: Icons.upload_rounded,
                    label: 'Sent',
                    value: formatBytes(up),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: onLatencyInfo,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Average round-trip to the connected peers',
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Refreshed every $healthCheckSec s · Settings → Connection',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The exit node card: the switch, the quota, the UDP relay and the IPv6 rows
/// with their checks, and the buttons that lead to the profiles.
class _ExitCard extends StatefulWidget {
  const _ExitCard({
    required this.app,
    required this.profile,
    required this.connected,
    required this.onOpenExit,
  });

  final AppState app;
  final ExitProfile? profile;
  final bool connected;
  final VoidCallback onOpenExit;

  @override
  State<_ExitCard> createState() => _ExitCardState();
}

class _ExitCardState extends State<_ExitCard> {
  bool _testingUdp = false;
  bool _testingIpv6 = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final theme = Theme.of(context);
    final status = app.exitStatus;
    final active = status.active;
    final quota = active?.quota;
    final suspended = active?.suspended ?? false;
    final connected = widget.connected;
    final uiColor = !app.exitEnabled
        ? theme.colorScheme.outline
        : suspended || status.state == 'denied' || status.state == 'unreachable'
        ? AppColors.pending
        : status.state == 'online'
        ? AppColors.online
        : connected
        ? AppColors.pending
        : theme.colorScheme.outline;
    final label = !app.exitEnabled
        ? 'Off'
        : widget.profile == null
        ? 'No node'
        : suspended
        ? 'Suspended'
        : switch (status.state) {
            'online' => 'Online',
            'denied' => 'Not allowed',
            'unreachable' => 'Unreachable',
            _ => connected ? 'Connecting…' : 'Off',
          };
    final detail = !app.exitEnabled
        ? 'Public traffic leaves the computer directly'
        : widget.profile == null
        ? 'Add a node to send public traffic through it'
        : status.state == 'online'
        ? '${widget.profile!.name} · '
              '${(active?.latencyMs ?? 0).toStringAsFixed(0)} ms'
              '${active?.dnsAddress.isNotEmpty == true ? ' · DNS ${active!.dnsAddress}' : ''}'
        : connected
        ? 'Bringing the exit node up'
        : 'The exit is used when the tunnel connects';
    final ipv6State = active?.ipv6State ?? '';
    final ipv6Broken = ipv6State == 'broken';
    final ipv6Missing = ipv6State == 'none';
    final ipv6Off = ipv6State == 'off';
    final ipv6Hint = ipv6Off
        ? 'IPv6 is turned off on the exit node. Only IPv4 traffic goes through '
              'this exit.'
        : ipv6Broken
        ? 'The exit has an IPv6 address, but its provider does not route IPv6. '
              'IPv6 traffic is not sent through this exit.'
        : ipv6Missing
        ? 'The exit has no global IPv6 address. IPv6 traffic is not sent '
              'through this exit.'
        : 'Global IPv6 addresses go through the exit node';
    final ipv6Color = ipv6Broken || ipv6Missing || ipv6Off
        ? AppColors.pending
        : theme.colorScheme.primary;

    return SectionCard(
      title: 'Exit node',
      children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          leading: CircleAvatar(
            backgroundColor: uiColor.withValues(alpha: 0.14),
            child: Icon(Icons.vpn_lock_rounded, color: uiColor),
          ),
          title: Row(
            children: [
              const Text('Exit node'),
              const SizedBox(width: 8),
              StatusPill(label: label, color: uiColor),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(detail),
          ),
          trailing: Switch(
            value: app.exitEnabled,
            onChanged: app.exits.isEmpty || app.busy
                ? null
                : app.setExitEnabled,
          ),
        ),
        if (connected && app.exitEnabled && quota != null)
          _QuotaRow(quota: quota),
        if (connected && app.exitEnabled)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            leading: const Icon(Icons.swap_vert_rounded, size: 20),
            title: const Text('UDP relay'),
            subtitle: Text(
              status.udp.enabled
                  ? status.udp.state == 'online'
                        ? 'Through the exit node'
                        : 'Ready, opens with the first datagram'
                  : 'Public UDP is not carried by the exit',
              style: theme.textTheme.bodySmall,
            ),
            trailing: _testingUdp
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Check UDP and QUIC',
                    onPressed: () => _testUdp(),
                    icon: const Icon(Icons.travel_explore, size: 20),
                  ),
          ),
        if (connected && app.exitEnabled)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            leading: Icon(Icons.language_rounded, size: 20, color: ipv6Color),
            title: Row(
              children: [
                const Text('IPv6'),
                if (ipv6Broken || ipv6Missing || ipv6Off) ...[
                  const SizedBox(width: 8),
                  StatusPill(
                    label: ipv6Off
                        ? 'IPv6 off'
                        : ipv6Broken
                        ? 'IPv6 not routed'
                        : 'No IPv6',
                    color: AppColors.pending,
                  ),
                ],
              ],
            ),
            subtitle: Text(ipv6Hint, style: theme.textTheme.bodySmall),
            trailing: _testingIpv6
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Check IPv6',
                    onPressed: () => _testIpv6(),
                    icon: const Icon(Icons.travel_explore, size: 20),
                  ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: widget.onOpenExit,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Manage'),
              ),
              const Spacer(),
              if (connected && app.exitEnabled)
                TextButton.icon(
                  onPressed: app.busy
                      ? null
                      : () async {
                          final report = await app.checkExit();
                          if (!context.mounted) return;
                          showMessage(context, 'Exit node check', report);
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check now'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _testUdp() async {
    setState(() => _testingUdp = true);
    final result = await widget.app.testExitUdp();
    if (!mounted) return;
    setState(() => _testingUdp = false);
    if (result == null) {
      showSnack(context, 'The check could not run');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('UDP relay check'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stageLine('UDP · DNS through the exit', result.udp),
              const SizedBox(height: 8),
              _stageLine('QUIC · h3 handshake', result.quic),
              const SizedBox(height: 8),
              Text(
                '${result.datagramsOut} datagram(s) out, '
                '${result.datagramsIn} in',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              if (result.profile.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Carried by ${result.profile}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
              if (result.error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  result.error,
                  style: Theme.of(dialogContext).textTheme.bodySmall
                      ?.copyWith(color: AppColors.pending),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _testIpv6() async {
    setState(() => _testingIpv6 = true);
    final result = await widget.app.testExitIpv6();
    if (!mounted) return;
    setState(() => _testingIpv6 = false);
    if (result == null) {
      showSnack(context, 'The IPv6 check could not run');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('IPv6 check'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stageLine('TCP · HTTPS over IPv6', result.tcp),
              const SizedBox(height: 8),
              _stageLine('UDP · DNS over IPv6', result.udp),
              if (result.tcp.address.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'The exit uses ${result.tcp.address}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
              if (result.profile.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Carried by ${result.profile}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
              if (result.error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  result.error,
                  style: Theme.of(dialogContext).textTheme.bodySmall
                      ?.copyWith(color: AppColors.pending),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _stageLine(String label, ExitProbeStage stage) {
    final theme = Theme.of(context);
    final color = stage.skipped
        ? theme.colorScheme.outline
        : stage.ok
        ? AppColors.online
        : AppColors.pending;
    final detail = [
      if (stage.version.isNotEmpty) 'h3 ${stage.version}',
      if (stage.target.isNotEmpty) stage.target,
    ].join(' · ');
    final text = stage.skipped
        ? 'not run'
        : stage.ok
        ? [
            'OK · ${stage.latencyMs.toStringAsFixed(0)} ms',
            if (detail.isNotEmpty) detail,
          ].join(' · ')
        : stage.error.isEmpty
        ? 'failed'
        : stage.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          stage.skipped
              ? Icons.remove_circle_outline
              : stage.ok
              ? Icons.check_circle_rounded
              : Icons.error_outline_rounded,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                text,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuotaRow extends StatelessWidget {
  const _QuotaRow({required this.quota});

  final ExitQuota quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = quota.exhausted
        ? AppColors.pending
        : theme.colorScheme.primary;
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    final lines = <Widget>[
      if (quota.monthlyBytes > 0)
        Text(
          'This month ${formatBytes(quota.monthUsed)} of '
          '${formatBytes(quota.monthlyBytes)}',
          style: style,
        )
      else if (quota.dailyBytes == 0)
        Text(
          'No traffic limit · ${formatBytes(quota.monthUsed)} this month',
          style: style,
        ),
      if (quota.dailyBytes > 0)
        Text(
          'Today ${formatBytes(quota.dayUsed)} of '
          '${formatBytes(quota.dailyBytes)}',
          style: style,
        ),
      if (quota.hasSpeed)
        Text(
          [
            if (quota.downKbps > 0)
              'Download limit ${formatBitRate(quota.downKbps)}',
            if (quota.upKbps > 0) 'Upload limit ${formatBitRate(quota.upKbps)}',
          ].join(' · '),
          style: style,
        ),
      if (quota.exhausted)
        Text(
          quota.reason.isEmpty
              ? 'The traffic quota is exhausted'
              : quota.reason,
          style: style,
        ),
    ];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      leading: Icon(Icons.data_usage_rounded, size: 20, color: color),
      title: const Text('Traffic quota'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: lines,
      ),
      isThreeLine: lines.length > 1,
    );
  }
}

/// The address balloon: what websites see with or without the tunnel.
class _IpDialog extends StatefulWidget {
  const _IpDialog({required this.viaExit});

  final bool viaExit;

  @override
  State<_IpDialog> createState() => _IpDialogState();
}

class _IpDialogState extends State<_IpDialog> {
  PublicIpResult? _result;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_result == null) _load();
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    final result = await app.publicIp(viaExit: widget.viaExit);
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final result = _result;
    final title = widget.viaExit ? 'Through the exit' : 'Without the tunnel';
    final hint = widget.viaExit
        ? 'What websites see while the exit carries the traffic'
        : 'What websites see on the real network';
    final message = () {
      if (_loading) return 'Checking the address…';
      if (result == null) return 'Could not read the address';
      if (result.ok) return result.ip;
      return switch (result.error) {
        'exit_off' => 'The exit is off',
        'timeout' => 'The check timed out',
        _ => 'Could not read the address',
      };
    }();

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    result?.ok == true
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: result?.ok == true
                        ? AppColors.online
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    message,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            if (!app.state.running && !widget.viaExit) ...[
              const SizedBox(height: 8),
              Text(
                'Connect the tunnel first',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.pending,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (result?.ok == true)
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result!.ip));
              if (context.mounted) showSnack(context, 'Address copied');
            },
            child: const Text('Copy'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
