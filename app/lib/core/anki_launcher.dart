import 'dart:io';

import 'package:path/path.dart' as p;

/// Starts the user's existing Anki installation. Openote never reads or
/// changes Anki's collection; this is only a convenient jump to study time.
abstract final class AnkiLauncher {
  static Future<bool> open(String? configuredPath) async {
    final configured = configuredPath?.trim();
    final executable = configured != null && File(configured).existsSync()
        ? configured
        : _knownInstall();
    try {
      if (executable != null) {
        await Process.start(executable, const []);
        return true;
      }
      // Linux packages expose Anki on PATH. Process.start uses argv directly,
      // never a shell, so this remains safe even when the path was user-set.
      if (Platform.isLinux) {
        await Process.start('anki', const []);
        return true;
      }
    } catch (_) {
      // Settings offers a file chooser when automatic discovery is not enough.
    }
    return false;
  }

  static String? _knownInstall() {
    if (!Platform.isWindows) return null;
    final programFiles = Platform.environment['ProgramFiles'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final candidates = [
      if (programFiles != null) p.join(programFiles, 'Anki', 'anki.exe'),
      if (localAppData != null)
        p.join(localAppData, 'Programs', 'Anki', 'anki.exe'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
