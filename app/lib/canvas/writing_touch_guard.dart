import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Filter before hit testing: a child Listener has already received a palm
/// by the time a parent Listener could reject it (including window buttons).
mixin WritingTouchBinding on GestureBinding {
  late final writingTouchGuard = WritingTouchGuard(
    dispatch: super.handlePointerEvent,
    enabled: Platform.isWindows,
  );

  @override
  void handlePointerEvent(PointerEvent event) =>
      writingTouchGuard.handle(event);
}

class OpenoteWidgetsBinding extends WidgetsFlutterBinding
    with WritingTouchBinding {}

class _TouchCandidate {
  _TouchCandidate(this.down);
  final PointerDownEvent down;
  PointerMoveEvent? last;
  int moves = 0;
  double path = 0;
  Offset get position => last?.position ?? down.position;
  double get distance => (position - down.position).distance;
}

/// Automatic pen priority, with fresh, deliberate finger gestures still allowed.
/// Old palms stay rejected until lift; they never become the third pinch finger.
class WritingTouchGuard {
  WritingTouchGuard(
      {required this.dispatch, this.enabled = true, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final void Function(PointerEvent) dispatch;
  final DateTime Function() _now;
  bool enabled;
  bool Function()? writingContext;
  bool Function(PointerDownEvent)? navigationTarget;
  final _touches = <int, PointerEvent>{};
  final _candidates = <int, _TouchCandidate>{};
  final _rejected = <int>{};
  final _navigation = <int>{};
  final _penContacts = <int>{};
  final _tapTimers = <Timer>{};
  bool _nativeInRange = false;
  DateTime? _lastPen;

  static const penGrace = Duration(milliseconds: 900);
  bool get _recentPen =>
      _nativeInRange ||
      _penContacts.isNotEmpty ||
      (_lastPen != null && _now().difference(_lastPen!) < penGrace);
  bool isNavigationPointer(int pointer) => _navigation.contains(pointer);

  void setPenInRange(bool value) {
    if (value && !_nativeInRange && enabled) _rejectExisting();
    if (value || _nativeInRange) _lastPen = _now();
    if (!value && _nativeInRange) _penContacts.clear();
    _nativeInRange = value;
  }

  void detach() {
    _rejected.addAll(_candidates.keys);
    _candidates.clear();
    writingContext = null;
    navigationTarget = null;
    _nativeInRange = false;
    _lastPen = null;
    _penContacts.clear();
    _cancelTaps();
  }

  void _cancelTaps() {
    for (final timer in _tapTimers) {
      timer.cancel();
    }
    _tapTimers.clear();
  }

  void _rejectExisting() {
    _cancelTaps();
    _rejected.addAll(_candidates.keys);
    _candidates.clear();
    final contacts = _touches.values.toList(growable: false);
    _touches.clear();
    for (final event in contacts) {
      _rejected.add(event.pointer);
      dispatch(PointerCancelEvent(
          pointer: event.pointer,
          device: event.device,
          kind: PointerDeviceKind.touch,
          position: event.position,
          viewId: event.viewId,
          timeStamp: event.timeStamp));
      _navigation.remove(event.pointer);
    }
  }

  void _reject(int pointer) {
    _candidates.remove(pointer);
    _rejected.add(pointer);
  }

  bool _onSurface(_TouchCandidate candidate) =>
      navigationTarget?.call(candidate.down) == true;

  void _recognizeNavigation() {
    final fingers = _candidates.values
        .where((candidate) => candidate.distance >= 4 && _onSurface(candidate))
        .toList();
    List<_TouchCandidate>? confirmed;
    if (fingers.length == 2) {
      final a = fingers[0], b = fingers[1];
      final span = (a.down.position - b.down.position).distance;
      final gap = (a.down.timeStamp - b.down.timeStamp).abs();
      if (span >= 24 &&
          span <= 500 &&
          gap <= const Duration(milliseconds: 300) &&
          a.distance >= 8 &&
          b.distance >= 8 &&
          a.moves + b.moves >= 4) {
        confirmed = fingers;
      }
    } else if (fingers.length == 1) {
      final finger = fingers.single;
      if (finger.moves >= 3 &&
          finger.distance >= 24 &&
          finger.distance >= finger.path * .8) {
        confirmed = fingers;
      }
    }
    if (confirmed == null) return;
    // Publish IDs before replay so the canvas can distinguish these new fingers
    // from a resting palm, even while the lifted pen is still hovering.
    for (final finger in confirmed) {
      _navigation.add(finger.down.pointer);
      _candidates.remove(finger.down.pointer);
      _touches[finger.down.pointer] = finger.last ?? finger.down;
    }
    for (final finger in confirmed) {
      dispatch(finger.down);
    }
    for (final finger in confirmed) {
      if (finger.last != null) dispatch(finger.last!);
    }
  }

  void _finishCandidate(_TouchCandidate candidate, PointerEvent event) {
    _candidates.remove(event.pointer);
    if (event is! PointerUpEvent ||
        candidate.distance > 6 ||
        candidate.path > 8 ||
        event.timeStamp - candidate.down.timeStamp >
            const Duration(milliseconds: 500) ||
        _recentPen) {
      return;
    }
    // A hand often lands before the nib. Give an impending pen contact a short
    // chance to cancel a touch tap, without delaying pen input or finger swipes.
    late Timer timer;
    timer = Timer(const Duration(milliseconds: 120), () {
      _tapTimers.remove(timer);
      if (_recentPen) return;
      dispatch(candidate.down);
      dispatch(event);
    });
    _tapTimers.add(timer);
  }

  void handle(PointerEvent event) {
    if (!enabled) {
      dispatch(event);
      return;
    }
    final pen = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (pen) {
      final approaching = !_recentPen;
      _lastPen = _now();
      if (approaching || event is PointerDownEvent) _rejectExisting();
      if (event is PointerDownEvent) _penContacts.add(event.pointer);
      if (event is PointerUpEvent ||
          event is PointerCancelEvent ||
          event is PointerRemovedEvent) {
        _penContacts.remove(event.pointer);
      }
      dispatch(event);
      return;
    }
    if (event is PointerSignalEvent && _penContacts.isNotEmpty) return;
    if (event.kind != PointerDeviceKind.touch) {
      dispatch(event);
      return;
    }
    final end = event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerRemovedEvent;
    if (_rejected.contains(event.pointer)) {
      if (end) _rejected.remove(event.pointer);
      return;
    }
    if (event is PointerDownEvent) {
      if (_penContacts.isNotEmpty ||
          _navigation.length >= 2 ||
          event.radiusMajor > 26) {
        _reject(event.pointer);
        return;
      }
      if (_recentPen || writingContext?.call() == true) {
        _candidates[event.pointer] = _TouchCandidate(event);
        return;
      }
      _touches[event.pointer] = event;
    }
    final candidate = _candidates[event.pointer];
    if (candidate != null) {
      if (end) {
        _finishCandidate(candidate, event);
      } else if (event is PointerMoveEvent) {
        final delta = (event.position - candidate.position).distance;
        final age = event.timeStamp - candidate.down.timeStamp;
        if (event.radiusMajor > 26 ||
            delta > 100 ||
            (candidate.moves == 0 && age > const Duration(milliseconds: 500))) {
          _reject(event.pointer);
        } else {
          candidate.path += delta;
          candidate.last = event;
          candidate.moves++;
          _recognizeNavigation();
        }
      }
      return;
    }
    if (event is PointerMoveEvent && _touches.containsKey(event.pointer)) {
      if (event.radiusMajor > 26 ||
          (_navigation.contains(event.pointer) &&
              (event.position - _touches[event.pointer]!.position).distance >
                  100)) {
        _rejectExisting();
        return;
      }
      _touches[event.pointer] = event;
    }
    dispatch(event);
    if (end) {
      _touches.remove(event.pointer);
      _navigation.remove(event.pointer);
    }
  }
}
