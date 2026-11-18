import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/store/media_store.dart';
import 'package:openote/store/notebook_writer.dart' show sha256Hex;
import 'package:openote/model/models.dart';
import 'support/sqlite.dart';

void main() {
  setUpAll(() {
    expect(initSqliteForTests(), isTrue);
  });

  test('full backup restores external media of a structured notebook',
      () async {
    final tmp = Directory.systemTemp.createTempSync('openote_storage_audit_');
    final repo = await Repository.openAt(
        Directory('${tmp.path}/workspace')..createSync());
    final nb = await repo.createNotebook('Media');
    final app = AppState(repo)..notebookId = nb.id;
    final media = MediaStore.dirFor(nb)..createSync(recursive: true);
    File('${media.path}/example.mp4').writeAsBytesSync([1, 2, 3, 4]);
    final page =
        repo.loadNodes(nb.id).firstWhere((n) => n.kind == NodeKind.page);
    repo.writePage(
        nb.id,
        page.id,
        [
          Block(
              type: BlockType.file,
              x: 0,
              y: 0,
              content: {'kind': 'video', 'media': 'example.mp4'})
        ],
        PageProps());
    final restoredRepo = await Repository.openAt(
        Directory('${tmp.path}/restored')..createSync());
    final restoredApp = AppState(restoredRepo)..spellCheckEnabled = false;
    try {
      await app.createWorkspaceBackup('${tmp.path}/backup.zip');
      await restoredApp.restoreWorkspaceBackup('${tmp.path}/backup.zip');
      final restored = restoredRepo.notebooks
          .singleWhere((n) => n.id == restoredApp.notebookId);
      expect(MediaStore.resolve(restored, 'example.mp4'), isNotNull);
      expect(await MediaStore.resolve(restored, 'example.mp4')!.readAsBytes(),
          [1, 2, 3, 4]);
    } finally {
      restoredApp.dispose();
      app.dispose();
      tmp.deleteSync(recursive: true);
    }
  });

  test('full workspace backup includes trashed notebook containers', () async {
    final tmp = Directory.systemTemp.createTempSync('openote_storage_audit_');
    final repo = await Repository.openAt(
        Directory('${tmp.path}/workspace')..createSync());
    final live = await repo.createNotebook('Live');
    final deleted = await repo.createNotebook('Deleted');
    final deletedAt = DateTime.now().millisecondsSinceEpoch - 5000;
    await repo.trashNotebook(deleted.id, deletedAt: deletedAt);
    final originalBytes = Uint8List.fromList([4, 3, 2, 1]);
    final hash = repo.putBlob(deleted.id, originalBytes, 'application/pdf');
    final app = AppState(repo)..notebookId = live.id;
    try {
      await app.createWorkspaceBackup('${tmp.path}/backup.zip');
      final archive = ZipDecoder()
          .decodeBytes(File('${tmp.path}/backup.zip').readAsBytesSync());
      expect(
          archive.any((e) =>
              e.name.contains('Recycle Bin/') && e.name.endsWith('.onote')),
          isTrue);
      final restoredRepo = await Repository.openAt(
          Directory('${tmp.path}/restored')..createSync());
      final restoredApp = AppState(restoredRepo)..spellCheckEnabled = false;
      try {
        expect(
            await restoredApp.restoreWorkspaceBackup('${tmp.path}/backup.zip'),
            2);
        expect(restoredRepo.notebooks.map((n) => n.title), ['Live']);
        final trashed = restoredRepo.trashedNotebooks.single;
        expect(trashed.title, 'Deleted');
        expect(trashed.deletedAt, deletedAt);
        await restoredRepo.restoreNotebook(trashed.id);
        expect(restoredRepo.getBlob(trashed.id, hash), originalBytes);
      } finally {
        restoredApp.dispose();
      }
    } finally {
      app.dispose();
      tmp.deleteSync(recursive: true);
    }
  });

  test('missing registry recovers structured notebooks', () async {
    final tmp = Directory.systemTemp.createTempSync('openote_storage_audit_');
    final source = Directory('${tmp.path}/source');
    var repo = await Repository.openAt(source);
    final live = await repo.createNotebook('Existing');
    final deleted = await repo.createNotebook('Deleted');
    await repo.trashNotebook(deleted.id);
    repo.dispose();
    final copied = Directory('${tmp.path}/copied')..createSync();
    await for (final entry
        in source.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entry.path, from: source.path);
      if (relative == 'workspace.json' || relative == 'workspace.json.bak') {
        continue;
      }
      final target = p.join(copied.path, relative);
      if (entry is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entry is File) {
        File(target).parent.createSync(recursive: true);
        entry.copySync(target);
      }
    }
    repo = await Repository.openAt(copied);
    try {
      expect(repo.notebooks.any((n) => n.title == 'Existing'), isTrue);
      expect(repo.notebooks.single.id, live.id);
      expect(repo.trashedNotebooks.single.id, deleted.id);
      expect(await repo.purgeExpiredNotebooks(), 0,
          reason: 'a lost deletion timestamp must not immediately purge data');
      expect(File('${copied.path}/workspace.json').existsSync(), isTrue);
    } finally {
      repo.dispose();
      tmp.deleteSync(recursive: true);
    }
  });

  test('single notebook backup preserves legacy originals independently',
      () async {
    final tmp = Directory.systemTemp.createTempSync('openote_portable_backup_');
    final repo = await Repository.openAt(Directory('${tmp.path}/source'));
    final nb = await repo.createNotebook('Originals');
    final bytes = Uint8List.fromList([7, 2, 5, 9, 1]);
    final hash = sha256Hex(bytes);
    final blobFile = File('${File(nb.file).parent.path}/blobs/$hash');
    blobFile.parent.createSync();
    blobFile.writeAsBytesSync(bytes);
    final page =
        repo.loadNodes(nb.id).firstWhere((n) => n.kind == NodeKind.page);
    repo.writePage(
        nb.id,
        page.id,
        [
          Block(
              type: BlockType.image,
              x: 5,
              y: 7,
              content: {'blob': 'sha256:$hash'})
        ],
        PageProps());
    final app = AppState(repo)..notebookId = nb.id;
    final targetRepo = await Repository.openAt(Directory('${tmp.path}/target'));
    final targetApp = AppState(targetRepo)..spellCheckEnabled = false;
    try {
      await app.createWorkspaceBackup('${tmp.path}/backup.zip',
          onlyNotebookId: nb.id);
      expect(repo.containerBlob(nb.id, hash), isNull,
          reason: 'backing up must not migrate the source notebook');
      await blobFile.rename('${blobFile.path}.unavailable');
      await targetApp.restoreWorkspaceBackup('${tmp.path}/backup.zip');
      final imported = targetRepo.notebooks.single;
      expect(File(imported.file).parent.path, endsWith('Originals.onotebook'));
      expect(targetRepo.getBlob(imported.id, hash), bytes);
      expect(targetRepo.readPage(imported.id, page.id).blocks.single.x, 5);
    } finally {
      targetApp.dispose();
      app.dispose();
      tmp.deleteSync(recursive: true);
    }
  });

  test('refresh finds copied folders once without reviving the recycle bin',
      () async {
    final tmp =
        Directory.systemTemp.createTempSync('openote_notebook_refresh_');
    final source = await Repository.openAt(Directory('${tmp.path}/source'));
    final original = await source.createNotebook('Manual');
    source.dispose();
    final repo = await Repository.openAt(Directory('${tmp.path}/target'));
    final folder = Directory('${repo.workspaceDir.path}/Manual.onotebook')
      ..createSync();
    File(original.file).copySync('${folder.path}/Manual.onote');
    final junk = File('${repo.workspaceDir.path}/Not a notebook.onote')
      ..writeAsStringSync('not SQLite');
    try {
      await Future.wait([repo.refreshNotebooks(), repo.refreshNotebooks()]);
      expect(repo.notebooks.single.id, original.id);
      await repo.trashNotebook(original.id);
      await repo.refreshNotebooks();
      expect(repo.notebooks, isEmpty);
      expect(repo.trashedNotebooks.single.id, original.id);
      expect(junk.readAsStringSync(), 'not SQLite');
    } finally {
      repo.dispose();
      tmp.deleteSync(recursive: true);
    }
  });
}
