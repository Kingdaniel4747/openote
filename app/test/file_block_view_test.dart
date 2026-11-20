import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/editor/file_block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  setUpAll(() => expect(initSqliteForTests(), isTrue));
  for (final linked in [true, false]) {
    testWidgets(
        'ordinary attachment saves its original bytes (linked: $linked)',
        (tester) async {
      late Directory directory;
      late AppState app;
      late Block block;
      const original = '<mxfile><diagram>original content</diagram></mxfile>';
      await tester.runAsync(() async {
        directory = Directory.systemTemp.createTempSync('onote_file_card_');
        final repo = await Repository.openAt(directory);
        final notebook = await repo.createNotebook('Files');
        app = AppState(repo)
          ..notebookId = notebook.id
          ..spellCheckEnabled = false;
        final source = File('${directory.path}/legacy.drawio')
          ..writeAsStringSync(original);
        block = Block(
            type: BlockType.file,
            x: 44,
            y: 100,
            w: 500,
            h: 110,
            content: linked
                ? {
                    'kind': 'drawio',
                    'path': source.path,
                    'name': 'legacy.drawio',
                    'extra': {'preserve': true},
                  }
                : {
                    'blob':
                        'sha256:${app.addBlob(utf8.encode(original), 'application/octet-stream')}',
                    'name': 'attachment.xml',
                  });
      });
      addTearDown(() {
        app.cancelPendingSave();
        app.dispose();
        directory.deleteSync(recursive: true);
      });
      final before = jsonEncode(block.toJson());
      final output = '${directory.path}/saved-copy.xml';
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        expect(call.method, 'getSavePath');
        return output;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 500,
                  height: 110,
                  child: FileBlockView(block: block, app: app)))));
      expect(find.text(linked ? 'legacy.drawio' : 'attachment.xml'),
          findsOneWidget);
      expect(find.byTooltip('Open with the default app'), findsOneWidget);
      expect(find.byTooltip('Open in draw.io'), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.tap(find.byTooltip('Save a copy…'));
      await tester.pump();
      for (var i = 0;
          find.text('Saved to $output').evaluate().isEmpty && i < 50;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(find.text('Saved to $output'), findsOneWidget);
      expect(File(output).readAsStringSync(), original);
      expect(jsonEncode(block.toJson()), before,
          reason:
              'unsupported metadata and the original reference survive unchanged');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
