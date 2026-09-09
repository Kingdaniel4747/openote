import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// First-party pan/zoom (Tech Eval §7.3: own transform, no InteractiveViewer).
/// Maps between screen space and page space. The page origin stays in the
/// upper-left corner, so the canvas cannot drift into an empty margin.
class CanvasController extends ChangeNotifier {
  double scale = 1.0;
  Offset offset = Offset.zero; // page-space origin's screen position

  static const minScale = 0.15;
  static const maxScale = 8.0;
  Timer? _leadingBounce;

  /// Whether the page is currently pulled past its natural top/left origin.
  /// Kept here rather than inferred by a gesture recognizer so touch, mouse
  /// and precision-touchpad releases all settle the exact same state.
  bool get hasLeadingOverscroll => offset.dx > .01 || offset.dy > .01;

  Matrix4 get matrix => Matrix4.identity()
    ..translate(offset.dx, offset.dy)
    ..scale(scale);

  Offset screenToPage(Offset screen) => (screen - offset) / scale;
  Offset pageToScreen(Offset page) => page * scale + offset;

  void panBy(Offset delta, {bool elasticLeading = false}) {
    _leadingBounce?.cancel();
    if (elasticLeading) {
      double resisted(double current, double movement) {
        if (movement <= 0) return current + movement;
        // The farther the page is already pulled beyond its upper/left edge,
        // the more each additional pixel resists. This remains screen-space,
        // so it feels identical at every zoom level.
        final pulled = math.max(0.0, current);
        // Start soft enough to communicate an edge, then grow distinctly
        // heavier. The old .35 multiplier made touch feel like it had simply
        // hit a slow wall; this keeps the pull visible before the spring.
        return current + movement * .62 / (1 + pulled / 92);
      }

      offset = Offset(
        resisted(offset.dx, delta.dx),
        resisted(offset.dy, delta.dy),
      );
    } else {
      offset += delta;
    }
    _resetRunwayAtMinimumZoom();
    clampToPage(allowLeadingOverscroll: elasticLeading);
    notifyListeners();
  }

  /// Zoom keeping the given screen point fixed (style guide §8.2).
  void zoomAt(Offset screenFocal, double factor) {
    transformAt(screenFocal, factor, Offset.zero);
  }

  /// Apply one pan/zoom frame and repaint once. Trackpads used to notify after
  /// zoom and again after pan, rebuilding a populated page twice per event.
  void transformAt(
    Offset screenFocal,
    double factor,
    Offset panDelta, {
    bool clamp = true,
  }) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final pageFocal = screenToPage(screenFocal);
    scale = newScale;
    offset = screenFocal - pageFocal * scale + panDelta;
    _resetRunwayAtMinimumZoom();
    if (clamp) clampToPage();
    notifyListeners();
  }

  /// Apply a two-finger zoom around the fingers. This uses the same focal-point
  /// invariant as mouse-wheel zoom; the previous special top/left pinning made
  /// every zoom-in push content down and every zoom-out pull it up.
  void transformPinchAt(
    Offset previousFocal,
    double factor,
    Offset currentFocal,
  ) {
    final pageFocal = screenToPage(previousFocal);
    final newScale = (scale * factor).clamp(minScale, maxScale);
    scale = newScale;
    offset = currentFocal - pageFocal * newScale;
    _resetRunwayAtMinimumZoom();
    clampToPage();
    notifyListeners();
  }

  /// Resolve a touch pinch from one immutable gesture-start snapshot.
  ///
  /// Touchscreens report the two contacts as separate pointer events. Applying
  /// an incremental transform for each event alternates between one fresh and
  /// one stale contact and accumulates a visible vertical jump. Recomputing
  /// from the start values makes the result independent of event ordering.
  void transformGestureFrom({
    required double startScale,
    required Offset startOffset,
    required Offset startFocal,
    required Offset currentFocal,
    required double scaleFactor,
  }) {
    final pageFocal = (startFocal - startOffset) / startScale;
    scale = (startScale * scaleFactor).clamp(minScale, maxScale);
    // Keep the page point below the fingers fixed, including when the gesture
    // starts at the top-left origin. Pinning that origin to zero made every
    // zoom-in visibly jump away from the fingers.
    offset = currentFocal - pageFocal * scale;
    _resetRunwayAtMinimumZoom();
    clampToPage();
    notifyListeners();
  }

  /// Restore an exact view (used by PDF export).
  void jumpTo(double s, Offset o) {
    scale = s;
    offset = o;
    notifyListeners();
  }

  void reset() {
    scale = 1.0;
    offset = Offset.zero; // page anchored top-left (OneNote-like)
    clampToPage();
    notifyListeners();
  }

  /// Last known viewport size (set by the canvas widget each layout).
  Size viewport = Size.zero;

  /// Current page-surface size in page coords. An ordinary canvas can keep a
  /// larger virtual runway the user has travelled into; paper/PDF pages keep
  /// their real finite bounds.
  Size? _pageSize;
  Size? _minimumPageSize;
  bool _growsTrailingEdges = false;

  Size? get pageSize => _pageSize;
  set pageSize(Size? value) {
    _pageSize = value;
    _minimumPageSize = value;
    _growsTrailingEdges = false;
  }

  void setPageBounds(Size minimum, {required bool growsTrailingEdges}) {
    _minimumPageSize = minimum;
    _growsTrailingEdges = growsTrailingEdges;
    final current = _pageSize;
    _pageSize =
        !growsTrailingEdges || current == null || scale <= minScale + .001
        ? minimum
        : Size(
            math.max(minimum.width, current.width),
            math.max(minimum.height, current.height),
          );
  }

  void resetPageBounds() {
    _pageSize = null;
    _minimumPageSize = null;
    _growsTrailingEdges = false;
  }

  /// Keep the page origin at upper-left. A small, zoomed-out page also stays
  /// there rather than floating inside the viewport.
  void clampToPage({bool allowLeadingOverscroll = false}) {
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) return;
    if (_growsTrailingEdges) _growTrailingRunway(offset);
    double axis(double o, double vp, double contentPx) {
      if (allowLeadingOverscroll && o > 0) return o.clamp(0.0, 132.0);
      if (contentPx <= vp) return 0.0;
      return o.clamp(vp - contentPx, 0.0);
    }

    offset = Offset(
      axis(offset.dx, viewport.width, ps.width * scale),
      axis(offset.dy, viewport.height, ps.height * scale),
    );
  }

  void _growTrailingRunway(Offset candidate) {
    final current = _pageSize;
    if (current == null || scale <= minScale + .001) return;
    // Keep roughly one screen beyond the camera, so writing at the former
    // right/bottom edge never feels like hitting a wall.
    const runwayPx = 640.0;
    final neededWidth = (viewport.width - candidate.dx + runwayPx) / scale;
    final neededHeight = (viewport.height - candidate.dy + runwayPx) / scale;
    if (neededWidth > current.width || neededHeight > current.height) {
      _pageSize = Size(
        math.max(current.width, neededWidth),
        math.max(current.height, neededHeight),
      );
    }
  }

  void _resetRunwayAtMinimumZoom() {
    // At the fully zoomed-out overview an unlimited surface must have an end.
    // The runway returns to actual content; zooming in and travelling onward
    // creates it again naturally.
    if (_growsTrailingEdges && scale <= minScale + .001) {
      _pageSize = _minimumPageSize;
    }
  }

  /// Apply the page boundary once after a gesture has finished, rather than
  /// during every pinch sample where it would move content away from fingers.
  void settleToPage() {
    clampToPage();
    notifyListeners();
  }

  /// Release the top/left pull with a short, contained spring. It never runs
  /// during a pinch transform, so the stable finger-anchored zoom path cannot
  /// be affected by the visual affordance.
  void springLeadingEdge() {
    final start = offset;
    if (start.dx <= 0 && start.dy <= 0) return;
    _leadingBounce?.cancel();
    final began = DateTime.now();
    _leadingBounce = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final t = (DateTime.now().difference(began).inMilliseconds / 300).clamp(
        0.0,
        1.0,
      );
      // One clear, contained overshoot sells the elastic edge without letting
      // the page visibly oscillate under a pen or a pinch gesture.
      final factor =
          math.pow(1 - t, 1.35).toDouble() * math.cos(t * math.pi * 2.25);
      offset = Offset(
        start.dx > 0 ? start.dx * factor : start.dx,
        start.dy > 0 ? start.dy * factor : start.dy,
      );
      if (t >= 1) {
        offset = Offset(
          start.dx > 0 ? 0 : offset.dx,
          start.dy > 0 ? 0 : offset.dy,
        );
        timer.cancel();
        if (identical(_leadingBounce, timer)) _leadingBounce = null;
      }
      notifyListeners();
    });
  }

  /// Initial view: page anchored top-left, filling the window (the page is at
  /// least viewport-wide, so no backdrop shows in normal use). Zooming out
  /// later reveals the page bounds — "a page that can become a canvas."
  void centerPage() {
    scale = 1.0;
    offset = Offset.zero;
    clampToPage();
    notifyListeners();
  }

  /// Fit [contentWidth] page-px to the viewport width, anchored top-left. Only
  /// zooms OUT (never past 100%), so a narrow page keeps its natural size while
  /// a wide imported page reveals its full width — including images placed to
  /// the right of the text at their original OneNote offsets, which otherwise
  /// sit off-screen at 100%. Vertical position stays at the top (scroll down
  /// for the rest), so text stays readable rather than shrinking to fit height.
  void fitWidth(double contentWidth) {
    if (viewport == Size.zero || contentWidth <= 0) {
      centerPage();
      return;
    }
    const pad = 24.0;
    final needed = contentWidth + pad;
    scale = needed <= viewport.width
        ? 1.0
        : (viewport.width / needed).clamp(minScale, 1.0);
    offset = Offset.zero;
    clampToPage();
    notifyListeners();
  }

  /// Center a page-space point in the viewport (find, navigation).
  void centerOn(Offset pagePoint) {
    offset =
        Offset(viewport.width / 2, viewport.height / 2) - pagePoint * scale;
    clampToPage();
    notifyListeners();
  }

  void setZoom(double newScale) {
    zoomAt(Offset(viewport.width / 2, viewport.height / 2), newScale / scale);
  }

  /// Zoom-to-fit a page-space rectangle (style guide §8.2).
  void fitTo(Rect pageBounds) {
    if (viewport == Size.zero || pageBounds.isEmpty) {
      reset();
      return;
    }
    final sx = viewport.width / pageBounds.width;
    final sy = viewport.height / pageBounds.height;
    scale = (sx < sy ? sx : sy).clamp(minScale, maxScale);
    // An overview stays attached to the title corner instead of recentring
    // everything around one distant block on the right or below.
    offset = Offset(-pageBounds.left * scale, -pageBounds.top * scale);
    clampToPage();
    notifyListeners();
  }
}
