import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:openote/core/original_download.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  test('downloads continue numbering across types without replacing originals', () async {
    final directory = await Directory.systemTemp.createTemp('openote_download_');
    try {
      final original = File('${directory.path}/OpenNote 7.pdf');
      await original.writeAsString('original');
      final image = await reserveOriginalDownload(directory.path, 'png');
      await image.writeAsString('image');
      final pdf = await reserveOriginalDownload(directory.path, 'pdf');
      expect(image.path, endsWith('OpenNote 8.png'));
      expect(pdf.path, endsWith('OpenNote 9.pdf'));
      expect(await original.readAsString(), 'original');
      expect(await image.readAsString(), 'image');
      final simultaneous = await Future.wait([
        reserveOriginalDownload(directory.path, 'png'),
        reserveOriginalDownload(directory.path, 'png'),
      ]);
      expect(simultaneous.map((f) => f.path).toSet(), hasLength(2));
      expect(await original.readAsString(), 'original');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  test('pool links store relative paths without copying file contents', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final directory = await Directory.systemTemp.createTemp('openote_pool_');
    final repo = await Repository.openAt(directory);
    final nb = await repo.createNotebook('Pool');
    final app = AppState(repo)..notebookId = nb.id;
    try {
      app.reloadNodes();
      await app.selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      final file = File(p.join(app.poolDirectory.path, 'Math', 'worksheet.mn'));
      await file.parent.create(recursive: true);
      await file.writeAsString('original');
      app.linkPoolFile(file.path);
      final link = app.blocks.last;
      expect(link.content['poolPath'], 'Math/worksheet.mn');
      expect(link.content.containsKey('blob'), isFalse);
      expect(app.resolvePoolFile(link.content['poolPath'] as String), file.path);
      expect(app.resolvePoolFile('../outside.pdf'), isNull);
      expect(await file.readAsString(), 'original');
      app.undo();
      expect(app.blocks.where((b) => b.id == link.id), isEmpty);
      expect(await file.exists(), isTrue);
    } finally {
      app.cancelPendingSave();
      repo.dispose();
      await directory.delete(recursive: true);
    }
  });
  for (final horizontal in [false, true]) {
    test('arrange rotated media ${horizontal ? 'horizontally' : 'vertically'} and undo', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final directory = await Directory.systemTemp.createTemp('openote_arrange_');
      final repo = await Repository.openAt(directory);
      final nb = await repo.createNotebook('Media');
      final app = AppState(repo)..notebookId = nb.id;
      try {
        app.reloadNodes();
        await app.selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
        final first = Block(type: BlockType.image, x: 200, y: 200,
            w: 200, h: 100, rotation: 90, content: {'pdf': 'pdf', 'locked': true});
        final second = Block(type: BlockType.image, x: 200, y: 200,
            w: 80, h: 120, content: {'blob': 'image'});
        final text = Block(type: BlockType.text, x: 300, y: 300,
            w: 100, content: {'text': 'Leave me here'});
        app.blocks = [first, second, text];
        app.selectMany([first.id, second.id, text.id]);
        app.arrangeSelectedMedia(horizontal: horizontal);
        final a = app.blockVisualBounds(first);
        final b = app.blockVisualBounds(second);
        if (horizontal) {
          expect(b.left - a.right, closeTo(24, .001));
          expect(b.top, closeTo(a.top, .001));
        } else {
          expect(b.top - a.bottom, closeTo(24, .001));
          expect(b.left, closeTo(a.left, .001));
        }
        expect(first.rotation, 90);
        expect(first.content['locked'], true);
        expect(text.x, 300);
        app.undo();
        expect(app.blocks.first.x, 200);
        expect(app.blocks[1].y, 200);
        expect(app.blocks.first.rotation, 90);
      } finally {
        app.cancelPendingSave();
        repo.dispose();
        await directory.delete(recursive: true);
      }
    });
  }
}
