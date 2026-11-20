// Images, phone scans and PDF printouts share one aligned append layout.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Size;

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp() async {
    final tmp = Directory.systemTemp.createTempSync('onote_pdfpos_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Slides');
    final app = AppState(repo)..notebookId = nb.id;
    addTearDown(() {
      app.cancelPendingSave();
      app.dispose();
    });
    app.nodes = repo.loadNodes(nb.id);
    return app;
  }

  Block img(String id, double y, double h) => Block(
        id: id,
        type: BlockType.image,
        x: 60,
        y: y,
        w: 400,
        content: {'blob': 'sha256:x'},
      )..h = h;

  test('with nothing focused, slides append below the last box', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    app.blocks = [img('a', 100, 200), img('b', 400, 150)];

    final anchor = app.mediaImportPlacement();

    expect(anchor.top, greaterThanOrEqualTo(550),
        reason: 'below the bottom-most block (400 + 150)');
    expect(anchor.left, AppState.pageLeftMargin);
    expect(anchor.width, 760);
  });

  test('editing a block still appends after all existing content', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    final top = img('a', 100, 200);
    final middle = img('b', 400, 100);
    final bottom = img('c', 700, 100);
    app.blocks = [top, middle, bottom];
    app.editingBlockId = 'b';

    final anchor = app.mediaImportPlacement();

    expect(anchor.top, closeTo(700 + 100 + 36, 0.01));
    expect([top.y, middle.y, bottom.y], [100, 400, 700],
        reason: 'an import must not displace existing notes');
  });

  test('selection does not change the aligned append position', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    app.blocks = [img('a', 100, 200), img('b', 900, 100)];
    app.select('a');

    final anchor = app.mediaImportPlacement();

    expect(anchor.top, closeTo(900 + 100 + 36, 0.01));
    expect(app.blocks.map((b) => b.y), [100, 900]);
  });

  test('an empty page anchors at the top, not at some stale extent', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    app.blocks = [];

    final anchor = app.mediaImportPlacement();

    expect(anchor.top, lessThan(400),
        reason: 'an empty page must not push the first slide down the canvas');
    expect(anchor.top, AppState.contentTop + 36);
    expect(anchor.left, AppState.pageLeftMargin);
  });

  test('placement uses measured content height and the phone width limits',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    final note = Block(
        type: BlockType.text,
        x: 44,
        y: 200,
        w: 400,
        content: {'text': 'A wrapped note'});
    app.blocks = [note];
    app.renderSizes[note.id] = const Size(400, 500);
    app.pageProps.pageWidth = 2000;
    expect(app.mediaImportPlacement().top, 736);
    expect(app.mediaImportPlacement().width, 760);
    app.pageProps.pageWidth = 600;
    expect(app.mediaImportPlacement().width, 512);
    app.pageProps.pageWidth = 320;
    expect(app.mediaImportPlacement().width, 280);
  });

  test(
      'off-screen scan placement uses the paired page instead of the active page',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    app.blocks = [img('active', 10000, 200)];
    final paired =
        PageData([img('paired', 500, 200)], PageProps(pageWidth: 600));
    final placement = app.mediaImportPlacement(page: paired);
    expect(placement.top, 736);
    expect(placement.left, 44);
    expect(placement.width, 512);
  });
}
