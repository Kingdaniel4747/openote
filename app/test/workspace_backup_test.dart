import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('workspace backup excludes live single-instance protocol files',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');

    final temporary = Directory.systemTemp.createTempSync('onote_backup_');
    final workspace = Directory(p.join(temporary.path, 'workspace'))
      ..createSync();
    final repository = await Repository.openAt(workspace);
    final notebook = await repository.createNotebook('School');
    final app = AppState(repository)
      ..notebookId = notebook.id
      ..spellCheckEnabled = false;
    app.reloadNodes();

    final lockFile = File(p.join(workspace.path, '.instance-lock'));
    final lock = lockFile.openSync(mode: FileMode.append);
    lock.lockSync(FileLock.exclusive);
    File(p.join(workspace.path, '.open-request')).writeAsStringSync('request');
    File(p.join(workspace.path, 'kept.txt')).writeAsStringSync('keep me');

    try {
      final backup = File(p.join(temporary.path, 'backup.zip'));
      await app.createWorkspaceBackup(backup.path);

      final archive = ZipDecoder().decodeBytes(backup.readAsBytesSync());
      final names = archive.map((entry) => entry.name).toSet();
      expect(names.any((name) => name.endsWith('.instance-lock')), isFalse);
      expect(names.any((name) => name.endsWith('.open-request')), isFalse);
      expect(names.any((name) => name.endsWith('kept.txt')), isTrue);
      expect(names.any((name) => name.endsWith('.onote')), isTrue);
    } finally {
      lock.unlockSync();
      lock.closeSync();
      await app.settleBackgroundWork();
      app.dispose();
      try {
        temporary.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
