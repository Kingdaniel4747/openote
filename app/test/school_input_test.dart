import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/block_view.dart';
import 'package:openote/canvas/ink_painter.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/windows_window_frame.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => expect(initSqliteForTests(), true));
  late Directory dir;
  late Repository repo;
  late AppState app;
  final boundaryKey = GlobalKey();

  setUp(() async {
    AppState.syncLogEnabled = false;
    dir = Directory.systemTemp.createTempSync('openote-school-input-');
    repo = await Repository.openAt(dir);
    final nb = await repo.createNotebook('School');
    app = AppState(repo)
      ..notebookId = nb.id
      ..tool = Tool.pen
      ..penSize = 10
      ..penColor = 2
      ..spellCheckEnabled = false
      ..penProximitySwitch = false
      ..snapToGrid = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
  });
  tearDown(() {
    app.cancelPendingSave();
    app.dispose();
    repo.dispose();
    dir.deleteSync(recursive: true);
    AppState.syncLogEnabled = true;
  });

  Future<void> mount(WidgetTester t,
      {bool dark = false,
      bool ribbon = false,
      WindowsWindowController? window,
      double width = 1200}) async {
    t.view.physicalSize = Size(width, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      builder: window == null
          ? null
          : (context, child) => WindowsWindowFrame(
              controller: window, startFullscreen: false, child: child!),
      home: Scaffold(
          body: ListenableBuilder(
              listenable: app,
              builder: (_, __) => Column(children: [
                    if (ribbon) CommandBar(app: app),
                    Expanded(
                        child: RepaintBoundary(
                            key: boundaryKey, child: PageCanvas(state: app))),
                  ]))),
    ));
    await t.pump();
    app.canvas.jumpTo(1, Offset.zero);
    await t.pump();
  }

  Offset at(WidgetTester t, Offset page) =>
      t.getTopLeft(find.byType(PageCanvas)) + page;
  Future<void> draw(WidgetTester t, {double y = 260}) async {
    final pen = await t.startGesture(at(t, Offset(150, y)),
        kind: PointerDeviceKind.stylus);
    for (var x = 155.0; x <= 300; x += 5) {
      await pen.moveTo(at(t, Offset(x, y)));
      await t.pump();
    }
    await pen.up();
    await t.pump();
  }

  List<Map> strokes() => [
        for (final b in app.blocks)
          if (b.type == BlockType.ink)
            ...(b.content['strokes'] as List).cast<Map>()
      ];
  CustomPainter overlay(WidgetTester t) => t
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<CustomPainter>()
      .singleWhere((p) => p.runtimeType.toString() == '_OverlayPainter');
  Future<Color> pixel(WidgetTester t, int x, int y) async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    return (await t.runAsync(() async {
      final image = await boundary.toImage();
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final offset = (y * image.width + x) * 4;
      final color = Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2));
      image.dispose();
      return color;
    }))!;
  }

  testWidgets('actual stylus contact opens Draw; hover leaves Home alone',
      (t) async {
    await mount(t, ribbon: true);
    expect(find.byKey(const ValueKey('pen-swatch-0')), findsNothing);
    final hover = await t.createGesture(kind: PointerDeviceKind.stylus);
    await hover.addPointer(location: at(t, const Offset(200, 200)));
    await hover.moveTo(at(t, const Offset(220, 220)));
    await t.pump();
    expect(find.byKey(const ValueKey('pen-swatch-0')), findsNothing);
    await hover.removePointer();
    await draw(t);
    expect(find.byKey(const ValueKey('pen-swatch-0')), findsOneWidget);
    expect(strokes(), hasLength(1));
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    testWidgets('palette and ink match in ${dark ? 'dark' : 'light'} mode',
        (t) async {
      app.penColor = 0;
      await mount(t, dark: dark, ribbon: true);
      await draw(t);
      final swatch =
          t.widget<Container>(find.byKey(const ValueKey('pen-swatch-0')));
      final shown = (swatch.decoration as BoxDecoration).color!;
      expect(shown, dark ? OnoteColors.moon0 : OnoteColors.graphite900);
      expect(colorFromHex(strokes().single['brush']['color'] as String), shown);
      expect(
          OnoteColors.drawingColors(dark: dark, highlighter: false)
              .skip(1)
              .take(5),
          OnoteColors.penColors.skip(1));
      // Explicit black remains available on white PDF paper in dark mode.
      await t.tap(find.byKey(const ValueKey('pen-swatch-6')));
      await draw(t, y: 300);
      expect(colorFromHex(strokes().last['brush']['color'] as String),
          Colors.black);
      app.cancelPendingSave();
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('larger eraser reaches nearby strokes; setting is persisted',
      (t) async {
    await mount(t, ribbon: true);
    await draw(t);
    app.setTool(Tool.eraser);
    app.eraserMode = EraserMode.stroke;
    app.setEraserSize(4);
    await t.pump();
    final slider = t.widget<Slider>(find.byKey(const ValueKey('eraser-size')));
    expect(slider.value, 4);
    await t.tapAt(at(t, const Offset(200, 280)),
        kind: PointerDeviceKind.stylus);
    await t.pump();
    expect(strokes(), hasLength(1));
    slider.onChanged!(80);
    await t.pump();
    expect(repo.getSetting('eraserSize'), 80);
    await t.tapAt(at(t, const Offset(200, 280)),
        kind: PointerDeviceKind.stylus);
    await t.pump();
    expect(strokes(), isEmpty);
    app.setEraserSize(double.nan);
    expect(app.eraserSize, 80);
    app.setEraserSize(999);
    expect(app.eraserSize, 100);
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('lasso repaints on each point and clears on cancellation',
      (t) async {
    app.tool = Tool.lasso;
    await mount(t);
    final gesture = await t.startGesture(at(t, const Offset(150, 220)),
        kind: PointerDeviceKind.stylus);
    await t.pump();
    final first = overlay(t);
    await gesture.moveTo(at(t, const Offset(250, 220)));
    await t.pump();
    final second = overlay(t);
    expect(second.shouldRepaint(first), true);
    final line = await pixel(t, 200, 220);
    await gesture.moveTo(at(t, const Offset(250, 320)));
    await t.pump();
    expect(overlay(t).shouldRepaint(second), true);
    await gesture.cancel();
    await t.pump();
    expect(await pixel(t, 200, 220), isNot(line),
        reason: 'visible outline cleared');
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('opaque objects cannot cover wet or saved handwriting',
      (t) async {
    app.blocks = [
      Block(
          type: BlockType.text,
          x: 100,
          y: 200,
          w: 350,
          h: 150,
          content: {'text': 'Worksheet', 'bg': 'FFFFFFFF', 'locked': true})
    ];
    await mount(t);
    expect(await pixel(t, 220, 260), Colors.white);
    final pen = await t.startGesture(at(t, const Offset(150, 260)),
        kind: PointerDeviceKind.stylus);
    for (var x = 160.0; x <= 300; x += 10) {
      await pen.moveTo(at(t, Offset(x, 260)));
      await t.pump();
    }
    final wet = await pixel(t, 220, 260);
    expect(wet.r, greaterThan(wet.g), reason: 'red ink is above white object');
    await pen.up();
    await t.pump();
    expect(await pixel(t, 220, 260), wet);
    expect(app.blocks.first.x, 100);
    expect(app.blocks.first.y, 200);
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  for (final type in [BlockType.image, BlockType.table]) {
    testWidgets('ink and lasso ignore ${type.name} hit targets', (t) async {
      final object = Block(
          type: type,
          x: 100,
          y: 200,
          w: 350,
          h: 150,
          content: type == BlockType.table
              ? {
                  'cells': [
                    ['A', 'B'],
                    ['C', 'D']
                  ]
                }
              : {'locked': true, 'pdf': 'sha256:not-downloaded', 'page': 0});
      app.blocks = [object];
      await mount(t);
      await draw(t);
      expect(strokes(), hasLength(1));
      expect(object.x, 100);
      expect(object.y, 200);
      final ignored = find.ancestor(
          of: find.byType(BlockView), matching: find.byType(Stack));
      expect(ignored, findsWidgets);
      app.setTool(Tool.lasso);
      await t.pump();
      final pen = await t.startGesture(at(t, const Offset(140, 240)),
          kind: PointerDeviceKind.stylus);
      for (final point in [
        const Offset(320, 240),
        const Offset(320, 280),
        const Offset(140, 280)
      ]) {
        await pen.moveTo(at(t, point));
        await t.pump();
      }
      await pen.up();
      await t.pump();
      expect(app.hasInkSelection, true);
      app.cancelPendingSave();
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('finger hold on a locked object opens its context menu',
      (t) async {
    app.tool = Tool.select;
    app.blocks = [
      Block(
          type: BlockType.text,
          x: 100,
          y: 200,
          w: 350,
          h: 150,
          content: {'text': 'Worksheet', 'locked': true})
    ];
    await mount(t);
    await t.longPressAt(at(t, const Offset(220, 260)));
    await t.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(app.blocks.first.x, 100);
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('finger hold on empty page opens menu without adding text',
      (t) async {
    app.tool = Tool.select;
    await mount(t);
    final count = app.blocks.length;
    await t.longPressAt(at(t, const Offset(450, 360)));
    await t.pumpAndSettle();
    expect(find.text('Page background'), findsOneWidget);
    expect(app.blocks.length, count);
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('window buttons stay right beside Settings on narrow ribbon',
      (t) async {
    final window = WindowsWindowController(enabled: true);
    addTearDown(window.dispose);
    await mount(t, ribbon: true, window: window, width: 700);
    final settings = t.getRect(find.byTooltip('Settings…'));
    final minimize = t.getRect(find.byTooltip('Minimize'));
    final close = t.getRect(find.byTooltip('Close Openote'));
    expect(minimize.left - settings.right, inInclusiveRange(0, 4));
    expect(close.right, 700);
    expect(t.takeException(), isNull);
    app.cancelPendingSave();
    await t.pumpWidget(const SizedBox());
  });
}
