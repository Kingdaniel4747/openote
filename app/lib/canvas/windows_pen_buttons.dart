import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Windows-only supplement to Flutter's unchanged position/pressure stream.
/// No global hooks, synthetic clicks or changes to the chosen drawing tool.
class WindowsPenButtons extends ChangeNotifier {
  WindowsPenButtons({bool? enabled}) : enabled = enabled ?? Platform.isWindows;

  static const channel = MethodChannel('openote/windows_pen_buttons');
  final bool enabled;
  bool nativeInRange = false;
  bool nativeEraser = false;
  bool _attached = false;
  int _revision = 0;

  Future<void> attach() async {
    if (!enabled || _attached) return;
    _attached = true;
    channel.setMethodCallHandler((call) async {
      if (_attached && call.method == 'state') _readState(call.arguments);
    });
    // A page can open while the same pen is already hovering with its button
    // held. Query once, rather than waiting for the native state to change.
    final revision = _revision;
    try {
      final state = await channel.invokeMethod<Object?>('getState');
      if (_attached && revision == _revision) _readState(state);
    } on MissingPluginException {
      // Widget tests/older Windows runners still use normal Flutter events.
    } on PlatformException {
      // A missing native supplement must never prevent ordinary handwriting.
    }
  }

  void _readState(Object? value) {
    if (value is! Map) return;
    _revision++;
    final inRange = value['inRange'] == true;
    final eraser = inRange && value['eraser'] == true;
    if (nativeInRange == inRange && nativeEraser == eraser) return;
    nativeInRange = inRange;
    nativeEraser = eraser;
    notifyListeners();
  }

  bool erases(PointerEvent event) {
    if (event.kind == PointerDeviceKind.invertedStylus) return true;
    if (event.kind != PointerDeviceKind.stylus) return false;
    final barrel = (event.buttons & kPrimaryStylusButton) != 0;
    // Preserve Linux exactly; the new secondary/native path is Windows.
    if (!enabled) return barrel;
    // Flutter can keep a button bit from pointer-down for the whole stroke.
    // A native release must win over that stale bit, not be OR-ed with it.
    if (nativeInRange) return nativeEraser;
    return barrel ||
        (event.buttons & kSecondaryStylusButton) != 0;
  }

  /// At the first contact a Galaxy S Pen can expose Flutter's barrel bit one
  /// event before Windows' raw-HID state arrives. Use it only to decide this
  /// new gesture; subsequent moves continue using [erases], where a live
  /// native release correctly wins over a stale Flutter button bit.
  bool erasesAtContact(PointerEvent event) {
    if (erases(event)) return true;
    if (!enabled || event.kind != PointerDeviceKind.stylus) return false;
    return (event.buttons & kPrimaryStylusButton) != 0 ||
        (event.buttons & kSecondaryStylusButton) != 0;
  }

  @override
  void dispose() {
    if (_attached) channel.setMethodCallHandler(null);
    _attached = false;
    super.dispose();
  }
}
