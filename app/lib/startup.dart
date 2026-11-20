import 'dart:io';

/// The per-user Windows "Run" entry of the application.
///
/// The entry is the whole setting: its presence means "start with Windows".
/// The command carries `--tray`, so a launch made by Windows opens the window
/// in the tray while a launch from the Start menu shows it. The registry is
/// read back after every change, so the switch shows what Windows will really
/// do.
class StartupEntry {
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _name = 'Y-Node';

  /// The argument the window uses to stay in the tray on launch.
  static const trayArgument = '--tray';

  static bool get supported => Platform.isWindows;

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      final result = await Process.run('reg', ['query', _key, '/v', _name]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Adds or removes the entry. Returns true when the registry ends up in the
  /// requested state.
  static Future<bool> setEnabled(bool enabled) async {
    if (!supported) return false;
    try {
      if (enabled) {
        final exe = Platform.resolvedExecutable;
        await Process.run('reg', [
          'add',
          _key,
          '/v',
          _name,
          '/t',
          'REG_SZ',
          '/d',
          '"$exe" $trayArgument',
          '/f',
        ]);
      } else {
        await Process.run('reg', ['delete', _key, '/v', _name, '/f']);
      }
    } catch (_) {
      return false;
    }
    return await isEnabled() == enabled;
  }
}
