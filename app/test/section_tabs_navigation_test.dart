import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/sidebar.dart';
import 'package:openote/canvas/page_title_view.dart';

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
    final addSection = find.byTooltip('New section');
    expect(addSection, findsOneWidget);
    final gap = tester.getTopLeft(addSection).dx - tester.getTopRight(tab).dx;
    expect(gap, greaterThanOrEqualTo(0));
    expect(gap, lessThan(30),
        reason: 'the plus follows the last section instead of the window edge');
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

    // Use the same driven clock as the sidebar: the first click stays instant.
    var clock = DateTime(2026, 10, 12, 12);
    sidebarNow = () => clock;
    addTearDown(() => sidebarNow = DateTime.now);
    await tester.tap(tab);
    await tester.pump();
    clock = clock.add(const Duration(milliseconds: 80));
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(find.byType(NodeInlineRename), findsOneWidget);
    final rename = find.descendant(
        of: find.byType(NodeInlineRename), matching: find.byType(TextField));
    await tester.enterText(rename, 'Renamed section');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(app.node(section.id)?.title, 'Renamed section');
    expect(find.byType(NodeInlineRename), findsNothing);

    clock = clock.add(const Duration(seconds: 1));
    await tester.tap(find.text('Renamed section'));
    await tester.pump();
    clock = clock.add(const Duration(milliseconds: 80));
    await tester.tap(find.text('Renamed section'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Cancelled rename');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(app.node(section.id)?.title, 'Renamed section');

    app.toggleNavCollapsed();
    await tester.pumpAndSettle();
    final rail = find.byType(Sidebar);
    expect(
        find.descendant(of: rail, matching: find.byTooltip('Renamed section')),
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
    expect(find.descendant(of: header, matching: find.text('Renamed section')),
        findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('Another page')),
        findsOneWidget);
    expect(tester.getCenter(find.text('Navigation book')).dx,
        lessThan(tester.getCenter(
            find.descendant(of: header, matching: find.text('Renamed section'))).dx));
    expect(tester.getCenter(
            find.descendant(of: header, matching: find.text('Renamed section'))).dx,
        lessThan(tester.getCenter(
            find.descendant(of: header, matching: find.text('Another page'))).dx));
    expect(tester.takeException(), isNull);

    final now = DateTime.now();
    app.planner.reminders.add(
        text: 'Linked task', at: now.add(const Duration(days: 1)),
        notebookId: app.notebookId, pageId: secondPage.id);
    // Warm the planner cache before editing, so a stale cached subtitle fails.
    expect(app.planner.agenda(now: now).single.subtitle, 'Another page');
    await tester.tap(find.descendant(
        of: find.byType(PageTitleView), matching: find.text('Another page')));
    await tester.pumpAndSettle();
    final titleField = find.descendant(
        of: find.byType(PageTitleView), matching: find.byType(TextField));
    await tester.enterText(titleField, 'Live page title');
    await tester.pumpAndSettle();
    expect(app.titleEditing, isTrue);
    expect(app.navCollapsed, isTrue);
    expect(app.node(secondPage.id)?.title, 'Live page title');
    expect(find.byTooltip('Live page title'), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('Live page title')),
        findsOneWidget);
    expect(app.planner.agenda(now: now).single.subtitle, 'Live page title');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
