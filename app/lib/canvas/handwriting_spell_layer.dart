import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../model/models.dart';
import '../spell/writing_services.dart';
import '../state/app_state.dart';

class HandwritingSpellLayer extends StatefulWidget {
  const HandwritingSpellLayer({super.key, required this.app});
  final AppState app;
  @override
  State<HandwritingSpellLayer> createState() => _HandwritingSpellLayerState();
}

class _HandwritingSpellLayerState extends State<HandwritingSpellLayer> {
  Timer? _timer;
  String _signature = '';
  int _revision = 0;
  List<Rect> _marks = const [];
  @override
  void initState() {
    super.initState();
    widget.app.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(HandwritingSpellLayer old) {
    super.didUpdateWidget(old);
    if (old.app != widget.app) {
      old.app.removeListener(_changed);
      widget.app.addListener(_changed);
      _signature = '';
      _changed();
    }
  }

  void _changed() {
    final app = widget.app;
    final signature =
        '${app.pageId}:${app.writingLanguage}:${app.spellCheckEnabled}:${app.handwritingSpellCheck}:'
        '${app.blocks.where((b) => b.type == BlockType.ink).map((b) => '${b.id}:${b.updatedAt}').join(',')}';
    if (_signature == signature) return;
    _signature = signature;
    final revision = ++_revision;
    _timer?.cancel();
    if (_marks.isNotEmpty) setState(() => _marks = const []);
    if (!Platform.isWindows ||
        !app.spellCheckEnabled ||
        !app.handwritingSpellCheck) return;
    final strokes = [
      for (final b in app.blocks)
        if (b.type == BlockType.ink)
          for (final raw in b.content['strokes'] as List)
            if ((raw as Map)['brush']?['tool'] != 'highlighter')
              {'x': List.of(raw['x'] as List), 'y': List.of(raw['y'] as List)}
    ];
    if (strokes.isEmpty) return;
    _timer = Timer(const Duration(milliseconds: 1200), () async {
      bool current() => mounted && revision == _revision;
      try {
        final marks = <Rect>[];
        // Bounded jobs keep large notebooks from pinning the native service.
        for (var start = 0; start < strokes.length; start += 256) {
          if (!current()) return;
          final end = (start + 256).clamp(0, strokes.length);
          final result = await WritingServices.run({
            'kind': 'ink',
            'language': app.writingLanguage,
            'strokes': strokes.sublist(start, end)
          }, current: current);
          for (final item in result as List) {
            final m = item as Map;
            marks.add(Rect.fromLTWH(
                (m['x'] as num).toDouble(),
                (m['y'] as num).toDouble(),
                (m['w'] as num).toDouble(),
                (m['h'] as num).toDouble()));
          }
        }
        if (current()) setState(() => _marks = marks);
      } catch (_) {
        if (current())
          app.writingServiceProblem =
              'Local writing services are unavailable. Check Windows language packs.';
      }
    });
  }

  @override
  void dispose() {
    _revision++;
    _timer?.cancel();
    widget.app.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _SpellingPainter(_marks)));
}

class _SpellingPainter extends CustomPainter {
  _SpellingPainter(this.marks);
  final List<Rect> marks;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final rect in marks) {
      final path = Path()..moveTo(rect.left, rect.bottom + 3);
      for (var x = rect.left; x < rect.right; x += 6) {
        path.relativeLineTo(3, 2);
        path.relativeLineTo(3, -2);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SpellingPainter old) => old.marks != marks;
}
