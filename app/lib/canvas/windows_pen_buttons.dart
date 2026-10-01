import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Windows-only supplement to Flutter's unchanged position/pressure stream.
/// No global hooks, synthetic clicks or changes to the chosen drawing tool.
class WindowsPenButtons extends ChangeNotifier {
  WindowsPenButtons({bool? enabled}) : enabled = enabled ?? Platform.isWindows;

  static const channel = MethodChannel('openote/windows_pen_buttons');
  static final Set<WindowsPenButtons> _clients = {};
  static bool _handlerInstalled = false;
  final bool enabled;
  bool nativeInRange = false;
  bool nativeEraser = false;
  bool _nativeReady = false;
  bool _attached = false;
  int _revision = 0;

  Future<void> attach() async {
    if (!enabled || _attached) return;
    _attached = true;
    _clients.add(this);
    if (!_handlerInstalled) {
      _handlerInstalled = true;
      channel.setMethodCallHandler((call) async {
        if (call.method != 'state') return;
        // PageCanvas is keyed by page id, so an old and a new page can briefly
        // overlap during a switch. One process-wide handler fans the native
        // state out to every live page; disposing the old page can no longer
        // unregister the new page's handler.
        for (final client in _clients.toList(growable: false)) {
          if (client._attached) client._readState(call.arguments);
        }
      });
    }
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
    _nativeReady = true;
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
    // Windows owns the barrel-button state once its channel answers. Flutter
    // can keep a stale bit for an entire contact and must never re-enable the
    // eraser after the physical button has been released.
    if (_nativeReady) return nativeEraser;
    return barrel || (event.buttons & kSecondaryStylusButton) != 0;
  }

  /// Use the same authority on pointer-down as on every later move. Mixing a
  /// Flutter bit on down with native state on move made one continuous contact
  /// alternate between eraser and pen.
  bool erasesAtContact(PointerEvent event) {
    return erases(event);
  }

  @override
  void dispose() {
    _clients.remove(this);
    _attached = false;
    if (_clients.isEmpty && _handlerInstalled) {
      _handlerInstalled = false;
      channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}
