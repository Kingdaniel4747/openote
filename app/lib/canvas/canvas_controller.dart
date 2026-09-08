import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// First-party pan/zoom (Tech Eval §7.3: own transform, no InteractiveViewer).
/// Maps between screen space and page space.
///
/// The open canvas has a firm origin at the top/left and an elastic edge there,
/// while its right/bottom extent grows ahead of the camera. PDF and paged
/// documents can opt out and keep their real paper bounds.
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
    offset = _bounded(offset + delta, allowLeadingOverscroll: true);
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
    if (clamp) offset = _bounded(offset, allowLeadingOverscroll: true);
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
    offset = _bounded(offset, allowLeadingOverscroll: true);
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
    // Do not pin a pinch that starts at the origin. Doing so breaks the normal
    // focal-point invariant and is the source of the touch zoom "jump". The
    // leading edge is still gently resisted by [_bounded].
    offset = _bounded(currentFocal - pageFocal * scale,
        allowLeadingOverscroll: true);
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

  /// Current page-surface size in page coordinates.
  ///
  /// Keep the setter for small controller tests and export callers. PageCanvas
  /// uses [setPageBounds], which importantly never shrinks an open canvas
  /// after the user has travelled beyond its current content.
  Size? _pageSize;
  Size? get pageSize => _pageSize;
  set pageSize(Size? value) => _pageSize = value;

  bool _growsTrailingEdges = false;

  /// Supply the content-derived minimum size. An open canvas retains any
  /// larger virtual extent already reached by the camera; a PDF/paged document
  /// replaces it with its finite paper bounds.
  void setPageBounds(Size minimum, {required bool growsTrailingEdges}) {
    _growsTrailingEdges = growsTrailingEdges;
    final current = _pageSize;
    _pageSize = !growsTrailingEdges || current == null
        ? minimum
        : Size(math.max(minimum.width, current.width),
            math.max(minimum.height, current.height));
  }

  /// A PageCanvas state is keyed by page id. Clear its previous page's virtual
  /// runway before the next state supplies its own content minimum.
  void resetPageBounds() {
    _pageSize = null;
    _growsTrailingEdges = false;
  }

  /// Keep the page origin at upper-left. A small, zoomed-out page also stays
  /// there rather than floating inside the viewport.
  void clampToPage() {
    offset = _bounded(offset, allowLeadingOverscroll: false);
  }

  /// Apply the page boundary once after a gesture has finished, rather than
  /// during every pinch sample where it would move content away from fingers.
  void settleToPage() {
    clampToPage();
    notifyListeners();
  }

  /// Move the short distance remaining in the elastic leading edge. Returning
  /// true tells PageCanvas that its 60fps bounce can stop.
  bool springTowardsPage({double amount = .42}) {
    final target = _bounded(offset, allowLeadingOverscroll: false);
    if ((target - offset).distance < .25) {
      offset = target;
      notifyListeners();
      return true;
    }
    offset = Offset.lerp(offset, target, amount)!;
    notifyListeners();
    return false;
  }

  /// Bound an offset while preserving a small, deliberately hard-to-pull
  /// leading overscroll. At the exact top-left corner a diagonal pull is
  /// ignored, matching native scroll surfaces rather than exposing a loose
  /// diagonal gap.
  Offset _bounded(Offset candidate, {required bool allowLeadingOverscroll}) {
    final ps = _pageSize;
    if (ps == null || viewport == Size.zero) return candidate;

    if (_growsTrailingEdges) _growFor(candidate);
    final live = _pageSize!;
    double axis(double value, double vp, double contentPx) {
      final trailing = math.min(0.0, vp - contentPx);
      if (value < trailing) return trailing;
      if (value <= 0) return value;
      if (!allowLeadingOverscroll) return 0.0;
      // About 56 screen pixels is the asymptote. It feels attached to the
      // edge, yet supplies the small native-looking pull/bounce affordance.
      return 56 * (1 - math.exp(-value / 56));
    }

    var result = Offset(
      axis(candidate.dx, viewport.width, live.width * scale),
      axis(candidate.dy, viewport.height, live.height * scale),
    );
    final fromCorner = offset.dx >= -.1 && offset.dy >= -.1;
    final pullsIntoCorner = candidate.dx > 0 && candidate.dy > 0;
    if (fromCorner && pullsIntoCorner) result = Offset.zero;
    return result;
  }

  void _growFor(Offset candidate) {
    final current = _pageSize!;
    // Leave a screen-sized runway after the viewport. This expansion happens
    // before the trailing clamp, so zoom never makes a previously reachable
    // writing area disappear behind the last PDF/image.
    const runwayPx = 480.0;
    final needWidth = (viewport.width - candidate.dx + runwayPx) / scale;
    final needHeight = (viewport.height - candidate.dy + runwayPx) / scale;
    if (needWidth > current.width || needHeight > current.height) {
      _pageSize = Size(math.max(current.width, needWidth),
          math.max(current.height, needHeight));
    }
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
