import 'dart:io';
import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/windows_pen_buttons.dart';
import 'package:openote/model/models.dart';
import 'package:openote/ui/handwriting_pad.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(WindowsPenButtons.channel,
      (_) async => {'inRange': false, 'eraser': false}));
  tearDown(() =>
      messenger.setMockMethodCallHandler(WindowsPenButtons.channel, null));

  Stroke line() => Stroke(
      tool: 'pen',
      colorHex: 'auto',
      size: 2.5,
      x: [20, 200],
      y: [80, 80],
      p: [.2, .8],
      t: [0, 100],
      strokeStart: 0);

  Future<void> nativeEraser(bool active) => messenger.handlePlatformMessage(
        WindowsPenButtons.channel.name,
        const StandardMethodCodec().encodeMethodCall(
            MethodCall('state', {'inRange': true, 'eraser': active})),
        (_) {},
      );

  Widget host(GlobalKey<HandwritingPadState> key,
          {bool eraser = false,
          double width = 300,
          String token = 'a',
          List<Stroke> ink = const []}) =>
      MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: width,
                    child: HandwritingPad(
                        key: key,
                        character: 'a',
                        sampleToken: token,
                        initialStrokes: ink,
                        eraser: eraser,
                        onChanged: () {})))),
      );

  Future<void> eraseMiddle(WidgetTester t) async {
    final rect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
    final pen = await t.startGesture(
        Offset(rect.center.dx, rect.top + rect.height * .35),
        kind: PointerDeviceKind.stylus);
    await pen.moveTo(Offset(rect.center.dx, rect.top + rect.height * .65));
    await pen.up();
    await t.pump();
  }

  testWidgets(
      'a half-size writing box records the same canonical letter geometry',
      (t) async {
    final key = GlobalKey<HandwritingPadState>();
    Future<Stroke> record(double width, String token) async {
      await t.pumpWidget(host(key, width: width, token: token));
      await t.pump();
      final rect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
      final pen = await t.startGesture(
          rect.topLeft + Offset(rect.width * .25, rect.height * .3),
          kind: PointerDeviceKind.stylus);
      await pen
          .moveTo(rect.topLeft + Offset(rect.width * .75, rect.height * .7));
      await pen.up();
      await t.pump();
      return Stroke.fromJson(key.currentState!.strokes.single.toJson());
    }

    final previousSize = await record(300, 'previous-size');
    final smaller = await record(160, 'smaller-size');
    for (var i = 0; i < previousSize.x.length; i++) {
      expect(smaller.x[i], closeTo(previousSize.x[i], .00001));
      expect(smaller.y[i], closeTo(previousSize.y[i], .00001));
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'size reference paints without becoming ink; retry and undo preserve the saved sample',
      (t) async {
    final key = GlobalKey<HandwritingPadState>();
    final original = line();
    await t.pumpWidget(host(key, ink: [original]));
    await t.pump();
    final region = find.descendant(
        of: find.byType(HandwritingPad), matching: find.byType(MouseRegion));
    expect(t.widget<MouseRegion>(region).cursor, SystemMouseCursors.none);
    expect(key.currentState!.strokes.single.tool, 'ballpoint');
    expect(key.currentState!.strokes.single.size, 2.5);
    expect(original.tool, 'pen',
        reason: 'loading does not mutate the saved input');
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is HandwritingSamplePainter),
        findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('handwriting-pad'))).width, 300);
    key.currentState!.clear();
    await t.pump();
    expect(key.currentState!.strokes, isEmpty);
    expect(original.x, [20, 200]);
    key.currentState!.undo();
    await t.pump();
    expect(key.currentState!.strokes.single.x, original.x);
    await t.pumpWidget(host(key, token: 'b'));
    expect(key.currentState!.strokes, isEmpty);
    expect(key.currentState!.canUndo, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'toolbar eraser cuts the draft and undo restores pressure and geometry',
      (t) async {
    final key = GlobalKey<HandwritingPadState>();
    final original = line();
    await t.pumpWidget(host(key, eraser: true, ink: [original]));
    await t.pump();
    await eraseMiddle(t);
    expect(key.currentState!.strokes, hasLength(2));
    expect(key.currentState!.strokes.every((s) => s.x.length == s.p.length),
        isTrue);
    expect(original.x, [20, 200]);
    key.currentState!.undo();
    await t.pump();
    expect(key.currentState!.strokes.single.x, [20, 200]);
    expect(key.currentState!.strokes.single.p, [.2, .8]);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'native pen button erases then release writes again without switching toolbar tools',
      (t) async {
    if (!Platform.isWindows) return markTestSkipped('Windows native pen state');
    final key = GlobalKey<HandwritingPadState>();
    await t.pumpWidget(host(key, ink: [line()]));
    await t.pump();
    await nativeEraser(true);
    await eraseMiddle(t);
    expect(key.currentState!.strokes, hasLength(2));
    await nativeEraser(false);
    final rect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
    final pen = await t.startGesture(rect.topLeft + const Offset(30, 30),
        kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(20, 20));
    await pen.up();
    await t.pump();
    expect(key.currentState!.strokes, hasLength(3));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('cancelled erasing restores the whole draft', (t) async {
    final key = GlobalKey<HandwritingPadState>();
    await t.pumpWidget(host(key, eraser: true, ink: [line()]));
    await t.pump();
    final rect = t.getRect(find.byKey(const ValueKey('handwriting-pad')));
    final pen =
        await t.startGesture(rect.center, kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(0, 20));
    await pen.cancel();
    await t.pump();
    expect(key.currentState!.strokes.single.x, [20, 200]);
    expect(key.currentState!.drawing, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('learning records one fixed width regardless of stylus pressure',
      (t) async {
    final key = GlobalKey<HandwritingPadState>();
    await t.pumpWidget(host(key));
    await t.pump();
    final at = t.getCenter(find.byKey(const ValueKey('handwriting-pad')));
    await t.sendEventToBinding(PointerDownEvent(
        pointer: 99,
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryButton,
        position: at,
        pressure: .1));
    await t.sendEventToBinding(PointerMoveEvent(
        pointer: 99,
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryButton,
        position: at + const Offset(20, 20),
        pressure: .9));
    await t.sendEventToBinding(PointerUpEvent(
        pointer: 99,
        kind: PointerDeviceKind.stylus,
        position: at + const Offset(20, 20),
        pressure: 0));
    await t.pump();
    final stroke = key.currentState!.strokes.single;
    expect(stroke.p, everyElement(.5));
    expect(stroke.tool, 'ballpoint');
    expect(stroke.size, 2.5);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a missing release cannot block the next writing contact',
      (t) async {
    final key = GlobalKey<HandwritingPadState>();
    await t.pumpWidget(host(key));
    await t.pump();
    final at = t.getCenter(find.byKey(const ValueKey('handwriting-pad')));
    final interrupted =
        await t.startGesture(at, pointer: 91, kind: PointerDeviceKind.stylus);
    await interrupted.moveBy(const Offset(20, 20));
    final next = await t.startGesture(at - const Offset(40, 20),
        pointer: 92, kind: PointerDeviceKind.stylus);
    await next.moveBy(const Offset(20, 10));
    await next.up();
    await t.pump();
    expect(key.currentState!.drawing, isFalse);
    expect(key.currentState!.strokes, hasLength(2));
    await interrupted.cancel();
    await t.pump();
    expect(key.currentState!.strokes, hasLength(2));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a removed pen ends its unfinished stroke without reopening the dialog',
      (t) async {
    final key = GlobalKey<HandwritingPadState>();
    await t.pumpWidget(host(key));
    await t.pump();
    final at = t.getCenter(find.byKey(const ValueKey('handwriting-pad')));
    final pen =
        await t.startGesture(at, pointer: 91, kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(20, 10));
    await t.sendEventToBinding(PointerRemovedEvent(
        pointer: 91, kind: PointerDeviceKind.stylus, position: at));
    await t.pump();
    expect(key.currentState!.drawing, isFalse);
    expect(key.currentState!.strokes, hasLength(1));
    await pen.cancel();
    await t.pumpWidget(const SizedBox());
  });

  for (final interrupt in ['focus', 'inactive', 'reload', 'hover']) {
    testWidgets('$interrupt ends an unfinished stroke and writing can continue',
        (t) async {
      final key = GlobalKey<HandwritingPadState>();
      await t.pumpWidget(host(key));
      await t.pump();
      final at = t.getCenter(find.byKey(const ValueKey('handwriting-pad')));
      final pen =
          await t.startGesture(at, pointer: 91, kind: PointerDeviceKind.stylus);
      await pen.moveBy(const Offset(20, 10));
      switch (interrupt) {
        case 'focus':
          t.binding.handleViewFocusChanged(ViewFocusEvent(
              viewId: t.view.viewId,
              state: ViewFocusState.unfocused,
              direction: ViewFocusDirection.undefined));
        case 'inactive':
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        case 'reload':
          final reassemble = t.binding.reassembleApplication();
          await t.pump();
          await reassemble;
        case 'hover':
          // Recover on the global route even after the hit-test stream was lost.
          t.binding.pointerRouter.route(PointerHoverEvent(
              pointer: 91, kind: PointerDeviceKind.stylus, position: at));
      }
      await t.pump();
      expect(key.currentState!.drawing, isFalse);
      expect(key.currentState!.strokes, hasLength(1));
      t.binding.handleViewFocusChanged(ViewFocusEvent(
          viewId: t.view.viewId,
          state: ViewFocusState.focused,
          direction: ViewFocusDirection.undefined));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pen.up();
      final next =
          await t.startGesture(at, pointer: 92, kind: PointerDeviceKind.stylus);
      await next.moveBy(const Offset(20, 10));
      await next.up();
      await t.pump();
      expect(key.currentState!.strokes, hasLength(2));
      expect(key.currentState!.drawing, isFalse);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('closing the pad during writing ignores a late release',
      (t) async {
    final key = GlobalKey<HandwritingPadState>();
    await t.pumpWidget(host(key));
    await t.pump();
    final pen = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('handwriting-pad'))),
        kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(10, 10));
    await t.pumpWidget(const SizedBox());
    await pen.up();
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
