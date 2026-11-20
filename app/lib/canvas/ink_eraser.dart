import 'dart:math' as math;
import 'dart:ui';

import '../model/models.dart';

/// Clips original segments against the disk swept from [from] to [to].
/// No resampling: even a sparse imported line has exact cut endpoints.
/// Null means untouched, an empty list means completely erased.
List<Stroke>? eraseStroke(
  Stroke source,
  Offset from,
  Offset to,
  double radius, {
  bool wholeStroke = false,
}) {
  final count = source.x.length;
  if (count == 0) return null;
  final sweep = Rect.fromPoints(from, to).inflate(radius);
  final bounds = source.bounds();
  if (bounds.maxX < sweep.left ||
      bounds.minX > sweep.right ||
      bounds.maxY < sweep.top ||
      bounds.minY > sweep.bottom) {
    return null;
  }

  Offset point(int i) => Offset(source.x[i], source.y[i]);
  if (count == 1) {
    return _insideInterval(point(0), point(0), from, to, radius) == null
        ? null
        : [];
  }
  final cuts = <int, (double, double)>{};
  for (var i = 1; i < count; i++) {
    final cut = _insideInterval(point(i - 1), point(i), from, to, radius);
    if (cut == null) continue;
    if (wholeStroke) return [];
    cuts[i] = cut;
  }
  if (cuts.isEmpty) return null;
  final result = <Stroke>[];
  Stroke? run;
  void finish() {
    if (run != null && run!.x.length >= 2) result.add(run!);
    run = null;
  }

  void append(int a, int b, double t) {
    run ??= Stroke(
        tool: source.tool,
        colorHex: source.colorHex,
        size: source.size,
        opacity: source.opacity,
        strokeStart: source.strokeStart);
    final target = run!;
    double lerp(List<double> values) => values[a] + (values[b] - values[a]) * t;
    final x = lerp(source.x), y = lerp(source.y);
    if (target.x.isNotEmpty && target.x.last == x && target.y.last == y) return;
    target.x.add(x);
    target.y.add(y);
    if (source.p.length == count) target.p.add(lerp(source.p));
    if (source.tx.length == count) target.tx.add(lerp(source.tx));
    if (source.ty.length == count) target.ty.add(lerp(source.ty));
    if (source.t.length == count) {
      target.t.add((source.t[a] + (source.t[b] - source.t[a]) * t).round());
    }
  }

  for (var i = 1; i < count; i++) {
    final cut = cuts[i];
    if (cut == null) {
      append(i - 1, i, 0);
      append(i - 1, i, 1);
      continue;
    }
    if (cut.$1 > 0) {
      append(i - 1, i, 0);
      append(i - 1, i, cut.$1);
    }
    finish();
    if (cut.$2 < 1) {
      append(i - 1, i, cut.$2);
      append(i - 1, i, 1);
    }
  }
  finish();
  return result;
}

/// A capsule is convex: the union of its two disks and connecting rectangle
/// intersects a line segment in at most one interval.
(double, double)? _insideInterval(
    Offset a, Offset b, Offset from, Offset to, double radius) {
  final delta = b - a;
  final lengthSquared = delta.distanceSquared;
  double dot(Offset u, Offset v) => u.dx * v.dx + u.dy * v.dy;
  double? lo, hi;
  void include(double start, double end) {
    start = math.max(0, start);
    end = math.min(1, end);
    if (end <= start) return;
    lo = lo == null ? start : math.min(lo!, start);
    hi = hi == null ? end : math.max(hi!, end);
  }

  void disk(Offset center) {
    final offset = a - center;
    final c = offset.distanceSquared - radius * radius;
    if (lengthSquared == 0) {
      if (c < 0) include(0, 1);
      return;
    }
    final projection = dot(offset, delta);
    final discriminant = projection * projection - lengthSquared * c;
    if (discriminant <= 0) return;
    final root = math.sqrt(discriminant);
    include((-projection - root) / lengthSquared,
        (-projection + root) / lengthSquared);
  }

  disk(from);
  final axis = to - from;
  final length = axis.distance;
  if (length > 0) {
    disk(to);
    final u = axis / length;
    final v = Offset(-u.dy, u.dx);
    var start = 0.0, end = 1.0;
    bool slab(double position, double direction, double min, double max) {
      if (direction == 0) return position >= min && position <= max;
      final first = (min - position) / direction;
      final last = (max - position) / direction;
      start = math.max(start, math.min(first, last));
      end = math.min(end, math.max(first, last));
      return start < end;
    }

    final relative = a - from;
    if (slab(dot(relative, u), dot(delta, u), 0, length) &&
        slab(dot(relative, v), dot(delta, v), -radius, radius)) {
      include(start, end);
    }
  }
  return lo == null ? null : (lo!, hi!);
}
