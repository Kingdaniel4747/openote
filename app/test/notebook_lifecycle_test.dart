// Regression coverage for the notebook recycle-bin lifecycle added in the
// navigator rework: delete → recycle bin → restore, rename, permanent purge
// (removes the .onote file), workspace persistence of the trashed list, and the
// AppState guard that refuses to delete the only notebook.
//
// Pure repository/state logic over a real temp SQLite workspace — no widgets,
// no document engine. Skips if the bundled sqlite3.dll isn't present.
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var haveSqlite = false;
  setUpAll(() {
    for (final rel in [
      'build/windows/x64/runner/Debug/sqlite3.dll',
      'build/windows/x64/runner/Release/sqlite3.dll',
    ]) {
      final f = File(rel);
      if (f.existsSync()) {
        open.overrideForAll(() => DynamicLibrary.open(f.absolute.path));
        haveSqlite = true;
        break;
      }
    }
  });

  test('notebook trash → restore → rename → purge, and it persists', () async {
    if (!haveSqlite) {
      markTestSkipped('sqlite3.dll not built');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('onote_nb_');
    var repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best-effort */}
    });

    final a = await repo.createNotebook('Alpha');
    final b = await repo.createNotebook('Beta');
    expect(repo.notebooks.map((n) => n.id), [a.id, b.id]);
    expect(repo.trashedNotebooks, isEmpty);

    // Trash Beta: moves its complete folder into the physical recycle bin.
    final betaLiveFile = b.file;
    await repo.trashNotebook(b.id);
    expect(repo.notebooks.map((n) => n.id), [a.id]);
    expect(repo.trashedNotebooks.map((n) => n.id), [b.id]);
    expect(repo.trashedNotebooks.single.deletedAt, isNotNull);
    expect(
        b.file,
        contains(
            '${Repository.recycleBinDirectoryName}${Platform.pathSeparator}'));
    expect(File(betaLiveFile).existsSync(), false,
        reason: 'a trashed notebook is no longer in the live workspace');
    expect(File(b.file).existsSync(), true, reason: 'restore must be lossless');

    // Restore moves the same complete folder back with its mark cleared.
    await repo.restoreNotebook(b.id);
    expect(repo.notebooks.map((n) => n.id).toSet(), {a.id, b.id});
    expect(repo.trashedNotebooks, isEmpty);
    expect(b.file, betaLiveFile);
    expect(File(betaLiveFile).existsSync(), true);

    // Rename sticks on the active ref.
    final oldFolder = File(a.file).parent;
    repo.closeNotebook(a.id);
    final oldSidecar = File('${a.file}-wal')..writeAsStringSync('sidecar');
    await repo.renameNotebook(a.id, 'Alpha renamed');
    expect(
        repo.notebooks.firstWhere((n) => n.id == a.id).title, 'Alpha renamed');
    expect(Directory(a.file).parent.existsSync(), true);
    expect(oldFolder.existsSync(), false);
    expect(File(a.file).existsSync(), true,
        reason: 'the database follows the renamed notebook folder');
    expect(File('${a.file}-wal').existsSync(), true,
        reason: 'SQLite sidecars follow the renamed database too');
    expect(oldSidecar.existsSync(), false);

    // Purge deletes the complete structured notebook folder for good.
    final notebookFolder = File(a.file).parent;
    File('${notebookFolder.path}${Platform.pathSeparator}leftover.tmp')
        .writeAsStringSync('must be removed with the notebook');
    await repo.trashNotebook(a.id);
    expect(notebookFolder.existsSync(), false,
        reason: 'the full folder is moved out of the live workspace');
    expect(
        File(a.file).parent.path,
        contains(
            '${Repository.recycleBinDirectoryName}${Platform.pathSeparator}'));
    expect(
        File('${File(a.file).parent.path}${Platform.pathSeparator}leftover.tmp')
            .existsSync(),
        true,
        reason: 'all notebook contents move together');
    await repo.purgeNotebook(a.id);
    expect(File(a.file).existsSync(), false);
    expect(notebookFolder.existsSync(), false,
        reason: 'no empty .onotebook folder or side file is left behind');
    expect(repo.trashedNotebooks, isEmpty);
    expect(repo.notebooks.map((n) => n.id), [b.id]);

    // The old name is genuinely free once the notebook has been purged.
    final replacement = await repo.createNotebook('Alpha renamed');
    expect(replacement.file, contains('Alpha renamed.onotebook'));

    // But an existing live or trashed notebook never silently gets a `-2`.
    await expectLater(repo.createNotebook('Alpha renamed'), throwsStateError);
    await repo.trashNotebook(replacement.id);
    await expectLater(repo.createNotebook('Alpha renamed'), throwsStateError);
    b.title = replacement.title;
    await expectLater(repo.restoreNotebook(replacement.id), throwsStateError,
        reason: 'a restore must never overwrite a same-named live notebook');
    b.title = 'Beta';
    await repo.purgeNotebook(replacement.id);

    // Repair the empty folder left by the old permanent-delete implementation
    // rather than silently turning the requested name into `-2`.
    final staleFolder =
        Directory('${tmp.path}${Platform.pathSeparator}Legacy.onotebook')
          ..createSync();
    final repaired = await repo.createNotebook('Legacy');
    expect(File(repaired.file).parent.path, staleFolder.path);
    await repo.trashNotebook(repaired.id);
    await repo.purgeNotebook(repaired.id);

    // Persistence: a trashed notebook survives reopening the workspace.
    await repo.trashNotebook(b.id);
    expect(repo.notebooks, isEmpty);
    repo.dispose();
    repo = await Repository.openAt(tmp);
    expect(repo.trashedNotebooks.map((n) => n.id), [b.id]);
    expect(repo.notebooks, isEmpty);
  });

  test('retention auto-purges expired trashed notebooks, keeps fresh ones',
      () async {
    if (!haveSqlite) {
      markTestSkipped('sqlite3.dll not built');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('onote_ret_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best-effort */}
    });

    await repo.createNotebook('Keep');
    final fresh = await repo.createNotebook('Fresh');
    final old = await repo.createNotebook('Old');
    await repo.trashNotebook(fresh.id);
    await repo.trashNotebook(old.id);

    // Backdate "Old" past the retention window; "Fresh" stays recent.
    final beyond = DateTime.now().millisecondsSinceEpoch -
        const Duration(days: Repository.recycleRetentionDays + 1)
            .inMilliseconds;
    repo.trashedNotebooks.firstWhere((n) => n.id == old.id).deletedAt = beyond;

    final purged = await repo.purgeExpiredNotebooks();
    expect(purged, 1);
    expect(repo.trashedNotebooks.map((n) => n.id), [fresh.id],
        reason: 'the fresh one survives the sweep');
    expect(File(old.file).existsSync(), false, reason: 'expired file removed');
    expect(File(fresh.file).existsSync(), true);
  });

  test('AppState.deleteNotebook refuses the only notebook', () async {
    if (!haveSqlite) {
      markTestSkipped('sqlite3.dll not built');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('onote_nb1_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best-effort */}
    });

    final only = await repo.createNotebook('Solo');
    final app = AppState(repo);
    app.notebookId = only.id;

    // Guard returns false before any teardown; the notebook stays put.
    expect(await app.deleteNotebook(only.id), false);
    expect(repo.notebooks.map((n) => n.id), [only.id]);
    expect(repo.trashedNotebooks, isEmpty);
    // AppState isn't init()'d, so no debounce timer to cancel; the teardown
    // disposes the shared repo (AppState.dispose would double-dispose it).
  });
}
