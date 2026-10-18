// Smoke tests for the notebook manager.
//
// The last review made the case for why
// that is worth more than it looks: BOTH bugs that shipped in the command bar
// were layout failures — a `Spacer` under an unbounded constraint, and a `Row`
// overflowing at 560px — and neither was visible to any state test or to
// reading the code. A dialog is exactly the same shape of risk: it is built
// once, in a window size the author happened to have.
//
// So these are deliberately shallow. They mount each dialog for real, at a
// couple of window sizes, and assert it lays out and shows its own name. That
// is the whole class of bug they exist to catch.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/notebook_manager.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_dialogs_');
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Smoke');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    return app;
  }

  /// Mount a host whose button opens [open], tap it, and settle.
  Future<void> openDialog(
    WidgetTester tester,
    AppState app,
    Future<void> Function(BuildContext, AppState) open, {
    required Size window,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context, app),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // The debounced workspace write (400ms) is drained too, so a dialog that
    // touches settings doesn't leave a pending timer behind.
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  // A laptop with the navigator open, and a small window. Both are ordinary,
  // and the second is where the command bar's overflow bug lived.
  const sizes = [Size(1280, 800), Size(900, 620)];

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('the notebook manager opens and lists notebooks ($label)',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(tester);
      await openDialog(tester, app, (c, a) => showNotebookManager(c, a),
          window: size);

      expect(tester.takeException(), isNull);
      expect(find.text('Notebooks'), findsOneWidget);
      expect(find.text('Smoke'), findsWidgets,
          reason: 'the notebook is listed');
      // Every action it offers must be reachable, not clipped off the edge.
      for (final label in ['New', 'Import', 'Backup']) {
        expect(find.text(label), findsOneWidget, reason: '"$label" is missing');
      }
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search'), findsNothing);
    });

    testWidgets('notebook search filters, clears and keeps backups complete ($label)',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(tester);
      await tester.runAsync(() async {
        await app.createNotebook('Mathematik');
        await app.createNotebook('Biologie');
      });
      await openDialog(tester, app, showNotebookManager, window: size);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
          isTrue);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '  MATHE  ');
      await tester.pumpAndSettle();
      expect(find.text('Mathematik'), findsOneWidget);
      expect(find.text('Biologie'), findsNothing);
      expect(find.text('Smoke'), findsNothing);

      // Filtering the cards must not restrict the backup menu's notebooks.
      await tester.tap(find.byTooltip('Create a portable ZIP backup'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'backup menu must fit');
      expect(find.text('Biologie'), findsOneWidget);
      expect(find.text('Smoke'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'no such notebook');
      await tester.pumpAndSettle();
      expect(find.text('No notebooks found.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Mathematik'), findsOneWidget);
      expect(find.text('Biologie'), findsOneWidget);
      expect(find.text('Smoke'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Biologie');
      // Reopening starts with an empty, permanently visible search field.
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
      expect(find.text('Mathematik'), findsOneWidget);
      expect(find.text('Biologie'), findsOneWidget);
      // Closing with the field focused must dispose its controller safely.
      await tester.tap(find.byType(TextField));
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.notebooks, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('notebook colours form a 4 by 4 palette and save the choice',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await openDialog(tester, app, (c, a) => showNotebookManager(c, a),
        window: const Size(900, 620));
    await tester.tap(find.byTooltip('Notebook options'));
    await tester.pumpAndSettle();
    final palette = find.byWidgetPredicate((widget) =>
        widget is PopupMenuItem<String> && widget.value == '__palette');
    expect(find.descendant(of: palette, matching: find.byType(Tooltip)),
        findsNWidgets(16));
    expect(find.byTooltip('Red'), findsOneWidget);
    expect(find.byTooltip('White'), findsOneWidget);
    expect(find.byTooltip('Black'), findsOneWidget);
    await tester.tap(find.byTooltip('White'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(app.notebookColor(app.notebookId!), 'White');
    expect(tester.takeException(), isNull);
  });
}
