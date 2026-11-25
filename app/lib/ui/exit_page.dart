import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// The exit nodes page: the same three cards the Android client shows — the
/// switch, the profiles and the settings block.
class ExitPage extends StatefulWidget {
  const ExitPage({super.key});

  @override
  State<ExitPage> createState() => _ExitPageState();
}

class _ExitPageState extends State<ExitPage> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final status = app.exitStatus;
    final active = status.active;
    final activeProfile = _profileOf(app, app.activeExitId);

    return PageScaffold(
      title: 'Exit nodes',
      actions: [
        OutlinedButton.icon(
          onPressed: app.busy ? null : () => _importLink(app),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('Import from link'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: app.busy ? null : () => _addManually(app),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add manually'),
        ),
      ],
      child: PageScroll(
        children: [
          SectionCard(
            title: 'Exit node',
            children: [
              SwitchListTile(
                value: app.exitEnabled,
                onChanged: app.exits.isEmpty || app.busy
                    ? null
                    : app.setExitEnabled,
                title: const Text('Exit node'),
                subtitle: Text(
                  app.exitEnabled
                      ? _stateLabel(status)
                      : 'Public traffic leaves the computer directly',
                ),
                secondary: Icon(
                  Icons.vpn_lock_rounded,
                  color: app.exitEnabled
                      ? AppColors.online
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Exit nodes',
            subtitle:
                'Public traffic goes through the selected node only. Tap '
                'another row to switch the tunnel to it; the other nodes are '
                'never used.',
            children: [
              if (app.exits.isEmpty)
                EmptyHint(
                  icon: Icons.dns_outlined,
                  title: 'Add an exit node',
                  body:
                      'Paste the yggnode://exit link from the X-Node '
                      'dashboard. It carries the address, the ports and the '
                      'one-time invite.',
                  action: FilledButton.tonalIcon(
                    onPressed: app.busy ? null : () => _importLink(app),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Import from link'),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: app.exits.length,
                  onReorderItem: (oldIndex, newIndex) {
                    final list = [...app.exits];
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    app.reorderExits([for (final profile in list) profile.id]);
                  },
                  itemBuilder: (context, index) {
                    final profile = app.exits[index];
                    return _ExitRow(
                      key: ValueKey(profile.id),
                      index: index,
                      profile: profile,
                      active: profile.id == app.activeExitId,
                      health: _healthOf(status, profile.id),
                      busy: app.busy,
                      onSelect: () => app.setActiveExit(profile.id),
                      onEdit: () => _editProfile(app, profile),
                      onRemove: () => _remove(app, profile),
                    );
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Import from link',
                      visualDensity: VisualDensity.compact,
                      onPressed: app.busy ? null : () => _importLink(app),
                      icon: const Icon(Icons.link_rounded, size: 18),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _checking || activeProfile == null
                          ? null
                          : () => _check(app),
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(_checking ? 'Checking…' : 'Check now'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Settings',
            children: [
              SwitchListTile(
                value: app.config.fallbackDirect,
                onChanged: app.busy
                    ? null
                    : (value) => app.setExitOptions(fallbackDirect: value),
                title: const Text(
                  'Use the direct connection if the exit is down',
                ),
                subtitle: const Text(
                  'When the selected node does not answer, public traffic '
                  'leaves the computer directly instead of being dropped',
                ),
                secondary: const Icon(Icons.alt_route_rounded),
              ),
              SwitchListTile(
                value: app.config.exitLabelEnabled,
                onChanged: app.busy
                    ? null
                    : (value) => app.setExitLabel(
                        enabled: value,
                        name: app.config.exitLabel,
                      ),
                title: const Text('My name on exit node'),
                subtitle: Text(
                  app.config.exitLabelEnabled
                      ? app.config.exitLabel.trim().isEmpty
                            ? 'Shown as: Device name'
                            : 'Shown as: ${app.config.exitLabel.trim()}'
                      : 'Off: the exit node shows the device name',
                ),
                secondary: const Icon(Icons.badge_outlined),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline_rounded),
                title: const Text('Name'),
                subtitle: Text(
                  app.config.exitLabel.trim().isEmpty
                      ? 'Device name'
                      : app.config.exitLabel.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit_rounded, size: 18),
                onTap: app.busy ? null : () => _editLabel(app),
              ),
              SwitchListTile(
                value: app.config.localDns,
                onChanged: app.busy
                    ? null
                    : (value) => app.setExitOptions(localDns: value),
                title: const Text('Resolve local names on the local network'),
                subtitle: const Text(
                  'Names like router.lan or nas.local are sent to the DNS of '
                  'the real network instead of the exit',
                ),
                secondary: const Icon(Icons.lan_outlined),
              ),
              SwitchListTile(
                value: app.config.exitDnsEnabled,
                onChanged: app.busy
                    ? null
                    : (value) => app.setExitOptions(exitDnsEnabled: value),
                title: const Text('DNS exit node'),
                subtitle: Text(
                  active?.dnsAddress.isNotEmpty == true
                      ? 'Use the resolver the exit node publishes for its '
                            'clients (${active!.dnsAddress}:${active.dnsPort})'
                      : 'Use the resolver the exit node publishes for its '
                            'clients',
                ),
                secondary: const Icon(Icons.dns_rounded),
              ),
              SwitchListTile(
                value: app.config.exitUdp,
                onChanged: app.busy
                    ? null
                    : (value) => app.setExitOptions(exitUdp: value),
                title: const Text('Carry UDP through the exit'),
                subtitle: const Text(
                  'DNS and QUIC use the UDP relay of the exit node. When it is '
                  'off, public UDP is dropped instead of leaking around the '
                  'exit.',
                ),
                secondary: const Icon(Icons.swap_vert_rounded),
              ),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Exit DNS'),
                subtitle: Text(
                  splitList(app.config.exitDns).isEmpty
                      ? '1.1.1.1, 9.9.9.9 · public names through the exit'
                      : '${splitList(app.config.exitDns).join(', ')} · '
                            'public names through the exit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit_rounded, size: 18),
                onTap: app.busy ? null : () => _editDns(app, exitDns: true),
              ),
              ListTile(
                leading: const Icon(Icons.router_outlined),
                title: const Text('Local DNS'),
                subtitle: Text(
                  splitList(app.config.systemDns).isEmpty
                      ? 'Automatic (real network) · local names only'
                      : '${splitList(app.config.systemDns).join(', ')} · '
                            'local names only',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit_rounded, size: 18),
                onTap: app.busy ? null : () => _editDns(app, exitDns: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _stateLabel(ExitStatus status) {
    if (!status.enabled) return 'Off';
    return switch (status.state) {
      'online' => 'Online',
      'denied' => 'Not allowed',
      'unreachable' => 'Unreachable',
      'unknown' => 'Connecting…',
      _ => status.state,
    };
  }

  static ExitProfile? _profileOf(AppState app, String id) {
    for (final profile in app.exits) {
      if (profile.id == id) return profile;
    }
    return app.exits.isEmpty ? null : app.exits.first;
  }

  static ExitProfileStatus? _healthOf(ExitStatus status, String id) {
    for (final profile in status.profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> _importLink(AppState app) async {
    final link = await promptText(
      context,
      title: 'Import an exit link',
      hint: 'yggnode://exit?v=1&a=…&i=…',
      helper:
          'The same link the QR code carries: copy it from the server '
          'output, a chat or a file',
      confirm: 'Add',
    );
    if (link == null || link.trim().isEmpty) return;
    await app.addExitLink(link);
    if (!mounted) return;
    showSnack(context, app.error ?? 'Exit node saved');
  }

  Future<void> _addManually(AppState app) async {
    final address = TextEditingController();
    final socks = TextEditingController(text: '1080');
    final api = TextEditingController(text: '1080');
    final name = TextEditingController();
    final invite = TextEditingController();
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Add manually'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Shown on the Tunnel tab',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: address,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Yggdrasil address',
                    hintText: '200:…',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: socks,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'SOCKS port',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: api,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'API port',
                          helperText: '0 = share the SOCKS port',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: invite,
                  decoration: const InputDecoration(
                    labelText: 'Invite token',
                    helperText: 'Leave it empty for a plain SOCKS5 profile',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final host = address.text.trim();
                if (!_isYggdrasilAddress(host)) {
                  setLocal(
                    () => error = 'Enter a Yggdrasil IPv6 address (200::/7)',
                  );
                  return;
                }
                final socksPort = int.tryParse(socks.text.trim()) ?? 0;
                if (socksPort < 1 || socksPort > 65535) {
                  setLocal(() => error = 'Enter a port between 1 and 65535');
                  return;
                }
                final apiPort = int.tryParse(api.text.trim()) ?? 0;
                final label = name.text.trim();
                final query = {
                  'a': host,
                  'p': '$socksPort',
                  'api': '${apiPort == 0 ? socksPort : apiPort}',
                  if (label.isNotEmpty) 'n': label,
                  if (invite.text.trim().isNotEmpty) 'i': invite.text.trim(),
                };
                final link = Uri(
                  scheme: 'yggnode',
                  host: 'exit',
                  queryParameters: query,
                ).toString();
                await app.addExitLink(link);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    address.dispose();
    socks.dispose();
    api.dispose();
    name.dispose();
    invite.dispose();
    if (saved == true && mounted) {
      showSnack(context, app.error ?? 'Exit node saved');
    }
  }

  static bool _isYggdrasilAddress(String value) {
    final ip = Uri.tryParse('http://[$value]')?.host;
    if (ip == null || ip.isEmpty) return false;
    final first = ip.split(':').first;
    final number = int.tryParse(first, radix: 16);
    if (number == null) return false;
    return number >= 0x200 && number <= 0x3ff;
  }

  Future<void> _editProfile(AppState app, ExitProfile profile) async {
    final name = TextEditingController(text: profile.name);
    final address = TextEditingController(text: profile.address);
    final socks = TextEditingController(text: '${profile.socksPort}');
    final api = TextEditingController(text: '${profile.apiPort}');
    final peer = TextEditingController(text: profile.peer);
    // The same values the Android edit form shows: the invite from the link and
    // the API token the exit issued. An empty field keeps the stored secret, so
    // clearing it on purpose still works.
    final invite = TextEditingController(text: profile.invite);
    final token = TextEditingController(text: profile.token);
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Edit exit node'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'Shown on the Tunnel tab',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: address,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Yggdrasil address',
                      hintText: '200:…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: socks,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'SOCKS port',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: api,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'API port',
                            helperText: '0 = share the SOCKS port',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: peer,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Peer address',
                      hintText: 'tls://host:port?key=…',
                      helperText:
                          'The exit node is added as a pinned peer so '
                          'the tunnel reaches it directly',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: invite,
                    decoration: const InputDecoration(
                      labelText: 'Invite token',
                      helperText: 'Leave it empty to keep the stored one',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: token,
                    decoration: const InputDecoration(
                      labelText: 'API token',
                      helperText: 'Leave it empty to keep the stored one',
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final host = address.text.trim();
                if (!_isYggdrasilAddress(host)) {
                  setLocal(
                    () => error = 'Enter a Yggdrasil IPv6 address (200::/7)',
                  );
                  return;
                }
                final socksPort = int.tryParse(socks.text.trim()) ?? 0;
                if (socksPort < 1 || socksPort > 65535) {
                  setLocal(() => error = 'Enter a port between 1 and 65535');
                  return;
                }
                await app.saveExit(
                  ExitProfile(
                    id: profile.id,
                    name: name.text.trim(),
                    address: host,
                    socksPort: socksPort,
                    apiPort: int.tryParse(api.text.trim()) ?? socksPort,
                    peer: peer.text.trim(),
                    invite: invite.text.trim(),
                    token: token.text.trim(),
                    dns: profile.dns,
                    dnsPort: profile.dnsPort,
                    registered: profile.registered,
                  ),
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    address.dispose();
    socks.dispose();
    api.dispose();
    peer.dispose();
    invite.dispose();
    token.dispose();
    if (saved == true && mounted) {
      showSnack(context, app.error ?? 'Exit node saved');
    }
  }

  Future<void> _check(AppState app) async {
    setState(() => _checking = true);
    final report = await app.checkExit();
    if (!mounted) return;
    setState(() => _checking = false);
    showMessage(context, 'Exit node check', report);
  }

  Future<void> _remove(AppState app, ExitProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this exit node?'),
        content: Text(
          '${profile.name} will be removed from the exit node list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await app.removeExit(profile.id);
    if (mounted) showSnack(context, 'Exit node removed');
  }

  Future<void> _editLabel(AppState app) async {
    final controller = TextEditingController(text: app.config.exitLabel);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('My name on exit node'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: 'Name',
              helperText: 'Up to 32 characters',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await app.setExitLabel(enabled: result.isNotEmpty, name: result);
    if (mounted) showSnack(context, 'Name sent to the exit node');
  }

  /// Edits one resolver list. The exit list is used for public names and goes
  /// through the exit; the local list is used for names like router.lan.
  Future<void> _editDns(AppState app, {required bool exitDns}) async {
    final current = exitDns
        ? splitList(app.config.exitDns)
        : splitList(app.config.systemDns);
    final controller = TextEditingController(text: current.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(exitDns ? 'Exit DNS' : 'Local DNS'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            autocorrect: false,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'DNS servers',
              hintText: exitDns ? '1.1.1.1, 9.9.9.9' : '192.168.1.1',
              helperText: exitDns
                  ? 'Public names such as example.com: asked through the exit '
                        'node, so the exit sees the query'
                  : 'Local names such as router.lan: asked from this network '
                        'directly. Empty means the DNS servers of the real '
                        'network.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final next = app.config;
    if (exitDns) {
      next.exitDns = result;
    } else {
      next.systemDns = result;
    }
    await app.saveConfig(next);
    if (mounted) showSnack(context, 'DNS servers saved');
  }
}

/// One profile row: the radio, the name, the health and the remove button.
class _ExitRow extends StatelessWidget {
  const _ExitRow({
    super.key,
    required this.index,
    required this.profile,
    required this.active,
    required this.health,
    required this.busy,
    required this.onSelect,
    required this.onEdit,
    required this.onRemove,
  });

  final int index;
  final ExitProfile profile;
  final bool active;
  final ExitProfileStatus? health;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = health?.state ?? 'unknown';
    final color = state == 'online'
        ? AppColors.online
        : state == 'denied' || state == 'unreachable'
        ? AppColors.offline
        : theme.colorScheme.onSurfaceVariant;
    final label = switch (state) {
      'online' when (health?.apiMissing ?? false) => 'socks5',
      'online' => 'online',
      'unreachable' => 'unreachable',
      'denied' => 'not allowed',
      _ => 'not checked',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: busy ? null : onSelect,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: active
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : null,
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary.withValues(alpha: 0.6)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (health != null && state != 'unknown') ...[
                          const SizedBox(width: 8),
                          StatusPill(
                            label: health!.suspended ? 'suspended' : label,
                            color: health!.suspended
                                ? AppColors.pending
                                : color,
                          ),
                        ],
                        if ((health?.latencyMs ?? 0) > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            formatLatency(health!.latencyMs),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.address}:${profile.socksPort}'
                      '${profile.token.isEmpty ? '' : ' · token'}'
                      '${profile.registered
                          ? ' · registered'
                          : profile.invite.isNotEmpty
                          ? ' · invite pending'
                          : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 19),
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
