import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../canvas/ink_eraser.dart';
import '../canvas/ink_painter.dart';
import '../canvas/windows_pen_buttons.dart';
import '../ink/handwriting_profile.dart';
import '../model/models.dart';

class HandwritingPad extends StatefulWidget {
  const HandwritingPad(
      {super.key,
      required this.character,
      required this.sampleToken,
      required this.onChanged,
      this.initialStrokes = const [],
      this.eraser = false});
  final String character;
  final Object sampleToken;
  final List<Stroke> initialStrokes;
  final bool eraser;
  final VoidCallback onChanged;

  @override
  State<HandwritingPad> createState() => HandwritingPadState();
}

class HandwritingPadState extends State<HandwritingPad> {
  final strokes = <Stroke>[];
  final _undo = <List<Stroke>>[];
  final _pen = WindowsPenButtons();
  List<Stroke>? _before;
  Stroke? _wet;
  int? _pointer;
  int _started = 0;
  Offset? _last, _erasePoint;
  bool _erasing = false;
  bool get drawing => _pointer != null;
  bool get canUndo => _undo.isNotEmpty && !drawing;

  List<Stroke> _copy(List<Stroke> source) => [
        for (final s in source) Stroke.fromJson(s.toJson()),
      ];

  @override
  void initState() {
    super.initState();
    strokes.addAll(_copy(widget.initialStrokes));
    unawaited(_pen.attach());
  }

  @override
  void didUpdateWidget(HandwritingPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sampleToken != widget.sampleToken) {
      strokes
        ..clear()
        ..addAll(_copy(widget.initialStrokes));
      _undo.clear();
      _wet = null;
      _before = null;
      _pointer = null;
      _last = null;
      _erasePoint = null;
    }
  }

  @override
  void dispose() {
    _pen.dispose();
    super.dispose();
  }

  void clear() {
    if (drawing || strokes.isEmpty) return;
    setState(() {
      _undo.add(_copy(strokes));
      strokes.clear();
    });
    widget.onChanged();
  }

  void undo() {
    if (!canUndo) return;
    setState(() {
      strokes
        ..clear()
        ..addAll(_undo.removeLast());
    });
    widget.onChanged();
  }

  Offset _point(PointerEvent e, Size size) => Offset(
        (e.localPosition.dx / size.width * HandwritingProfile.boxWidth)
            .clamp(0, HandwritingProfile.boxWidth),
        (e.localPosition.dy / size.height * HandwritingProfile.boxHeight)
            .clamp(0, HandwritingProfile.boxHeight),
      );

  void _append(PointerEvent e, Offset at) {
    _wet!.x.add(at.dx);
    _wet!.y.add(at.dy);
    _wet!.p.add(e.kind == PointerDeviceKind.stylus && e.pressure > 0
        ? e.pressure.clamp(.05, 1)
        : .5);
    _wet!.t.add(e.timeStamp.inMilliseconds - _started);
  }

  void _finishWet() {
    if (_wet != null) strokes.add(_wet!);
    _wet = null;
  }

  void _update(PointerEvent e, Size size) {
    final at = _point(e, size);
    final erase = widget.eraser || _pen.erases(e);
    if (erase != _erasing) {
      _finishWet();
      _last = at;
      _erasing = erase;
    }
    if (_erasing) {
      final result = <Stroke>[];
      for (final s in strokes) {
        final fragments = eraseStroke(s, _last ?? at, at, 10);
        result.addAll(fragments ?? [s]);
      }
      strokes
        ..clear()
        ..addAll(result);
      _erasePoint = at;
    } else {
      if (_wet == null) {
        _started = e.timeStamp.inMilliseconds;
        _wet = Stroke(tool: 'pen', colorHex: 'auto', size: 2.5, strokeStart: 0);
      }
      _append(e, at);
      _erasePoint = null;
    }
    _last = at;
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: HandwritingProfile.boxWidth / HandwritingProfile.boxHeight,
        child: LayoutBuilder(builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final scheme = Theme.of(context).colorScheme;
          return MouseRegion(
            cursor: SystemMouseCursors.precise,
            child: Listener(
              key: const ValueKey('handwriting-pad'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                if (drawing ||
                    e.kind == PointerDeviceKind.touch ||
                    (e.buttons & kPrimaryButton) == 0 &&
                        !widget.eraser &&
                        !_pen.erases(e)) {
                  return;
                }
                setState(() {
                  _before = _copy(strokes);
                  _pointer = e.pointer;
                  _erasing = widget.eraser || _pen.erases(e);
                  _last = _point(e, size);
                  _update(e, size);
                });
                widget.onChanged();
              },
              onPointerMove: (e) {
                if (_pointer == e.pointer) setState(() => _update(e, size));
              },
              onPointerUp: (e) {
                if (_pointer != e.pointer) return;
                setState(() {
                  _update(e, size);
                  _finishWet();
                  _undo.add(_before!);
                  _before = null;
                  _pointer = null;
                  _erasePoint = null;
                });
                widget.onChanged();
              },
              onPointerCancel: (e) {
                if (_pointer != e.pointer) return;
                setState(() {
                  strokes
                    ..clear()
                    ..addAll(_before!);
                  _before = null;
                  _wet = null;
                  _pointer = null;
                  _erasePoint = null;
                });
                widget.onChanged();
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8)),
                child: CustomPaint(
                    painter: HandwritingSamplePainter(
                  character: widget.character,
                  strokes: strokes,
                  wet: _wet,
                  ink: scheme.onSurface,
                  guide: scheme.onSurfaceVariant,
                  erasePoint: _erasePoint,
                )),
              ),
            ),
          );
        }),
      );
}

/// The same baseline and faint size reference appear in the pad and previews.
/// Only the user's recorded paths are saved; this reference never becomes ink.
class HandwritingSamplePainter extends CustomPainter {
  HandwritingSamplePainter(
      {required this.character,
      required this.strokes,
      required this.ink,
      required this.guide,
      this.wet,
      this.erasePoint});
  final String character;
  final List<Stroke> strokes;
  final Color ink, guide;
  final Stroke? wet;
  final Offset? erasePoint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / HandwritingProfile.boxWidth,
        size.height / HandwritingProfile.boxHeight);
    final text = TextPainter(
        text: TextSpan(
            text: character,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 88,
                fontWeight: FontWeight.w400,
                color: guide.withValues(alpha: .13))),
        textDirection: TextDirection.ltr)
      ..layout();
    text.paint(
        canvas,
        Offset(
            (HandwritingProfile.boxWidth - text.width) / 2,
            HandwritingProfile.baseline -
                text.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    for (final y in [48.0, HandwritingProfile.baseline, 144.0]) {
      canvas.drawLine(
          Offset(8, y),
          Offset(HandwritingProfile.boxWidth - 8, y),
          Paint()
            ..color = guide.withValues(
                alpha: y == HandwritingProfile.baseline ? .35 : .15)
            ..strokeWidth = y == HandwritingProfile.baseline ? 1 : .5);
    }
    InkPainter(strokes, wet: wet, autoColor: ink).paint(canvas,
        const Size(HandwritingProfile.boxWidth, HandwritingProfile.boxHeight));
    if (erasePoint case final at?) {
      canvas.drawCircle(at, 10, Paint()..color = ink.withValues(alpha: .15));
      canvas.drawCircle(
          at,
          10,
          Paint()
            ..color = ink.withValues(alpha: .6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HandwritingSamplePainter oldDelegate) => true;
}
