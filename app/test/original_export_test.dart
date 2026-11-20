import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/original_download.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/selection_toolbar.dart';

import 'support/sqlite.dart';

void main() {
  setUpAll(() => expect(initSqliteForTests(), isTrue));

  test(
      'PDF originals deduplicate independently of preview, page and block type',
      () {
    final slides = [
      for (var i = 0; i < 6; i++)
        Block(type: BlockType.image, x: 0, y: 0, content: {
          'pdf': 'sha256:first',
          'blob': 'preview$i',
          'page': i,
        })
    ];
    final other = Block(
        type: BlockType.image,
        x: 0,
        y: 0,
        content: {'pdf': 'sha256:second', 'blob': 'preview0'});
    final sameAttachment = Block(
        type: BlockType.file,
        x: 0,
        y: 0,
        content: {'blob': 'first', 'name': 'same.pdf'});
    expect(uniqueOriginals([...slides, other, sameAttachment]),
        [slides.first, other]);
  });

  for (final multiple in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
          'save originals chooses destination and writes sources once (multiple: $multiple, cancel: $cancel)',
          (tester) async {
        late Directory directory;
        late AppState app;
        late Block first;
        final pdf = Uint8List.fromList([37, 80, 68, 70, 1, 2, 3]);
        final second = Uint8List.fromList([37, 80, 68, 70, 4, 5, 6]);
        await tester.runAsync(() async {
          directory = Directory.systemTemp.createTempSync('openote_originals_');
          final repo = await Repository.openAt(directory);
          final nb = await repo.createNotebook('Originals');
          app = AppState(repo)..notebookId = nb.id;
          final source = 'sha256:${app.addBlob(pdf, 'application/pdf')}';
          for (var i = 0; i < 6; i++) {
            final block = Block(
                type: BlockType.image,
                x: 0,
                y: 100.0 * i,
                content: {'pdf': source, 'blob': 'preview$i', 'page': i});
            app.blocks.add(block);
            if (i == 0) first = block;
          }
          if (multiple) {
            app.blocks.add(Block(type: BlockType.image, x: 0, y: 700, content: {
              'pdf': 'sha256:${app.addBlob(second, 'application/pdf')}',
              'page': 0
            }));
          }
          app.selectedIds.addAll(app.blocks.map((b) => b.id));
        });
        addTearDown(() {
          app.cancelPendingSave();
          app.dispose();
          directory.deleteSync(recursive: true);
        });
        final output = Directory('${directory.path}/export')..createSync();
        final calls = <String>[];
        const channel = MethodChannel('plugins.flutter.io/file_selector');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          calls.add(call.method);
          expect(call.method, multiple ? 'getDirectoryPath' : 'getSavePath');
          if (cancel) return null;
          return multiple ? output.path : '${output.path}/chosen.pdf';
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));
        var finished = false;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Builder(
          builder: (context) => TextButton(
              onPressed: () async {
                await SelectionToolbar.saveOriginal(context, app, first);
                finished = true;
              },
              child: const Text('Save')),
        ))));
        await tester.tap(find.text('Save'));
        for (var i = 0; !finished && i < 100; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(finished, isTrue);
        expect(calls, hasLength(1));
        final files = output.listSync().whereType<File>().toList();
        expect(
            files,
            hasLength(cancel
                ? 0
                : multiple
                    ? 2
                    : 1));
        if (!cancel) {
          final bytes = files.map((f) => f.readAsBytesSync().toList()).toList();
          expect(bytes, contains(orderedEquals(pdf)));
          if (multiple) expect(bytes, contains(orderedEquals(second)));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
