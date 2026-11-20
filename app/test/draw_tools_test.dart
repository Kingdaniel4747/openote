// Picking a pen must actually pick the pen.
//
// Reported: "I am at the moment unable to select the pen or anything in the
// menu." Ink is the reason half the users are here, so the tool buttons are
// worth pinning at the widget level rather than trusting that a state method
// with no branches must work.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_draw_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Draw');
      app = AppState(repo)..notebookId = nb.id;
      app.nodes = repo.loadNodes(nb.id);
    });
    return app;
  }

  /// The bar at a realistic desktop width, inside a Listenable rebuild exactly
  /// as `AppShell` mounts it — the rebuild is the part that could plausibly
  /// throw the tab selection away.
  Widget host(AppState app, {double width = 1280}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, __) => Column(children: [CommandBar(app: app)]),
            ),
          ),
        ),
      );

  testWidgets('the Draw tab selects each ink tool', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));

    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Text  (T)'), findsNothing);
    expect(find.byTooltip('Select / move  (V)'), findsOneWidget);

    for (final (tip, want) in const [
      ('Pen  (P)', Tool.pen),
      ('Ballpoint — constant width', Tool.ballpoint),
      ('Highlighter  (H)', Tool.highlighter),
      ('Eraser  (E)', Tool.eraser),
      ('Lasso-select ink', Tool.lasso),
    ]) {
      await tester.tap(find.byTooltip(tip));
      await tester.pumpAndSettle();
      expect(app.tool, want, reason: 'tapping "$tip" must select $want');
    }
  });

  testWidgets('the Draw tab survives the rebuild its own tap causes',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));

    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pen  (P)'));
    await tester.pumpAndSettle();

    // Selecting a tool calls notifyListeners, which rebuilds the whole shell.
    // If the bar's tab index were lost in that rebuild the user would be
    // bounced back to Home and it would look exactly like "the pen won't
    // select" — so assert the Draw row is still on screen.
    expect(find.byTooltip('Pen  (P)'), findsOneWidget,
        reason: 'the Draw row must still be showing after picking a tool');
    expect(app.tool, Tool.pen);
  });

  testWidgets('ink size slider selects five fixed widths per tool',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pen  (P)'));
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('ink-size'));
    for (final (index, width) in [0.5, 1.5, 2.5, 6.0, 10.0].indexed) {
      final slider = tester.widget<Slider>(finder);
      expect(slider.divisions, 4);
      slider.onChanged!(index.toDouble());
      await tester.pump();
      expect(app.penSize, width);
    }
    app.setTool(Tool.highlighter);
    await tester.pump();
    expect(app.penSize, 6);
    app.setTool(Tool.pen);
    await tester.pump();
    expect(app.penSize, 10);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets('eraser size slider selects five fixed widths', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eraser  (E)'));
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('eraser-size'));
    final mode = find.byKey(const ValueKey('eraser-mode'));
    expect(tester.getCenter(mode).dx, lessThan(tester.getCenter(finder).dx));
    await tester.tap(mode);
    await tester.pumpAndSettle();
    expect(app.eraserMode, EraserMode.stroke);
    await tester.tap(find.text('Area'));
    await tester.pumpAndSettle();
    expect(app.eraserMode, EraserMode.area);
    for (final (index, width) in [4.0, 12.0, 24.0, 48.0, 80.0].indexed) {
      final slider = tester.widget<Slider>(finder);
      expect(slider.divisions, 4);
      slider.onChanged!(index.toDouble());
      await tester.pump();
      expect(app.eraserSize, width);
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets('the tab row stays usable on a narrow window', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    // A laptop with the navigator open leaves the bar well under 900px. The
    // command row scrolls; the TAB row must not overflow, because an
    // overflowing child is clipped and clipped pixels do not hit-test — the
    // tabs would silently stop responding.
    await tester.pumpWidget(host(app, width: 560));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'a narrow command bar must not overflow');

    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pen  (P)'));
    await tester.pumpAndSettle();
    expect(app.tool, Tool.pen);
  });
}
