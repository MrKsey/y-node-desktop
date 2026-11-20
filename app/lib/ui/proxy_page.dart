import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// The desktop-only proxy screen. The Android client creates a TUN device; the
/// desktop build starts a local HTTP and SOCKS5 proxy instead, so its ports,
/// bind address and the system proxy switch live here.
class ProxyPage extends StatefulWidget {
  const ProxyPage({super.key});

  @override
  State<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends State<ProxyPage> {
  final _bind = TextEditingController();
  final _httpPort = TextEditingController();
  final _socksPort = TextEditingController();
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final app = AppScope.of(context);
    if (!app.ready) return;
    _apply(app.config);
    _loaded = true;
  }

  void _apply(CoreConfig config) {
    _bind.text = config.bind;
    _httpPort.text = config.httpPort;
    _socksPort.text = config.socksPort;
  }

  @override
  void dispose() {
    _bind.dispose();
    _httpPort.dispose();
    _socksPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final live = app.state;
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return PageScaffold(
      title: 'Proxy',
      subtitle:
          'The desktop tunnel is a local HTTP and SOCKS5 proxy. Point an '
          'application at one of these addresses, or let the system proxy do it '
          'for every program.',
      child: PageScroll(
        children: [
          ResponsiveRow(
            first: SectionCard(
              title: 'Local proxy',
              subtitle: live.running
                  ? 'Listening while the tunnel is up.'
                  : 'The addresses become active when the tunnel connects.',
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.12,
                    ),
                    child: Icon(
                      Icons.http_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  title: const Text('HTTP proxy'),
                  subtitle: SelectableText(
                    live.proxyHttp.isEmpty ? '—' : live.proxyHttp,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: IconButton(
                    tooltip: 'Copy',
                    onPressed: live.proxyHttp.isEmpty
                        ? null
                        : () => copyText(
                            context,
                            live.proxyHttp,
                            'HTTP proxy copied',
                          ),
                    icon: const Icon(Icons.copy_rounded, size: 19),
                  ),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.teal.withValues(alpha: 0.12),
                    child: const Icon(Icons.lan_rounded, color: AppColors.teal),
                  ),
                  title: const Text('SOCKS5 proxy'),
                  subtitle: SelectableText(
                    live.proxySocks.isEmpty ? '—' : live.proxySocks,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: IconButton(
                    tooltip: 'Copy',
                    onPressed: live.proxySocks.isEmpty
                        ? null
                        : () => copyText(
                            context,
                            live.proxySocks,
                            'SOCKS5 proxy copied',
                          ),
                    icon: const Icon(Icons.copy_rounded, size: 19),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Text(
                    live.running
                        ? 'Open http://example.com through the proxy to check '
                              'the public path, or a .ygg address to check the '
                              'in-network path.'
                        : 'Start the tunnel on the Tunnel page first.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            second: SectionCard(
              title: 'System proxy',
              children: [
                SwitchListTile(
                  value: app.config.systemProxy,
                  onChanged: app.busy ? null : app.setSystemProxy,
                  title: const Text('Use as the system proxy'),
                  subtitle: Text(
                    live.systemProxy && live.systemProxyAddress.isNotEmpty
                        ? 'Active: ${live.systemProxyAddress}'
                        : !live.running
                        ? (app.config.systemProxy
                              ? 'Applied when the tunnel connects'
                              : _systemProxyHint())
                        : 'Not applied: the operating system does not point '
                              'at this proxy',
                  ),
                  secondary: Icon(
                    Icons.settings_ethernet_rounded,
                    color: app.config.systemProxy
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('What it changes'),
                  subtitle: Text(
                    'Windows: the WinINET settings of the current user. '
                    'macOS: every network service. Linux: gsettings. The '
                    'previous value is restored when the tunnel stops or the '
                    'switch is turned off.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Ports and bind address',
            subtitle:
                'Applied on the next connect. Keep the bind address on '
                '127.0.0.1 unless another device really has to use the proxy.',
            trailing: FilledButton.icon(
              onPressed: app.busy ? null : () => _save(app),
              icon: app.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bind,
                            decoration: const InputDecoration(
                              labelText: 'Bind address',
                              helperText: '127.0.0.1 or 0.0.0.0',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _httpPort,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'HTTP port',
                              helperText: 'Default 7890',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _socksPort,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'SOCKS5 port',
                              helperText: 'Default 7891',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 15,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '0.0.0.0 exposes the proxy to the local network. '
                            'Anyone who can reach the port can use the tunnel.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _save(AppState app) async {
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
    next.bind = _bind.text.trim().isEmpty ? '127.0.0.1' : _bind.text.trim();
    next.httpPort = _httpPort.text.trim();
    next.socksPort = _socksPort.text.trim();
    await app.saveConfig(next);
    if (!mounted) return;
    _apply(app.config);
    showSnack(
      context,
      app.error ?? 'Proxy settings saved. Reconnect to apply the ports.',
    );
  }

  static String _systemProxyHint() =>
      'Windows: WinINET settings · macOS: network services · Linux: gsettings';
}
