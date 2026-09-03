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
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
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
  Timer? _hideTimer;
  bool _visible = false;
  bool _hovering = false;
  double _dragDistance = 0;

  @override
  void initState() {
    super.initState();
    _window = widget.controller ?? WindowsWindowController();
    _window.addListener(_changed);
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

  void _changed() {
    if (mounted) setState(() {});
  }

  void _show() {
    _hideTimer?.cancel();
    setState(() => _visible = true);
    if (!_hovering) {
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_window.enabled) HardwareKeyboard.instance.removeHandler(_key);
    _window.removeListener(_changed);
    if (widget.controller == null) _window.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_window.enabled) return widget.child;
    return _WindowScope(
      controller: _window,
      // This frame is above the Navigator in MaterialApp.builder, so its
      // tooltips need their own overlay. The notebook keeps its own Navigator.
      child: Overlay.wrap(
          child: Stack(fit: StackFit.expand, children: [
        widget.child,
        if (_window.fullscreen)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _visible
                ? MouseRegion(
                    onEnter: (_) {
                      _hovering = true;
                      _hideTimer?.cancel();
                    },
                    onExit: (_) {
                      _hovering = false;
                      _show();
                    },
                    child: Listener(
                      onPointerDown: (_) => _hideTimer?.cancel(),
                      onPointerUp: (_) => _show(),
                      onPointerCancel: (_) => _show(),
                      child: Material(
                        elevation: 8,
                        color: Theme.of(context).colorScheme.surface,
                        child: SizedBox(
                            height: 48,
                            child: Row(children: [
                              Expanded(
                                  child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onDoubleTap: () => _window.setFullscreen(false),
                                child: const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 16),
                                    child: Text('Openote',
                                        style: TextStyle(fontSize: 14))),
                              )),
                              IconButton(
                                  tooltip: 'Hide window controls',
                                  onPressed: () {
                                    _hideTimer?.cancel();
                                    setState(() => _visible = false);
                                  },
                                  icon: const Icon(Icons.keyboard_arrow_up)),
                              IconButton(
                                  tooltip: 'Minimize',
                                  onPressed: _window.minimize,
                                  icon: const Icon(Icons.minimize)),
                              IconButton(
                                  tooltip: 'Exit full screen (F11)',
                                  onPressed: () => _window.setFullscreen(false),
                                  icon: const Icon(Icons.fullscreen_exit)),
                              IconButton(
                                  tooltip: 'Close Openote',
                                  onPressed: _window.close,
                                  icon: const Icon(Icons.close)),
                            ])),
                      ),
                    ),
                  )
                : MouseRegion(
                    onEnter: (_) => _show(),
                    child: GestureDetector(
                      key: const ValueKey('window-top-edge'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _show,
                      onVerticalDragStart: (_) => _dragDistance = 0,
                      onVerticalDragUpdate: (event) {
                        _dragDistance += event.delta.dy;
                        if (_dragDistance >= 12) _show();
                      },
                      child: Semantics(
                          label: 'Show window controls',
                          button: true,
                          child: SizedBox(
                              height: 12,
                              child: Center(
                                  child: Container(
                                width: 42,
                                height: 3,
                                decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                    borderRadius: BorderRadius.circular(2)),
                              )))),
                    ),
                  ),
          ),
      ])),
    );
  }
}
