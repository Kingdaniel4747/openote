import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/inline_section_strip.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  setUpAll(() => expect(initSqliteForTests(), isTrue));

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('left sections reorder inline with $kind and keep groups',
        (tester) async {
      late Directory directory;
      late AppState app;
      late TreeNode first, second, third, group;
      await tester.runAsync(() async {
        directory = Directory.systemTemp.createTempSync('onote_left_reorder_');
        final repo = await Repository.openAt(directory);
        final notebook = await repo.createNotebook('Reorder book');
        app = AppState(repo)
          ..notebookId = notebook.id
          ..sectionTabsAbovePage = false
          ..spellCheckEnabled = false;
        app.reloadNodes();
        first = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
        app.renameNode(first.id, 'Alpha');
        second = app.importNode(notebook.id,
            TreeNode(kind: NodeKind.section, title: 'Beta', position: 'z1'));
        third = app.importNode(notebook.id,
            TreeNode(kind: NodeKind.section, title: 'Gamma', position: 'z2'));
        group = app.importNode(
            notebook.id,
            TreeNode(
                kind: NodeKind.sectionGroup, title: 'Group', position: 'z3'));
        app.reloadNodes();
        app.activateSection(first.id);
      });
      addTearDown(() {
        app.cancelPendingSave();
        app.dispose();
        directory.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: onoteTheme(Brightness.light),
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: app,
                  builder: (context, _) =>
                      Row(children: [Sidebar(app: app)])))));
      await tester.pumpAndSettle();
      final strip = find.ancestor(
          of: find.text('Alpha'), matching: find.byType(InlineSectionStrip));
      Finder row(String title) =>
          find.descendant(of: strip, matching: find.text(title));
      final alpha = row('Alpha');
      final beta = row('Beta');
      final gamma = row('Gamma');
      if (kind == PointerDeviceKind.touch) {
        final hold = await tester.startGesture(tester.getCenter(alpha));
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.text('Rename'), findsNothing);
        await tester.pump(const Duration(milliseconds: 180));
        await hold.up();
        await tester.pumpAndSettle();
        expect(find.text('Rename'), findsOneWidget);
        await tester.tapAt(const Offset(950, 650));
        await tester.pumpAndSettle();
      }
      final before = tester.getCenter(beta);
      final start = tester.getCenter(alpha);
      final destination = tester.getCenter(gamma);
      final gesture = await tester.startGesture(start, kind: kind);
      await gesture.moveTo(start + const Offset(0, 22));
      await tester.pump();
      await gesture.moveTo(destination);
      await tester.pump();
      expect(tester.getCenter(alpha).dy, closeTo(destination.dy, .01));
      expect(tester.getCenter(alpha).dx, closeTo(start.dx, .01));
      expect(app.nodes.where((n) => n.kind == NodeKind.section).first.id,
          first.id);
      expect(
          find.descendant(of: strip, matching: find.byType(Draggable<String>)),
          findsNothing);
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getCenter(beta).dy, lessThan(before.dy));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          app.nodes
              .where((n) => n.kind == NodeKind.section && n.parentId == null)
              .map((n) => n.id),
          [second.id, third.id, first.id]);

      // The first ungrouped slot must be reachable without leaving the list.
      final toFirst =
          await tester.startGesture(tester.getCenter(alpha), kind: kind);
      await toFirst.moveTo(tester.getCenter(beta));
      await tester.pump();
      await toFirst.up();
      await tester.pumpAndSettle();
      expect(
          app.nodes
              .where((n) => n.kind == NodeKind.section && n.parentId == null)
              .map((n) => n.id),
          [first.id, second.id, third.id]);
      expect(tester.getCenter(alpha).dy, lessThan(tester.getCenter(beta).dy));

      // Dropping immediately after an empty/collapsed group header moves into it.
      final into =
          await tester.startGesture(tester.getCenter(alpha), kind: kind);
      await into.moveTo(tester.getCenter(row('Group')) + const Offset(0, 12));
      await tester.pump();
      await into.up();
      await tester.pumpAndSettle();
      expect(app.node(first.id)!.parentId, group.id);
      // Drag down past the group boundary to return to ungrouped sections.
      final out =
          await tester.startGesture(tester.getCenter(alpha), kind: kind);
      await out.moveTo(tester.getCenter(row('Gamma')) + const Offset(0, 20));
      await tester.pump();
      await out.up();
      await tester.pumpAndSettle();
      expect(app.node(first.id)!.parentId, isNull);
      // Touch menus and double-click rename still use the existing row actions.
      await tester.longPress(alpha);
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsOneWidget);
      await tester.tapAt(const Offset(900, 650));
      await tester.pumpAndSettle();
      var clock = DateTime(2026, 11, 20, 12);
      sidebarNow = () => clock;
      addTearDown(() => sidebarNow = DateTime.now);
      await tester.tap(alpha);
      await tester.pump();
      clock = clock.add(const Duration(milliseconds: 80));
      await tester.tap(alpha);
      await tester.pumpAndSettle();
      final rename =
          find.descendant(of: strip, matching: find.byType(NodeInlineRename));
      expect(rename, findsOneWidget);
      await tester.enterText(
          find.descendant(of: rename, matching: find.byType(TextField)),
          'Renamed Alpha');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(app.node(first.id)!.title, 'Renamed Alpha');
      if (kind == PointerDeviceKind.touch) {
        app.toggleNavCollapsed();
        app.cancelPendingSave();
        await tester.pumpAndSettle();
        final icon = find.byTooltip('Renamed Alpha');
        final hold = await tester.startGesture(tester.getCenter(icon));
        await tester.pump(const Duration(milliseconds: 650));
        await hold.up();
        await tester.pumpAndSettle();
        expect(find.text('Rename'), findsOneWidget);
        expect(app.navCollapsed, isTrue);
        await tester.tapAt(const Offset(950, 650));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      app.cancelPendingSave();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      app.cancelPendingSave();
    });
  }
}
