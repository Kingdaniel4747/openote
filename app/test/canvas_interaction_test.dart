// Two canvas-feel asks from PLANNING.md, pinned:
//
//   "On touch screens, by default dragging with a finger should pan around
//    the page, it shouldn't be the selector tool."
//   "[Boxes] should automatically stop growing before going off the screen
//    (with a small amount of buffer room)."
import 'dart:io';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/canvas/page_title_view.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('where an auto-width box stops growing', () {
    test('far from the edge, the ordinary clamp wins and the edge is moot', () {
      expect(autoWidthEdgeCap(blockX: 100, viewportRightPage: 2000), isNull);
    });

    test('near the edge, the box stops a buffer short of it', () {
      expect(autoWidthEdgeCap(blockX: 600, viewportRightPage: 1000),
          1000 - 24 - 600);
    });

    test('hard against the edge, a usable minimum beats a sliver', () {
      expect(autoWidthEdgeCap(blockX: 990, viewportRightPage: 1000),
          TextBlockView.minAutoW,
          reason: 'a 10px text box is worse than poking past the edge');
    });
  });

  group('on the canvas', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      tmp = Directory.systemTemp.createTempSync('onote_canvas_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Canvas');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });

    tearDown(() {
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> pump(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: PageCanvas(state: app),
          ),
        ),
      ));
      await t.pump(); // the post-frame view restore
      await t.pump();
    }

    void makePdfPage() {
      app.addBlock(Block(
        type: BlockType.image,
        x: AppState.pageLeftMargin,
        y: AppState.contentTop,
        w: 960,
        h: 1200,
        content: {'pdf': 'sha256:fixture', 'page': 0},
      ));
      app.setPdfEditorView(true);
    }

    testWidgets('PDF title moves with the page instead of staying fixed',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      makePdfPage();
      await pump(t);

      expect(find.byType(PageTitleView), findsOneWidget);
      final before = t.getTopLeft(find.byType(PageTitleView));
      app.canvas.panBy(const Offset(0, -30));
      await t.pump();
      final after = t.getTopLeft(find.byType(PageTitleView));
      expect(after.dy, closeTo(before.dy - 30, 0.01));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));
    });

    testWidgets('PDF trackpad pinch stays under the mouse cursor', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      makePdfPage();
      await pump(t);
      const cursor = Offset(250, 300);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await t.sendEventToBinding(mouse.hover(cursor));
      final pagePoint = app.canvas.screenToPage(cursor);

      final trackpad = TestPointer(2, PointerDeviceKind.trackpad);
      const gesturePosition = Offset(600, 450);
      await t.sendEventToBinding(trackpad.panZoomStart(gesturePosition));
      await t.sendEventToBinding(trackpad.panZoomUpdate(gesturePosition,
          pan: const Offset(80, 40), scale: 1.5));
      await t.sendEventToBinding(trackpad.panZoomEnd());
      expect(app.canvas.scale, greaterThan(1));
      final after = app.canvas.screenToPage(cursor);
      expect(after.dx, closeTo(pagePoint.dx, .01));
      expect(after.dy, closeTo(pagePoint.dy, .01));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));
    });

    testWidgets('PDF trackpad swipe coasts after the fingers lift', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      makePdfPage();
      await pump(t);
      final trackpad = TestPointer(2, PointerDeviceKind.trackpad);
      const position = Offset(400, 400);
      await t.sendEventToBinding(trackpad.panZoomStart(position));
      await t.sendEventToBinding(
          trackpad.panZoomUpdate(position, pan: const Offset(0, -80)));
      await t.sendEventToBinding(trackpad.panZoomEnd());
      final liftedAt = app.canvas.offset.dy;
      await t.pump(const Duration(milliseconds: 80));
      expect(app.canvas.offset.dy, lessThan(liftedAt));
      app.canvas.stopMotion();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));
    });

    testWidgets('PDF finger swipe coasts after release', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      makePdfPage();
      await pump(t);
      final finger = await t.startGesture(const Offset(400, 400),
          kind: PointerDeviceKind.touch);
      await finger.moveBy(const Offset(0, -80));
      await finger.up();
      final liftedAt = app.canvas.offset.dy;
      await t.pump(const Duration(milliseconds: 80));
      expect(app.canvas.offset.dy, lessThan(liftedAt));
      app.canvas.stopMotion();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));
    });

    testWidgets('PDF precision scroll signal gets a short coast', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      makePdfPage();
      await pump(t);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await t.sendEventToBinding(pointer.hover(const Offset(400, 400)));
      await t.sendEventToBinding(pointer.scroll(const Offset(0, 32)));
      final afterSignal = app.canvas.offset.dy;
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 50));
      expect(app.canvas.offset.dy, lessThan(afterSignal));
      app.canvas.stopMotion();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));
    });

    testWidgets('A FINGER DRAG PANS; IT DOES NOT MARQUEE', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A block that a marquee from the centre would certainly catch, so a
      // wrong turn in the drag routing shows up as a selection.
      app.addBlock(Block(
          type: BlockType.text,
          x: 200,
          y: 200,
          w: 300,
          content: {'text': 'catch me', 'autoWidth': false}));
      app.select(null);
      await pump(t);

      final before = app.canvas.offset;
      final g = await t.startGesture(const Offset(400, 300),
          kind: PointerDeviceKind.touch);
      await g.moveBy(const Offset(-120, -60));
      await t.pump();
      await g.up();
      await t.pump();

      expect(app.canvas.offset, isNot(before),
          reason: 'the page moved under the finger');
      expect(app.selectedIds, isEmpty,
          reason: 'and nothing was marquee-selected on the way');
      app.cancelPendingSave();
    });

    testWidgets('DRAGGING THE SCROLL BAR SCROLLS — IT DOES NOT MARQUEE',
        (t) async {
      // The canvas's select handler is a raw Listener, outside the gesture
      // arena — so the bar's GestureDetector winning meant nothing to it,
      // and a drag on the track was also a marquee: "it draws up a box
      // behind it as it goes up". The bar now claims its pointers.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Content far below the fold, so the page is taller than the window
      // (the bar only exists then) and a stray marquee would catch nothing —
      // the tell is the pending→marquee mode itself selecting NOTHING while
      // the page also fails to move. Selection empty AND offset moved is
      // the pass.
      app.addBlock(Block(
          type: BlockType.text,
          x: 100,
          y: 2400,
          w: 300,
          content: {'text': 'far below', 'autoWidth': false}));
      app.select(null);
      await pump(t);

      final before = app.canvas.offset;
      final g = await t.startGesture(const Offset(794, 100),
          kind: PointerDeviceKind.mouse);
      await t.pump();
      // Several small moves, as a real mouse produces: a single big jump is
      // swallowed whole by the drag recognizer's ACCEPT and never arrives
      // as an update.
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(0, 30));
        await t.pump();
      }
      await g.up();
      await t.pump();

      expect(app.canvas.offset.dy, lessThan(before.dy),
          reason: 'dragging the thumb down scrolls the page down');
      expect(app.selectedIds, isEmpty,
          reason: 'and no marquee ran behind the bar');
      app.cancelPendingSave();
    });

    testWidgets('a mouse drag still marquees', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = app.addBlock(Block(
          type: BlockType.text,
          x: 200,
          y: 300,
          w: 200,
          h: 60,
          content: {'text': 'catch me', 'autoWidth': false}));
      app.select(null);
      await pump(t);

      // Drag a screen rect that certainly covers the block, computed from the
      // live transform so the zoom the canvas restored does not matter.
      final tl = app.canvas.pageToScreen(const Offset(150, 250));
      final br = app.canvas.pageToScreen(const Offset(450, 400));
      final g = await t.startGesture(tl, kind: PointerDeviceKind.mouse);
      await g.moveTo(br);
      await t.pump();
      await g.up();
      await t.pump();

      expect(app.selectedIds, contains(b.id),
          reason: 'pen and mouse keep the selector drag');
      app.cancelPendingSave();
    });

    testWidgets(
        'wheel scrolls; Shift-wheel zooms; middle drag pans over a block',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.addBlock(Block(
          type: BlockType.text,
          x: 180,
          y: 180,
          w: 300,
          h: 250,
          content: {'text': 'block', 'autoWidth': false}));
      app.addBlock(Block(
          type: BlockType.text,
          x: 100,
          y: 1600,
          w: 300,
          content: {'text': 'below', 'autoWidth': false}));
      await pump(t);

      final wheel = TestPointer(1, PointerDeviceKind.mouse);
      await t.sendEventToBinding(wheel.hover(const Offset(400, 300)));
      await t.sendEventToBinding(wheel.scroll(const Offset(0, 120)));
      await t.pump();
      expect(app.canvas.offset.dy, lessThan(0));
      final scale = app.canvas.scale;
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendEventToBinding(wheel.scroll(const Offset(0, -120)));
      await t.pump();
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(app.canvas.scale, greaterThan(scale));

      final from = app.canvas.pageToScreen(const Offset(250, 250));
      final middle =
          TestPointer(2, PointerDeviceKind.mouse, null, kMiddleMouseButton);
      await t.sendEventToBinding(middle.down(from));
      final before = app.canvas.offset;
      await t.sendEventToBinding(middle.move(from + const Offset(-60, -40)));
      await t.sendEventToBinding(middle.up());
      await t.pump();
      expect(app.canvas.offset.dy, lessThan(before.dy));
      app.cancelPendingSave();
    });
  });
}
