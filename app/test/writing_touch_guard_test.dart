import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/canvas/windows_pen_buttons.dart';
import 'package:openote/canvas/writing_touch_guard.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/windows_window_frame.dart';

import 'support/sqlite.dart';

class _WritingTestBinding extends AutomatedTestWidgetsFlutterBinding
    with WritingTouchBinding {
  int exits = 0;
  @override
  Future<AppExitResponse> exitApplication(AppExitType exitType,
      [int exitCode = 0]) async {
    exits++;
    return AppExitResponse.cancel;
  }
}

void main() {
  final binding = _WritingTestBinding();

  group('automatic pointer classification', () {
    late DateTime now;
    late List<PointerEvent> delivered;
    late WritingTouchGuard guard;
    setUp(() {
      now = DateTime(2026, 11, 9);
      delivered = [];
      guard = WritingTouchGuard(dispatch: delivered.add, now: () => now)
        ..writingContext = (() => true)
        ..navigationTarget = ((_) => true);
    });
    tearDown(() => guard.detach());

    void down(int id, [Offset at = Offset.zero]) =>
        guard.handle(PointerDownEvent(
            pointer: id, kind: PointerDeviceKind.touch, position: at));
    void move(int id, Offset at) => guard.handle(PointerMoveEvent(
        pointer: id, kind: PointerDeviceKind.touch, position: at));
    void up(int id) => guard
        .handle(PointerUpEvent(pointer: id, kind: PointerDeviceKind.touch));
    void penDown() => guard.handle(
        const PointerDownEvent(pointer: 99, kind: PointerDeviceKind.stylus));
    void penUp() => guard.handle(
        const PointerUpEvent(pointer: 99, kind: PointerDeviceKind.stylus));

    test('the hand can land before the pen and stays ignored until it lifts',
        () {
      down(1);
      penDown();
      penUp();
      now = now.add(const Duration(seconds: 4));
      move(1, const Offset(60, 70));
      up(1);
      expect(
          delivered.where((e) => e.kind == PointerDeviceKind.touch), isEmpty);
    });

    test('pen hover cancels a previously delivered finger instead of clicking',
        () {
      guard.writingContext = () => false;
      down(1);
      guard.handle(
          const PointerHoverEvent(pointer: 99, kind: PointerDeviceKind.stylus));
      up(1);
      expect(delivered.map((e) => e.runtimeType),
          [PointerDownEvent, PointerCancelEvent, PointerHoverEvent]);
    });

    test('small sleeve jitter and large jumps never become navigation', () {
      guard.setPenInRange(true);
      down(1);
      move(1, const Offset(2, 1));
      move(1, const Offset(-2, 2));
      move(1, const Offset(1, -1));
      up(1);
      down(2);
      move(2, const Offset(450, 600));
      up(2);
      expect(delivered, isEmpty);
    });

    test('large palms are rejected without any earlier pen event', () {
      guard.handle(const PointerDownEvent(
          pointer: 1, kind: PointerDeviceKind.touch, radiusMajor: 40));
      move(1, const Offset(30, 0));
      move(1, const Offset(60, 0));
      move(1, const Offset(90, 0));
      up(1);
      expect(delivered, isEmpty);
    });

    test('a fresh clear swipe works with the old palm and hovering pen present',
        () {
      down(1);
      guard.setPenInRange(true);
      down(2);
      move(2, const Offset(10, 0));
      move(2, const Offset(20, 0));
      expect(delivered, isEmpty);
      move(2, const Offset(30, 0));
      expect(guard.isNavigationPointer(2), isTrue);
      expect(guard.isNavigationPointer(1), isFalse);
      up(2);
      up(1);
      expect(delivered.map((e) => e.pointer).toSet(), {2});
    });

    test('two fresh fingers pinch without treating the resting palm as a third',
        () {
      down(1);
      penDown();
      penUp();
      guard.setPenInRange(true);
      down(4, const Offset(300, 300)); // Another stationary sleeve contact.
      down(2, const Offset(100, 100));
      down(3, const Offset(200, 100));
      move(2, const Offset(90, 100));
      move(3, const Offset(210, 100));
      move(2, const Offset(80, 100));
      move(3, const Offset(220, 100));
      expect(guard.isNavigationPointer(2), isTrue);
      expect(guard.isNavigationPointer(3), isTrue);
      expect(
          delivered
              .where((e) => e.kind == PointerDeviceKind.touch)
              .map((e) => e.pointer)
              .toSet(),
          {2, 3});
      penDown();
      expect(delivered.whereType<PointerCancelEvent>().map((e) => e.pointer),
          [2, 3]);
      up(1);
      up(2);
      up(3);
      up(4);
      penUp();
    });

    test('a stationary palm does not turn into a swipe after a long rest', () {
      down(1);
      guard.handle(const PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.touch,
          timeStamp: Duration(seconds: 2),
          position: Offset(30, 0)));
      move(1, const Offset(60, 0));
      move(1, const Offset(90, 0));
      up(1);
      expect(delivered, isEmpty);
    });

    test('scroll-track movement cannot be promoted to a canvas gesture', () {
      guard.navigationTarget = (_) => false;
      guard.setPenInRange(true);
      down(1);
      move(1, const Offset(0, 10));
      move(1, const Offset(0, 20));
      move(1, const Offset(0, 40));
      up(1);
      expect(delivered, isEmpty);
    });

    test('new contacts during an active pen stroke never reach controls', () {
      penDown();
      down(1);
      move(1, const Offset(20, 0));
      move(1, const Offset(40, 0));
      penUp();
      move(1, const Offset(60, 0));
      up(1);
      expect(
          delivered.where((e) => e.kind == PointerDeviceKind.touch), isEmpty);
    });

    test('native focus/range loss cannot leave touch permanently suppressed',
        () {
      guard.setPenInRange(true);
      penDown();
      guard.setPenInRange(false);
      now = now.add(const Duration(seconds: 2));
      guard.writingContext = () => false;
      down(1);
      up(1);
      expect(delivered.where((e) => e.kind == PointerDeviceKind.touch),
          hasLength(2));
    });

    test('scroll signals cannot move the page during a pen contact', () {
      penDown();
      guard.handle(const PointerScrollEvent(scrollDelta: Offset(0, 120)));
      penUp();
      expect(delivered.whereType<PointerScrollEvent>(), isEmpty);
      guard.handle(const PointerScrollEvent(scrollDelta: Offset(0, 120)));
      expect(delivered.whereType<PointerScrollEvent>(), hasLength(1));
    });

    test('normal mouse, trackpad, pen and non-Windows touch stay intact', () {
      for (final kind in [
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus
      ]) {
        guard.handle(PointerDownEvent(pointer: kind.index + 10, kind: kind));
        guard.handle(PointerUpEvent(pointer: kind.index + 10, kind: kind));
      }
      guard.handle(const PointerPanZoomStartEvent(pointer: 77));
      guard.handle(const PointerPanZoomUpdateEvent(pointer: 77, scale: 1.2));
      guard.handle(const PointerPanZoomEndEvent(pointer: 77));
      guard.enabled = false;
      down(1);
      up(1);
      expect(delivered, hasLength(11));
    });
  });

  group('real app input', () {
    late Directory dir;
    late Repository repo;
    late AppState app;
    late WindowsWindowController window;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());
    setUp(() async {
      if (!haveSqlite) return;
      binding.writingTouchGuard.detach();
      binding.writingTouchGuard.enabled = true;
      binding.exits = 0;
      messenger.setMockMethodCallHandler(WindowsWindowController.channel,
          (call) async => call.method == 'customChrome' ? true : null);
      messenger.setMockMethodCallHandler(WindowsPenButtons.channel,
          (_) async => {'inRange': false, 'eraser': false});
      dir = Directory.systemTemp.createTempSync('openote-palm-');
      repo = await Repository.openAt(dir);
      final nb = await repo.createNotebook('Palm rejection');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      app.setTool(Tool.pen);
      window = WindowsWindowController(enabled: true);
    });
    tearDown(() {
      if (!haveSqlite) return;
      binding.writingTouchGuard.detach();
      binding.writingTouchGuard.enabled = false;
      app.cancelPendingSave();
      app.dispose();
      repo.dispose();
      window.dispose();
      dir.deleteSync(recursive: true);
      messenger.setMockMethodCallHandler(WindowsWindowController.channel, null);
      messenger.setMockMethodCallHandler(WindowsPenButtons.channel, null);
    });

    Future<void> mount(WidgetTester t) async {
      t.view.physicalSize = const Size(1280, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (_, child) => WindowsWindowFrame(
            controller: window, startMaximized: false, child: child!),
        home: AppShell(app: app),
      ));
      await t.pumpAndSettle();
      app.canvas.jumpTo(1, Offset.zero);
      await t.pump();
    }

    Future<void> draw(WidgetTester t, Offset origin) async {
      final pen = await t.startGesture(origin + const Offset(150, 240),
          pointer: 99, kind: PointerDeviceKind.stylus);
      await pen.moveBy(const Offset(100, 30));
      await pen.up();
      await t.pump();
    }

    testWidgets('hand first cannot close the window when the pen then writes',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await mount(t);
      final palm = await t.startGesture(
          t.getCenter(find.byTooltip('Close Openote')),
          pointer: 1);
      await draw(t, t.getTopLeft(find.byType(PageCanvas)));
      await palm.up();
      await t.pump(const Duration(milliseconds: 200));
      expect(binding.exits, 0);
      expect(app.blocks.where((b) => b.type == BlockType.ink), isNotEmpty);
      await t.tap(find.byTooltip('Close Openote'),
          kind: PointerDeviceKind.mouse);
      await t.pump();
      expect(binding.exits, 1);
      app.cancelPendingSave();
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('resting palm is ignored and fresh fingers can swipe and pinch',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await mount(t);
      final origin = t.getTopLeft(find.byType(PageCanvas));
      final before = app.canvas.offset;
      final scale = app.canvas.scale;
      final palm =
          await t.startGesture(origin + const Offset(300, 480), pointer: 1);
      await messenger.handlePlatformMessage(
          WindowsPenButtons.channel.name,
          const StandardMethodCodec().encodeMethodCall(
              const MethodCall('state', {'inRange': true, 'eraser': false})),
          (_) {});
      await draw(t, origin);
      await palm.moveBy(const Offset(80, 60));
      await t.pump();
      expect(app.canvas.offset, before);
      expect(app.canvas.scale, scale);
      final a =
          await t.startGesture(origin + const Offset(300, 350), pointer: 2);
      final b =
          await t.startGesture(origin + const Offset(450, 350), pointer: 3);
      await a.moveBy(const Offset(-12, 0));
      await b.moveBy(const Offset(12, 0));
      await a.moveBy(const Offset(-12, 0));
      await b.moveBy(const Offset(12, 0));
      await t.pump();
      expect(app.canvas.scale, greaterThan(scale));
      await a.up();
      await b.up();
      final swipe =
          await t.startGesture(origin + const Offset(400, 400), pointer: 4);
      final swipeStart = app.canvas.offset;
      for (var i = 0; i < 4; i++) {
        await swipe.moveBy(const Offset(-12, -8));
      }
      await t.pump();
      expect(app.canvas.offset, isNot(swipeStart));
      await swipe.up();
      await palm.up();
      app.cancelPendingSave();
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('sleeve drag on the right scroll track does not jump the page',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await mount(t);
      final canvas = find.byType(PageCanvas);
      final origin = t.getTopLeft(canvas);
      final size = t.getSize(canvas);
      final before = app.canvas.offset;
      final sleeve = await t.startGesture(origin + Offset(size.width - 5, 180));
      for (var i = 0; i < 5; i++) {
        await sleeve.moveBy(const Offset(0, 40));
      }
      await sleeve.up();
      await t.pump(const Duration(milliseconds: 300));
      expect(app.canvas.offset, before);
      app.cancelPendingSave();
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('ordinary finger taps still work without a pen approaching',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await mount(t);
      await t.tap(find.byTooltip('Close Openote'));
      await t.pump(const Duration(milliseconds: 200));
      expect(binding.exits, 1);
      app.cancelPendingSave();
      await t.pumpWidget(const SizedBox());
    });
  });
}
