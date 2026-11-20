import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ui/inline_section_strip.dart';

void main() {
  testWidgets('nesting requires 500 continuous milliseconds on the same target',
      (tester) async {
    String? preview, nested;
    await tester.pumpWidget(MaterialApp(
        home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
          width: 200,
          height: 300,
          child: InlineSectionStrip(
            axis: Axis.vertical,
            ids: const ['a', 'b', 'c'],
            widths: const [60, 60, 60],
            trailing: const SizedBox.shrink(),
            canNest: (moving, target) => moving != target,
            onNestPreview: (_, target) => preview = target,
            onNest: (moving, target) => nested = '$moving:$target',
            onReorder: (_, __, ___) {},
            children: [
              for (final id in ['a', 'b', 'c'])
                ColoredBox(key: ValueKey('nest-$id'), color: Colors.blue)
            ],
          )),
    )));
    final gesture = await tester.startGesture(const Offset(50, 150));
    await gesture.moveTo(const Offset(50, 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(preview, isNull);
    await gesture.moveTo(const Offset(50, 150));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(preview, isNull, reason: 'time on A must not count toward B');
    await tester.pump(const Duration(milliseconds: 200));
    expect(preview, 'b');
    expect(nested, isNull);
    await gesture.moveTo(const Offset(250, 150));
    await tester.pump();
    expect(preview, isNull, reason: 'leaving the list cancels the preview');
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(nested, isNull);
    final commit = await tester.startGesture(const Offset(50, 150));
    await commit.moveTo(const Offset(50, 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(preview, 'a');
    await commit.up();
    await tester.pumpAndSettle();
    expect(nested, 'c:a');
    expect(preview, isNull);
    // A pending hover timer must not outlive the list.
    final pending = await tester.startGesture(const Offset(50, 150));
    await pending.moveTo(const Offset(50, 30));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await pending.cancel();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  for (final axis in Axis.values) {
    for (final movingExtent in [30.0, 60.0]) {
      testWidgets('first slot is reachable on $axis with extent $movingExtent',
          (tester) async {
        String? result;
        await tester.pumpWidget(MaterialApp(
            home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 300,
              height: 200,
              child: InlineSectionStrip(
                axis: axis,
                ids: const ['a', 'b', 'c'],
                widths: [30, 30, movingExtent],
                trailing: const SizedBox.shrink(),
                onReorder: (moving, target, after) =>
                    result = '$moving:$target:$after',
                children: [
                  for (final id in ['a', 'b', 'c'])
                    ColoredBox(key: ValueKey('entry-$id'), color: Colors.blue)
                ],
              )),
        )));
        final first = find.byKey(const ValueKey('entry-a'));
        final moving = find.byKey(const ValueKey('entry-c'));
        final start = tester.getTopLeft(moving) + const Offset(10, 10);
        final target = tester.getTopLeft(first) + const Offset(10, 10);
        final gesture = await tester.startGesture(start);
        await gesture.moveTo(target);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(result, 'c:a:false');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final external in [false, true]) {
    testWidgets(
        'vertical edge scroll and cancel keep entries inside the list (external: $external)',
        (tester) async {
      var committed = false;
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 150,
            height: 120,
            child: InlineSectionStrip(
              axis: Axis.vertical,
              allowExternalDrops: external,
              ids: const ['a', 'b', 'c', 'd', 'e', 'f'],
              widths: const [30, 30, 30, 30, 30, 30],
              trailing: const SizedBox.shrink(),
              onReorder: (_, __, ___) => committed = true,
              children: [
                for (final id in ['a', 'b', 'c', 'd', 'e', 'f'])
                  ColoredBox(key: ValueKey('row-$id'), color: Colors.blue),
              ],
            ),
          ),
        ),
      ));
      final row = find.byKey(const ValueKey('row-a'));
      final gesture = await tester.startGesture(const Offset(40, 15));
      await gesture.moveTo(const Offset(250, 118));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, greaterThan(0));
      expect(tester.getTopLeft(row).dy, greaterThanOrEqualTo(0));
      expect(tester.getBottomRight(row).dy, lessThanOrEqualTo(120));
      expect(tester.getTopLeft(row).dx, 0);
      expect(tester.getSize(row).width, 150);
      await gesture.moveTo(const Offset(-100, -200));
      await tester.pump();
      expect(tester.getTopLeft(row).dy, greaterThanOrEqualTo(0));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(committed, isFalse);
      scrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(row).dy, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('edge scroll keeps the tab visible and cancel preserves order',
      (tester) async {
    var committed = false;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 220,
          height: 34,
          child: InlineSectionStrip(
            ids: const ['a', 'b', 'c', 'd'],
            widths: const [80, 80, 80, 80],
            trailing: const Icon(Icons.add),
            onReorder: (_, __, ___) => committed = true,
            children: [
              for (final id in ['a', 'b', 'c', 'd'])
                ColoredBox(key: ValueKey('tab-$id'), color: Colors.blue),
            ],
          ),
        ),
      ),
    ));
    final tab = find.byKey(const ValueKey('tab-a'));
    final gesture = await tester.startGesture(const Offset(27, 16));
    await gesture.moveTo(const Offset(215, 16));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.getTopLeft(tab).dx, greaterThanOrEqualTo(0));
    expect(tester.getTopRight(tab).dx, lessThanOrEqualTo(220));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(committed, isFalse);
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(tab).dx, 7);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('inline reorder follows $kind and commits on release',
        (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
            width: 400,
            height: 34,
            child: InlineSectionStrip(
              ids: const ['a', 'b', 'c'],
              widths: const [80, 120, 60],
              onReorder: (moving, target, after) =>
                  result = '$moving:$target:$after',
              trailing: const Icon(Icons.add),
              children: [
                for (final id in ['a', 'b', 'c'])
                  ColoredBox(
                      key: ValueKey('tab-$id'),
                      color: Colors.blue,
                      child: Text(id))
              ],
            )),
      ))));
      final a = find.byKey(const ValueKey('tab-a'));
      final b = find.byKey(const ValueKey('tab-b'));
      final start = tester.getTopLeft(a) + const Offset(20, 15);
      final gesture = await tester.startGesture(start, kind: kind);
      await gesture.moveTo(start + const Offset(40, 0));
      await tester.pump();
      await gesture.moveTo(start + const Offset(150, 0));
      await tester.pump();
      expect(tester.getTopLeft(a).dx, closeTo(157, .01));
      expect(result, isNull);
      expect(find.byType(Draggable<String>), findsNothing);
      final before = tester.getTopLeft(b).dx;
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(b).dx, lessThan(before));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(b).dx, closeTo(7, .01));
      await gesture.moveTo(const Offset(1000, 300));
      await tester.pump();
      expect(tester.getTopRight(a).dx, lessThanOrEqualTo(400));
      expect(tester.getTopLeft(a).dy, 0);
      await gesture.moveTo(start + const Offset(100, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(result, 'a:b:true');
      expect(tester.takeException(), isNull);
    });
  }
}
