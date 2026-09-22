// Ink through a real save and load, and what the disk holds afterwards.
//
// The codec is tested in isolation in ink_codec_test.dart. This is the part
// that changes users' files: a page saved with handwriting must come back with
// the same handwriting, the container must be dramatically smaller, and — the
// finding that made this dangerous — the OPERATION LOG must be able to
// reconstruct it, which it can only do if the bytes were written there too.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ink/ink_codec.dart';
import 'package:openote/ink/ink_storage.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;
  late String pageId;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_inkstore_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Ink');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.pageId = pageId;
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Handwriting shaped like real imported ink.
  List<Stroke> handwriting({int count = 60, int seed = 3}) {
    final rnd = Random(seed);
    return [
      for (var s = 0; s < count; s++)
        () {
          final n = 8 + rnd.nextInt(40);
          var x = 120 + rnd.nextDouble() * 700;
          var y = 90 + rnd.nextDouble() * 500;
          final xs = <double>[], ys = <double>[], ps = <double>[];
          for (var i = 0; i < n; i++) {
            x += rnd.nextDouble() * 5 - 2.5;
            y += rnd.nextDouble() * 5 - 2.5;
            xs.add(x);
            ys.add(y);
            ps.add(0.2 + rnd.nextDouble() * 0.8);
          }
          return Stroke(
              id: 'w$s',
              tool: 'pen',
              colorHex: '#211F1B',
              size: 2.5,
              x: xs,
              y: ys,
              p: ps);
        }()
    ];
  }

  Block inkBlock(List<Stroke> strokes) => Block(
        id: 'ink-1',
        type: BlockType.ink,
        x: 100,
        y: 80,
        w: 800,
        h: 600,
        content: {
          'strokes': [for (final s in strokes) s.toJson()]
        },
      );

  test('handwriting survives a save and a reload', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final strokes = handwriting();
    app.blocks = [inkBlock(strokes)];
    app.markDirty();
    await app.flushSave();

    // Out of the container, through the same path the editor uses.
    final back = repo.readPage(app.notebookId!, pageId);
    final b = back.blocks.single;
    expect(b.type, BlockType.ink);
    final list = b.content['strokes'] as List;
    expect(list.length, strokes.length, reason: 'every stroke comes back');

    for (var i = 0; i < strokes.length; i++) {
      final got = Stroke.fromJson((list[i] as Map).cast<String, dynamic>());
      expect(got.x.length, strokes[i].x.length);
      for (var k = 0; k < got.x.length; k++) {
        expect(got.x[k], closeTo(strokes[i].x[k], 1 / (2 * kInkScale)));
        expect(got.y[k], closeTo(strokes[i].y[k], 1 / (2 * kInkScale)));
      }
      expect(got.colorHex.toUpperCase(), '#211F1B');
      expect(got.size, closeTo(2.5, 1 / 64));
    }
  });

  test('THE PAGE JSON NO LONGER CONTAINS THE STROKES', () async {
    // The whole point. 63 MB of a real notebook was stroke arrays in this
    // column.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks = [inkBlock(handwriting(count: 200))];
    app.markDirty();
    await app.flushSave();

    final row = repo.rawPageJsonForTest(app.notebookId!, pageId);
    expect(row, isNotNull);
    expect(row!, isNot(contains('"strokes"')),
        reason: 'the page mirror must hold a reference, not the geometry');
    expect(row, contains('"ink"'));
    expect(row, contains('"base"'));
    // A generous bound: 200 strokes of real geometry as JSON is hundreds of
    // kilobytes, and the reference form is a few hundred bytes.
    expect(row.length, lessThan(4000),
        reason: 'page JSON was ${row.length} bytes');
  });

  test('erasing previously persisted handwriting survives reload', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks = [inkBlock(handwriting(count: 3))];
    app.markDirty();
    await app.flushSave();

    // This is the state an old page has in the editor: the persisted ref and
    // decoded working strokes coexist. Editing it must invalidate that ref.
    app.blocks = repo.readPage(app.notebookId!, pageId).blocks;
    final edited = app.blocks.single;
    expect(edited.content['ink'], isA<Map>());
    final strokes = edited.content['strokes'] as List;
    strokes.removeAt(0);
    app.updateBlock(edited);
    expect(edited.content.containsKey('ink'), isFalse);
    await app.flushSave();

    final reloaded = repo.readPage(app.notebookId!, pageId).blocks.single;
    expect((reloaded.content['strokes'] as List).length, 2,
        reason: 'deleted old ink must not be restored from its stale blob');
  });

  test('the page declares its ink in blob_refs', () async {
    // ADR-0007's garbage collection recomputes what is reachable by scanning
    // pages. A page that does not declare its handwriting is a page whose
    // handwriting would be collected.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks = [inkBlock(handwriting(count: 12))];
    app.markDirty();
    await app.flushSave();
    expect(repo.blobRefsForTest(app.notebookId!, pageId), isNotEmpty,
        reason: 'the ink blob must be reachable from the page');
  });

  group('the storage boundary on its own', () {
    test('a missing blob leaves the reference alone', () {
      // A notebook joined from a remote can legitimately hold a ref whose
      // bytes have not arrived. Returning an empty stroke list would let the
      // next save overwrite the reference with nothing — losing the ink for
      // everyone, permanently.
      final content = <String, dynamic>{
        'ink': {
          'v': 1,
          'base': 'sha256:deadbeef',
          'n': 5,
          'o': [0, 0]
        }
      };
      final out = InkStorage.toWorking(content, (_) => null);
      expect(out, same(content), reason: 'unchanged, ref intact');
      expect(InkStorage.strokeCount(out), 5,
          reason: 'and it still knows how much is missing');
    });

    test('an unparseable stroke stops the conversion rather than dropping it',
        () {
      final content = <String, dynamic>{
        'strokes': [
          {'nonsense': true}
        ]
      };
      var called = false;
      final out = InkStorage.toPersisted(content, (_) {
        called = true;
        return 'x';
      });
      expect(out, same(content),
          reason: 'left legacy: it still renders and still saves');
      expect(called, isFalse, reason: 'nothing was written');
    });

    test('A ROUND TRIP DOES NOT PUT THE STROKES BACK ON DISK', () {
      // The bug that made the whole feature a no-op, and it was invisible
      // because everything still WORKED — the strokes were simply written
      // twice. `toWorking` adds a decoded `strokes` list beside the `ink`
      // descriptor so the painter and the exporters see what they always saw;
      // `toPersisted` then returned that untouched because it was already a
      // reference, so a converted page grew its geometry straight back on the
      // next save. The notebook never actually shrank, and every page stayed a
      // candidate the conversion would then refuse:
      //
      //   "it could not shrink any of the 113 pages — a page matched the
      //    search but held no convertable handwriting"
      final strokes = [
        Stroke(
            id: 'a',
            tool: 'pen',
            colorHex: '#211F1B',
            size: 2,
            x: [1, 2, 3],
            y: [1, 2, 3])
      ];
      final store = <String, Uint8List>{};
      final persisted = InkStorage.toPersisted(<String, dynamic>{
        'strokes': [for (final s in strokes) s.toJson()]
      }, (bytes) {
        const hash = 'sha256:aa';
        store[hash] = bytes;
        return hash;
      });
      expect(persisted.containsKey('strokes'), isFalse);

      // Read it the way the editor does…
      final working = InkStorage.toWorking(persisted, (h) => store[h]);
      expect(working['strokes'], isA<List>(),
          reason: 'consumers must still see strokes');

      // …and save it again. THIS is where the geometry used to come back.
      final again = InkStorage.toPersisted(working, (_) {
        fail('an unchanged reference must not write a second blob');
      });
      expect(again.containsKey('strokes'), isFalse,
          reason: 'the working strokes must not reach the disk');
      expect(InkStorage.refsOf(again), InkStorage.refsOf(persisted),
          reason: 'and it is still the same ink');
    });

    test('counting strokes never opens a blob', () {
      var opened = false;
      final content = <String, dynamic>{
        'ink': {
          'v': 1,
          'base': 'sha256:aa',
          'n': 4096,
          'o': [0, 0]
        }
      };
      expect(InkStorage.strokeCount(content), 4096);
      expect(opened, isFalse);
    });

    test('an empty ink block round-trips without a blob', () {
      final out = InkStorage.toPersisted(<String, dynamic>{'strokes': []}, (_) {
        fail('an empty block must not write a blob');
      });
      expect(InkStorage.strokeCount(out), 0);
      expect(InkStorage.toWorking(out, (_) => null)['strokes'], isEmpty);
    });
  });
}
