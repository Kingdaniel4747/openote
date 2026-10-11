import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  setUpAll(() => expect(initSqliteForTests(), isTrue));

  testWidgets('section tabs have menus and the collapsed rail switches pages',
      (tester) async {
    late Directory directory;
    late Repository repo;
    late AppState app;
    late TreeNode section;
    late TreeNode secondPage;
    await tester.runAsync(() async {
      directory = Directory.systemTemp.createTempSync('onote_tabs_nav_');
      repo = await Repository.openAt(directory);
      final notebook = await repo.createNotebook('Navigation book');
      app = AppState(repo)
        ..notebookId = notebook.id
        ..spellCheckEnabled = false
        ..sectionTabsAbovePage = true;
      app.reloadNodes();
      section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      app.renameNode(section.id, 'Navigation section');
      secondPage = app.importNode(
          notebook.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: 'Another page',
              position: 'z'));
      app.reloadNodes();
      await app.selectPage(
          app.pagesOf(section.id).firstWhere((p) => p.id != secondPage.id).id);
    });
    addTearDown(() async {
      app.cancelPendingSave();
      app.dispose();
      await repo.flushWorkspace();
      repo.dispose();
      await directory.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await tester.pumpAndSettle();

    // Both desktop and touch open the same structural actions as sidebar rows.
    final tab = find.text('Navigation section');
    final mouse = await tester.startGesture(tester.getCenter(tab),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tapAt(const Offset(1350, 850));
    await tester.pumpAndSettle();
    await tester.longPress(tab);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    await tester.tapAt(const Offset(1350, 850));
    await tester.pumpAndSettle();

    app.toggleNavCollapsed();
    await tester.pumpAndSettle();
    final rail = find.byType(Sidebar);
    expect(
        find.descendant(of: rail, matching: find.byTooltip('Navigation section')),
        findsNothing);
    expect(
        find.descendant(of: rail, matching: find.byIcon(Icons.description_outlined)),
        findsNWidgets(app.pagesOf(section.id).length));
    final pageButton =
        find.descendant(of: rail, matching: find.byTooltip('Another page'));
    await tester.tap(pageButton);
    await tester.pumpAndSettle();
    expect(app.pageId, secondPage.id);
    expect(app.navCollapsed, isTrue);

    // The breadcrumb contains the complete path in order.
    final header = find.ancestor(
        of: find.text('Navigation book'), matching: find.byType(Row)).first;
    expect(find.descendant(of: header, matching: find.text('Navigation section')),
        findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('Another page')),
        findsOneWidget);
    expect(tester.getCenter(find.text('Navigation book')).dx,
        lessThan(tester.getCenter(
            find.descendant(of: header, matching: find.text('Navigation section'))).dx));
    expect(tester.getCenter(
            find.descendant(of: header, matching: find.text('Navigation section'))).dx,
        lessThan(tester.getCenter(
            find.descendant(of: header, matching: find.text('Another page'))).dx));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
