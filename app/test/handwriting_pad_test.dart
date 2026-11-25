import 'dart:io';

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
}
