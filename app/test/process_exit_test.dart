import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved process exits with a blocked native worker and releases its lock',
      () async {
    final config = File('.dart_tool/package_config.json').absolute;
    final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
    final flutterPackage = packages.singleWhere((p) => p['name'] == 'flutter');
    final flutter = Directory.fromUri(
            config.uri.resolve(flutterPackage['rootUri'] as String))
        .parent
        .parent;
    final dart = '${flutter.path}/bin/cache/dart-sdk/bin/dart.exe';
    final temp = Directory.systemTemp.createTempSync('openote-exit-');
    final saved = File('${temp.path}/saved');
    Process? child;
    try {
      child = await Process.start(
          dart, ['test/native/process_exit_probe.dart', saved.path]);
      final errors =
          child.stderr.transform(const SystemEncoding().decoder).join();
      expect(await child.exitCode.timeout(const Duration(seconds: 15)), 0,
          reason: await errors);
      expect(saved.readAsStringSync(), 'saved and closed');
      final lock = File('${saved.path}.lock').openSync(mode: FileMode.append);
      try {
        lock.lockSync(FileLock.exclusive);
        lock.unlockSync();
      } finally {
        lock.closeSync();
      }
    } finally {
      child?.kill();
      if (child != null) await child.exitCode;
      temp.deleteSync(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
