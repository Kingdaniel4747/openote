import 'dart:math' as math;
import 'dart:ui';
import '../model/models.dart';

/// A recognised outline in the original page coordinates.
class RecognisedShape {
  const RecognisedShape(this.kind, this.points);
  final String kind;
  final List<Offset> points;
}

double distanceToSegment(Offset p, Offset a, Offset b) {
  final v = b - a;
  if (v.distanceSquared == 0) return (p - a).distance;
  final t = (((p - a).dx * v.dx + (p - a).dy * v.dy) / v.distanceSquared)
      .clamp(0.0, 1.0);
  return (p - (a + v * t)).distance;
}

List<Offset> _simplify(List<Offset> points, double tolerance) {
  if (points.length <= 2) return points;
  var largest = tolerance;
  var at = -1;
  for (var i = 1; i < points.length - 1; i++) {
    final d = distanceToSegment(points[i], points.first, points.last);
    if (d > largest) {
      largest = d;
      at = i;
    }
  }
  if (at < 0) return [points.first, points.last];
  final left = _simplify(points.sublist(0, at + 1), tolerance);
  final right = _simplify(points.sublist(at), tolerance);
  return [...left.take(left.length - 1), ...right];
}

RecognisedShape? recogniseShape(List<Offset> raw) {
  if (raw.length < 3) return null;
  final points = <Offset>[raw.first];
  for (final p in raw.skip(1)) {
    if ((p - points.last).distance > .5) points.add(p);
  }
  if (points.length < 3) return null;
  var bounds = Rect.fromPoints(points.first, points.last);
  for (final p in points) {
    bounds = bounds.expandToInclude(p & Size.zero);
  }
  final diagonal = bounds.size.longestSide;
  if (diagonal < 28) return null;
  final closed = (points.first - points.last).distance < diagonal * .18;
  if (!closed) {
    var pathLength = 0.0;
    var deviation = 0.0;
    for (var i = 1; i < points.length; i++) {
      pathLength += (points[i] - points[i - 1]).distance;
      deviation = math.max(
          deviation, distanceToSegment(points[i], points.first, points.last));
    }
    final chord = (points.last - points.first).distance;
    if (deviation > chord * .045 || pathLength > chord * 1.12) return null;
    return RecognisedShape('line', [points.first, points.last]);
  }

  // Split a closed loop across its farthest point before simplifying; a
  // single start=end chord loses the corners around the closure seam.
  var far = 1;
  for (var i = 2; i < points.length; i++) {
    if ((points[i] - points.first).distanceSquared >
        (points[far] - points.first).distanceSquared) {
      far = i;
    }
  }
  final a = _simplify(points.sublist(0, far + 1), diagonal * .045);
  final b = _simplify([...points.sublist(far), points.first], diagonal * .045);
  final corners = [...a.take(a.length - 1), ...b.take(b.length - 1)];
  var changed = true;
  while (changed && corners.length > 3) {
    changed = false;
    for (var i = 0; i < corners.length; i++) {
      if (distanceToSegment(
              corners[i],
              corners[(i + corners.length - 1) % corners.length],
              corners[(i + 1) % corners.length]) <
          diagonal * .05) {
        corners.removeAt(i);
        changed = true;
        break;
      }
    }
  }
  if (corners.length == 3) {
    return RecognisedShape('triangle', [...corners, corners.first]);
  }
  if (corners.length == 4) {
    // Rectify a roughly rectangular polygon while retaining its rotation.
    final axis = corners[1] - corners[0];
    if (axis.distance < 1) return null;
    final u = axis / axis.distance;
    final v = Offset(-u.dy, u.dx);
    double dot(Offset x, Offset y) => x.dx * y.dx + x.dy * y.dy;
    final center = corners.reduce((x, y) => x + y) / 4;
    final w = corners.map((p) => dot(p - center, u).abs()).reduce(math.max);
    final h = corners.map((p) => dot(p - center, v).abs()).reduce(math.max);
    final rect = [
      center - u * w - v * h,
      center + u * w - v * h,
      center + u * w + v * h,
      center - u * w + v * h
    ];
    var error = 0.0;
    for (final p in points) {
      var nearest = double.infinity;
      for (var i = 0; i < 4; i++) {
        nearest =
            math.min(nearest, distanceToSegment(p, rect[i], rect[(i + 1) % 4]));
      }
      error += nearest;
    }
    if (error / points.length < diagonal * .05) {
      return RecognisedShape('rectangle', [...rect, rect.first]);
    }
    return null;
  }
  if (bounds.width < 12 || bounds.height < 12) return null;
  var error = 0.0;
  for (final p in points) {
    final x = (p.dx - bounds.center.dx) / (bounds.width / 2);
    final y = (p.dy - bounds.center.dy) / (bounds.height / 2);
    error += (math.sqrt(x * x + y * y) - 1).abs();
  }
  if (error / points.length > .16) return null;
  final ellipse = <Offset>[
    for (var i = 0; i < 96; i++)
      Offset(bounds.center.dx + math.cos(i * math.pi / 48) * bounds.width / 2,
          bounds.center.dy + math.sin(i * math.pi / 48) * bounds.height / 2),
  ];
  return RecognisedShape('ellipse', [...ellipse, ellipse.first]);
}

/// Sample geometric segments so area erasing sees their interiors as well as
/// their vertices. Used for old sparse shapes as well as newly drawn ones.
List<Offset> sampleOutline(List<Offset> points, double spacing) {
  if (points.isEmpty) return [];
  final result = <Offset>[points.first];
  for (var i = 1; i < points.length; i++) {
    final count =
        math.max(1, ((points[i] - points[i - 1]).distance / spacing).ceil());
    for (var j = 1; j <= count; j++) {
      result.add(Offset.lerp(points[i - 1], points[i], j / count)!);
    }
  }
  return result;
}

Stroke sampleStroke(Stroke source, double spacing) {
  if (source.x.length < 2) return source;
  final points = [
    for (var i = 0; i < source.x.length; i++) Offset(source.x[i], source.y[i])
  ];
  if (!List.generate(
          points.length - 1, (i) => (points[i + 1] - points[i]).distance)
      .any((d) => d > spacing)) {
    return source;
  }
  final result = Stroke(
      id: source.id,
      tool: source.tool,
      colorHex: source.colorHex,
      size: source.size,
      opacity: source.opacity,
      strokeStart: source.strokeStart);
  void add(int a, int b, double t) {
    double value(List<double> channel) =>
        channel[a] + (channel[b] - channel[a]) * t;
    result.x.add(value(source.x));
    result.y.add(value(source.y));
    if (source.p.length == points.length) result.p.add(value(source.p));
    if (source.tx.length == points.length) result.tx.add(value(source.tx));
    if (source.ty.length == points.length) result.ty.add(value(source.ty));
    result.t.add(source.t.length == points.length
        ? (source.t[a] + (source.t[b] - source.t[a]) * t).round()
        : 0);
  }

  add(0, 0, 0);
  for (var i = 1; i < points.length; i++) {
    final n =
        math.max(1, ((points[i] - points[i - 1]).distance / spacing).ceil());
    for (var j = 1; j <= n; j++) {
      add(i - 1, i, j / n);
    }
  }
  return result;
}
