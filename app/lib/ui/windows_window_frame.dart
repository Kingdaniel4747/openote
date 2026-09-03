import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A small native bridge; Linux continues to use its normal desktop frame.
class WindowsWindowController extends ChangeNotifier {
  WindowsWindowController({bool? enabled})
      : enabled = enabled ?? Platform.isWindows;
  static const channel = MethodChannel('openote/window_controls');
  final bool enabled;
  bool fullscreen = false;
  bool _disposed = false;
  bool closing = false;
  Future<void> _pending = Future.value();

  Future<void> setFullscreen(bool value) {
    if (!enabled || _disposed) return Future.value();
    // Serialize fast F11/button presses so the final native and Flutter state
    // agree. A missing bridge (tests/old runners) leaves the normal frame alone.
    return _pending = _pending.then((_) async {
      if (_disposed) return;
      try {
        final result = await channel.invokeMethod<bool>('setFullscreen', value);
        if (_disposed) return;
        fullscreen = result ?? false;
        notifyListeners();
      } on MissingPluginException {
        // No custom frame: keep the OS caption and close button.
      } on PlatformException {
        // Keep the last confirmed state if Windows rejects the transition.
      }
    });
  }

  Future<void> minimize() async {
    if (!enabled) return;
    try {
      await channel.invokeMethod<void>('minimize');
    } on MissingPluginException {
      // Older runners retain the native minimize button.
    } on PlatformException {
      // A failed minimize must not close or discard the notebook.
    }
  }

  Future<void> close() async {
    // Same lifecycle request as the native close button. In particular, await
    // OpenoteBoot's app.shutdown() before exiting: never terminate the process.
    if (closing || _disposed) return;
    closing = true;
    notifyListeners();
    try {
      await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
    } finally {
      closing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class WindowsWindowFrame extends StatefulWidget {
  const WindowsWindowFrame(
      {super.key,
      required this.child,
      required this.startFullscreen,
      this.controller});
  final Widget child;
  final bool startFullscreen;
  final WindowsWindowController? controller;

  static WindowsWindowController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WindowScope>()?.controller;

  @override
  State<WindowsWindowFrame> createState() => _WindowsWindowFrameState();
}

class _WindowScope extends InheritedWidget {
  const _WindowScope({required this.controller, required super.child});
  final WindowsWindowController controller;
  @override
  bool updateShouldNotify(_WindowScope oldWidget) =>
      controller != oldWidget.controller;
}

class _WindowsWindowFrameState extends State<WindowsWindowFrame> {
  late final WindowsWindowController _window;

  @override
  void initState() {
    super.initState();
    _window = widget.controller ?? WindowsWindowController();
    if (_window.enabled) {
      HardwareKeyboard.instance.addHandler(_key);
      unawaited(_window.setFullscreen(widget.startFullscreen));
    }
  }

  bool _key(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.f11) return false;
    if (event is KeyDownEvent) {
      unawaited(_window.setFullscreen(!_window.fullscreen));
    }
    return true;
  }

  @override
  void dispose() {
    if (_window.enabled) HardwareKeyboard.instance.removeHandler(_key);
    if (widget.controller == null) _window.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _window.enabled
      ? _WindowScope(controller: _window, child: widget.child)
      : widget.child;
}

/// Permanently beside Settings, inside the Navigator's normal overlay. No
/// hover/swipe activation, no floating strip that can cover the drawing tools.
class WindowsCaptionButtons extends StatelessWidget {
  const WindowsCaptionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final window = WindowsWindowFrame.of(context);
    if (window == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: window,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        _button('Minimize', Icons.minimize, window.minimize),
        _button(
            window.fullscreen ? 'Exit full screen (F11)' : 'Full screen (F11)',
            window.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            () => window.setFullscreen(!window.fullscreen)),
        window.closing
            ? const SizedBox(
                width: 36,
                height: 32,
                child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : _button('Close Openote', Icons.close, window.close),
      ]),
    );
  }

  Widget _button(String label, IconData icon, VoidCallback pressed) => SizedBox(
        width: 36,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: label,
          icon: Icon(icon, size: 18),
          onPressed: pressed,
        ),
      );
}
