import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/ink_painter.dart';
import '../ink/handwriting_profile.dart';
import '../l10n/app_strings.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

Future<void> showHandwritingDialog(BuildContext context, AppState app) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HandwritingDialog(app: app),
    );

class HandwritingButton extends StatelessWidget {
  const HandwritingButton({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('handwriting-beta'),
        icon: const Icon(Icons.draw_outlined, size: 18),
        tooltip: tr(context, 'My handwriting · Beta'),
        visualDensity: VisualDensity.compact,
        onPressed: () => showHandwritingDialog(context, app),
      );
}

class HandwritingDialog extends StatefulWidget {
  const HandwritingDialog({super.key, required this.app});
  final AppState app;

  @override
  State<HandwritingDialog> createState() => _HandwritingDialogState();
}

class _HandwritingDialogState extends State<HandwritingDialog> {
  late final HandwritingProfile _profile = widget.app.handwritingProfile;
  final _text = TextEditingController();
  final _padKey = GlobalKey<_WritingPadState>();
  String _character = 'a';
  bool _write = false;
  double _height = 28, _width = 600, _words = 1, _lines = 1;

  double get _maxWidth => widget.app.pageProps.isPaged
      ? math.min(
          900, widget.app.pageProps.paper.width - AppState.sheetMargin * 2)
      : 900;
  double get _effectiveWidth => math.min(_width, _maxWidth);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _train(String character) {
    _padKey.currentState?.clear();
    setState(() {
      _character = character;
      _write = false;
    });
  }

  List<String> get _characters => {
        ...HandwritingProfile.characters.runes.map(String.fromCharCode),
        ..._profile.samples.keys,
        ..._profile.missing(_text.text),
      }.toList();

  void _save({required bool next}) {
    final pad = _padKey.currentState;
    if (pad == null || pad.strokes.isEmpty || pad.drawing) return;
    _profile.addSample(_character, pad.strokes);
    widget.app.saveHandwritingProfile(_profile);
    pad.clear();
    setState(() {
      if (next) {
        final characters = _characters;
        final after = characters.indexOf(_character) + 1;
        _character = characters
                .skip(after)
                .where((c) => !_profile.samples.containsKey(c))
                .firstOrNull ??
            characters
                .where((c) => !_profile.samples.containsKey(c))
                .firstOrNull ??
            _character;
      }
    });
  }

  List<Stroke> _generate({Offset origin = const Offset(12, 6)}) =>
      _profile.generate(_text.text,
          origin: origin,
          height: _height,
          width: _effectiveWidth,
          wordSpacing: _words,
          lineSpacing: _lines,
          size: widget.app.inkSizeFor(Tool.pen),
          color: widget.app.penCustomColor == null && widget.app.penColor == 0
              ? 'auto'
              : _inkColor);

  String get _inkColor {
    final custom = widget.app.penCustomColor;
    if (custom != null) return '#$custom';
    final colors = OnoteColors.drawingColors(
        dark: Theme.of(context).brightness == Brightness.dark,
        highlighter: false);
    return '#${(colors[widget.app.penColor % colors.length].toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  void _insert() {
    final app = widget.app;
    if (_profile.samples.isEmpty || _profile.missing(_text.text).isNotEmpty) {
      return;
    }
    final at =
        app.smartTextPosition(app.canvas.screenToPage(const Offset(60, 100)));
    final block = app.insertHandwriting(_generate(origin: at));
    if (block != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canInsert = widget.app.pageId != null &&
        !widget.app.isPageLocked(widget.app.pageId!);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: Text(tr(context, 'My handwriting · Beta'),
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                  tooltip: tr(context, 'Close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const AppText('1. Learn handwriting'),
                showCheckmark: false,
                selected: !_write,
                onSelected: (_) => setState(() => _write = false),
              ),
              ChoiceChip(
                label: const AppText('2. Write text'),
                showCheckmark: false,
                selected: _write,
                onSelected: (_) => setState(() => _write = true),
              ),
            ]),
            const SizedBox(height: 16),
            Flexible(
                child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.trackpad
              }),
              child: SingleChildScrollView(
                child: _write ? _generation(canInsert) : _training(),
              ),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _training() {
    final variants = _profile.samples[_character] ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const AppText(
          'Write each character yourself with a pen or mouse. Keep the baseline and size consistent. Save several variants for more variety. Samples stay on this device.'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey('handwriting-character-$_character'),
          initialValue: _character,
          decoration: InputDecoration(labelText: tr(context, 'Character')),
          items: [
            for (final c in _characters)
              DropdownMenuItem(
                  value: c,
                  child:
                      Text('$c  ${_profile.samples.containsKey(c) ? '✓' : ''}'))
          ],
          onChanged: (c) {
            if (c != null) _train(c);
          },
        )),
        const SizedBox(width: 16),
        Text('${variants.length}/5 ${tr(context, 'variants')}'),
      ]),
      const SizedBox(height: 12),
      Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _WritingPad(key: _padKey, onChanged: () => setState(() {})),
      )),
      const SizedBox(height: 8),
      const AppText(
          'Write between the upper guide and the baseline. Descenders go below the baseline. Touch is reserved for scrolling.'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        TextButton.icon(
            onPressed: () => _padKey.currentState?.undo(),
            icon: const Icon(Icons.undo),
            label: const AppText('Undo stroke')),
        TextButton(
            onPressed: () => _padKey.currentState?.clear(),
            child: const AppText('Clear')),
        OutlinedButton(
          onPressed: (_padKey.currentState?.strokes.isNotEmpty ?? false) &&
                  !(_padKey.currentState?.drawing ?? false)
              ? () => _save(next: false)
              : null,
          child: const AppText('Save variant'),
        ),
        FilledButton(
          key: const ValueKey('handwriting-save-next'),
          onPressed: (_padKey.currentState?.strokes.isNotEmpty ?? false) &&
                  !(_padKey.currentState?.drawing ?? false)
              ? () => _save(next: true)
              : null,
          child: const AppText('Save & next character'),
        ),
      ]),
      if (variants.isNotEmpty) ...[
        const SizedBox(height: 8),
        const AppText('Last saved variant'),
        SizedBox(
            height: 80,
            child: FittedBox(
                child: SizedBox(
              width: HandwritingProfile.boxWidth,
              height: HandwritingProfile.boxHeight,
              child: CustomPaint(
                  painter: InkPainter(variants.last,
                      autoColor: Theme.of(context).colorScheme.onSurface)),
            ))),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() {
                  variants.removeLast();
                  if (variants.isEmpty) _profile.samples.remove(_character);
                  widget.app.saveHandwritingProfile(_profile);
                });
              },
              child: const AppText('Remove last variant'),
            )),
      ],
      const SizedBox(height: 8),
      Text('${_profile.samples.length} ${tr(context, 'characters learned')}'),
      const AppText(
          'Beta uses individual characters. Connected cursive and learning from existing notes will come later.'),
    ]);
  }

  Widget _slider(String label, double value, double min, double max,
          ValueChanged<double> change,
          {int? divisions}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${tr(context, label)}: ${value.toStringAsFixed(1)}'),
          Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => setState(() => change(v))),
        ],
      );

  Widget _generation(bool canInsert) {
    final missing = _profile.missing(_text.text);
    final ready = _profile.samples.isNotEmpty &&
        missing.isEmpty &&
        _text.text.trim().isNotEmpty;
    final preview = ready ? _generate() : <Stroke>[];
    final previewHeight = preview.isEmpty
        ? 180.0
        : math.max(
            180.0, preview.map((s) => s.bounds().maxY).reduce(math.max) + 16);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_profile.samples.isEmpty) ...[
        const AppText(
            'First record your own characters in Learn handwriting. Text can only use characters you have saved.'),
        const SizedBox(height: 12),
      ],
      TextField(
        key: const ValueKey('handwriting-text'),
        controller: _text,
        minLines: 2,
        maxLines: 5,
        maxLength: 2000,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        decoration: InputDecoration(
            labelText: tr(context, 'Text to write'),
            border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      if (missing.isNotEmpty) ...[
        const AppText(
            'Record these missing characters first. Tap a character to learn it:'),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in missing)
            ActionChip(label: Text(c), onPressed: () => _train(c)),
        ]),
        const SizedBox(height: 12),
      ],
      _slider('Letter height', _height, 14, 60, (v) => _height = v,
          divisions: 46),
      _slider('Line width', _effectiveWidth, math.min(200, _maxWidth),
          _maxWidth, (v) => _width = v,
          divisions: 14),
      _slider('Word spacing', _words, .5, 2, (v) => _words = v, divisions: 15),
      _slider('Line spacing', _lines, 1, 2, (v) => _lines = v, divisions: 10),
      const AppText('Preview'),
      const SizedBox(height: 8),
      Container(
        height: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.hardEdge,
        child: InteractiveViewer(
          constrained: false,
          minScale: .2,
          maxScale: 3,
          child: SizedBox(
            width: _effectiveWidth + 32,
            height: previewHeight,
            child: CustomPaint(
                painter: InkPainter(preview,
                    autoColor: Theme.of(context).colorScheme.onSurface)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const AppText(
          'Insert as normal pen strokes, then erase, move or add your own writing. The saved samples remain unchanged.'),
      if (!canInsert) ...[
        const SizedBox(height: 8),
        const AppText('Open an unlocked page to insert handwriting.'),
      ],
      const SizedBox(height: 12),
      Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('handwriting-insert'),
            onPressed: ready && canInsert ? _insert : null,
            icon: const Icon(Icons.add),
            label: const AppText('Insert pen strokes'),
          )),
    ]);
  }
}

class _WritingPad extends StatefulWidget {
  const _WritingPad({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<_WritingPad> createState() => _WritingPadState();
}

class _WritingPadState extends State<_WritingPad> {
  final strokes = <Stroke>[];
  Stroke? _wet;
  int? _pointer;
  int _started = 0;
  bool get drawing => _pointer != null;

  void clear() {
    setState(() {
      strokes.clear();
      _wet = null;
      _pointer = null;
    });
    widget.onChanged();
  }

  void undo() {
    if (drawing || strokes.isEmpty) return;
    setState(strokes.removeLast);
    widget.onChanged();
  }

  void _point(PointerEvent event, Size size) {
    final point = Offset(
        (event.localPosition.dx / size.width * HandwritingProfile.boxWidth)
            .clamp(0, HandwritingProfile.boxWidth),
        (event.localPosition.dy / size.height * HandwritingProfile.boxHeight)
            .clamp(0, HandwritingProfile.boxHeight));
    _wet!.x.add(point.dx);
    _wet!.y.add(point.dy);
    _wet!.p.add(event.kind == PointerDeviceKind.stylus && event.pressure > 0
        ? event.pressure.clamp(.05, 1)
        : .5);
    _wet!.t.add(event.timeStamp.inMilliseconds - _started);
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: HandwritingProfile.boxWidth / HandwritingProfile.boxHeight,
        child: LayoutBuilder(builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return MouseRegion(
            cursor: SystemMouseCursors.precise,
            child: Listener(
              key: const ValueKey('handwriting-pad'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                if (_pointer != null ||
                    e.kind == PointerDeviceKind.touch ||
                    e.kind == PointerDeviceKind.invertedStylus ||
                    e.buttons != kPrimaryButton) {
                  return;
                }
                setState(() {
                  _pointer = e.pointer;
                  _started = e.timeStamp.inMilliseconds;
                  _wet = Stroke(
                      tool: 'pen', colorHex: 'auto', size: 2.5, strokeStart: 0);
                  _point(e, size);
                });
                widget.onChanged();
              },
              onPointerMove: (e) {
                if (_pointer == e.pointer) setState(() => _point(e, size));
              },
              onPointerUp: (e) {
                if (_pointer != e.pointer) return;
                setState(() {
                  _point(e, size);
                  strokes.add(_wet!);
                  _wet = null;
                  _pointer = null;
                });
                widget.onChanged();
              },
              onPointerCancel: (e) {
                if (_pointer != e.pointer) return;
                setState(() {
                  _wet = null;
                  _pointer = null;
                });
                widget.onChanged();
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8)),
                child: CustomPaint(
                    painter: _PadPainter(
                        strokes,
                        _wet,
                        Theme.of(context).colorScheme.onSurface,
                        Theme.of(context).colorScheme.outlineVariant)),
              ),
            ),
          );
        }),
      );
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes, this.wet, this.color, this.guide);
  final List<Stroke> strokes;
  final Stroke? wet;
  final Color color, guide;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / HandwritingProfile.boxWidth,
        size.height / HandwritingProfile.boxHeight);
    for (final y in [
      HandwritingProfile.baseline - HandwritingProfile.letterHeight,
      HandwritingProfile.baseline,
      144.0
    ]) {
      canvas.drawLine(
          Offset(8, y),
          Offset(HandwritingProfile.boxWidth - 8, y),
          Paint()
            ..color = guide
            ..strokeWidth = y == HandwritingProfile.baseline ? 1 : .5);
    }
    InkPainter(strokes, wet: wet, autoColor: color).paint(canvas,
        const Size(HandwritingProfile.boxWidth, HandwritingProfile.boxHeight));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PadPainter oldDelegate) => true;
}
