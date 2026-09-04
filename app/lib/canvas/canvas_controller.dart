import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// First-party pan/zoom (Tech Eval §7.3: own transform, no InteractiveViewer).
/// Maps between screen space and page space. The model has a bounded overview
/// at minimum zoom: when the whole page fits, it may be positioned anywhere
/// inside the viewport; when it is larger, its edges bound the camera.
class CanvasController extends ChangeNotifier {
  double scale = 1.0;
  Offset offset = Offset.zero; // page-space origin's screen position

  static const minScale = 0.15;
  static const maxScale = 8.0;

  Matrix4 get matrix => Matrix4.identity()
    ..translate(offset.dx, offset.dy)
    ..scale(scale);

  Offset screenToPage(Offset screen) => (screen - offset) / scale;
  Offset pageToScreen(Offset page) => page * scale + offset;

  void panBy(Offset delta) {
    offset += delta;
    clampToPage();
    notifyListeners();
  }

  /// Zoom keeping the given screen point fixed (style guide §8.2).
  void zoomAt(Offset screenFocal, double factor) {
    transformAt(screenFocal, factor, Offset.zero);
  }

  /// Apply one pan/zoom frame and repaint once. Trackpads used to notify after
  /// zoom and again after pan, rebuilding a populated page twice per event.
  void transformAt(Offset screenFocal, double factor, Offset panDelta,
      {bool clamp = true}) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final pageFocal = screenToPage(screenFocal);
    scale = newScale;
    offset = screenFocal - pageFocal * scale + panDelta;
    if (clamp) clampToPage();
    notifyListeners();
  }

  /// Apply a two-finger zoom without making a visible page edge drift away
  /// from the window. Once an edge has scrolled off-screen, that axis instead
  /// follows the pinch focal point so the content remains under the fingers.
  ///
  /// Bounds are applied to each axis in this same transform frame. Previously
  /// the view was allowed outside the page until the fingers lifted, then was
  /// corrected by [settleToPage]. That delayed correction was the visible jump
  /// on every pinch, especially on a page containing PDF printouts.
  void transformPinchAt(
    Offset previousFocal,
    double factor,
    Offset currentFocal,
  ) {
    final pageFocal = screenToPage(previousFocal);
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final proposed = currentFocal - pageFocal * newScale;
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) {
      scale = newScale;
      offset = proposed;
    } else {
      final pinLeftEdge =
          offset.dx.abs() <= 0.5 && ps.width * scale >= viewport.width;
      final pinTopEdge =
          offset.dy.abs() <= 0.5 && ps.height * scale >= viewport.height;
      scale = newScale;

      double axis(double next, double viewportExtent, double contentExtent,
          bool pinOrigin) {
        // Keep the named edge in place once it is visible. If the gesture
        // reaches it from inside the page, stop at the edge in this frame —
        // never after the gesture has ended.
        final travel = viewportExtent - contentExtent;
        if (pinOrigin && travel <= 0) return 0;
        // With the entire page on screen, its origin may travel between the
        // two opposing edges. This is what lets a student zoom into the
        // upper-right of a fully zoomed-out endless page instead of being
        // pulled back to the left edge.
        return next.clamp(math.min(0, travel), math.max(0, travel));
      }

      offset = Offset(
        axis(proposed.dx, viewport.width, ps.width * scale, pinLeftEdge),
        axis(proposed.dy, viewport.height, ps.height * scale, pinTopEdge),
      );
    }
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

  /// Current page-surface size in page coords (set by the canvas each build);
  /// used to clamp panning so the page can't be lost (CANVAS-1 v0.3).
  Size? pageSize;

  /// Keep the camera within the page. When a page is smaller than the window,
  /// its origin can travel from one visible edge to the other, rather than
  /// being forced back to top-left; this makes the low-zoom overview useful.
  void clampToPage() {
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) return;
    double axis(double o, double vp, double contentPx) {
      final travel = vp - contentPx;
      return o.clamp(math.min(0, travel), math.max(0, travel));
    }

    offset = Offset(
      axis(offset.dx, viewport.width, ps.width * scale),
      axis(offset.dy, viewport.height, ps.height * scale),
    );
  }

  /// Apply the page boundary once after a gesture has finished, rather than
  /// during every pinch sample where it would move content away from fingers.
  void settleToPage() {
    clampToPage();
    notifyListeners();
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
    const pad = 48.0;
    final sx = (viewport.width - pad * 2) / pageBounds.width;
    final sy = (viewport.height - pad * 2) / pageBounds.height;
    scale = (sx < sy ? sx : sy).clamp(minScale, maxScale);
    offset = Offset(
      (viewport.width - pageBounds.width * scale) / 2 - pageBounds.left * scale,
      (viewport.height - pageBounds.height * scale) / 2 -
          pageBounds.top * scale,
    );
    notifyListeners();
  }
}
