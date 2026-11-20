// The command bar's own trailing cluster compacts, instead of scrolling
// (UI consistency pass, 2026-09-01).
//
// Reported: "it doesnt handle resizing well (menus should either compact as
// required or become sliding, again i belive the former is cleaner)." The
// generic mechanics are covered by compacting_toolbar_test.dart; these are
// the tests that would have caught the WIRING into the real command bar
// specifically being wrong — the right controls folding, the folded ones
// still doing the same thing, and nothing else on the row moving.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/learning_access_dialog.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_cmdbar_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester tester, Size size,
      {bool titlebarOnly = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => CommandBar(app: app, titlebarOnly: titlebarOnly),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('removed app launchers stay absent with legacy settings enabled',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    repo.setSetting('ankiShortcutEnabled', true);
    repo.setSetting('browserShortcutEnabled', true);
    repo.setSetting('ankiExecutablePath', 'legacy-anki.exe');
    for (final titlebarOnly in [false, true]) {
      for (final width in [2600.0, 600.0]) {
        await pump(tester, Size(width, 1200), titlebarOnly: titlebarOnly);
        expect(find.byTooltip('Open default browser'), findsNothing);
        expect(find.byTooltip('Open Anki'), findsNothing);
        expect(find.byIcon(Icons.open_in_browser_outlined), findsNothing);
        expect(find.byTooltip('Settings…'), findsOneWidget);
      }
    }
    expect(find.byTooltip('Recherche und YouTube'), findsNothing);
    await tester.tap(find.byTooltip('Settings…'));
    await tester.pumpAndSettle();
    expect(find.text('Show Anki shortcut'), findsNothing);
    expect(find.text('Show browser shortcut'), findsNothing);
    expect(find.text('Change Anki app'), findsNothing);
    expect(find.text('Integrations'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('MCP settings are only available through the AI button',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(2600, 1200));
    await tester.tap(find.byTooltip('Settings…'));
    await tester.pumpAndSettle();
    expect(find.byType(LearningAccessPanel), findsNothing);
    expect(find.text('AI learning access'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI: off'));
    await tester.pumpAndSettle();
    expect(find.byType(LearningAccessPanel), findsOneWidget);
    final popover =
        tester.getRect(find.byKey(const ValueKey('learning-access-popover')));
    expect(popover.width, 360);
    expect(popover.right, greaterThan(2500));
    expect(popover.top, lessThan(120));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(LearningAccessPanel), findsNothing);
  });

  testWidgets('a wide window shows every trailing control inline, no fold',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(2600, 1200));
    // The planner's task count is a badge; its calendar icon stays visible.
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget,
        reason: 'Planner');
    for (final tip in const [
      'AI: off',
      'Find on page  (Ctrl+F)',
      'Settings…',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(find.byTooltip('Export page…'), findsNothing);
    expect(find.byIcon(Icons.ios_share_outlined), findsNothing);
    expect(find.byTooltip('More'), findsNothing,
        reason:
            'the compact utility cluster does not need a menu at full width');
    app.cancelPendingSave();
  });

  testWidgets('planner badge counts unfinished homework on every page',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(2600, 1200));

    app.planner.reminders.add(
      text: 'Finish worksheet',
      at: DateTime.now().add(const Duration(days: 10)),
      notebookId: app.notebookId,
      pageId: app.pageId,
    );
    await tester.pumpAndSettle();

    expect(
        find.byTooltip('Hausaufgaben, To-dos und Klausuren'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    app.planner.dispose();
    app.cancelPendingSave();
  });

  testWidgets('a narrow window keeps Find inline after export moves to pages',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(700, 900));
    expect(find.byTooltip('More'), findsNothing);
    expect(find.byTooltip('Find on page  (Ctrl+F)'), findsOneWidget);
    expect(find.byTooltip('Export page…'), findsNothing);
    await tester.tap(find.byTooltip('Find on page  (Ctrl+F)'));
    await tester.pumpAndSettle();
    expect(app.findOpen, isTrue);
    expect(tester.takeException(), isNull);
    app.cancelPendingSave();
  });

  testWidgets('Settings remains reachable in a narrow window', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(700, 900));
    await tester.tap(find.byTooltip('Settings…'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Settings')),
        findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'folding the trailing cluster leaves the tabs and Home row '
      'exactly where they were', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(2600, 1200));
    final wideTabLeft = tester.getTopLeft(find.text('Home')).dx;

    await pump(tester, const Size(700, 900));
    final narrowTabLeft = tester.getTopLeft(find.text('Home')).dx;

    expect(narrowTabLeft, wideTabLeft,
        reason: 'folding the trailing cluster must not shove the tabs, '
            'which sit at the OPPOSITE end of the same row');
    app.cancelPendingSave();
  });
}
