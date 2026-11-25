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
  late final HandwritingProfile _profile;
  final _text = TextEditingController();
  final _padKey = GlobalKey<_WritingPadState>();
  final _scroll = ScrollController();
  late String _character;
  late bool _write;
  bool _returnToText = false;
  double _height = 28, _width = 600, _words = 1, _lines = 1;

  @override
  void initState() {
    super.initState();
    _profile = widget.app.handwritingProfile;
    _character = _profile.pendingCharacters.firstOrNull ?? 'a';
    _write = _profile.isComplete;
  }

  double get _maxWidth => widget.app.pageProps.isPaged
      ? math.min(
          900, widget.app.pageProps.paper.width - AppState.sheetMargin * 2)
      : 900;
  double get _effectiveWidth => math.min(_width, _maxWidth);
  bool get _hasDrawing =>
      (_padKey.currentState?.strokes.isNotEmpty ?? false) &&
      !(_padKey.currentState?.drawing ?? false);
  bool get _ready =>
      _profile.isComplete &&
      _text.text.trim().isNotEmpty &&
      _profile.missing(_text.text).isEmpty;
  bool get _canInsert =>
      widget.app.pageId != null && !widget.app.isPageLocked(widget.app.pageId!);

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _train(String character, {bool returnToText = false}) {
    _padKey.currentState?.clear();
    _top();
    setState(() {
      _character = character;
      _returnToText = returnToText;
      _write = false;
    });
  }

  List<String> get _characters => {
        ...HandwritingProfile.characters.runes.map(String.fromCharCode),
        ..._profile.samples.keys,
        ..._profile.missing(_text.text),
      }.toList();

  void _save() {
    final pad = _padKey.currentState;
    if (pad == null || !_hasDrawing) return;
    final wasComplete = _profile.isComplete;
    _profile.addSample(_character, pad.strokes);
    widget.app.saveHandwritingProfile(_profile);
    pad.clear();
    _top();
    setState(() {
      if (!wasComplete) {
        _character = _profile.pendingCharacters.firstOrNull ?? _character;
        _write = _profile.isComplete;
      } else if (_returnToText) {
        _write = true;
        _returnToText = false;
      } else {
        final characters = _characters;
        _character = characters[
            (characters.indexOf(_character) + 1) % characters.length];
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
    if (!_ready || !_canInsert) return;
    final app = widget.app;
    final at =
        app.smartTextPosition(app.canvas.screenToPage(const Offset(60, 100)));
    if (app.insertHandwriting(_generate(origin: at)) != null) {
      Navigator.of(context).pop();
    }
  }

  String get _group {
    final index = HandwritingProfile.characters.indexOf(_character);
    if (index < 0) return 'Additional character';
    if (index < 30) return 'Lowercase letters';
    if (index < 59) return 'Uppercase letters';
    if (index < 69) return 'Numbers';
    return 'Punctuation';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: SizedBox(
          width: 720,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(tr(context, 'My handwriting'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  fontSize: 20, fontWeight: FontWeight.w500)),
                      Text(tr(context, 'Beta · saved on this device'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ])),
                IconButton(
                  tooltip: tr(context, 'Close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ]),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Flexible(
                child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.trackpad,
              }),
              child: SingleChildScrollView(
                key: const ValueKey('handwriting-scroll'),
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child:
                    _write && _profile.isComplete ? _generation() : _training(),
              ),
            )),
            Divider(height: 1, color: scheme.outlineVariant),
            _footer(),
          ]),
        ),
      ),
    );
  }

  Widget _training() {
    final scheme = Theme.of(context).colorScheme;
    final complete = _profile.isComplete;
    final variants = _profile.samples[_character] ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!complete) ...[
        Row(children: [
          Expanded(
              child: Text(tr(context, 'Set up your handwriting'),
                  style: Theme.of(context).textTheme.titleMedium)),
          Text(
              '${_profile.learnedCharacters} / ${HandwritingProfile.characters.runes.length}',
              key: const ValueKey('handwriting-progress'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: _profile.learnedCharacters /
              HandwritingProfile.characters.runes.length,
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
          semanticsLabel: tr(context, 'Handwriting setup'),
        ),
        const SizedBox(height: 12),
        Text(
            tr(context,
                'Conversion becomes available after all characters are saved.'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ] else ...[
        Row(children: [
          Expanded(
              child: DropdownButtonFormField<String>(
            key: ValueKey('handwriting-character-$_character'),
            isExpanded: true,
            initialValue: _character,
            decoration: InputDecoration(labelText: tr(context, 'Character')),
            items: [
              for (final c in _characters)
                DropdownMenuItem(value: c, child: Text(c))
            ],
            onChanged: (c) {
              if (c != null) _train(c);
            },
          )),
          const SizedBox(width: 12),
          Text('${variants.length}/5 ${tr(context, 'variants')}'),
        ]),
      ],
      const SizedBox(height: 20),
      Semantics(
          liveRegion: true,
          child: Row(children: [
            SizedBox(
                width: 80,
                child: Text(_character,
                    key: const ValueKey('handwriting-current-character'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 64,
                        height: 1.1,
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurface))),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      tr(
                          context,
                          complete
                              ? 'Write another variant'
                              : 'Write this character'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(tr(context, _group),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ])),
          ])),
      const SizedBox(height: 16),
      Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 396),
        child: _WritingPad(key: _padKey, onChanged: () => setState(() {})),
      )),
      const SizedBox(height: 8),
      Row(children: [
        IconButton(
          tooltip: tr(context, 'Undo stroke'),
          onPressed: _hasDrawing ? () => _padKey.currentState?.undo() : null,
          icon: const Icon(Icons.undo_outlined, size: 18),
        ),
        TextButton(
            onPressed: _hasDrawing ? () => _padKey.currentState?.clear() : null,
            child: const AppText('Write again')),
        const Spacer(),
        if (variants.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: tr(context, 'Saved variants'),
            icon: const Icon(Icons.more_horiz, size: 20),
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'remove', child: AppText('Remove last variant'))
            ],
            onSelected: (_) {
              setState(() {
                variants.removeLast();
                if (variants.isEmpty) _profile.samples.remove(_character);
                widget.app.saveHandwritingProfile(_profile);
              });
            },
          ),
      ]),
      Text(tr(context, 'Pen or mouse to write. Finger to scroll.'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
      if (variants.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(tr(context, 'Last saved variant'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        SizedBox(
            height: 64,
            child: FittedBox(
                child: SizedBox(
              width: HandwritingProfile.boxWidth,
              height: HandwritingProfile.boxHeight,
              child: CustomPaint(
                  painter:
                      InkPainter(variants.last, autoColor: scheme.onSurface)),
            ))),
      ],
    ]);
  }

  Widget _footer() {
    final setup = !_profile.isComplete;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_write && _profile.isComplete && !_canInsert) ...[
          Text(tr(context, 'Open an unlocked page to insert handwriting.'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
        Row(children: [
          if (!_write && !setup) ...[
            TextButton(
                onPressed: () {
                  _top();
                  setState(() => _write = true);
                },
                child: const AppText('Back to text')),
            const SizedBox(width: 12),
          ],
          Expanded(
              child: FilledButton(
            key: ValueKey(_write && !setup
                ? 'handwriting-insert'
                : 'handwriting-save-next'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _write && !setup
                ? (_ready && _canInsert ? _insert : null)
                : (_hasDrawing ? _save : null),
            child: AppText(_write && !setup
                ? 'Insert pen strokes'
                : (setup && _profile.pendingCharacters.length == 1
                    ? 'Finish setup'
                    : 'Confirm & continue')),
          )),
        ]),
      ]),
    );
  }

  Widget _slider(String label, double value, double min, double max,
          ValueChanged<double> change,
          {int? divisions}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${tr(context, label)}: ${value.toStringAsFixed(1)}'),
        Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) => setState(() => change(v))),
      ]);

  Widget _generation() {
    final scheme = Theme.of(context).colorScheme;
    final missing = _profile.missing(_text.text);
    final preview = _ready ? _generate() : <Stroke>[];
    final previewHeight = preview.isEmpty
        ? 180.0
        : math.max(
            180.0, preview.map((s) => s.bounds().maxY).reduce(math.max) + 16);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_outline,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            const AppText('Your handwriting is ready'),
          ]),
          TextButton(
              onPressed: () => _train('a'),
              child: const AppText('Edit handwriting')),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('handwriting-text'),
        controller: _text,
        minLines: 2,
        maxLines: 4,
        maxLength: 2000,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        decoration: InputDecoration(
            labelText: tr(context, 'Text to write'),
            hintText: tr(context, 'Type here. Your handwriting appears below.'),
            border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      if (missing.isNotEmpty) ...[
        const AppText(
            'Record these missing characters first. Tap a character to learn it:'),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in missing)
            ActionChip(
                label: Text(c), onPressed: () => _train(c, returnToText: true)),
        ]),
        const SizedBox(height: 12),
      ],
      const AppText('Preview'),
      const SizedBox(height: 8),
      Container(
        height: 220,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.hardEdge,
        child: preview.isEmpty
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr(context, 'Your text, in your handwriting'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant))))
            : InteractiveViewer(
                constrained: false,
                minScale: .2,
                maxScale: 3,
                child: SizedBox(
                    width: _effectiveWidth + 32,
                    height: previewHeight,
                    child: CustomPaint(
                        painter:
                            InkPainter(preview, autoColor: scheme.onSurface)))),
      ),
      const SizedBox(height: 12),
      ExpansionTile(
        key: const ValueKey('handwriting-layout'),
        tilePadding: EdgeInsets.zero,
        title: const AppText('Size & spacing'),
        children: [
          _slider('Letter height', _height, 14, 60, (v) => _height = v,
              divisions: 46),
          _slider('Line width', _effectiveWidth, math.min(200, _maxWidth),
              _maxWidth, (v) => _width = v,
              divisions: 14),
          _slider('Word spacing', _words, .5, 2, (v) => _words = v,
              divisions: 15),
          _slider('Line spacing', _lines, 1, 2, (v) => _lines = v,
              divisions: 10),
        ],
      ),
      const SizedBox(height: 8),
      Text(
          tr(context,
              'Inserted as editable pen strokes. Erase, move or write between them.'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
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
