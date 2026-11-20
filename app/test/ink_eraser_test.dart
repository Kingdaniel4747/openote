import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/ink_eraser.dart';
import 'package:openote/canvas/ink_painter.dart';
import 'package:openote/model/models.dart';

void main() {
  Stroke line({String tool = 'pen'}) => Stroke(
        tool: tool,
        colorHex: '#123456',
        size: 2,
        opacity: .4,
        x: [0, 100],
        y: [0, 0],
        p: [.2, .8],
        tx: [10, 20],
        ty: [-20, 20],
        t: [0, 1000],
        strokeStart: 123,
      );

  test('editing a middle stroke repaints even when stroke count stays equal',
      () {
    final first = line(), middle = line(), last = line();
    final before = InkPainter([first, middle, last]);
    final replacement =
        eraseStroke(middle, Offset.zero, Offset.zero, 5)!.single;
    expect(
        InkPainter([first, replacement, last]).shouldRepaint(before), isTrue);
    expect(InkPainter([first, middle, last]).shouldRepaint(before), isFalse);
  });

  test('cuts sparse segments exactly and interpolates every point channel', () {
    final source = line();
    final parts =
        eraseStroke(source, const Offset(50, 0), const Offset(50, 0), 5)!;
    expect(parts.length, 2);
    expect(parts.first.x, [0, 45]);
    expect(parts.last.x.first, closeTo(55, 1e-9));
    expect(parts.last.x.last, 100);
    expect(parts.first.p.last, closeTo(.47, 1e-9));
    expect(parts.first.tx.last, 14.5);
    expect(parts.last.ty.first, closeTo(2, 1e-9));
    expect(parts.first.t, [0, 450]);
    expect(parts.last.strokeStart, 123);
    expect(parts.last.colorHex, source.colorHex);
    expect(parts.last.opacity, .4);
    expect(parts.first.id, isNot(source.id));
    expect(source.x, [0, 100]);
  });

  test('fast sweeps erase between events in both directions', () {
    for (final reverse in [false, true]) {
      final a = Offset(50, reverse ? 100 : -100);
      final b = Offset(50, reverse ? -100 : 100);
      final parts = eraseStroke(line(), a, b, 5)!;
      expect(parts.first.x.last, closeTo(45, 1e-9));
      expect(parts.last.x.first, closeTo(55, 1e-9));
      expect(eraseStroke(line(), a, b, 5, wholeStroke: true), isEmpty);
    }
  });

  test('parallel and diagonal sweeps include their round end caps', () {
    final parallel =
        eraseStroke(line(), const Offset(30, 0), const Offset(70, 0), 5)!;
    expect(parallel.first.x.last, 25);
    expect(parallel.last.x.first, 75);
    final diagonal =
        eraseStroke(line(), const Offset(0, -50), const Offset(100, 50), 5)!;
    expect(diagonal.first.x.last, closeTo(50 - 5 * 1.41421356237, 1e-8));
    expect(diagonal.last.x.first, closeTo(50 + 5 * 1.41421356237, 1e-8));
  });

  test('misses and tangencies preserve original geometry', () {
    expect(eraseStroke(line(), const Offset(50, 10), const Offset(50, 10), 5),
        isNull);
    expect(eraseStroke(line(), const Offset(50, 5), const Offset(50, 5), 5),
        isNull);
  });

  test('empty pressure and time channels stay empty', () {
    final source = Stroke(
        tool: 'ballpoint', colorHex: 'auto', size: 2, x: [0, 100], y: [0, 0]);
    final parts =
        eraseStroke(source, const Offset(50, 0), const Offset(50, 0), 5)!;
    for (final part in parts) {
      expect(part.p, isEmpty);
      expect(part.tx, isEmpty);
      expect(part.ty, isEmpty);
      expect(part.t, isEmpty);
    }
  });

  test('repeated erasing does not eat beyond the same boundary', () {
    final parts =
        eraseStroke(line(), const Offset(50, 0), const Offset(50, 0), 5)!;
    for (final part in parts) {
      expect(eraseStroke(part, const Offset(50, 0), const Offset(50, 0), 5),
          isNull);
    }
  });

  test('dots and complete strokes can be removed', () {
    final dot =
        Stroke(tool: 'pen', colorHex: 'auto', size: 2, x: [50, 50], y: [0, 0]);
    expect(
        eraseStroke(dot, const Offset(50, 0), const Offset(50, 0), 5), isEmpty);
    expect(eraseStroke(line(), Offset.zero, const Offset(100, 0), 5), isEmpty);
  });
}
