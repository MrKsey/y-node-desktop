// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

import 'app_state.dart';
import 'core_process.dart';
import 'models.dart';
import 'theme.dart';
import 'tray.dart';
import 'ui/exit_page.dart';
import 'ui/logs_page.dart';
import 'ui/peers_page.dart';
import 'ui/proxy_page.dart';
import 'ui/services_page.dart';
import 'ui/settings_page.dart';
import 'ui/tunnel_page.dart';
import 'ui/update_dialog.dart';
import 'ui/widgets.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // Windows starts the app with `--tray` from the "Run" entry, so a logon
  // launch waits in the tray. A launch from the Start menu has no argument and
  // shows the window.
  runApp(YNodeApp(startInTray: args.contains('--tray')));
}

class YNodeApp extends StatefulWidget {
  const YNodeApp({super.key, this.startInTray = false});

  /// True when the process was started by the Windows "Run" entry: the window
  /// stays hidden until the tray icon is clicked.
  final bool startInTray;

  @override
  State<YNodeApp> createState() => _YNodeAppState();
}

class _YNodeAppState extends State<YNodeApp> with WindowListener {
  late final AppState _state = AppState(CoreProcess());
  TrayController? _tray;
  ThemeMode _themeMode = ThemeMode.system;
  String _theme = 'auto';
  bool _quitting = false;
  bool _quitProgress = false;

  /// The window exists only after [windowManager] is ready; the title is
  /// pushed once that happens.
  bool _windowReady = false;
  String _windowTitle = 'Y-Node';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _state.addListener(_syncTheme);
    _state.addListener(_syncWindowTitle);
    _state.start();
    unawaited(_initWindow());
  }

  Future<void> _initWindow() async {
    try {
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: _initialWindowSize(),
          minimumSize: const Size(760, 600),
          center: true,
          title: 'Y-Node',
        ),
        () async {
          // The native runner skips its first show when `--tray` is present,
          // so a logon launch never flashes a window.
          if (widget.startInTray) return;
          await windowManager.show();
          await windowManager.focus();
        },
      );
      _windowReady = true;
      _syncWindowTitle();
      _tray = TrayController(_state, showWindow: _showWindow, quit: _quit);
      final trayReady = await _tray!.init();
      // A desktop without a tray cannot host a hidden window: the window is
      // the only way back, so it is shown instead of leaving the app blind.
      if (widget.startInTray && !trayReady) await _showWindow();
    } catch (_) {
      // A platform without window_manager support still shows the window.
    }
  }

  /// Puts the tunnel state into the title. The taskbar reads the same string,
  /// so the button there shows what the window shows.
  void _syncWindowTitle() {
    if (!_windowReady) return;
    final live = _state.state;
    final next = !_state.ready
        ? 'Y-Node'
        : live.running
        ? 'Y-Node — Tunnel up · ${live.peersUp}/${live.peersTotal} peers'
        : 'Y-Node — Tunnel down';
    if (next == _windowTitle) return;
    _windowTitle = next;
    unawaited(windowManager.setTitle(next));
  }

  /// The window opens 5 % wider and 10 % taller than the previous 1000×780
  /// layout, but never larger than the display it appears on: a small laptop
  /// screen keeps the whole window, taskbar and title bar included.
  static Size _initialWindowSize() {
    const preferred = Size(1050, 858);
    const minimum = Size(760, 600);
    var width = preferred.width;
    var height = preferred.height;
    final displays = WidgetsBinding.instance.platformDispatcher.displays;
    if (displays.isNotEmpty) {
      final display = displays.first;
      final ratio = display.devicePixelRatio <= 0
          ? 1.0
          : display.devicePixelRatio;
      final screen = display.size / ratio;
      width = width < screen.width - 60 ? width : screen.width - 60;
      height = height < screen.height - 100 ? height : screen.height - 100;
    }
    return Size(
      width < minimum.width ? minimum.width : width,
      height < minimum.height ? minimum.height : height,
    );
  }

  void _syncTheme() {
    final next = _state.config.theme;
    if (next == _theme) return;
    final mode = switch (next) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    setState(() {
      _theme = next;
      _themeMode = mode;
    });
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    await _tray?.dispose();
    // The core drops the tunnel and restores the system proxy while it shuts
    // down. A live node can take a moment, so the progress is shown only when
    // the stop is not instant: a quick exit never flashes a window.
    final stopping =
        _state.state.running || _state.state.systemProxyAddress.isNotEmpty;
    Timer? progress;
    if (stopping) {
      progress = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() => _quitProgress = true);
        unawaited(windowManager.show());
        unawaited(windowManager.focus());
      });
    }
    await _state.shutdown();
    progress?.cancel();
    // Destroying the window after the plugins are gone aborts the engine
    // (`0xc0000409` in flutter_windows.dll), whichever step runs first. Ending
    // the process once the core and the system proxy are restored is the only
    // order that closes the app without the crash dialog.
    exit(0);
  }

  @override
  void onWindowClose() async {
    if (_quitting) return;
    // A running tunnel is a background service: closing the window must not
    // drop it. The setting controls the idle case; the tray is always the exit
    // while the tunnel is up.
    if (_state.state.running || _state.config.closeToTray) {
      await windowManager.hide();
      return;
    }
    // The close handler runs inside the window's own message: destroying the
    // window from here re-enters it, so the shutdown waits for the next turn.
    Timer.run(_quit);
  }

  @override
  void onWindowMinimize() async {
    if (_state.config.minimizeToTray) {
      await windowManager.hide();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _state.removeListener(_syncTheme);
    _state.removeListener(_syncWindowTitle);
    unawaited(_tray?.dispose());
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Y-Node',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: AppScope(
        state: _state,
        child: NoticeHost(
          child: Stack(
            children: [const _Shell(), if (_quitProgress) const _QuitOverlay()],
          ),
        ),
      ),
    );
  }
}

/// Covers the window while the core stops the tunnel and the system proxy is
/// restored. The quit path is short for an idle app and this overlay never
/// appears; it is shown only when the shutdown takes longer than a blink.
class _QuitOverlay extends StatelessWidget {
  const _QuitOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            width: 420,
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 26),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text('Closing Y-Node…', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Stopping the tunnel and restoring the system proxy.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
  bool _updateChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_updateChecked) return;
    final app = AppScope.of(context);
    if (!app.ready) return;
    _updateChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkForUpdate());
    });
  }

  /// Startup release check. Announces a newer release once per version, and
  /// only when the user turned the automatic check on.
  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    final app = AppScope.of(context);
    final update = await app.checkForUpdateOnStart();
    if (update == null || !mounted) return;
    await app.markUpdateNotified(update);
    if (!mounted) return;
    await showUpdatePrompt(context, update);
  }

  static const _destinations = [
    (
      icon: Icons.shield_outlined,
      selected: Icons.shield_rounded,
      label: 'Tunnel',
    ),
    (icon: Icons.hub_outlined, selected: Icons.hub_rounded, label: 'Peers'),
    (
      icon: Icons.book_outlined,
      selected: Icons.book_rounded,
      label: 'Services',
    ),
    (
      icon: Icons.vpn_lock_outlined,
      selected: Icons.vpn_lock_rounded,
      label: 'Exit node',
    ),
    (
      icon: Icons.swap_horiz_outlined,
      selected: Icons.swap_horiz_rounded,
      label: 'Proxy',
    ),
    (
      icon: Icons.article_outlined,
      selected: Icons.article_rounded,
      label: 'Logs',
    ),
    (
      icon: Icons.tune_outlined,
      selected: Icons.tune_rounded,
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

    final pages = [
      TunnelPage(
        onOpenPeers: () => setState(() => _index = 1),
        onOpenExit: () => setState(() => _index = 3),
        onOpenSettings: () => setState(() => _index = 6),
      ),
      const PeersPage(),
      const ServicesPage(),
      const ExitPage(),
      const ProxyPage(),
      const LogsPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: Row(
        children: [
          _SideBar(
            index: _index,
            destinations: _destinations,
            onSelect: (value) => setState(() => _index = value),
            onOpenTunnel: () => setState(() => _index = 0),
          ),
          Expanded(
            child: Column(
              children: [
                // The notices and the errors are snack bars at the bottom of
                // the window: a banner above the page pushed its content down
                // on every message and moved the layout back a few seconds
                // later.
                Expanded(child: pages[_index]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The side navigation: the same destinations the Android client keeps in its
/// bottom bar, plus the two desktop-only screens. The tunnel state lives at the
/// bottom of the rail, where the phone puts its navigation bar.
class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.index,
    required this.destinations,
    required this.onSelect,
    required this.onOpenTunnel,
  });

  final int index;
  final List<({IconData icon, IconData selected, String label})> destinations;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenTunnel;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    return Container(
      width: 278,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            child: Row(
              children: [
                Image.asset(
                  'assets/app_icon.png',
                  width: 38,
                  height: 38,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Y-Node',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'A Yggdrasil network client',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: NavigationRail(
              selectedIndex: index,
              onDestinationSelected: onSelect,
              labelType: NavigationRailLabelType.none,
              extended: true,
              leading: const SizedBox.shrink(),
              destinations: [
                for (final item in destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selected),
                    // The rail labels use labelMedium (12 sp) by default; the
                    // desktop window is wider than a phone, so the menu reads
                    // two points larger. The status block and the theme switch
                    // at the bottom keep their own sizes.
                    label: Text(item.label, style: theme.textTheme.labelLarge),
                  ),
              ],
            ),
          ),
          _RailStatus(state: app, onTap: onOpenTunnel),
          _ThemeSwitch(state: app),
        ],
      ),
    );
  }
}

/// The colour scheme switch under the status block: auto, day or night.
class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = state.config.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            _ThemeOption(
              icon: Icons.brightness_auto_rounded,
              tooltip: 'Auto (system)',
              selected: current == 'auto',
              onTap: () => state.setTheme('auto'),
            ),
            _ThemeOption(
              icon: Icons.light_mode_rounded,
              tooltip: 'Day',
              selected: current == 'light',
              onTap: () => state.setTheme('light'),
            ),
            _ThemeOption(
              icon: Icons.dark_mode_rounded,
              tooltip: 'Night',
              selected: current == 'dark',
              onTap: () => state.setTheme('dark'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.secondaryContainer : null,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The live tunnel status at the bottom of the rail: the state, the peers and
/// the two counters. A click brings the tunnel screen back.
class _RailStatus extends StatelessWidget {
  const _RailStatus({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = state.state;
    final color = live.running ? AppColors.online : theme.colorScheme.outline;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    live.running ? 'Tunnel up' : 'Tunnel down',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              live.running
                  ? '${live.peersUp}/${live.peersTotal} peers · '
                        '↓ ${formatBytes(live.rxBytes)} · ↑ ${formatBytes(live.txBytes)}'
                  : 'Not connected',
              maxLines: 2,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
