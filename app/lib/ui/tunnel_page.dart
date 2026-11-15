import 'package:flutter/material.dart';

import '../models.dart';
import 'widgets.dart';

class TunnelPage extends StatelessWidget {
  const TunnelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final state = app.state;
    final theme = Theme.of(context);
    final connected = state.running;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
                theme.colorScheme.surfaceContainerLow,
              ],
            ),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusPill(
                    label: connected ? 'Connected' : 'Disconnected',
                    color: connected
                        ? const Color(0xFF3DDC84)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const Spacer(),
                  if (app.busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connected
                              ? 'Your Yggdrasil address'
                              : 'Not connected',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          state.address.isEmpty ? '—' : state.address,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: app.busy
                        ? null
                        : () => connected ? app.disconnect() : app.connect(),
                    icon: Icon(
                      connected
                          ? Icons.power_settings_new_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(connected ? 'Disconnect' : 'Connect'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      backgroundColor: connected
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      foregroundColor: connected
                          ? theme.colorScheme.onError
                          : theme.colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
              if (state.exitEnabled && state.exitName.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.exit_to_app_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Exit node: ${state.exitName}'
                      '${state.exitState.isEmpty ? '' : ' · ${state.exitState}'}',
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
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _SizedPanel(
              width: 430,
              child: Panel(
                title: 'Traffic',
                subtitle: connected
                    ? 'Up ${formatBytes(state.rxBytes)} · Down ${formatBytes(state.txBytes)}'
                    : 'Start the tunnel to see the counters',
                child: Wrap(
                  spacing: 32,
                  runSpacing: 18,
                  children: [
                    StatTile(
                      label: 'Peers',
                      value: '${state.peersUp} / ${state.peersTotal}',
                      icon: Icons.lan_rounded,
                    ),
                    StatTile(
                      label: 'Connections',
                      value:
                          '${state.openConnections} / ${state.totalConnections}',
                      icon: Icons.compare_arrows_rounded,
                    ),
                    StatTile(
                      label: 'Uptime',
                      value: formatUptime(state.uptimeSeconds),
                      icon: Icons.timer_outlined,
                    ),
                    StatTile(
                      label: 'MTU',
                      value: app.config.mtu,
                      icon: Icons.straighten_rounded,
                    ),
                  ],
                ),
              ),
            ),
            _SizedPanel(
              width: 430,
              child: Panel(
                title: 'Local proxy',
                subtitle:
                    'Point a browser or an app at one of these addresses. '
                    'The system proxy switch edits the operating system settings.',
                child: Column(
                  children: [
                    KeyValue(
                      label: 'HTTP',
                      value: state.proxyHttp.isEmpty ? '—' : state.proxyHttp,
                      monospace: true,
                      copyable: state.proxyHttp.isNotEmpty,
                    ),
                    KeyValue(
                      label: 'SOCKS5',
                      value: state.proxySocks.isEmpty ? '—' : state.proxySocks,
                      monospace: true,
                      copyable: state.proxySocks.isNotEmpty,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use as system proxy'),
                      subtitle: Text(
                        state.systemProxy
                            ? 'Active: ${state.systemProxyAddress}'
                            : _systemProxyHint(),
                      ),
                      value: state.systemProxy,
                      onChanged: app.busy
                          ? null
                          : (value) => app.setSystemProxy(value),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (state.lastError.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ErrorPanel(message: state.lastError),
        ],
      ],
    );
  }

  String _systemProxyHint() =>
      'Windows: WinINET settings · macOS: network services · Linux: gsettings';
}

class _SizedPanel extends StatelessWidget {
  const _SizedPanel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: child);
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
