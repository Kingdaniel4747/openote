import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  setUpAll(() => expect(initSqliteForTests(), isTrue));
  Future<void> flushWorkspace(WidgetTester tester, Repository repo) async {
    var flushed = false;
    repo.flushWorkspace().then((_) => flushed = true);
    for (var i = 0; !flushed && i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(flushed, isTrue);
  }

  for (final isGroup in [false, true]) {
    testWidgets(
        'section/group menu keeps colours without removed actions (group: $isGroup)',
        (tester) async {
      late Directory directory;
      late AppState app;
      late Repository repo;
      late TreeNode section;
      final exam = DateTime(2026, 12, 12);
      await tester.runAsync(() async {
        directory = Directory.systemTemp.createTempSync('onote_section_menu_');
        repo = await Repository.openAt(directory);
        final nb = await repo.createNotebook('Section menu');
        app = AppState(repo)
          ..notebookId = nb.id
          ..spellCheckEnabled = false;
        app.reloadNodes();
        if (isGroup) app.addSectionGroup();
        section = app.nodes.firstWhere((n) =>
            n.kind == (isGroup ? NodeKind.sectionGroup : NodeKind.section));
        app.study.setExamDate(section.id, exam);
      });
      addTearDown(() {
        app.cancelPendingSave();
        app.dispose();
        directory.deleteSync(recursive: true);
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showNodeMenu(context, app, section,
                          canIndent: false, position: const Offset(100, 100)),
                      child: const Text('Open section menu'))))));
      await tester.tap(find.text('Open section menu'));
      await tester.pumpAndSettle();
      for (final label in [
        'Move up',
        'Move down',
        'Colour',
        'Color',
        'New page',
        'Sort pages A→Z',
        'Sort pages by last edited',
        'Export section as PDF…',
        'Print section…',
        'Set exam date…',
        'Remove exam date'
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.textContaining('Exam '), findsNothing);
      for (final label in ['Rename', 'Lock with a passcode…', 'Delete']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
          find.text('Move to group…'), isGroup ? findsNothing : findsOneWidget);
      expect(find.byTooltip('blue'), findsOneWidget);
      await tester.tap(find.byTooltip('blue'));
      await tester.pumpAndSettle();
      expect(app.node(section.id)!.color, 'blue');
      expect(app.study.examDate(section.id), exam);
      expect(find.text('Move to group…'), findsNothing);
      expect(tester.takeException(), isNull);
      await flushWorkspace(tester, repo);
      app.cancelPendingSave();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final rightEdge in [false, true]) {
    testWidgets(
        'page export submenu opens to the available side (right edge: $rightEdge)',
        (tester) async {
      late Directory directory;
      late AppState app;
      late Repository repo;
      late TreeNode page;
      await tester.runAsync(() async {
        directory = Directory.systemTemp.createTempSync('onote_page_menu_');
        repo = await Repository.openAt(directory);
        final nb = await repo.createNotebook('Menus');
        app = AppState(repo)
          ..notebookId = nb.id
          ..spellCheckEnabled = false;
        app.reloadNodes();
        final initial = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
        await app.selectPage(initial.id);
        page = app.importNode(
            nb.id,
            TreeNode(
                kind: NodeKind.page,
                parentId: initial.parentId,
                title: 'Export this page',
                position: 'z1'));
        app.importPage(
            nb.id,
            page.id,
            [
              Block(
                  type: BlockType.text,
                  x: 44,
                  y: 100,
                  content: {'text': 'Content of the right-clicked page'})
            ],
            PageProps());
        app.reloadNodes();
        repo.setSetting('favourites', ['${nb.id}:${page.id}']);
      });
      addTearDown(() async {
        app.cancelPendingSave();
        app.dispose();
        repo.dispose();
        for (var attempt = 0;; attempt++) {
          try {
            directory.deleteSync(recursive: true);
            break;
          } on FileSystemException {
            if (attempt == 9) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      });
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final position = Offset(rightEdge ? 980 : 20, 200);
      Future<void>? menuWork;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () {
                        menuWork = showNodeMenu(context, app, page,
                            canIndent: true, position: position);
                      },
                      child: const Text('Open page menu'))))));
      await tester.tap(find.text('Open page menu'));
      await tester.pumpAndSettle();
      for (final removed in [
        'Move up',
        'Move down',
        'Add to favourites',
        'Remove from favourites',
        'Share as PDF…',
        'Print…'
      ]) {
        expect(find.text(removed), findsNothing);
      }
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      final export = find.widgetWithText(SubmenuButton, 'Export');
      expect(export, findsOneWidget);
      final parentBounds = tester.getRect(export);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(500, 50));
      if (rightEdge) {
        await tester.tap(export);
      } else {
        await mouse.moveTo(tester.getCenter(export));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      final markdown = find.widgetWithText(MenuItemButton, 'Markdown (.md)');
      expect(markdown, findsOneWidget);
      for (final label in [
        'PDF (.pdf)',
        'PDF — picture of the page',
        'For Obsidian Canvas (.canvas)',
        'Just the drawing (.inkml)',
        'Save the whole notebook as folders and files…'
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final childBounds = tester.getRect(markdown);
      if (rightEdge) {
        expect(childBounds.right, lessThanOrEqualTo(parentBounds.left + 1));
      } else {
        expect(childBounds.left, greaterThanOrEqualTo(parentBounds.right - 1));
      }
      expect(childBounds.left, greaterThanOrEqualTo(0));
      expect(childBounds.right, lessThanOrEqualTo(1000));
      // Clicking an export must use the clicked page rather than the active one.
      final out = '${directory.path}/export.md';
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        expect(call.method, 'getSavePath');
        expect((call.arguments as Map)['suggestedName'], 'Export this page.md');
        return out;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.tap(markdown);
      await tester.pumpAndSettle();
      var finished = false;
      menuWork!.then((_) => finished = true);
      for (var i = 0; !finished && i < 50; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(finished, isTrue, reason: 'the export has completed writing');
      await tester.pumpAndSettle();
      expect(File(out).readAsStringSync(),
          contains('Content of the right-clicked page'));
      expect(find.text('Export'), findsNothing);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await flushWorkspace(tester, repo);
      app.cancelPendingSave();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
