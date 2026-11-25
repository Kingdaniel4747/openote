import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/ink_painter.dart';
import '../canvas/writing_touch_guard.dart';
import '../ink/handwriting_profile.dart';
import '../l10n/app_strings.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'handwriting_pad.dart';

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

enum _HandwritingView { setup, overview, edit, text }

class _HandwritingDialogState extends State<HandwritingDialog> {
  late final HandwritingProfile _profile;
  final _text = TextEditingController();
  final _padKey = GlobalKey<HandwritingPadState>();
  final _dialogKey = GlobalKey();
  final _headerKey = GlobalKey();
  final _footerKey = GlobalKey();
  final _controlsKey = GlobalKey();
  final _resetActionsKey = GlobalKey();
  final _scroll = ScrollController();
  WritingTouchGuard? _touchGuard;
  late String _character;
  late _HandwritingView _view;
  int? _variant;
  int _draftRevision = 0;
  List<Stroke> _initialStrokes = const [];
  bool _returnToText = false, _canSave = false, _saved = false;
  bool _resetPending = false;
  double _height = 28, _width = 600, _words = 1, _lines = 1;

  @override
  void initState() {
    super.initState();
    _profile = widget.app.handwritingProfile;
    _character = _profile.pendingCharacters.firstOrNull ?? 'a';
    _view =
        _profile.isComplete ? _HandwritingView.text : _HandwritingView.setup;
    final binding = WidgetsBinding.instance;
    if (binding is WritingTouchBinding) {
      _touchGuard = (binding as WritingTouchBinding).writingTouchGuard;
      _touchGuard!.registerControlTarget(this, _controlHit);
    }
  }

  bool _controlHit(PointerDownEvent event) {
    final root = _dialogKey.currentContext?.findRenderObject();
    if (!mounted || root is! RenderBox || !root.hasSize) return false;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    final resetActions = _resetActionsKey.currentContext?.findRenderObject();
    if (resetActions is RenderBox &&
        hit.path.any((entry) => entry.target == resetActions)) {
      return true;
    }
    if (!hit.path.any((entry) => entry.target == root)) return false;
    // These explicit regions are outside the writing pad. A previous palm
    // contact is never promoted by this callback.
    for (final key in [_headerKey, _footerKey, _controlsKey]) {
      final box = key.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          (Offset.zero & box.size)
              .contains(box.globalToLocal(event.position))) {
        return true;
      }
    }
    return false;
  }

  double get _maxWidth => widget.app.pageProps.isPaged
      ? math.min(
          900, widget.app.pageProps.paper.width - AppState.sheetMargin * 2)
      : 900;
  double get _effectiveWidth => math.min(_width, _maxWidth);
  bool get _write => _view == _HandwritingView.text;
  bool get _ready =>
      _profile.isComplete &&
      _text.text.trim().isNotEmpty &&
      _profile.missing(_text.text).isEmpty;
  bool get _canInsert =>
      widget.app.pageId != null && !widget.app.isPageLocked(widget.app.pageId!);
  List<String> get _characters => {
        ...HandwritingProfile.characters.runes.map(String.fromCharCode),
        ..._profile.samples.keys,
        ..._profile.missing(_text.text),
      }.toList();

  @override
  void dispose() {
    _touchGuard?.unregisterControlTarget(this);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _openOverview() {
    _discardEmptyVariant();
    _top();
    setState(() {
      _view = _HandwritingView.overview;
      _canSave = false;
    });
  }

  void _backFromCharacter() {
    _discardEmptyVariant();
    _top();
    setState(() {
      _view = _returnToText && _profile.isComplete
          ? _HandwritingView.text
          : _HandwritingView.overview;
      _returnToText = false;
      _canSave = false;
    });
  }

  /// Empty saved variants disappear on leaving; unsaved nonempty edits still
  /// require Save. A new empty draft never occupies a stored variant slot.
  int? _discardEmptyVariant() {
    final pad = _padKey.currentState;
    if (_view != _HandwritingView.edit ||
        _variant == null ||
        pad == null ||
        pad.widget.sampleToken != '$_character:$_draftRevision' ||
        pad.drawing ||
        pad.strokes.isNotEmpty) {
      return null;
    }
    final removed = _variant!;
    _profile.removeVariant(_character, removed);
    widget.app.saveHandwritingProfile(_profile);
    _variant = null;
    return removed;
  }

  void _selectVariant(int? index) {
    final removed = _discardEmptyVariant();
    if (removed != null && index != null) {
      if (index == removed) {
        index = null;
      } else if (index > removed) {
        index--;
      }
    }
    _top();
    setState(() => _loadVariant(index));
  }

  Future<void> _resetHandwriting() async {
    if (_resetPending || _profile.samples.isEmpty) return;
    setState(() => _resetPending = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const AppText('Delete all handwriting samples?'),
          content: const AppText(
              'All learned characters and variants on this device will be deleted. Handwriting already inserted into your pages is kept. Setup will start again from the beginning.'),
          actions: [
            Wrap(key: _resetActionsKey, spacing: 12, runSpacing: 8, children: [
              TextButton(
                key: const ValueKey('handwriting-reset-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const AppText('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('handwriting-reset-confirm'),
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    minimumSize: const Size(0, 48),
                    visualDensity: VisualDensity.standard),
                onPressed: () => Navigator.of(context).pop(true),
                child: const AppText('Delete everything & restart'),
              ),
            ]),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      _profile.samples.clear();
      widget.app.saveHandwritingProfile(_profile);
      _text.clear();
      _top();
      setState(() {
        _character = 'a';
        _view = _HandwritingView.setup;
        _returnToText = false;
        _height = 28;
        _width = 600;
        _words = 1;
        _lines = 1;
        _loadVariant(null);
      });
    } finally {
      if (mounted) setState(() => _resetPending = false);
    }
  }

  void _openCharacter(String character, {bool returnToText = false}) {
    _top();
    final variants = _profile.samples[character] ?? [];
    setState(() {
      _character = character;
      _returnToText = returnToText;
      _view = _HandwritingView.edit;
      _loadVariant(variants.isEmpty ? null : 0);
    });
  }

  void _loadVariant(int? index) {
    _variant = index;
    _initialStrokes =
        index == null ? const [] : _profile.samples[_character]![index];
    _canSave = _initialStrokes.isNotEmpty;
    _saved = false;
    _draftRevision++;
  }

  void _save() {
    final pad = _padKey.currentState;
    if (!_canSave || pad == null || pad.drawing) return;
    final savedIndex = _variant ?? (_profile.samples[_character]?.length ?? 0);
    if (!_profile.saveVariant(_character, pad.strokes,
        index: _view == _HandwritingView.edit ? _variant : null)) {
      return;
    }
    widget.app.saveHandwritingProfile(_profile);
    _top();
    setState(() {
      if (_view == _HandwritingView.setup) {
        _character = _profile.pendingCharacters.firstOrNull ?? _character;
        _view = _profile.isComplete
            ? _HandwritingView.text
            : _HandwritingView.setup;
        _loadVariant(null);
      } else {
        final hasRoom = (_profile.samples[_character]?.length ?? 0) < 5;
        _loadVariant(hasRoom ? null : savedIndex);
        _saved = true;
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
    final editing = _view == _HandwritingView.edit;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 820),
        child: SizedBox(
          key: _dialogKey,
          width: 860,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              key: _headerKey,
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(children: [
                if (editing)
                  IconButton(
                    key: const ValueKey('handwriting-back-overview'),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        visualDensity: VisualDensity.standard),
                    tooltip: tr(context, 'All characters'),
                    onPressed: _backFromCharacter,
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          tr(
                              context,
                              _view == _HandwritingView.overview
                                  ? 'All characters'
                                  : 'My handwriting'),
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
                    key: const ValueKey('handwriting-reset'),
                    tooltip: tr(context, 'Delete all handwriting & start over'),
                    style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        visualDensity: VisualDensity.standard),
                    onPressed: _profile.samples.isEmpty || _resetPending
                        ? null
                        : _resetHandwriting,
                    icon: const Icon(Icons.restart_alt, size: 20)),
                IconButton(
                    style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        visualDensity: VisualDensity.standard),
                    tooltip: tr(context, 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20)),
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
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: switch (_view) {
                  _HandwritingView.text => _generation(),
                  _HandwritingView.overview => _overview(),
                  _ => _training(),
                },
              ),
            )),
            Divider(height: 1, color: scheme.outlineVariant),
            _footer(),
          ]),
        ),
      ),
    );
  }

  Widget _sample(String character, List<Stroke> strokes) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
        aspectRatio: HandwritingProfile.boxWidth / HandwritingProfile.boxHeight,
        child: CustomPaint(
            painter: HandwritingSamplePainter(
                character: character,
                strokes: strokes,
                ink: scheme.onSurface,
                guide: scheme.onSurfaceVariant)));
  }

  Widget _overview() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
        key: _controlsKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr(context, 'Tap a character to compare and edit its variants.'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final columns = math.max(2, (constraints.maxWidth / 108).floor());
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _characters)
                SizedBox(
                    width: width,
                    child: Material(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        key: ValueKey('handwriting-tile-$c'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openCharacter(c),
                        child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(children: [
                              Row(children: [
                                Text(c,
                                    style:
                                        Theme.of(context).textTheme.labelLarge),
                                const Spacer(),
                                Text('${_profile.samples[c]?.length ?? 0}/5',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: scheme.onSurfaceVariant)),
                              ]),
                              const SizedBox(height: 4),
                              _sample(c,
                                  _profile.samples[c]?.firstOrNull ?? const []),
                            ])),
                      ),
                    )),
            ]);
          }),
        ]);
  }

  Widget _training() {
    final scheme = Theme.of(context).colorScheme;
    final setup = _view == _HandwritingView.setup;
    final variants = _profile.samples[_character] ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (setup) ...[
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
        const SizedBox(height: 8),
        LinearProgressIndicator(
            value: _profile.learnedCharacters /
                HandwritingProfile.characters.runes.length,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
            semanticsLabel: tr(context, 'Handwriting setup')),
        const SizedBox(height: 8),
        Text(
            tr(context,
                'Conversion becomes available after all characters are saved.'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
      ],
      Row(children: [
        Text(_character,
            key: const ValueKey('handwriting-current-character'),
            style:
                TextStyle(fontSize: 32, height: 1.2, color: scheme.onSurface)),
        const SizedBox(width: 16),
        Expanded(
            child: Text(tr(context, _group),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant))),
      ]),
      const SizedBox(height: 12),
      Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: HandwritingPad(
          key: _padKey,
          character: _character,
          sampleToken: '$_character:$_draftRevision',
          initialStrokes: _initialStrokes,
          onChanged: () => setState(() {
            final pad = _padKey.currentState;
            _canSave = pad != null && !pad.drawing && pad.strokes.isNotEmpty;
            _saved = false;
          }),
        ),
      )),
      const SizedBox(height: 8),
      Column(
          key: _controlsKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
                child: IconButton(
              key: const ValueKey('handwriting-retry'),
              tooltip: tr(context, 'Write again'),
              style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  visualDensity: VisualDensity.standard),
              onPressed: _canSave ? () => _padKey.currentState?.clear() : null,
              icon: const Icon(Icons.refresh_rounded, size: 24),
            )),
            const SizedBox(height: 4),
            Text(
                tr(context,
                    'Trace the size, keep your own letter shape. The pen button also erases.'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (!setup) ...[
              const SizedBox(height: 20),
              const AppText('Variants'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < variants.length; i++)
                  _variantTile(i, variants[i]),
                if (variants.length < 5) _variantTile(null, const []),
              ]),
            ],
          ]),
    ]);
  }

  Widget _variantTile(int? index, List<Stroke> strokes) {
    final scheme = Theme.of(context).colorScheme;
    final selected = index == _variant;
    final pad = _padKey.currentState;
    final preview = selected &&
            pad != null &&
            pad.widget.sampleToken == '$_character:$_draftRevision'
        ? pad.strokes
        : strokes;
    return SizedBox(
        width: 112,
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: .08)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey(index == null
                ? 'handwriting-new-variant'
                : 'handwriting-variant-$index'),
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              _selectVariant(index);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          selected ? scheme.primary : scheme.outlineVariant)),
              child: Column(children: [
                Text(
                    index == null
                        ? tr(context, 'New variant')
                        : '${tr(context, 'Variant')} ${index + 1}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                _sample(_character, preview),
              ]),
            ),
          ),
        ));
  }

  Widget _footer() {
    final editing =
        _view == _HandwritingView.edit || _view == _HandwritingView.setup;
    return Padding(
      key: _footerKey,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_write && !_canInsert) ...[
          Text(tr(context, 'Open an unlocked page to insert handwriting.'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
        if (editing)
          FilledButton(
            key: const ValueKey('handwriting-save-next'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                visualDensity: VisualDensity.standard),
            onPressed: _canSave && !_saved ? _save : null,
            child: AppText(_view == _HandwritingView.edit
                ? (_saved ? 'Saved' : 'Save variant')
                : (_profile.pendingCharacters.length == 1 ? 'Finish' : 'Next')),
          )
        else
          FilledButton(
            key: ValueKey(
                _write ? 'handwriting-insert' : 'handwriting-overview-done'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                visualDensity: VisualDensity.standard),
            onPressed: _write
                ? (_ready && _canInsert ? _insert : null)
                : () {
                    _top();
                    setState(() {
                      _view = _profile.isComplete
                          ? _HandwritingView.text
                          : _HandwritingView.setup;
                      _character =
                          _profile.pendingCharacters.firstOrNull ?? 'a';
                      _loadVariant(null);
                    });
                  },
            child: AppText(_write
                ? 'Insert pen strokes'
                : (_profile.isComplete ? 'Back to text' : 'Continue setup')),
          ),
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
    return Column(
        key: _controlsKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  onPressed: _openOverview,
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
                hintText:
                    tr(context, 'Type here. Your handwriting appears below.'),
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
                    label: Text(c),
                    onPressed: () => _openCharacter(c, returnToText: true)),
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
                        child: Text(
                            tr(context, 'Your text, in your handwriting'),
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
                            painter: InkPainter(preview,
                                autoColor: scheme.onSurface)))),
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
