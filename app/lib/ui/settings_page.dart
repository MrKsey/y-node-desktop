import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _bind = TextEditingController();
  final _httpPort = TextEditingController();
  final _socksPort = TextEditingController();
  final _mtu = TextEditingController();
  final _yggDns = TextEditingController();
  final _systemDns = TextEditingController();
  final _exitDns = TextEditingController();
  final _privateKey = TextEditingController();

  bool _fallbackDirect = true;
  bool _localDns = true;
  bool _systemProxy = false;
  bool _autoConnect = false;
  bool _revealKey = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final app = AppScope.of(context);
    if (!app.ready) return;
    _apply(app.config, app.privateKey);
    _loaded = true;
  }

  void _apply(CoreConfig config, String privateKey) {
    _bind.text = config.bind;
    _httpPort.text = config.httpPort;
    _socksPort.text = config.socksPort;
    _mtu.text = config.mtu;
    _yggDns.text = config.yggDns;
    _systemDns.text = config.systemDns;
    _exitDns.text = config.exitDns;
    _privateKey.text = privateKey;
    _fallbackDirect = config.fallbackDirect;
    _localDns = config.localDns;
    _systemProxy = config.systemProxy;
    _autoConnect = config.autoConnect;
  }

  @override
  void dispose() {
    for (final controller in [
      _bind,
      _httpPort,
      _socksPort,
      _mtu,
      _yggDns,
      _systemDns,
      _exitDns,
      _privateKey,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(AppState app) async {
    final next = CoreConfig(
      bind: _bind.text,
      httpPort: _httpPort.text,
      socksPort: _socksPort.text,
      mtu: _mtu.text,
      yggDns: _yggDns.text,
      systemDns: _systemDns.text,
      exitDns: _exitDns.text,
      fallbackDirect: _fallbackDirect,
      localDns: _localDns,
      systemProxy: _systemProxy,
      autoConnect: _autoConnect,
    );
    await app.saveConfig(next, key: _privateKey.text.trim());
    if (!mounted) return;
    final error = app.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Settings saved'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final state = app.state;

    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Panel(
          title: 'Identity',
          subtitle: 'The address and key of this device inside Yggdrasil.',
          child: Column(
            children: [
              KeyValue(
                label: 'Address',
                value: state.address.isEmpty ? '—' : state.address,
                monospace: true,
                copyable: state.address.isNotEmpty,
              ),
              KeyValue(
                label: 'Subnet',
                value: state.subnet.isEmpty ? '—' : state.subnet,
                monospace: true,
                copyable: state.subnet.isNotEmpty,
              ),
              KeyValue(
                label: 'Public key',
                value: state.publicKey.isEmpty ? '—' : state.publicKey,
                monospace: true,
                copyable: state.publicKey.isNotEmpty,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _privateKey,
                obscureText: !_revealKey,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Private key',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _revealKey ? 'Hide' : 'Show',
                        icon: Icon(
                          _revealKey
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                        onPressed: () =>
                            setState(() => _revealKey = !_revealKey),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () => copyText(
                          context,
                          _privateKey.text,
                          'Private key copied',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'The key is stored in the core configuration file. Changing '
                  'it changes the address.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Network',
          child: Column(
            children: [
              _row(
                TextField(
                  controller: _bind,
                  decoration: const InputDecoration(
                    labelText: 'Bind address',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                TextField(
                  controller: _mtu,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'MTU',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _row(
                TextField(
                  controller: _httpPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'HTTP proxy port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                TextField(
                  controller: _socksPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'SOCKS5 proxy port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ports and the bind address are applied on the next connect.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'DNS',
          subtitle: 'Comma or space separated lists. Empty means the defaults.',
          child: Column(
            children: [
              TextField(
                controller: _yggDns,
                decoration: const InputDecoration(
                  labelText: 'Yggdrasil DNS servers',
                  hintText: '308:84:68:55::, 308:25:40:bd::',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _systemDns,
                decoration: const InputDecoration(
                  labelText: 'System DNS (resolved through the tunnel)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _exitDns,
                decoration: const InputDecoration(
                  labelText: 'Exit node DNS',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Resolve DNS inside the tunnel'),
                value: _localDns,
                onChanged: (value) => setState(() => _localDns = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'Behaviour',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fall back to a direct connection'),
                subtitle: const Text(
                  'If the exit node cannot open a destination, the proxy tries '
                  'the Yggdrasil network directly.',
                ),
                value: _fallbackDirect,
                onChanged: (value) => setState(() => _fallbackDirect = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Set the system proxy on connect'),
                subtitle: const Text(
                  'Windows: WinINET · macOS: network services · Linux: gsettings',
                ),
                value: _systemProxy,
                onChanged: (value) => setState(() => _systemProxy = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Connect on start'),
                value: _autoConnect,
                onChanged: (value) => setState(() => _autoConnect = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: app.busy
                  ? null
                  : () async {
                      await app.loadConfig();
                      if (!mounted) return;
                      _apply(app.config, app.privateKey);
                      setState(() {});
                    },
              child: const Text('Reload'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: app.busy ? null : () => _save(app),
              icon: app.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save settings'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Y-Node Desktop ${state.version.isEmpty ? '' : state.version}'
          '${state.yggVersion.isEmpty ? '' : ' · Yggdrasil ${state.yggVersion}'}'
          '${state.platform.isEmpty ? '' : ' · ${state.platform}'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _row(Widget first, Widget second) => Row(
    children: [
      Expanded(child: first),
      const SizedBox(width: 12),
      Expanded(child: second),
    ],
  );
}
