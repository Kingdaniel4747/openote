import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/windows_touch_input.dart';
import 'package:openote/canvas/writing_touch_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows palm confidence prevents a tap outside writing context',
      (tester) async {
    final delivered = <PointerEvent>[];
    final guard = WritingTouchGuard(dispatch: delivered.add);
    final input = WindowsTouchInput(
        dispatch: guard.handleNativeTouch, view: () => tester.view);
    addTearDown(guard.detach);
    input.handlePacket(packet(1, 0, intended: false));
    input.handlePacket(packet(1, 2, intended: false));
    await tester.pump(const Duration(milliseconds: 200));
    expect(delivered, isEmpty);
  });

  testWidgets('confidence loss cancels a swipe and cannot recover until lift',
      (tester) async {
    final delivered = <PointerEvent>[];
    final guard = WritingTouchGuard(dispatch: delivered.add)
      ..navigationTarget = (_) => true;
    final input = WindowsTouchInput(
        dispatch: guard.handleNativeTouch, view: () => tester.view);
    addTearDown(guard.detach);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    input.handlePacket(packet(1, 0));
    for (final x in [10.0, 20.0, 30.0]) {
      input.handlePacket(packet(1, 1, x: x));
    }
    input.handlePacket(packet(1, 1, x: 35, intended: false));
    input.handlePacket(packet(1, 1, x: 60));
    input.handlePacket(packet(1, 2, x: 60));
    expect(delivered.whereType<PointerCancelEvent>(), hasLength(1));
    expect(delivered.whereType<PointerUpEvent>(), isEmpty);
    expect(delivered.whereType<PointerMoveEvent>().last.position.dx, 30);
  });

  testWidgets('fresh Windows finger can pan while the pen and palm are down',
      (tester) async {
    final delivered = <PointerEvent>[];
    final guard = WritingTouchGuard(dispatch: delivered.add)
      ..navigationTarget = (_) => true;
    final input = WindowsTouchInput(
        dispatch: guard.handleNativeTouch, view: () => tester.view);
    addTearDown(guard.detach);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    input.handlePacket(packet(1, 0, intended: false));
    guard.handle(
        const PointerDownEvent(pointer: 99, kind: PointerDeviceKind.stylus));
    input.handlePacket(packet(2, 0));
    for (final x in [10.0, 20.0, 30.0]) {
      input.handlePacket(packet(2, 1, x: x));
    }
    final fingers = delivered.where((e) => e.kind == PointerDeviceKind.touch);
    expect(fingers.whereType<PointerDownEvent>(), hasLength(1));
    expect(guard.isNavigationPointer(fingers.first.pointer), isTrue);
    guard.setPenInRange(true);
    expect(delivered.whereType<PointerCancelEvent>(), isEmpty);
  });

  testWidgets(
      'transport scales position and contact area and renews reused IDs',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    final events = <PointerEvent>[];
    final input = WindowsTouchInput(
        dispatch: (e, _) => events.add(e), view: () => tester.view);
    input.handlePacket(packet(7, 0, x: 100));
    input.handlePacket(packet(7, 1, x: 120));
    input.handlePacket(packet(7, 2, x: 120));
    input.handlePacket(packet(7, 0, x: 200));
    expect(events.first.position, const Offset(50, 50));
    expect(events.first.radiusMajor, 5);
    expect(events[1].delta, const Offset(10, 0));
    expect(events.last.pointer, isNot(events.first.pointer));
    expect(events.last.device, events.first.device);
  });

  testWidgets('ordinary native touch retains immediate down and long presses',
      (tester) async {
    final delivered = <PointerEvent>[];
    final guard = WritingTouchGuard(dispatch: delivered.add);
    final input = WindowsTouchInput(
        dispatch: guard.handleNativeTouch, view: () => tester.view);
    addTearDown(guard.detach);
    input.handlePacket(packet(1, 0));
    expect(delivered.single, isA<PointerDownEvent>());
    await tester.pump(const Duration(seconds: 1));
    input.handlePacket({...packet(1, 2), 'time': 2000});
    expect(delivered.last, isA<PointerUpEvent>());
  });

  testWidgets('enlarging native contact cancels only that contact',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final delivered = <PointerEvent>[];
    final guard = WritingTouchGuard(dispatch: delivered.add);
    final input = WindowsTouchInput(
        dispatch: guard.handleNativeTouch, view: () => tester.view);
    addTearDown(guard.detach);
    input.handlePacket(packet(1, 0));
    input.handlePacket(packet(2, 0));
    input.handlePacket({...packet(1, 1), 'width': 100.0});
    input.handlePacket(packet(1, 2));
    input.handlePacket(packet(2, 2));
    expect(delivered.whereType<PointerCancelEvent>(), hasLength(1));
    expect(delivered.whereType<PointerUpEvent>(), hasLength(1));
    expect(delivered.last.device, -3);
  });
}

Map<String, Object> packet(int id, int phase,
        {bool intended = true, double x = 0}) =>
    {
      'id': id,
      'phase': phase,
      'x': x,
      'y': 100.0,
      'width': 20.0,
      'height': 12.0,
      'intended': intended,
      'time': 1000,
    };
