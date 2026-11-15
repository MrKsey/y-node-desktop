import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'widgets.dart';

class PeersPage extends StatefulWidget {
  const PeersPage({super.key});

  @override
  State<PeersPage> createState() => _PeersPageState();
}

class _PeersPageState extends State<PeersPage> {
  final _peer = TextEditingController();

  @override
  void dispose() {
    _peer.dispose();
    super.dispose();
  }

  Future<void> _add(AppState app) async {
    final uri = _peer.text.trim();
    if (uri.isEmpty) return;
    await app.addPeer(uri);
    if (app.error == null) _peer.clear();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final live = {for (final peer in app.peers) peer.uri: peer};
    final configured = app.configuredPeers;
    final inbound = [
      for (final peer in app.peers)
        if (!configured.contains(peer.uri)) peer,
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Panel(
          title: 'Peers',
          subtitle:
              'Public Yggdrasil nodes the tunnel connects to. '
              'At least one peer is required to connect.',
          trailing: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: app.probeRunning || app.peers.isEmpty
                    ? null
                    : () async {
                        final report = await app.probePeers();
                        if (!context.mounted) return;
                        showMessage(context, 'Peer latency', report);
                      },
                icon: app.probeRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed_rounded, size: 18),
                label: const Text('Probe'),
              ),
              FilledButton.tonalIcon(
                onPressed: app.autoPeersRunning
                    ? null
                    : () => app.autoPeers(),
                icon: app.autoPeersRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Auto'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _peer,
                      decoration: const InputDecoration(
                        labelText: 'Peer URI',
                        hintText: 'tls://example.com:12345',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _add(app),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: app.busy ? null : () => _add(app),
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Auto downloads the public peer list and keeps the nodes '
                'that answer.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Configured peers (${configured.length})',
          child: configured.isEmpty
              ? Text(
                  'No peers yet. Press Auto or add a URI above.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (final uri in configured)
                      _PeerRow(
                        uri: uri,
                        status: live[uri],
                        onRemove: app.busy ? null : () => app.removePeer(uri),
                      ),
                  ],
                ),
        ),
        if (inbound.isNotEmpty) ...[
          const SizedBox(height: 16),
          Panel(
            title: 'Inbound peers (${inbound.length})',
            subtitle: 'Nodes that connected to you.',
            child: Column(
              children: [
                for (final peer in inbound)
                  _PeerRow(
                    uri: peer.uri,
                    status: peer,
                    onRemove: null,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({
    required this.uri,
    required this.status,
    required this.onRemove,
  });

  final String uri;
  final PeerStatus? status;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peer = status;
    final up = peer?.up ?? false;
    final color = up
        ? const Color(0xFF3DDC84)
        : theme.colorScheme.onSurfaceVariant;
    final details = <String>[
      if (peer == null) 'not started',
      if (peer != null && peer.inbound) 'inbound',
      if (peer != null && peer.latencyMs > 0)
        '${peer.latencyMs.toStringAsFixed(0)} ms',
      if (peer != null && peer.rxBytes > 0) 'rx ${formatBytes(peer.rxBytes)}',
      if (peer != null && peer.txBytes > 0) 'tx ${formatBytes(peer.txBytes)}',
      if (peer != null && peer.lastError.isNotEmpty) peer.lastError,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  uri,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}
