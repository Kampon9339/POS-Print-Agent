import 'dart:io';
import 'package:path/path.dart' as p;
import '../logging/app_logger.dart';

/// Manages login auto-start registration for Windows (`HKCU\...\Run`)
/// and macOS (`~/Library/LaunchAgents/com.pos.printagent.plist`).
class AutoStartService {
  final AppLogger logger;

  static const String _macosLabel = 'com.pos.printagent';
  static const String _windowsRegValue = 'POSPrintAgent';

  const AutoStartService({required this.logger});

  /// Enables or disables starting POS Print Agent automatically at user login.
  Future<bool> setAutoStart(bool enabled) async {
    try {
      if (Platform.isMacOS) {
        return _setMacosLaunchAgent(enabled);
      } else if (Platform.isWindows) {
        return await _setWindowsRegistryRun(enabled);
      }
      return false;
    } catch (e) {
      logger.error('AutoStart', 'Failed to update auto-start setting: $e');
      return false;
    }
  }

  bool _setMacosLaunchAgent(bool enabled) {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return false;

    final agentsDir = Directory(p.join(home, 'Library', 'LaunchAgents'));
    final plistFile = File(p.join(agentsDir.path, '$_macosLabel.plist'));

    if (!enabled) {
      if (plistFile.existsSync()) {
        plistFile.deleteSync();
      }
      logger.info('AutoStart', 'Removed macOS LaunchAgent plist');
      return true;
    }

    if (!agentsDir.existsSync()) {
      agentsDir.createSync(recursive: true);
    }

    final execPath = Platform.resolvedExecutable;
    final plistXml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_macosLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>$execPath</string>
    <string>--minimized</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
''';
    plistFile.writeAsStringSync(plistXml);
    logger.info('AutoStart', 'Registered macOS LaunchAgent plist', {
      'plistPath': plistFile.path,
    });
    return true;
  }

  Future<bool> _setWindowsRegistryRun(bool enabled) async {
    const regKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    if (!enabled) {
      final res = await Process.run('reg', [
        'delete',
        regKey,
        '/v',
        _windowsRegValue,
        '/f',
      ]);
      return res.exitCode == 0;
    }

    final execPath = '"${Platform.resolvedExecutable}" --minimized';
    final res = await Process.run('reg', [
      'add',
      regKey,
      '/v',
      _windowsRegValue,
      '/t',
      'REG_SZ',
      '/d',
      execPath,
      '/f',
    ]);
    return res.exitCode == 0;
  }
}
