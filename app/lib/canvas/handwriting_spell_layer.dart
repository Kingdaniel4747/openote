import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../model/models.dart';
import '../spell/spell_checker.dart';
import '../spell/writing_services.dart';
import '../state/app_state.dart';
import '../l10n/app_strings.dart';

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
  List<_HandwritingMark> _marks = const [];
  String? _selectedMarkKey;
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
    // Editing or drawing anywhere else dismisses the transient suggestion
    // chrome; the underline remains until the word is corrected or ignored.
    if (_selectedMarkKey != null) _selectedMarkKey = null;
    final revision = ++_revision;
    _timer?.cancel();
    if (!Platform.isWindows ||
        !app.spellCheckEnabled ||
        !app.handwritingSpellCheck) return;
    final strokes = [
      for (final b in app.blocks)
        if (b.type == BlockType.ink)
          for (final raw in b.content['strokes'] as List)
            if ((raw as Map)['brush']?['tool'] != 'highlighter')
              {'x': List.of(raw['x'] as List), 'y': List.of(raw['y'] as List)},
    ];
    if (strokes.isEmpty) return;
    _timer = Timer(const Duration(milliseconds: 350), () async {
      bool current() => mounted && revision == _revision;
      try {
        final marks = <_HandwritingMark>[];
        final dictionary = app.writingLanguage == 'en-US'
            ? await SpellChecker.instance()
            : null;
        // Bounded jobs keep large notebooks from pinning the native service.
        for (var start = 0; start < strokes.length; start += 256) {
          if (!current()) return;
          final end = (start + 256).clamp(0, strokes.length);
          final result = await WritingServices.run({
            'kind': 'ink',
            'language': app.writingLanguage,
            'strokes': strokes.sublist(start, end),
          }, current: current);
          for (final item in result as List) {
            final m = item as Map;
            final text = m['text'] as String? ?? '';
            final nativeSuggestions = m['suggestions'];
            final rect = Rect.fromLTWH(
              (m['x'] as num).toDouble(),
              (m['y'] as num).toDouble(),
              (m['w'] as num).toDouble(),
              (m['h'] as num).toDouble(),
            );
            final key = '${app.pageId}|$text|${rect.left.round()}|'
                '${rect.top.round()}|${rect.width.round()}|${rect.height.round()}';
            if (!app.isHandwritingMarkIgnored(key)) {
              marks.add(
                _HandwritingMark(
                  rect: rect,
                  key: key,
                  text: text,
                  suggestions: nativeSuggestions is List
                      ? nativeSuggestions.whereType<String>().take(5).toList()
                      : dictionary?.suggest(text) ?? const [],
                ),
              );
            }
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

  Future<void> _showMarkMenu(
    BuildContext context,
    _HandwritingMark mark,
    Offset position,
  ) async {
    setState(() => _selectedMarkKey = mark.key);
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final anchor =
        box?.localToGlobal(Offset(mark.rect.left, mark.rect.bottom)) ??
            position;
    final overlaySize = overlay?.size ?? MediaQuery.sizeOf(context);
    final action = await showMenu<String>(
      context: context,
      // A RelativeRect with zero right/bottom pins a popup to the screen edge.
      // Anchor it below the recognised word instead.
      position: RelativeRect.fromRect(
        Rect.fromLTWH(anchor.dx, anchor.dy + 4, 1, 1),
        Offset.zero & overlaySize,
      ),
      items: [
        for (final suggestion in mark.suggestions)
          PopupMenuItem(value: 'suggest:$suggestion', child: Text(suggestion)),
        if (mark.suggestions.isEmpty)
          PopupMenuItem(
            enabled: false,
            value: 'none',
            child: Text(
              mark.text.isEmpty
                  ? tr(context, 'No spelling suggestion')
                  : 'Recognised as “${mark.text}”',
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'ignore', child: AppText('Ignore')),
      ],
    );
    if (!mounted) return;
    setState(() => _selectedMarkKey = null);
    if (action == 'ignore') {
      widget.app.ignoreHandwritingMark(mark.key);
      setState(() => _marks = _marks.where((m) => m.key != mark.key).toList());
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: _SpellingPainter(_marks, selectedKey: _selectedMarkKey),
            ),
          ),
          for (final mark in _marks)
            Positioned.fromRect(
              rect: mark.rect.inflate(7),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) =>
                    _showMarkMenu(context, mark, details.globalPosition),
                onLongPressStart: (details) =>
                    _showMarkMenu(context, mark, details.globalPosition),
                onSecondaryTapUp: (details) =>
                    _showMarkMenu(context, mark, details.globalPosition),
              ),
            ),
        ],
      );
}

class _HandwritingMark {
  const _HandwritingMark({
    required this.rect,
    required this.key,
    required this.text,
    required this.suggestions,
  });
  final Rect rect;
  final String key;
  final String text;
  final List<String> suggestions;
}

class _SpellingPainter extends CustomPainter {
  _SpellingPainter(this.marks, {this.selectedKey});
  final List<_HandwritingMark> marks;
  final String? selectedKey;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final mark in marks) {
      final rect = mark.rect;
      if (mark.key == selectedKey) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(3)),
          Paint()..color = const Color(0x3342A5F5),
        );
      }
      final path = Path()..moveTo(rect.left, rect.bottom + 3);
      for (var x = rect.left; x < rect.right; x += 6) {
        path.relativeLineTo(3, 2);
        path.relativeLineTo(3, -2);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SpellingPainter old) =>
      old.marks != marks || old.selectedKey != selectedKey;
}
