import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core_process.dart';
import 'models.dart';
import 'ui/exit_page.dart';
import 'ui/logs_page.dart';
import 'ui/peers_page.dart';
import 'ui/settings_page.dart';
import 'ui/tunnel_page.dart';
import 'ui/widgets.dart';

void main() {
  runApp(const YNodeApp());
}

class YNodeApp extends StatefulWidget {
  const YNodeApp({super.key});

  @override
  State<YNodeApp> createState() => _YNodeAppState();
}

class _YNodeAppState extends State<YNodeApp> {
  late final AppState _state = AppState(CoreProcess());

  @override
  void initState() {
    super.initState();
    _state.start();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4C8BF5),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Y-Node',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF10131A),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      home: AppScope(state: _state, child: const _Shell()),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  static const _destinations = [
    (
      icon: Icons.shield_outlined,
      selected: Icons.shield_rounded,
      label: 'Tunnel',
    ),
    (icon: Icons.lan_outlined, selected: Icons.lan_rounded, label: 'Peers'),
    (
      icon: Icons.exit_to_app_outlined,
      selected: Icons.exit_to_app_rounded,
      label: 'Exit node',
    ),
    (
      icon: Icons.article_outlined,
      selected: Icons.article_rounded,
      label: 'Logs',
    ),
    (
      icon: Icons.settings_outlined,
      selected: Icons.settings_rounded,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);

    if (!app.ready) {
      return Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (app.error == null) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    'Starting the Yggdrasil core…',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The window launches y-node-core next to the application '
                    'and waits for the local API.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.error_outline_rounded,
                    size: 44,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'The core did not start',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    app.error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      app.error = null;
                      app.start();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    const pages = [
      TunnelPage(),
      PeersPage(),
      ExitPage(),
      LogsPage(),
      SettingsPage(),
    ];

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 210,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border(
                right: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hub_rounded,
                        color: theme.colorScheme.primary,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Text('Y-Node', style: theme.textTheme.titleLarge),
                    ],
                  ),
                ),
                Expanded(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (value) =>
                        setState(() => _index = value),
                    labelType: NavigationRailLabelType.none,
                    extended: true,
                    destinations: [
                      for (final item in _destinations)
                        NavigationRailDestination(
                          icon: Icon(item.icon),
                          selectedIcon: Icon(item.selected),
                          label: Text(item.label),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _SidebarStatus(state: app.state),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(index: _index),
                if (app.error != null)
                  _Banner(message: app.error!, isError: true),
                if (app.notice != null)
                  _Banner(message: app.notice!, isError: false),
                Expanded(child: pages[_index]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.index});

  final int index;

  static const _titles = ['Tunnel', 'Peers', 'Exit node', 'Logs', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Text(_titles[index], style: theme.textTheme.titleLarge),
          const Spacer(),
          if (app.state.running)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${formatBytes(app.state.rxBytes)} up · '
                '${formatBytes(app.state.txBytes)} down',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          StatusPill(
            label: app.state.running ? 'Tunnel up' : 'Tunnel down',
            color: app.state.running
                ? const Color(0xFF3DDC84)
                : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppScope.of(context);
    final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 17),
            onPressed: app.clearMessages,
          ),
        ],
      ),
    );
  }
}

class _SidebarStatus extends StatelessWidget {
  const _SidebarStatus({required this.state});

  final TunnelState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.address.isEmpty ? 'No address' : state.address,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${state.peersUp}/${state.peersTotal} peers',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: app.busy
                ? null
                : () => app.setSystemProxy(!state.systemProxy),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              textStyle: theme.textTheme.labelSmall,
            ),
            child: Text(
              state.systemProxy ? 'System proxy on' : 'System proxy off',
            ),
          ),
        ),
      ],
    );
  }
}
