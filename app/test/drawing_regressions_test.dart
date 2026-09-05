import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/canvas/ink_painter.dart';
import 'package:openote/canvas/shape_geometry.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/app_shell.dart';
import 'support/sqlite.dart';

void main() {
  test('closed rectangles and triangles keep their vertices and size', () {
    final rectangle = sampleOutline(const [
      Offset(100, 100),
      Offset(400, 100),
      Offset(400, 300),
      Offset(100, 300),
      Offset(100, 100)
    ], 3);
    final triangle = sampleOutline(const [
      Offset(250, 100),
      Offset(400, 300),
      Offset(100, 300),
      Offset(250, 100)
    ], 3);
    final r = recogniseShape(rectangle)!;
    final t = recogniseShape(triangle)!;
    expect(r.kind, 'rectangle');
    expect(t.kind, 'triangle');
    expect(r.points.map((p) => p.dx).reduce(math.max), closeTo(400, 1));
    expect(t.points.map((p) => p.dy).reduce(math.max), closeTo(300, 1));
    expect(r.points.first, r.points.last);
    expect(t.points.first, t.points.last);
  });
  test('ellipse keeps the drawn bounds; waves are not straight lines', () {
    final circle = [
      for (var i = 0; i <= 96; i++)
        Offset(250 + 150 * math.cos(i * math.pi / 48),
            200 + 100 * math.sin(i * math.pi / 48))
    ];
    final shape = recogniseShape(circle)!;
    expect(shape.kind, 'ellipse');
    expect(shape.points.first, shape.points.last);
    expect(shape.points.map((p) => p.dx).reduce(math.max), closeTo(400, 1));
    expect(
        recogniseShape([
          for (var i = 0; i <= 100; i++)
            Offset(i * 3, 20 * math.sin(i * math.pi / 20))
        ]),
        isNull);
  });
  test('old two-point lines expose their middle to area erasing', () {
    final s = Stroke(
        tool: 'pen',
        colorHex: '#000000',
        size: 2,
        x: [0, 300],
        y: [100, 100],
        p: [.2, .8],
        t: [0, 1000]);
    final sampled = sampleStroke(s, 2);
    expect(sampled.x.any((x) => (x - 150).abs() < 2), isTrue);
    expect(sampled.p.length, sampled.x.length);
    expect(sampled.t.last, 1000);
    expect(s.x.length, 2, reason: 'the input/cache stays unchanged');
  });

  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  group('drawing surfaces', () {
    late Directory tmp;
    late Repository repo;
    late AppState app;
    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('openote_drawing_regression_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Drawing');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.markOnboardingSeen();
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });
    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    testWidgets('writing mode fills the page and its exit is reachable',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: AppShell(app: app)));
      await t.pump();
      app.setWritingMode(true);
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(PageCanvas)).width, greaterThan(1000));
      expect(t.getSize(find.byType(PageCanvas)).height, greaterThan(700));
      expect(find.byTooltip('Pen  (P)'), findsOneWidget);
      await t.tap(find.byTooltip('Pen  (P)'));
      await t.pump();
      expect(app.tool, Tool.pen);
      await t.tap(find.byTooltip('Leave writing mode').last);
      await t.pump();
      expect(app.writingMode, isFalse);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
        'shape endpoint, erasing and deliberate pen choices work together',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setTool(Tool.pen);
      app.shapeRecognition = true;
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: app,
                  builder: (_, __) => PageCanvas(state: app)))));
      await t.pump();
      await t.pump();
      final end = app.canvas.screenToPage(const Offset(460, 300));
      final pen = await t.startGesture(const Offset(200, 300),
          kind: PointerDeviceKind.stylus);
      for (var x = 210.0; x <= 400; x += 10) {
        await pen.moveTo(Offset(x, 300));
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 1000));
      final livePainter = t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<InkPainter>()
          .single;
      expect(livePainter.wet?.tool, 'ballpoint',
          reason: 'the shape must be visible before PointerUp');
      expect(app.blocks.where((b) => b.type == BlockType.ink), isEmpty,
          reason: 'the stylus is still touching the page');
      await pen.moveTo(const Offset(460, 300));
      await pen.up();
      await t.pump();
      List<Stroke> ink() => [
            for (final b in app.blocks.where((b) => b.type == BlockType.ink))
              for (final s in b.content['strokes'] as List)
                Stroke.fromJson((s as Map).cast<String, dynamic>())
          ];
      expect(ink().single.tool, 'ballpoint');
      expect(ink().single.p, isEmpty);
      expect(ink().single.x.last, closeTo(end.dx, .01));
      app.setTool(Tool.eraser);
      app.eraserMode = EraserMode.stroke;
      await t.pump();
      final eraser = await t.startGesture(const Offset(330, 300),
          kind: PointerDeviceKind.stylus);
      await eraser.up();
      await t.pump();
      expect(ink(), isEmpty);
      app.shapeRecognition = false;
      for (final choice in [
        Tool.highlighter,
        Tool.pen,
        Tool.highlighter,
        Tool.pen
      ]) {
        app.setTool(choice);
        await t.pump();
        final stroke = await t.startGesture(const Offset(200, 350),
            kind: PointerDeviceKind.stylus);
        await stroke.moveTo(const Offset(300, 350));
        await stroke.up();
        await t.pump();
        expect(ink().last.tool, choice == Tool.pen ? 'pen' : 'highlighter');
      }
      app.cancelPendingSave();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('drawing tools keep independent sizes and persist eraser mode',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setTool(Tool.pen);
      app.setInkSize(7);
      app.setTool(Tool.ballpoint);
      app.setInkSize(4);
      app.setTool(Tool.highlighter);
      app.setInkSize(26);
      app.setEraserMode(EraserMode.stroke);
      expect(app.inkSizeFor(Tool.pen), 7);
      expect(app.inkSizeFor(Tool.ballpoint), 4);
      expect(app.inkSizeFor(Tool.highlighter), 26);
      app.setTool(Tool.pen);
      expect(app.penSize, 7);
      app.setTool(Tool.highlighter);
      expect(app.penSize, 26);
      expect(repo.getSetting('eraserMode'), EraserMode.stroke.name);
      final stored = repo.getSetting('inkToolSizes') as Map;
      expect(stored[Tool.pen.name], 7);
      expect(stored[Tool.ballpoint.name], 4);
      expect(stored[Tool.highlighter.name], 26);
      app.cancelPendingSave();
      expect(t.takeException(), isNull);
    });
    testWidgets('a lasso-selected block follows one finger, not the canvas',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.snapToGrid = false;
      app.setTool(Tool.lasso);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: app,
                  builder: (_, __) => PageCanvas(state: app)))));
      await t.pump();
      const start = Offset(220, 280);
      final page = app.canvas.screenToPage(start);
      final selected = app.addBlock(
        Block(
            type: BlockType.ink,
            x: page.dx - 40,
            y: page.dy - 20,
            w: 140,
            h: 40,
            content: {
              'strokes': [
                Stroke(
                    tool: 'pen',
                    colorHex: '#000000',
                    size: 2,
                    x: [page.dx - 30, page.dx + 80],
                    y: [page.dy, page.dy],
                    t: [0, 1]).toJson(),
              ],
            }),
      );
      app.select(selected.id);
      await t.pump();
      final canvasBefore = app.canvas.offset;
      final finger = await t.startGesture(start, kind: PointerDeviceKind.touch);
      await finger.moveBy(const Offset(80, 30));
      await t.pump();
      await finger.up();
      await t.pump();
      expect(selected.x, closeTo(page.dx + 40, .1));
      expect(selected.y, closeTo(page.dy + 10, .1));
      expect(app.canvas.offset, canvasBefore);
      app.cancelPendingSave();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('moving and stretching the ruler never moves the canvas',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setTool(Tool.pen);
      app.setRulerVisible(true);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: app,
                  builder: (_, __) => PageCanvas(state: app)))));
      await t.pump();
      await t.pump();
      final before = app.canvas.offset;
      final scale = app.canvas.scale;
      final body = find.byKey(const ValueKey('ruler-body'));
      final rulerBefore = t.getCenter(body);
      final g = await t.startGesture(const Offset(400, 210),
          kind: PointerDeviceKind.touch);
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(-12, 8));
        await t.pump();
      }
      await g.up();
      await t.pump();
      expect(app.canvas.offset, before);
      final rulerDelta = t.getCenter(body) - rulerBefore;
      expect(rulerDelta.dx, closeTo(-72, .5));
      expect(rulerDelta.dy, closeTo(48, .5));
      app.setTool(Tool.select);
      await t.pump();
      final first = await t.startGesture(const Offset(280, 250), pointer: 11);
      final rulerWidth = t.getSize(body).width;
      final second = await t.startGesture(const Offset(380, 250), pointer: 12);
      await first.moveBy(const Offset(-40, 0));
      await t.pump();
      await second.moveBy(const Offset(40, 0));
      await t.pump();
      await first.up();
      await second.up();
      await t.pump();
      expect(app.canvas.offset, before);
      expect(app.canvas.scale, scale);
      expect(t.getSize(body).width, greaterThan(rulerWidth));
      expect(app.blocks.where((b) => b.type == BlockType.ink), isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });
}
