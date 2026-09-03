import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/canvas/windows_pen_buttons.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  var initialState = <String, bool>{'inRange': false, 'eraser': false};

  setUp(() {
    initialState = {'inRange': false, 'eraser': false};
    messenger.setMockMethodCallHandler(WindowsPenButtons.channel,
        (call) async => call.method == 'getState' ? initialState : null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(WindowsPenButtons.channel, null);
  });

  Future<void> nativeState(bool inRange, bool eraser) async {
    await messenger.handlePlatformMessage(
      WindowsPenButtons.channel.name,
      codec.encodeMethodCall(MethodCall('state', {
        'inRange': inRange,
        'eraser': eraser,
      })),
      (_) {},
    );
  }

  test('Windows recognizes barrel, eraser tip and secondary stylus button', () {
    final pen = WindowsPenButtons(enabled: true);
    addTearDown(pen.dispose);
    for (final button in [kPrimaryStylusButton, kSecondaryStylusButton]) {
      expect(
          pen.erases(PointerMoveEvent(
              kind: PointerDeviceKind.stylus, buttons: button)),
          true);
    }
    expect(
        pen.erases(
            const PointerMoveEvent(kind: PointerDeviceKind.invertedStylus)),
        true);
    expect(pen.erases(const PointerMoveEvent(kind: PointerDeviceKind.stylus)),
        false);
  });

  test('non-Windows retains exactly the original button interpretation', () {
    final pen = WindowsPenButtons(enabled: false);
    addTearDown(pen.dispose);
    expect(
        pen.erases(const PointerMoveEvent(
            kind: PointerDeviceKind.stylus, buttons: kPrimaryStylusButton)),
        true);
    expect(
        pen.erases(const PointerMoveEvent(
            kind: PointerDeviceKind.stylus, buttons: kSecondaryStylusButton)),
        false);
    expect(
        pen.erases(
            const PointerMoveEvent(kind: PointerDeviceKind.invertedStylus)),
        true);
  });

  test('native hover is queried on attach and release clears eraser state',
      () async {
    initialState = {'inRange': true, 'eraser': true};
    final pen = WindowsPenButtons(enabled: true);
    addTearDown(pen.dispose);
    await pen.attach();
    expect(pen.nativeEraser, true);
    expect(pen.erases(const PointerMoveEvent(kind: PointerDeviceKind.stylus)),
        true);
    await nativeState(true, false);
    expect(pen.nativeEraser, false);
    expect(pen.erases(const PointerMoveEvent(kind: PointerDeviceKind.stylus)),
        false);
  });

  test('native pen state never turns mouse or touch into an eraser', () async {
    final pen = WindowsPenButtons(enabled: true);
    addTearDown(pen.dispose);
    await pen.attach();
    await nativeState(true, true);
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      expect(
          pen.erases(PointerMoveEvent(kind: kind, buttons: kSecondaryButton)),
          false);
    }
  });

  test('live release wins over Flutter button latched at pointer-down',
      () async {
    final pen = WindowsPenButtons(enabled: true);
    addTearDown(pen.dispose);
    await pen.attach();
    const stale = PointerMoveEvent(
        kind: PointerDeviceKind.stylus, buttons: kPrimaryStylusButton);
    // Same proximity session, including repeated toggles while hovering.
    for (var i = 0; i < 4; i++) {
      await nativeState(true, true);
      expect(pen.erases(stale), true);
      await nativeState(true, false);
      expect(pen.nativeInRange, true);
      expect(pen.erases(stale), false);
    }
  });

  test('leaving range/focus clears native state even with an old eraser bit',
      () async {
    final pen = WindowsPenButtons(enabled: true);
    addTearDown(pen.dispose);
    await pen.attach();
    await nativeState(true, true);
    await nativeState(false, true);
    expect(pen.nativeInRange, false);
    expect(pen.nativeEraser, false);
  });

  test('missing Windows channel falls back to Flutter flags', () async {
    messenger.setMockMethodCallHandler(WindowsPenButtons.channel, null);
    final pen = WindowsPenButtons(enabled: true);
    addTearDown(pen.dispose);
    await pen.attach();
    expect(
        pen.erases(const PointerMoveEvent(
            kind: PointerDeviceKind.stylus, buttons: kPrimaryStylusButton)),
        true);
  });

  group('Windows canvas integration', () {
    setUpAll(() => expect(initSqliteForTests(), true,
        reason: 'Build Windows first so its bundled SQLite DLL is available.'));

    Future<AppState> makeApp() async {
      AppState.syncLogEnabled = false;
      final dir =
          Directory.systemTemp.createTempSync('openote-windows-pen-test-');
      final repo = await Repository.openAt(dir);
      final nb = await repo.createNotebook('Pen test');
      final app = AppState(repo)
        ..notebookId = nb.id
        ..tool = Tool.pen
        ..penSize = 4
        ..penColor = 2
        ..spellCheckEnabled = false
        ..penProximitySwitch = false
        ..snapToGrid = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      addTearDown(() {
        app.cancelPendingSave();
        app.dispose();
        repo.dispose();
        AppState.syncLogEnabled = true;
        dir.deleteSync(recursive: true);
      });
      return app;
    }

    Future<AppState> mount(WidgetTester t) async {
      final app = (await t.runAsync(makeApp))!;
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: app,
                  builder: (_, __) => PageCanvas(state: app)))));
      await t.pump();
      app.canvas.jumpTo(1, Offset.zero);
      await t.pump();
      return app;
    }

    List<Map> strokes(AppState app) => [
          for (final b in app.blocks)
            if (b.type == BlockType.ink)
              ...(b.content['strokes'] as List).cast<Map>(),
        ];

    Future<void> event(WidgetTester t, PointerEvent e) async {
      await t.sendEventToBinding(e);
      await t.pump(const Duration(milliseconds: 20));
    }

    Future<void> down(WidgetTester t, double x,
            {int buttons = kPrimaryButton,
            PointerDeviceKind kind = PointerDeviceKind.stylus}) =>
        event(
            t,
            PointerDownEvent(
                pointer: 41,
                kind: kind,
                position: Offset(x, 210),
                buttons: buttons,
                pressure: .6));
    Future<void> move(WidgetTester t, double x,
            {int buttons = kPrimaryButton,
            PointerDeviceKind kind = PointerDeviceKind.stylus}) =>
        event(
            t,
            PointerMoveEvent(
                pointer: 41,
                kind: kind,
                position: Offset(x, 210),
                buttons: buttons,
                pressure: .6));
    Future<void> up(WidgetTester t, double x,
            {PointerDeviceKind kind = PointerDeviceKind.stylus}) =>
        event(t,
            PointerUpEvent(pointer: 41, kind: kind, position: Offset(x, 210)));

    Future<void> finish(WidgetTester t, AppState app) async {
      await t.pumpWidget(const SizedBox());
      app.cancelPendingSave();
    }

    testWidgets(
        'button pressed before contact erases and release returns to pen',
        (t) async {
      final app = await mount(t);
      await down(t, 100);
      await move(t, 150);
      await up(t, 150);
      expect(strokes(app), hasLength(1));
      await down(t, 100, buttons: kPrimaryButton | kPrimaryStylusButton);
      await up(t, 100);
      expect(strokes(app), isEmpty);
      await down(t, 250);
      await move(t, 300);
      await up(t, 300);
      expect(strokes(app), hasLength(1));
      expect(app.tool, Tool.pen);
      await finish(t, app);
    });

    testWidgets('button transitions during a stroke do not split or erase it',
        (t) async {
      final app = await mount(t);
      app.tool = Tool.highlighter;
      await t.pump();
      await down(t, 100);
      await move(t, 140);
      await move(t, 280, buttons: kPrimaryButton | kPrimaryStylusButton);
      await move(t, 340);
      await move(t, 390);
      await up(t, 390);
      final ink = strokes(app);
      expect(ink, hasLength(1));
      expect(ink[0]['x'], [100.0, 140.0, 280.0, 340.0, 390.0]);
      expect((ink[0]['brush'] as Map)['tool'], 'highlighter');
      expect(app.tool, Tool.highlighter);
      expect(app.penSize, 4);
      expect(app.penColor, 2);
      await finish(t, app);
    });

    testWidgets('native button changes apply only after lifting the pen',
        (t) async {
      final app = await mount(t);
      await down(t, 100);
      await move(t, 140);
      await nativeState(true, true);
      await t.pump();
      expect(app.tool, Tool.pen);
      expect(strokes(app), isEmpty,
          reason: 'wet stroke is not prematurely committed');
      await move(t, 180);
      await up(t, 180);
      expect(strokes(app), hasLength(1));
      expect(app.tool, Tool.eraser);
      // Release while erasing: keep erasing until lift, then restore the pen.
      await down(t, 100);
      await nativeState(true, false);
      await t.pump();
      expect(app.tool, Tool.eraser);
      await move(t, 140, buttons: kPrimaryStylusButton);
      await up(t, 140);
      expect(app.tool, Tool.pen);
      await down(t, 280);
      await move(t, 320);
      await up(t, 320);
      expect(strokes(app).last['x'], [280.0, 320.0]);
      await finish(t, app);
    });

    testWidgets('hover toggles eraser without leaving range and restores lasso',
        (t) async {
      final app = await mount(t);
      app.setTool(Tool.lasso);
      await nativeState(true, true);
      await t.pump();
      expect(app.tool, Tool.eraser);
      await nativeState(true, false);
      await t.pump();
      expect(app.tool, Tool.lasso);
      await finish(t, app);
    });

    testWidgets('mouse right-click never erases even while pen button is held',
        (t) async {
      final app = await mount(t);
      await down(t, 100);
      await move(t, 140);
      await up(t, 140);
      await nativeState(true, true);
      await t.pump();
      await down(t, 100,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
      await move(t, 140,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
      await up(t, 140, kind: PointerDeviceKind.mouse);
      expect(strokes(app), hasLength(2));
      await finish(t, app);
    });

    testWidgets(
        'another pointer cannot finish the pen and cancellation leaves no ink',
        (t) async {
      final app = await mount(t);
      await down(t, 100);
      await move(t, 140);
      await event(
          t,
          const PointerUpEvent(
              pointer: 99,
              kind: PointerDeviceKind.mouse,
              position: Offset(140, 210)));
      expect(strokes(app), isEmpty);
      await event(
          t,
          const PointerCancelEvent(
              pointer: 41,
              kind: PointerDeviceKind.stylus,
              position: Offset(140, 210)));
      expect(strokes(app), isEmpty);
      await down(t, 250);
      await move(t, 300);
      await up(t, 300);
      expect(strokes(app), hasLength(1));
      await finish(t, app);
    });
  }, skip: !Platform.isWindows);
}
