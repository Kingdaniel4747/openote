import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// App-local Windows touch packets, including the hardware's confidence flag.
/// The native runner consumes these packets only after this handler is ready;
/// pen and mouse continue through Flutter's engine unchanged.
class WindowsTouchInput {
  WindowsTouchInput({required this.dispatch, required this.view});

  static const channel = MethodChannel('openote/windows_touch_input');
  final void Function(PointerEvent event, bool intended) dispatch;
  final FlutterView Function() view;
  final _contacts = <int, PointerEvent>{};
  int _nextPointer = -1; // Engine-generated pointers are nonnegative.

  Future<void> attach() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pointer') handlePacket(call.arguments);
    });
    try {
      await channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // Older runners and widget tests retain the engine transport.
    } on PlatformException {
      // A failed native attachment must not disable ordinary touch input.
    }
  }

  void handlePacket(Object? packet) {
    if (packet is! Map) return;
    final id = packet['id'];
    final phase = packet['phase'];
    if (id is! int || phase is! int || phase < 0 || phase > 3) return;
    final currentView = view();
    final ratio = currentView.devicePixelRatio;
    final x = packet['x'], y = packet['y'];
    if (x is! num || y is! num) return;
    final position = Offset(x.toDouble(), y.toDouble()) / ratio;
    final width = (packet['width'] as num?)?.toDouble() ?? 0;
    final height = (packet['height'] as num?)?.toDouble() ?? 0;
    final radius = math.max(width, height) / (2 * ratio);
    final time = Duration(milliseconds: (packet['time'] as int?) ?? 0);
    final intended = packet['intended'] == true;
    final previous = _contacts[id];
    if (phase == 0) {
      if (previous != null) {
        dispatch(
            PointerCancelEvent(
                viewId: previous.viewId,
                pointer: previous.pointer,
                device: previous.device,
                kind: PointerDeviceKind.touch,
                position: previous.position,
                timeStamp: time),
            false);
      }
      final down = PointerDownEvent(
          viewId: currentView.viewId,
          pointer: _nextPointer--,
          device: -id - 1,
          kind: PointerDeviceKind.touch,
          position: position,
          radiusMajor: radius,
          radiusMinor: math.min(width, height) / (2 * ratio),
          timeStamp: time);
      _contacts[id] = down;
      dispatch(down, intended);
    } else if (previous != null) {
      final PointerEvent event;
      if (phase == 1) {
        event = PointerMoveEvent(
            viewId: previous.viewId,
            pointer: previous.pointer,
            device: previous.device,
            kind: PointerDeviceKind.touch,
            position: position,
            delta: position - previous.position,
            radiusMajor: radius,
            radiusMinor: math.min(width, height) / (2 * ratio),
            timeStamp: time);
        _contacts[id] = event;
      } else {
        _contacts.remove(id);
        event = phase == 2
            ? PointerUpEvent(
                viewId: previous.viewId,
                pointer: previous.pointer,
                device: previous.device,
                kind: PointerDeviceKind.touch,
                position: position,
                timeStamp: time)
            : PointerCancelEvent(
                viewId: previous.viewId,
                pointer: previous.pointer,
                device: previous.device,
                kind: PointerDeviceKind.touch,
                position: position,
                timeStamp: time);
      }
      dispatch(event, intended);
    }
  }
}
