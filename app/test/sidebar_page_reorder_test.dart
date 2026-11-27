import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  setUpAll(() => expect(initSqliteForTests(), isTrue));
  for (final (kind, compact) in [
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch])
      for (final compact in [false, true]) (kind, compact),
  ]) {
    testWidgets(
        'pages move inline with descendants using $kind (compact: $compact)',
        (tester) async {
      late Directory directory;
      late AppState app;
      late TreeNode a,
          child,
          grandchild,
          child2,
          b,
          c,
          section,
          other,
          existing;
      await tester.runAsync(() async {
        directory = Directory.systemTemp.createTempSync('onote_page_reorder_');
        final repo = await Repository.openAt(directory);
        final notebook = await repo.createNotebook('Pages');
        app = AppState(repo)
          ..notebookId = notebook.id
          ..sectionTabsAbovePage = compact
          ..navCollapsed = compact
          ..spellCheckEnabled = false;
        app.reloadNodes();
        section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
        app.renameNode(section.id, 'Original section');
        a = app.pagesOf(section.id).first;
        app.renameNode(a.id, 'Parent A');
        TreeNode add(String title, String position, int level) =>
            app.importNode(
                notebook.id,
                TreeNode(
                    kind: NodeKind.page,
                    parentId: section.id,
                    title: title,
                    position: position)
                  ..level = level);
        child = add('Child A1', '${a.position}b', 1);
        grandchild = add('Grandchild', '${a.position}c', 2);
        child2 = add('Child A2', '${a.position}d', 1);
        b = add('Page B', 'z1', 0);
        c = add('Page C', 'z2', 0);
        other = app.importNode(
            notebook.id,
            TreeNode(
                kind: NodeKind.section,
                title: 'Other section',
                position: 'z3'));
        existing = app.importNode(
            notebook.id,
            TreeNode(
                kind: NodeKind.page,
                parentId: other.id,
                title: 'Existing destination page',
                position: 'z9'));
        app.reloadNodes();
        await app.selectPage(a.id);
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
      final sidebar = find.byType(Sidebar);
      Finder row(String title) => find.descendant(
          of: sidebar,
          matching: compact
              ? find.descendant(
                  of: find.byTooltip(title), matching: find.byType(Icon))
              : find.text(title));
      final parent = row('Parent A');
      if (kind == PointerDeviceKind.touch) {
        final hold = await tester.startGesture(tester.getCenter(parent));
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.text('Rename'), findsNothing);
        await tester.pump(const Duration(milliseconds: 180));
        await hold.up();
        await tester.pumpAndSettle();
        expect(find.text('Rename'), findsOneWidget);
        await tester.tapAt(const Offset(950, 650));
        await tester.pumpAndSettle();
      }
      final start = tester.getCenter(parent);
      final childStart = tester.getCenter(row('Child A1'));
      final destination = tester.getCenter(row('Page C'));
      final drag = await tester.startGesture(start, kind: kind);
      await drag.moveTo(start + const Offset(0, 24));
      await tester.pump();
      await drag.moveTo(destination);
      await tester.pump();
      expect(tester.getCenter(parent).dy, closeTo(destination.dy, .01));
      expect(tester.getCenter(row('Child A1')).dy - childStart.dy,
          closeTo(destination.dy - start.dy, .01));
      expect(app.pagesOf(section.id).first.id, a.id);
      final pageDrag = tester.widget<Draggable<String>>(find
          .ancestor(of: parent, matching: find.byType(Draggable<String>))
          .first);
      expect(pageDrag.feedback, isA<SizedBox>());
      final bBefore = tester.getCenter(row('Page B')).dy;
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getCenter(row('Page B')).dy, lessThan(bBefore));
      await drag.up();
      await tester.pumpAndSettle();
      expect(app.pagesOf(section.id).map((p) => p.id),
          [b.id, c.id, a.id, child.id, grandchild.id, child2.id]);
      expect(
          [app.node(child.id)!.level, app.node(grandchild.id)!.level], [1, 2]);
      expect(app.pageId, a.id);

      // Return the entire branch to the very first slot.
      final toFirst =
          await tester.startGesture(tester.getCenter(parent), kind: kind);
      await toFirst.moveTo(tester.getCenter(row('Page B')));
      await tester.pump();
      await toFirst.up();
      await tester.pumpAndSettle();
      expect(app.pagesOf(section.id).map((p) => p.id),
          [a.id, child.id, grandchild.id, child2.id, b.id, c.id]);
      // A subpage moves independently; its parent and sibling's child stay put.
      final childDrag = await tester
          .startGesture(tester.getCenter(row('Child A2')), kind: kind);
      await childDrag.moveTo(tester.getCenter(row('Child A1')));
      await tester.pump();
      await childDrag.up();
      await tester.pumpAndSettle();
      expect(app.pagesOf(section.id).map((p) => p.id),
          [a.id, child2.id, child.id, grandchild.id, b.id, c.id]);
      expect(app.node(child2.id)!.level, 1);

      // Holding B over C previews nesting after exactly 500 milliseconds. The
      // document changes only on release, even when its sort slot is unchanged.
      final bLeft = tester.getTopLeft(row('Page B')).dx;
      final nest = await tester.startGesture(tester.getCenter(row('Page B')),
          kind: kind);
      await nest.moveTo(tester.getCenter(row('Page C')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(tester.getTopLeft(row('Page B')).dx, closeTo(bLeft, .01));
      expect(app.node(b.id)!.level, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.getTopLeft(row('Page B')).dx,
          closeTo(bLeft + (compact ? 3 : 15), .01));
      expect(app.node(b.id)!.level, 0);
      await nest.up();
      await tester.pumpAndSettle();
      expect(app.pagesOf(section.id).map((p) => p.id),
          [a.id, child2.id, child.id, grandchild.id, c.id, b.id]);
      expect(app.node(b.id)!.level, 1);

      // An activated preview can still be cancelled without changing the tree.
      final cancelNest = await tester
          .startGesture(tester.getCenter(row('Page B')), kind: kind);
      await cancelNest.moveTo(tester.getCenter(row('Child A2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await cancelNest.cancel();
      await tester.pumpAndSettle();
      expect(app.node(b.id)!.level, 1);
      expect(app.pagesOf(section.id).map((p) => p.id),
          [a.id, child2.id, child.id, grandchild.id, c.id, b.id]);

      // Collapse stays available and hidden descendants still move with A.
      app.togglePageCollapsed(a.id);
      await tester.pumpAndSettle();
      expect(row('Child A1'), findsNothing);
      if (compact) {
        final moveHidden =
            await tester.startGesture(tester.getCenter(parent), kind: kind);
        await moveHidden.moveTo(tester.getCenter(row('Page C')));
        await tester.pump();
        await moveHidden.up();
        await tester.pumpAndSettle();
        expect(app.pagesOf(section.id).map((p) => p.id),
            [c.id, b.id, a.id, child2.id, child.id, grandchild.id]);
        app.toggleNavCollapsed();
        await tester.pumpAndSettle();
        expect(find.text('Parent A'), findsOneWidget);
        expect(find.text('Child A1'), findsNothing);
      } else {
        final crossSection =
            await tester.startGesture(tester.getCenter(parent), kind: kind);
        await crossSection.moveTo(tester.getCenter(row('Other section')));
        await tester.pump();
        await crossSection.up();
        await tester.pumpAndSettle();
        expect(app.pagesOf(other.id).map((p) => p.id),
            [existing.id, a.id, child2.id, child.id, grandchild.id]);
        expect(app.pagesOf(section.id).map((p) => p.id), [c.id, b.id]);
      }
      expect(app.node(grandchild.id)!.level, 2);
      expect(tester.takeException(), isNull);
      app.cancelPendingSave();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      app.cancelPendingSave();
    });
  }
}
