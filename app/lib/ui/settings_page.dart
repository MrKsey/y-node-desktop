import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../startup.dart';
import '../theme.dart';
import '../update_service.dart';
import 'update_dialog.dart';
import 'widgets.dart';

/// The settings screen: the same sections the Android client shows —
/// Connection, DNS, Network, Appearance, Donate, Update and About — plus the
/// tray block the desktop needs.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// The Windows "Run" entry, read once when the page opens. Null while the
  /// registry is being read: the switch is disabled until the real value is
  /// known, so it never shows a guess.
  bool? _startWithWindows;

  @override
  void initState() {
    super.initState();
    if (StartupEntry.supported) unawaited(_loadStartup());
  }

  Future<void> _loadStartup() async {
    final enabled = await StartupEntry.isEnabled();
    if (!mounted) return;
    setState(() => _startWithWindows = enabled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (app.ready) app.loadDnsPresets();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final config = app.config;
    final mode = config.dnsMode == 'system' ? 'system' : 'yggdrasil';
    // The live status knows the resolver the exit publishes; the stored profile
    // keeps the last known one, so the row does not disappear while the exit is
    // offline. With the switch off the resolver is not used at all.
    final exitResolver = app.exitDnsServer;
    final configured = splitList(
      mode == 'system' ? config.systemDns : config.yggDns,
    );
    // The resolver the exit publishes is not part of the list on disk: the
    // "DNS exit node" switch owns it, and exitJSON adds it at runtime. It is
    // shown anyway, first and locked, so the page tells the whole truth.
    final servers = [
      if (mode != 'system' &&
          exitResolver.isNotEmpty &&
          !configured.contains(exitResolver))
        exitResolver,
      ...configured,
    ];

    return PageScaffold(
      title: 'Settings',
      child: PageScroll(
        children: [
          SectionCard(
            title: 'Connection',
            children: [
              SliderTile(
                label: 'Peers in the tunnel',
                hint: 'How many nodes to keep connected at once',
                value: _peerCount(config).toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
                display: '${_peerCount(config)}',
                onChanged: (value) =>
                    _save(app, (next) => next.peerCount = '${value.round()}'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: config.peerAutoReplace,
                onChanged: (value) =>
                    _save(app, (next) => next.peerAutoReplace = value),
                title: const Text('Replace dropped peers'),
                subtitle: const Text(
                  'Swap a lost node for a live one from the pool',
                ),
              ),
              const Divider(height: 1),
              SliderTile(
                label: 'Treat a peer as dead after',
                value: _seconds(config.peerDeadTimeoutSec, 90).toDouble(),
                min: 15,
                max: 300,
                divisions: 57,
                display: '${_seconds(config.peerDeadTimeoutSec, 90)} s',
                onChanged: (value) => _save(
                  app,
                  (next) => next.peerDeadTimeoutSec = '${value.round()}',
                ),
              ),
              SliderTile(
                label: 'Check interval',
                hint:
                    'How often the peer list and the latency are re-read '
                    'from the node',
                value: _seconds(config.peerCheckIntervalSec, 30).toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                display: '${_seconds(config.peerCheckIntervalSec, 30)} s',
                onChanged: (value) => _save(
                  app,
                  (next) => next.peerCheckIntervalSec = '${value.round()}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'DNS',
            subtitle:
                'The internal DNS servers resolve .ygg names and '
                'Yggdrasil addresses. With System DNS those names will not '
                'resolve.',
            trailing: TextButton.icon(
              onPressed: app.dnsChecking
                  ? null
                  : () async {
                      await app.verifyDns();
                      if (!context.mounted) return;
                      showSnack(context, 'DNS check finished');
                    },
              icon: app.dnsChecking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded, size: 18),
              label: Text(app.dnsChecking ? 'Checking…' : 'Check now'),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    alignment: Alignment.center,
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 'yggdrasil',
                      label: Text(
                        'Yggdrasil internal DNS',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    ButtonSegment(
                      value: 'system',
                      label: Text('System DNS', textAlign: TextAlign.center),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (value) async {
                    final next = value.first;
                    await _save(app, (nextConfig) {
                      nextConfig.dnsMode = next;
                      if (next == 'yggdrasil' &&
                          splitList(nextConfig.yggDns).isEmpty) {
                        nextConfig.yggDns = CoreConfig().yggDns;
                      }
                    });
                    if (mounted) app.verifyDns();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                child: Text(
                  'IN USE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              if (servers.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    mode == 'system'
                        ? 'Automatic: the resolver of the real network'
                        : 'No DNS server answered; check the tunnel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final server in servers)
                  _DnsTile(
                    server: server,
                    label: server == exitResolver
                        ? 'Published by the exit node'
                        : _presetLabel(app, server),
                    check: app.dnsChecks[server],
                    fromExit: exitResolver.isNotEmpty && server == exitResolver,
                    // With the exit node off its resolver is not in the tunnel:
                    // the row offers a cross instead of the lock, and the
                    // "DNS exit node" switch adds it back when the exit is on.
                    removable:
                        exitResolver.isNotEmpty &&
                        server == exitResolver &&
                        !app.exitEnabled,
                    onCheck: app.dnsChecking
                        ? null
                        : () async {
                            await app.checkDnsServer(server);
                            if (mounted) setState(() {});
                          },
                    onRemove: server == exitResolver && !app.exitEnabled
                        ? app.hideExitDns
                        : () => _removeDns(app, mode, server),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addDns(app, mode),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add a server'),
                      ),
                    ),
                  ],
                ),
              ),
              if (mode != 'system') ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                  child: Text(
                    'AVAILABLE SERVERS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
                ...() {
                  final available = [
                    for (final preset in app.dnsPresets)
                      if (!servers.contains(preset.address)) preset,
                  ];
                  if (available.isEmpty) {
                    return [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Text(
                          'Servers published in the Yggdrasil wiki and by '
                          'your exit nodes',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ];
                  }
                  return [
                    for (final preset in available)
                      _DnsTile(
                        server: preset.address,
                        label: preset.label,
                        check: app.dnsChecks[preset.address],
                        onCheck: app.dnsChecking
                            ? null
                            : () async {
                                await app.checkDnsServer(preset.address);
                                if (mounted) setState(() {});
                              },
                        onAdd: () async {
                          await _save(app, (next) {
                            final list = splitList(next.yggDns);
                            if (list.contains(preset.address)) return;
                            list.add(preset.address);
                            next.yggDns = list.join(', ');
                          });
                          if (!mounted) return;
                          app.checkDnsServer(preset.address);
                        },
                      ),
                  ];
                }(),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Network',
            children: [
              SliderTile(
                label: 'MTU',
                hint:
                    '1280 bytes is the smallest MTU IPv6 allows. Yggdrasil '
                    'runs over IPv6 and the path to a peer may cross tunnels '
                    'with a smaller MTU, so a larger value risks silent packet '
                    'loss. Change it only if you know the path is clean.',
                value:
                    int.tryParse(config.mtu)?.toDouble().clamp(1280, 1500) ??
                    1280,
                min: 1280,
                max: 1500,
                divisions: 22,
                display: config.mtu,
                onChanged: (value) =>
                    _save(app, (next) => next.mtu = '${value.round()}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ResponsiveRow(
            first: SectionCard(
              title: 'Appearance',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Theme', style: theme.textTheme.bodyMedium),
                      ),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'auto', label: Text('System')),
                          ButtonSegment(value: 'light', label: Text('Light')),
                          ButtonSegment(value: 'dark', label: Text('Dark')),
                        ],
                        selected: {config.theme},
                        onSelectionChanged: (value) =>
                            _save(app, (next) => next.theme = value.first),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            second: SectionCard(
              title: 'Tray and launch',
              children: [
                SwitchListTile(
                  value: config.autoConnect,
                  onChanged: (value) =>
                      _save(app, (next) => next.autoConnect = value),
                  title: const Text('Connect on launch'),
                  subtitle: const Text(
                    'Turn the tunnel on automatically when Y-Node starts',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: config.closeToTray,
                  onChanged: (value) =>
                      _save(app, (next) => next.closeToTray = value),
                  title: const Text('Close to tray'),
                  subtitle: const Text(
                    'Closing the window hides it. While the tunnel is running '
                    'the application stays in the tray even when this is off.',
                  ),
                ),
                SwitchListTile(
                  value: config.minimizeToTray,
                  onChanged: (value) =>
                      _save(app, (next) => next.minimizeToTray = value),
                  title: const Text('Minimize to tray'),
                  subtitle: const Text(
                    'Minimising the window hides it from the taskbar.',
                  ),
                ),
                if (StartupEntry.supported) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _startWithWindows ?? false,
                    onChanged: _startWithWindows == null
                        ? null
                        : (value) => _setStartWithWindows(value),
                    title: const Text('Start with Windows'),
                    subtitle: const Text(
                      'Open Y-Node minimised in the tray when you sign in',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Donate',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 12.0;
                    final columns = constraints.maxWidth >= 520 ? 2 : 1;
                    final width =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final donation in _donations)
                          SizedBox(
                            width: width,
                            child: _DonationCard(donation: donation),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Update',
            children: [
              SwitchListTile(
                value: app.config.updateCheck,
                onChanged: app.saveUpdateCheck,
                title: const Text('Check for updates automatically'),
                subtitle: const Text(
                  'Look for a newer release when the app starts',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                enabled: !app.updateCheckInFlight,
                leading: const Icon(Icons.refresh_rounded),
                title: Text(
                  app.updateCheckInFlight
                      ? 'Checking…'
                      : 'Check for updates now',
                ),
                trailing: app.updateCheckInFlight
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: app.updateCheckInFlight
                    ? null
                    : () => _checkForUpdates(app),
              ),
              if (app.availableUpdate != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: Text(
                    'Open the release page for '
                    '${app.availableUpdate!.version}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openReleasePage(context, app.availableUpdate!),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'About',
            children: [
              InfoRow(
                label: 'Version',
                value: app.state.version.isEmpty ? '—' : app.state.version,
              ),
              InfoRow(
                label: 'Yggdrasil version',
                value: app.state.yggVersion.isEmpty
                    ? '—'
                    : app.state.yggVersion,
              ),
              InfoRow(
                label: 'Source code',
                value: 'github.com/MrKsey/y-node-desktop',
                onTap: () async {
                  final opened = await openExternalUrl(
                    'https://github.com/MrKsey/y-node-desktop',
                  );
                  if (!opened && context.mounted) {
                    showSnack(context, 'The browser did not open the link');
                  }
                },
              ),
              const InfoRow(label: 'License', value: 'MIT'),
            ],
          ),
        ],
      ),
    );
  }

  static String? _presetLabel(AppState app, String server) {
    for (final preset in app.dnsPresets) {
      if (preset.address == server) return preset.label;
    }
    return null;
  }

  static int _peerCount(CoreConfig config) =>
      (int.tryParse(config.peerCount) ?? 3).clamp(1, 20);

  static int _seconds(String value, int fallback) =>
      (int.tryParse(value) ?? fallback).clamp(1, 3600);

  /// Manual release check from the Update section. Reports the outcome inline:
  /// up to date, a new version (opens the download dialog) or a failure.
  Future<void> _checkForUpdates(AppState app) async {
    try {
      final update = await app.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        showSnack(context, 'You are running the latest version');
        return;
      }
      await app.markUpdateNotified(update);
      if (!mounted) return;
      await showUpdatePrompt(context, update);
    } on UpdateCheckException catch (e) {
      if (!mounted) return;
      showSnack(context, 'Could not check for updates: ${e.message}');
    }
  }

  Future<void> _save(
    AppState app,
    void Function(CoreConfig next) change,
  ) async {
    final next = CoreConfig.fromJson(
      app.config.toJson(
        privateKey: app.privateKey,
        peers: app.configuredPeers,
        pool: app.pool,
        exits: app.exits,
        activeId: app.activeExitId,
        exitEnabled: app.exitEnabled,
      ),
    );
    change(next);
    await app.saveConfig(next);
  }

  Future<void> _setStartWithWindows(bool enabled) async {
    final ok = await StartupEntry.setEnabled(enabled);
    final actual = ok ? enabled : await StartupEntry.isEnabled();
    if (!mounted) return;
    setState(() => _startWithWindows = actual);
    if (!ok) {
      showSnack(context, 'Windows did not accept the startup entry');
    }
  }

  Future<void> _addDns(AppState app, String mode) async {
    final controller = TextEditingController();
    String? error;
    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Add a server'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'DNS servers',
                hintText: mode == 'system' ? '9.9.9.9' : '308:84:68:55::',
                helperText: mode == 'system'
                    ? 'An IPv4 resolver for ordinary names'
                    : 'An IPv6 resolver for .ygg names',
                errorText: error,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty || !_validDns(value)) {
                  setLocal(() => error = 'Enter an IPv6 DNS server address');
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (address == null) return;
    await _save(app, (next) {
      final list = splitList(mode == 'system' ? next.systemDns : next.yggDns);
      if (list.contains(address)) return;
      list.add(address);
      final joined = list.join(', ');
      if (mode == 'system') {
        next.systemDns = joined;
      } else {
        next.yggDns = joined;
      }
    });
    if (!mounted) return;
    app.checkDnsServer(address);
  }

  Future<void> _removeDns(AppState app, String mode, String server) async {
    await _save(app, (next) {
      final source = mode == 'system' ? next.systemDns : next.yggDns;
      final list = splitList(source)..remove(server);
      final joined = list.join(', ');
      if (mode == 'system') {
        next.systemDns = joined;
      } else {
        next.yggDns = joined;
      }
    });
  }

  static bool _validDns(String value) {
    if (!value.contains(':') && !value.contains('.')) return false;
    try {
      if (value.contains(':')) {
        Uri.parseIPv6Address(value);
        return true;
      }
      final parts = value.split('.');
      if (parts.length != 4) return false;
      for (final part in parts) {
        final number = int.tryParse(part);
        if (number == null || number < 0 || number > 255) return false;
      }
      return true;
    } on FormatException {
      return false;
    }
  }
}

class _Donation {
  const _Donation(this.name, this.address, this.qr, this.icon);

  final String name;
  final String address;

  /// The QR code the project page shows next to the address.
  final String qr;
  final IconData icon;
}

/// The same four wallets the project page shows, with the same QR codes.
const List<_Donation> _donations = [
  _Donation(
    'Bitcoin',
    'bc1qdf9wryj6tnyyr7ed4dkfv03nn0dxjf27xshfcr',
    'assets/donate/bitcoin.jpg',
    Icons.currency_bitcoin_rounded,
  ),
  _Donation(
    'Ethereum',
    '0xE22FAB5337A5506D9e7Ef9D4914De4d963Fbbf88',
    'assets/donate/ethereum.jpg',
    Icons.diamond_outlined,
  ),
  _Donation(
    'Solana',
    '7XcNM2M9rndFbJdjRtyycxkQXq8dPXEP87toiQX4EZfx',
    'assets/donate/solana.jpg',
    Icons.bolt_rounded,
  ),
  _Donation(
    'Tron',
    'TCYpTxSmdPN8p4fmRwtPGk3HHBf77FypeA',
    'assets/donate/tron.jpg',
    Icons.toll_rounded,
  ),
];

/// One wallet of the Donate block: the QR code on top, the name and the address
/// below. Tapping the card copies the address, the way the Android block does.
class _DonationCard extends StatelessWidget {
  const _DonationCard({required this.donation});

  final _Donation donation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: donation.address));
          if (context.mounted) {
            showSnack(context, '${donation.name} address copied');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    donation.qr,
                    width: 168,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    donation.icon,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(donation.name, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                donation.address,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One resolver row: the address, the last check and the buttons. A resolver
/// the exit node publishes is locked: the "DNS exit node" switch owns it.
class _DnsTile extends StatelessWidget {
  const _DnsTile({
    required this.server,
    required this.check,
    this.label,
    this.fromExit = false,
    this.removable = false,
    this.onCheck,
    this.onAdd,
    this.onRemove,
  });

  final String server;
  final DnsCheck? check;
  final String? label;
  final bool fromExit;

  /// The row belongs to the exit node but may be removed: the exit is off, so
  /// the resolver is not in the tunnel. The switch brings it back.
  final bool removable;
  final VoidCallback? onCheck;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = check?.ok ?? false;
    final color = check == null
        ? theme.colorScheme.onSurfaceVariant
        : ok
        ? AppColors.online
        : AppColors.offline;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      leading: Icon(
        check == null
            ? (fromExit ? Icons.vpn_lock_rounded : Icons.dns_outlined)
            : ok
            ? Icons.check_circle_rounded
            : Icons.error_outline_rounded,
        size: 20,
        color: color,
      ),
      title: Text(
        server,
        style: TextStyle(
          fontFamily: 'monospace',
          color: check != null && !ok ? AppColors.offline : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null && label!.isNotEmpty)
            Text(label!, style: theme.textTheme.bodySmall),
          if (check != null)
            Text(
              ok
                  ? (check!.via == 'tcp'
                        ? 'Resolved in ${check!.ms.toStringAsFixed(0)} ms over TCP'
                        : 'Resolved in ${check!.ms.toStringAsFixed(0)} ms')
                  : 'Not working',
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          if (ok && check!.address.isNotEmpty)
            Text(
              '${check!.name} → ${check!.address}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fromExit && !removable)
            Tooltip(
              message: 'Managed by the DNS exit node switch',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.lock_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          else ...[
            if (onAdd != null)
              IconButton(
                tooltip: 'Add',
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
          ],
          if (onCheck != null)
            IconButton(
              tooltip: 'Check now',
              onPressed: onCheck,
              icon: const Icon(Icons.network_check_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}
