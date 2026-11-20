import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/api/scanner_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/insert_catalog.dart';

import 'support/sqlite.dart';

void main() {
  setUpAll(() => expect(initSqliteForTests(), isTrue));
  testWidgets(
      'picked images continue the phone scan stack instead of centering',
      (tester) async {
    late Directory directory;
    late AppState app;
    late Block scan;
    late String firstPath, secondPath;
    await tester.runAsync(() async {
      directory = Directory.systemTemp.createTempSync('onote_media_layout_');
      final repo = await Repository.openAt(directory);
      final notebook = await repo.createNotebook('Media');
      app = AppState(repo)
        ..notebookId = notebook.id
        ..snapToGrid = false
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      app.addBlock(Block(
          type: BlockType.text,
          x: 150,
          y: 400,
          w: 300,
          h: 200,
          content: {'text': 'Existing notes'}));
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
      scan = await importPhoneScan(app,
          notebookId: notebook.id,
          pageId: app.pageId!,
          bytes: png,
          mime: 'image/png');
      firstPath = '${directory.path}/first.png';
      secondPath = '${directory.path}/second.png';
      File(firstPath).writeAsBytesSync(png);
      File(secondPath).writeAsBytesSync(png);
    });
    addTearDown(() {
      app.cancelPendingSave();
      app.dispose();
      directory.deleteSync(recursive: true);
    });
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'openFile');
      return [secondPath, '${directory.path}/missing.png', firstPath];
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('Import'))));
    app.select(app.blocks.first.id);
    final context = tester.element(find.text('Import'));
    await tester.runAsync(
        () => insertPickedImage(context, app, const Offset(9000, 9000)));
    await tester.pump();
    final images = app.blocks.where((b) => b.type == BlockType.image).toList();
    expect(images, hasLength(3));
    expect(scan.y, 636);
    for (var i = 1; i < images.length; i++) {
      expect(images[i].x, scan.x);
      expect(images[i].w, scan.w);
      expect(images[i].h, scan.h);
      expect(
          images[i].y, closeTo(images[i - 1].y + images[i - 1].h! + 36, .01));
    }
    expect(app.blocks.first.y, 400);
    expect(app.blocks.first.h, 200);
    app.cancelPendingSave();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
