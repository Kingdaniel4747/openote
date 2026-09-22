import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/store/media_store.dart';
import 'package:openote/store/notebook_writer.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('legacy sync assets are copied into local notebook storage', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');

    final temporary = Directory.systemTemp.createTempSync('onote_assets_');
    final workspace = Directory(p.join(temporary.path, 'workspace'))
      ..createSync();
    final legacy = Directory(p.join(temporary.path, 'old-assets'));
    Repository? repository;
    try {
      repository = await Repository.openAt(workspace);
      final notebook = await repository.createNotebook('School');
      final notebookId = notebook.id;
      await repository.flushWorkspace();
      repository.dispose();
      repository = null;

      final image = Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 1, 2]);
      final hash = sha256Hex(image);
      final blobs = Directory(p.join(legacy.path, 'blobs'))
        ..createSync(recursive: true);
      File(p.join(blobs.path, hash)).writeAsBytesSync(image);
      final media = Directory(p.join(legacy.path, 'media'))..createSync();
      File(p.join(media.path, 'lecture.mp4')).writeAsBytesSync([3, 4, 5]);

      final registryFile = File(p.join(workspace.path, 'workspace.json'));
      final registry =
          jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>;
      final entries = registry['notebooks'] as List<dynamic>;
      (entries.single as Map<String, dynamic>)['logDir'] = legacy.path;
      registryFile.writeAsStringSync(jsonEncode(registry));

      repository = await Repository.openAt(workspace);
      expect(repository.getBlob(notebookId, hash), image);
      final reopened = repository.notebooks.single;
      expect(
          File(p.join(MediaStore.dirFor(reopened).path, 'lecture.mp4'))
              .readAsBytesSync(),
          <int>[3, 4, 5]);
      expect(File(p.join(blobs.path, hash)).existsSync(), isTrue,
          reason: 'migration must leave the recoverable source untouched');
    } finally {
      repository?.dispose();
      try {
        temporary.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
