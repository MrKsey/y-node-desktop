// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tray_manager/legacy.dart';

import 'app_state.dart';

/// The tray icon and its menu. The menu is the only way to control the tunnel
/// while the window is hidden, so it mirrors the two switches of the Tunnel
/// page and shows the live state in the tooltip.
class TrayController with TrayListener {
  TrayController(this.state, {required this.showWindow, required this.quit});

  final AppState state;
  final Future<void> Function() showWindow;
  final Future<void> Function() quit;

  bool _started = false;

  /// The menu is built once and its items are updated in place. Rebuilding the
  /// whole menu on every state change made Windows re-create the popup while
  /// the click was still being handled: the next right click opened it a few
  /// pixels higher and the new labels were not visible.
  Menu? _menu;
  MenuItem? _stateItem;
  MenuItem? _tunnelItem;
  MenuItem? _exitItem;
  MenuItem? _exitCheckItem;
  MenuItem? _proxyItem;
  MenuItem? _copyItem;

  Future<bool> init() async {
    if (_started) return true;
    if (!trayManager.isSupported) return false;
    _started = true;
    try {
      try {
        await trayManager.setIcon(
          Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
          iconSize: 22,
        );
      } catch (_) {
        // Some native backends accept PNG but not ICO (and the other way
        // round). The PNG is shipped next to the ICO for exactly this case.
        await trayManager.setIcon('assets/tray_icon.png', iconSize: 22);
      }
      await trayManager.setToolTip(_tooltip());
      _menu = _buildMenu();
      await trayManager.setContextMenu(_menu!);
      trayManager.addListener(this);
      state.addListener(_onState);
      _applied = _stateSignature();
      _applyState();
      return true;
    } catch (_) {
      // A desktop without a tray (a bare X session, for example) keeps the
      // window controls working; the menu is simply unavailable.
      _started = false;
      return false;
    }
  }

  Future<void> dispose() async {
    if (!_started) return;
    _started = false;
    state.removeListener(_onState);
    trayManager.removeListener(this);
    await trayManager.destroy();
  }

  String _tooltip() {
    final live = state.state;
    final tunnel = live.running
        ? 'Tunnel up · ${live.peersUp}/${live.peersTotal} peers'
        : 'Tunnel down';
    return 'Y-Node — $tunnel · ${_exitState()} · ${_proxyState()}';
  }

  /// The exit node line of the tooltip: off, the profile name and its state, or
  /// the reason it is not used.
  String _exitState() {
    final live = state.state;
    if (!state.exitEnabled) return 'exit off';
    if (live.exitName.isEmpty) return 'exit: no profile';
    final exitState = live.exitState.isEmpty ? 'unknown' : live.exitState;
    return 'exit ${live.exitName} ($exitState)';
  }

  /// The system proxy setting is the user's intent; the address is filled in
  /// only while the operating system really points at this app.
  String _proxyState() {
    if (!state.state.systemProxy) return 'system proxy off';
    if (state.state.systemProxyAddress.isEmpty) {
      return 'system proxy on connect';
    }
    return 'system proxy on';
  }

  Menu _buildMenu() {
    final live = state.state;
    _stateItem = MenuItem(
      key: 'state',
      label: live.running ? 'Connected' : 'Disconnected',
      disabled: true,
    );
    // A check mark is the only feedback a tray menu can show: the item is
    // ticked while the tunnel, the exit node and the system proxy are on.
    _tunnelItem = MenuItem.checkbox(
      key: 'tunnel',
      label: 'Tunnel',
      checked: live.running,
      onClick: (_) => _afterClick(() async {
        final next = !state.state.running;
        _tunnelItem?.checked = next;
        if (next) {
          await state.connect();
        } else {
          await state.disconnect();
        }
        _onState();
      }),
    );
    _exitItem = MenuItem.checkbox(
      key: 'exit',
      label: 'Exit node',
      checked: state.exitEnabled && state.exits.isNotEmpty,
      disabled: state.exits.isEmpty,
      onClick: (_) => _afterClick(() async {
        final next = !state.exitEnabled;
        _exitItem?.checked = next && state.exits.isNotEmpty;
        await state.setExitEnabled(next);
        _onState();
      }),
    );
    _exitCheckItem = MenuItem(
      key: 'exit-check',
      label: 'Check the exit node',
      disabled: !live.running || state.exits.isEmpty,
      onClick: (_) => _afterClick(() async {
        final report = await state.checkExit();
        await _notify('Exit node', report);
      }),
    );
    _proxyItem = MenuItem.checkbox(
      key: 'proxy',
      label: 'System proxy',
      checked: state.config.systemProxy,
      onClick: (_) => _afterClick(() async {
        final next = !state.config.systemProxy;
        _proxyItem?.checked = next;
        await state.setSystemProxy(next);
        _onState();
      }),
    );
    _copyItem = MenuItem(
      key: 'copy',
      label: 'Copy the address',
      disabled: live.address.isEmpty,
      onClick: (_) => _afterClick(() => _copyAddress(state.state.address)),
    );
    return Menu(
      items: [
        MenuItem(
          key: 'show',
          label: 'Show Y-Node',
          onClick: (_) => _afterClick(showWindow),
        ),
        MenuItem.separator(),
        _stateItem!,
        _tunnelItem!,
        MenuItem.separator(),
        _exitItem!,
        _exitCheckItem!,
        MenuItem.separator(),
        _proxyItem!,
        _copyItem!,
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit Y-Node',
          onClick: (_) => _afterClick(quit),
        ),
      ],
    );
  }

  /// Runs a menu action after the native click handler has returned.
  ///
  /// The click is delivered from the popup's own callback, and the popup still
  /// owns its native objects while that callback runs. Touching them from
  /// inside the click — re-creating or destroying the menu, freeing the tray
  /// icon — corrupts the menu and takes the whole process down with
  /// `0xc0000409` (the `tray_manager` example warns about exactly this: "not
  /// from inside the click: let the menu finish closing first"). A `Timer.run`
  /// is enough: the callback returns, the popup closes, and only then does the
  /// action touch the tray.
  void _afterClick(FutureOr<void> Function() action) {
    Timer.run(() async {
      try {
        await action();
      } catch (_) {
        // A failed tray action must not kill the app: the window still shows
        // the state and the next click retries.
      }
    });
  }

  /// Pushes the live state into the existing menu items. The legacy
  /// tray_manager API updates the native item behind each setter, so no popup
  /// is re-created and the menu keeps its position.
  void _applyState() {
    final live = state.state;
    final running = live.running;
    _stateItem?.label = running
        ? 'Connected · ${live.peersUp}/${live.peersTotal} peers'
        : 'Disconnected';
    _tunnelItem?.checked = running;
    // The first launch has nothing to connect to until the discovery finds a
    // live node: the same lock the power button shows.
    _tunnelItem?.disabled = !running && state.noPeers;
    final exitName = live.exitName.isEmpty
        ? (state.exits.isEmpty ? 'no profile' : state.exits.first.name)
        : live.exitName;
    _exitItem?.label = state.exits.isEmpty
        ? 'Exit node · no profile'
        : 'Exit node · ${state.exitEnabled ? exitName : 'off'}';
    _exitItem?.checked = state.exitEnabled && state.exits.isNotEmpty;
    _exitItem?.disabled = state.exits.isEmpty;
    _exitCheckItem?.disabled = !running || state.exits.isEmpty;
    _proxyItem?.checked = state.config.systemProxy;
    _copyItem?.disabled = live.address.isEmpty;
  }

  /// The tray has no dialogs, so a check result is announced through the
  /// tooltip and the log. The window shows the same message when it is opened.
  Future<void> _notify(String title, String body) async {
    state.showNotice('$title: $body');
    await trayManager.setToolTip('Y-Node — ${_tooltip()}');
    await _showBalloon(title, body);
  }

  Future<void> _showBalloon(String title, String body) async {
    // tray_manager has no portable balloon API; the tooltip carries the state
    // and the window keeps the full text in its notice banner.
    await trayManager.setToolTip('Y-Node — $title: $body');
    _onState();
  }

  Future<void> _copyAddress(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    await trayManager.setToolTip('Y-Node — address copied');
    _onState();
  }

  void _onState() {
    if (!_started) return;
    // The state listener fires once a second for the counters, but the menu
    // only shows a few of them. Applying an unchanged state would still call
    // into the native menu, so the signature guards the calls.
    final signature = _stateSignature();
    if (signature == _applied) return;
    _applied = signature;
    _applyState();
    trayManager.setToolTip(_tooltip());
  }

  String? _applied;

  String _stateSignature() {
    final live = state.state;
    return [
      live.running,
      live.peersUp,
      live.peersTotal,
      live.exitName,
      live.exitState,
      live.address,
      state.exitEnabled,
      state.exits.length,
      state.config.systemProxy,
      state.configuredPeers.length,
      state.probing,
      state.noPeers,
    ].join('|');
  }

  @override
  void onTrayIconMouseDown() {
    // The window is shown from the icon's own callback; the tray must not be
    // touched while that callback runs, so the call is deferred like a menu
    // click.
    _afterClick(showWindow);
  }

  @override
  void onTrayIconRightMouseDown() {
    // Only the press opens the menu. Opening it again on the release made
    // Windows show a second popup under the first one, which looked like the
    // menu jumping up on every click.
    trayManager.popUpContextMenu();
  }
}
