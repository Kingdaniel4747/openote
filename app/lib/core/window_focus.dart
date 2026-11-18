/// User-requested activation of the running Openote window.
///
/// A second launch grants its foreground right before handing over a request.
/// The running process uses its own native window channel to show maximized;
/// older runners fall back to Win32 window lookup. Background MCP reads never
/// activate or resize the window. Other platforms leave this to the desktop.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

abstract final class WindowFocus {
  /// The class the Flutter Windows runner registers for its top-level window
  /// (`windows/runner/win32_window.cpp`), and the title `wWinMain` gives it
  /// (`windows/runner/main.cpp`). Matched together: the class alone would find
  /// ANY Flutter desktop app's window, and raising somebody else's app is a
  /// worse bug than not raising ours.
  static const _windowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
  static const _windowTitles = ['openote', 'Openote'];

  static const int _swShowMaximized = 3;
  static const channel = MethodChannel('openote/window_controls');

  /// `ASFW_ANY` — `(DWORD)-1`.
  static const int _asfwAny = 0xFFFFFFFF;

  /// Called by the process that is about to hand its work to the running
  /// Openote and exit.
  ///
  /// Windows refuses `SetForegroundWindow` from a process that did not
  /// recently receive user input — the anti-focus-stealing rule. A process the
  /// user just launched by double-clicking a file DOES have that right, and
  /// this is the documented way to pass it on. Without it the running Openote
  /// switches notebooks correctly and its taskbar button merely blinks, which
  /// reads exactly like nothing happening.
  static bool allowForegroundHandover() {
    if (!Platform.isWindows) return false;
    try {
      return _allowSetForegroundWindow(_asfwAny) != 0;
    } catch (_) {
      return false;
    }
  }

  /// Called for an explicit launch request, never for background MCP reads.
  /// Maximize the current process's own window before bringing it forward.
  static Future<bool> raiseSelf() async {
    if (!Platform.isWindows) return false;
    try {
      await channel.invokeMethod<void>('ensureMaximized');
      await channel.invokeMethod<void>('show');
      return true;
    } on MissingPluginException {
      // Older runners can still be activated through Win32 below.
    } on PlatformException {
      // Best effort: the notebook request must remain usable.
    }
    try {
      final hwnd = _findOpenoteWindow();
      if (hwnd == 0) return false;
      _showWindow(hwnd, _swShowMaximized);
      return _setForegroundWindow(hwnd) != 0;
    } catch (_) {
      // A missing user32 export or a hostile window manager must never take
      // the app down; the notebook has already been switched by this point.
      return false;
    }
  }

  static int _findOpenoteWindow() {
    final cls = _windowClass.toNativeUtf16();
    try {
      for (final title in _windowTitles) {
        final name = title.toNativeUtf16();
        try {
          final hwnd = _findWindowW(cls, name);
          if (hwnd != 0) return hwnd;
        } finally {
          calloc.free(name);
        }
      }
      return 0;
    } finally {
      calloc.free(cls);
    }
  }

  // Resolved lazily, exactly as `PlatformOpen` resolves shell32: a top-level
  // `DynamicLibrary.open('user32.dll')` would run on Linux the moment anything
  // in this library is touched.
  static DynamicLibrary get _user32 => DynamicLibrary.open('user32.dll');

  static final _findWindowW = _user32.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');

  static final _setForegroundWindow = _user32.lookupFunction<
      Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');

  static final _showWindow = _user32.lookupFunction<Int32 Function(IntPtr, Int32),
      int Function(int, int)>('ShowWindow');

  static final _allowSetForegroundWindow = _user32.lookupFunction<
      Int32 Function(Uint32), int Function(int)>('AllowSetForegroundWindow');
}
