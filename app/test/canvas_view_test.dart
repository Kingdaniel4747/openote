// Regression coverage for "fit page on open" (the navigator/image-visibility
// fix): a wide imported page zooms out to reveal its full width — including
// images placed to the right of the text — while a narrow page stays at 100%.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/canvas_controller.dart';

void main() {
  test('fitWidth zooms out wide pages, leaves narrow pages at 100%', () {
    final c = CanvasController()
      ..viewport = const Size(940, 700)
      ..pageSize = const Size(1500, 1400);

    // Wide page (content extends to x=1400): scale down so the full width fits.
    c.fitWidth(1400);
    expect(c.scale, closeTo(940 / (1400 + 24), 0.001));
    expect(c.scale, lessThan(1.0));
    expect(c.offset, Offset.zero, reason: 'anchored top-left');
    // The right edge of content is now within the viewport.
    expect(1400 * c.scale, lessThanOrEqualTo(940));

    // Narrow page: never enlarge past natural size.
    c.fitWidth(600);
    expect(c.scale, 1.0);
    expect(c.offset, Offset.zero);

    // Degenerate viewport falls back to the default view.
    final c2 = CanvasController()..viewport = Size.zero;
    c2.fitWidth(1400);
    expect(c2.scale, 1.0);
  });

  test('finger pinch preserves its focal point exactly like mouse zoom', () {
    final touch = CanvasController()
      ..viewport = const Size(900, 700)
      ..pageSize = const Size(2400, 1800);
    final mouse = CanvasController()
      ..viewport = const Size(900, 700)
      ..pageSize = const Size(2400, 1800);
    const focal = Offset(360, 280);
    final pageUnderFinger = touch.screenToPage(focal);
    touch.transformPinchAt(focal, 1.35, focal);
    mouse.zoomAt(focal, 1.35);
    expect(touch.scale, mouse.scale);
    expect(touch.offset, mouse.offset);
    expect(touch.pageToScreen(pageUnderFinger), focal);
  });

  test('touch pinch is stable when contacts update in alternating events', () {
    final c = CanvasController()
      ..viewport = const Size(900, 700)
      ..pageSize = const Size(2400, 1800);
    const startScale = 1.0;
    const startOffset = Offset(-260, -180);
    const startFocal = Offset(420, 310);
    c.jumpTo(startScale, startOffset);
    final pageUnderStartFocal = c.screenToPage(startFocal);

    // Intermediate hardware samples may contain one newer contact. The final
    // result must still be derived from the same immutable start transform.
    c.transformGestureFrom(
      startScale: startScale,
      startOffset: startOffset,
      startFocal: startFocal,
      currentFocal: const Offset(417, 307),
      scaleFactor: 1.18,
    );
    c.transformGestureFrom(
      startScale: startScale,
      startOffset: startOffset,
      startFocal: startFocal,
      currentFocal: const Offset(420, 310),
      scaleFactor: 1.4,
    );

    expect(c.scale, closeTo(1.4, 0.0001));
    expect(c.pageToScreen(pageUnderStartFocal), startFocal);
  });

  test('touch pinch at the origin keeps the content under the fingers stable',
      () {
    final c = CanvasController()
      ..viewport = const Size(900, 700)
      ..pageSize = const Size(2400, 1800);

    c.transformGestureFrom(
      startScale: 1,
      startOffset: Offset.zero,
      startFocal: const Offset(500, 350),
      currentFocal: const Offset(500, 350),
      scaleFactor: 1.6,
    );

    expect(c.scale, 1.6);
    expect(c.offset, const Offset(-300, -210));
    expect(c.pageToScreen(const Offset(500, 350)),
        const Offset(500, 350));
  });

  test('open canvas grows before its trailing boundary is reached', () {
    final c = CanvasController()
      ..viewport = const Size(900, 700)
      ..setPageBounds(const Size(1200, 1400), growsTrailingEdges: true);

    c.panBy(const Offset(-6000, -7000));

    expect(c.offset.dx, lessThan(-5000));
    expect(c.offset.dy, lessThan(-6000));
    expect(c.pageSize!.width, greaterThan(6500));
    expect(c.pageSize!.height, greaterThan(7500));
  });

  test('finite paper still stops at its real trailing edge', () {
    final c = CanvasController()
      ..viewport = const Size(900, 700)
      ..setPageBounds(const Size(1200, 1400), growsTrailingEdges: false);

    c.panBy(const Offset(-6000, -7000));

    expect(c.offset, const Offset(-300, -700));
    expect(c.pageSize, const Size(1200, 1400));
  });

  test('the fixed origin resists a one-edge pull then settles back', () {
    final c = CanvasController()
      ..viewport = const Size(900, 700)
      ..setPageBounds(const Size(1200, 1400), growsTrailingEdges: true);

    c.panBy(const Offset(400, 0));
    expect(c.offset.dx, greaterThan(0));
    expect(c.offset.dx, lessThan(56));

    for (var i = 0; i < 20; i++) {
      if (c.springTowardsPage()) break;
    }
    expect(c.offset.dx, 0);
  });
}
