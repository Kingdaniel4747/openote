import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';

import '../editor/list_editing.dart';
import '../canvas/media_drop.dart';

import '../markdown/md_syntax.dart';
import '../state/app_state.dart';
import '../platform/screen_capture.dart';
import '../theme/onote_theme.dart';
import 'color_picker.dart';
import 'command_button.dart';
import 'compacting_toolbar.dart';
import 'fixed_toolbar.dart';
import 'font_picker.dart';
import 'insert_catalog.dart';
import 'object_face.dart';
import 'object_row.dart';
import 'onote_switch.dart';
import 'settings_dialog.dart';
import 'learning_access_dialog.dart';
import 'handwriting_dialog.dart';
import 'scanner_pairing_dialog.dart';
import 'update_dialog.dart';
import '../theme/tokens.dart';
import 'windows_window_frame.dart';

class _InkSizeIndicator extends SliderComponentShape {
  const _InkSizeIndicator(this.width, {this.maxWidth = 24});
  final double width;
  final double maxWidth;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(32, 32);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final at = center + const Offset(0, -35);
    final scale = activationAnimation.value;
    context.canvas.drawCircle(at, 16 * scale,
        Paint()..color = sliderTheme.valueIndicatorColor ?? Colors.black);
    context.canvas.drawCircle(
        at,
        width / maxWidth * 12 * scale,
        Paint()
          ..color = sliderTheme.valueIndicatorTextStyle?.color ?? Colors.white);
  }
}

/// The tabbed command bar (style guide §7 revised): Home · Insert · Draw ·
/// View. OneNote's few-clicks accessibility in Openote's calm language — a
/// slim tab row over a single command row of grouped icon buttons.
class CommandBar extends StatefulWidget {
  const CommandBar({
    super.key,
    required this.app,
    this.titlebarOnly = false,
    this.drawOnly = false,
    this.verticalDrawOnly = false,
  });
  final AppState app;
  final bool titlebarOnly;
  final bool drawOnly;
  final bool verticalDrawOnly;

  @override
  State<CommandBar> createState() => _CommandBarState();
}

/// The planner is a to-do inbox, so its toolbar entry shows the same compact
/// count as the month grid. A number is more useful than a generic calendar
/// glyph when the student has just opened the app to see what is waiting.
class _PlannerButton extends StatelessWidget {
  const _PlannerButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final count = app.planner
        .agenda()
        .where((item) => !item.done && item.kind.name != 'event')
        .length;
    return Stack(clipBehavior: Clip.none, children: [
      IconButton(
        icon: const Icon(Icons.calendar_month_outlined, size: 18),
        tooltip: 'Hausaufgaben, To-dos und Klausuren',
        isSelected: app.showPlannerPanel,
        visualDensity: VisualDensity.compact,
        onPressed: app.togglePlannerPanel,
      ),
      if (count > 0)
        Positioned(
          right: 3,
          top: 3,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 14),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onPrimary)),
            ),
          ),
        ),
    ]);
  }
}

class _CommandBarState extends State<CommandBar> {
  /// The tab the user last chose among the permanent ones.
  int _tab = 0;
  late int _drawRequest;

  @override
  void initState() {
    super.initState();
    _drawRequest = app.drawTabRequest;
    app.addListener(_followDrawing);
  }

  void _followDrawing() {
    if (_drawRequest == app.drawTabRequest) return;
    _drawRequest = app.drawTabRequest;
    if (mounted && _tab != 2) setState(() => _tab = 2);
  }

  @override
  void didUpdateWidget(CommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != app) {
      oldWidget.app.removeListener(_followDrawing);
      _drawRequest = app.drawTabRequest;
      app.addListener(_followDrawing);
    }
  }

  @override
  void dispose() {
    app.removeListener(_followDrawing);
    super.dispose();
  }

  /// Home is write and format, Insert is add, Draw is ink, and View owns page
  /// appearance and zoom. Actual stylus drawing opens Draw; hover does not.
  static const _tabs = ['Home', 'Insert', 'Draw', 'View'];

  AppState get app => widget.app;

  Future<void> _insertScreenRegion(BuildContext context) async {
    Uint8List? bytes;
    try {
      bytes = await ScreenCapture.selectRegion();
    } on PlatformException catch (_) {
      // A cancelled or interrupted native overlay is equivalent to cancelling
      // the picker. Crucially, no stale selection is kept for the next use.
      return;
    }
    if (bytes == null || bytes.isEmpty || !context.mounted) return;
    ui.Codec? codec;
    ui.FrameInfo? frame;
    double? naturalWidth;
    double? naturalHeight;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      frame = await codec.getNextFrame();
      naturalWidth = frame.image.width.toDouble();
      naturalHeight = frame.image.height.toDouble();
    } catch (_) {
      // The native selector always sends PNG, but retaining the insertion path
      // keeps a captured file useful even if a future encoder changes.
    } finally {
      frame?.image.dispose();
      codec?.dispose();
    }
    if (!context.mounted) return;
    final at = app.canvas.screenToPage(
      Offset(app.canvas.viewport.width / 2, app.canvas.viewport.height / 2),
    );
    final width = naturalWidth == null
        ? 480.0
        : naturalWidth.clamp(160.0, 720.0).toDouble();
    final height = naturalHeight != null && naturalWidth != null
        ? width * naturalHeight / naturalWidth
        : null;
    insertImageBytes(
      app,
      bytes,
      'image/png',
      at,
      width: width,
      height: height,
      naturalWidth: naturalWidth,
      naturalHeight: naturalHeight,
    );
  }

  List<Widget> _utilityControls(BuildContext context, ColorScheme scheme) => [
        // The trailing cluster COMPACTS rather than scrolling.
        //
        // Reported: "it doesnt handle resizing well (menus should
        // either compact as required or become sliding, again i
        // belive the former is cleaner)." A `Row` that overflows is
        // CLIPPED, and clipped pixels do not hit-test — so on a
        // narrow window (laptop + navigator open) the rightmost
        // buttons used to stop responding, and the horizontal-scroll
        // fix that followed traded that for "responds, but you can't
        // see it without scrolling first." `CompactingToolbar` folds
        // whatever does not fit into one "More" menu instead —
        // `alignment: end` keeps it flush against the window edge,
        // the one thing the scrolling version got right.
        Expanded(
          child: CompactingToolbar(
            alignment: MainAxisAlignment.end,
            fillAvailable: true,
            controls: [
              // Update-through-app: the "little update button" of
              // the original update feature request. Exists only when launch found a newer
              // release, and leads with the version so the tooltip
              // answers "to what?" before the click.
              if (app.updateAvailable != null)
                ToolbarControl(
                  width: 40,
                  icon: Icons.system_update_alt,
                  label: 'Update to ${app.updateAvailable!.version}…',
                  onPressed: () => showUpdateDialog(context, app),
                  inline: IconButton(
                    icon: Icon(
                      Icons.system_update_alt,
                      size: 18,
                      color: scheme.primary,
                    ),
                    tooltip: 'Update to ${app.updateAvailable!.version}…',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showUpdateDialog(context, app),
                  ),
                ),
              ToolbarControl(
                width: 40,
                icon: Icons.search,
                label: 'Find on page',
                selected: app.findOpen,
                onPressed: app.toggleFind,
                inline: IconButton(
                  icon: const Icon(Icons.search, size: 18),
                  tooltip: tr(context, 'Find on page  (Ctrl+F)'),
                  isSelected: app.findOpen,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleFind,
                ),
              ),
            ],
          ),
        ),
        _PlannerButton(app: app),
        LearningAccessButton(app: app),
        HandwritingButton(app: app),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 18),
          tooltip: tr(context, 'Settings…'),
          visualDensity: VisualDensity.compact,
          onPressed: () => showSettingsDialog(context, app),
        ),
        const WindowsCaptionButtons(),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.drawOnly) {
      return Material(
        color: scheme.surface,
        child: SingleChildScrollView(
          scrollDirection:
              widget.verticalDrawOnly ? Axis.vertical : Axis.horizontal,
          child: _drawRow(context, vertical: widget.verticalDrawOnly),
        ),
      );
    }
    if (widget.titlebarOnly) {
      final window = WindowsWindowFrame.of(context);
      return Material(
        color: scheme.surface,
        child: SizedBox(
          height: 36,
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => window?.beginDrag(),
                onDoubleTap: window?.maximize,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppText('Openote'),
                  ),
                ),
              ),
            ),
            _PlannerButton(app: app),
            LearningAccessButton(app: app),
            HandwritingButton(app: app),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 18),
              tooltip: tr(context, 'Settings…'),
              visualDensity: VisualDensity.compact,
              onPressed: () => showSettingsDialog(context, app),
            ),
            const WindowsCaptionButtons(),
          ]),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // ── Tab row ──
          SizedBox(
            height: 32,
            child: LayoutBuilder(builder: (context, constraints) {
              final compactTabRow = constraints.maxWidth < 700;
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen, size: 18),
                    tooltip: tr(context, 'Writing mode'),
                    visualDensity: VisualDensity.compact,
                    constraints: compactTabRow
                        ? const BoxConstraints.tightFor(width: 36, height: 32)
                        : null,
                    padding: compactTabRow ? EdgeInsets.zero : null,
                    onPressed: () => app.setWritingMode(true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.undo, size: 18),
                    tooltip: tr(context, 'Undo  (Ctrl+Z)'),
                    visualDensity: VisualDensity.compact,
                    constraints: compactTabRow
                        ? const BoxConstraints.tightFor(width: 36, height: 32)
                        : null,
                    padding: compactTabRow ? EdgeInsets.zero : null,
                    onPressed: app.canUndo ? app.undo : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo, size: 18),
                    tooltip: tr(context, 'Redo  (Ctrl+Y)'),
                    visualDensity: VisualDensity.compact,
                    constraints: compactTabRow
                        ? const BoxConstraints.tightFor(width: 36, height: 32)
                        : null,
                    padding: compactTabRow ? EdgeInsets.zero : null,
                    onPressed: app.canRedo ? app.redo : null,
                  ),
                  const SizedBox(width: 4),
                  // **No leading gutter.** A fixed chrome region runs to the edge
                  // of the region it owns (§7d); the first control's own padding
                  // is the optical margin. An extra 6px here made the toolbar
                  // look inset from the window — a floating strip rather than
                  // part of the frame — and cost hit area at the screen edge,
                  // which is the one place a pointer can be thrown at infinitely
                  // fast (Fitts's law) and always land.
                  for (var i = 0; i < _tabs.length; i++)
                    _tabButton(scheme, i, _tabs[i], compact: compactTabRow),
                  // **A badge, not a tab.** It says what the row below is
                  // about and it cannot be pressed, so there is nothing here to
                  // be moved onto and nothing to be moved back from. It sits
                  // where the old Maths tab sat, deliberately: same place,
                  // opposite kind.
                  if (objectFaceOf(app) == ObjectFace.equation)
                    const _SubjectBadge(
                        icon: Icons.functions, label: 'Equation'),
                  const Spacer(),
                  if (WindowsWindowFrame.of(context)?.customChrome != true)
                    ..._utilityControls(context, scheme),
                ],
              );
            }),
          ),
          // ── Command row ──
          // Horizontally scrollable so a narrow window scrolls the controls
          // instead of throwing a RenderFlex overflow (style guide §7).
          Container(
            height: 44,
            // Flush left for the same reason as the tab row above it, so the
            // two rows share an edge instead of being inset by different
            // amounts. `IconButton` brings its own 8px, which is the margin.
            alignment: Alignment.centerLeft,
            // Tab switches animate (PLANNING "Consistency/UX": "animation
            // switching between menus"): the outgoing row fades as the new
            // one fades in with a small upward drift — same 150ms register
            // as the dialog transition, so the app has ONE sense of motion.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.15),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: _tab == 1
                    ? _insertRow(context)
                    : _tab == 2
                        ? _drawRow(context)
                        : _tab == 3
                            ? PageFace(app: app)
                            : _homeRow(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeRow(BuildContext context) {
    // Enable from state, not child build order (fixes the greyed-out bug).
    final canFormat = app.canFormatText;
    // What is switched ON at the caret. With the markers collapsed to nothing
    // in the editor, these buttons are the ONLY thing that can tell a student
    // whether the word they are in is already bold — "just have it appear in
    // the toolbar as on" was the whole request.
    final active = app.marksAtCaret();
    Widget fmt(IconData icon, String tip, VoidCallback fn, [MdInline? mark]) =>
        IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tr(context, tip),
          visualDensity: VisualDensity.compact,
          isSelected: mark != null && active.contains(mark),
          onPressed: canFormat ? fn : null,
        );
    final lcv = int.tryParse(app.lastColor, radix: 16) ?? 0;
    final curColor = app.lastColor.length == 8
        ? Color(((lcv & 0xFF) << 24) | (lcv >> 8))
        : Color(0xFF000000 | lcv);
    return FixedToolbar(
      children: [
        // **The row never changes shape.** An earlier revision collapsed the
        // formatting commands to three group heads when nothing was focused, on
        // the reasoning that a wall of greyed glyphs reads as broken. That traded
        // one problem for a worse one: clicking into a text box made ~15 buttons
        // appear and shoved everything to their right across the toolbar, so the
        // control you were reaching for moved out from under the pointer at the
        // exact moment you started using the app. Layout that moves while you aim
        // at it is a harder failure than layout that looks quiet.
        //
        // So: "disabled ≠ hidden" (§7a.2) applies without exception here. Every
        // command holds its position always; the ones that need a caret are
        // greyed, and the hint at the end of the row — which only ever appears
        // AFTER the last control, so it displaces nothing — says why.
        fmt(
          Icons.format_bold,
          'Bold  (Ctrl+B)',
          () => app.wrapSelection('**'),
          MdInline.bold,
        ),
        fmt(
          Icons.format_italic,
          'Italic  (Ctrl+I)',
          () => app.wrapSelection('*'),
          MdInline.italic,
        ),
        fmt(
          Icons.format_underlined,
          'Underline  (Ctrl+U)',
          () => app.wrapSelection('++'),
          MdInline.underline,
        ),
        fmt(
          Icons.strikethrough_s,
          'Strikethrough',
          () => app.wrapSelection('~~'),
          MdInline.strike,
        ),
        fmt(
          Icons.code,
          'Inline code',
          () => app.wrapSelection('`'),
          MdInline.code,
        ),
        fmt(
          Icons.border_color,
          'Highlight',
          () => app.wrapSelection('=='),
          MdInline.highlight,
        ),
        const _Div(),
        fmt(Icons.title, 'Heading 1', () => app.toggleLinePrefix('# ')),
        _TextBtn('H2', canFormat, () => app.toggleLinePrefix('## ')),
        _TextBtn('H3', canFormat, () => app.toggleLinePrefix('### ')),
        const _Div(),
        fmt(
          Icons.format_list_bulleted,
          'Bullet list',
          () => app.toggleList(ListKind.bullet),
        ),
        fmt(
          Icons.format_list_numbered,
          'Numbered list',
          () => app.toggleList(ListKind.numbered),
        ),
        fmt(
          Icons.check_box_outlined,
          'Checkbox',
          () => app.toggleList(ListKind.checkbox),
        ),
        fmt(Icons.format_quote, 'Quote', () => app.toggleLinePrefix('> ')),
        const _Div(),
        const _Div(),
        // Text colour — split button (§7a.2): main area applies the current
        // colour; the arrow opens the full picker (palette/wheel/RGBA).
        Tooltip(
          message: 'Apply text colour',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: canFormat ? () => app.applyTextColor(app.lastColor) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.format_color_text,
                    size: 18,
                    color: canFormat ? null : context.surfaces.textSecondary,
                  ),
                  Container(
                    width: 18,
                    height: 3,
                    margin: const EdgeInsets.only(top: 1),
                    color:
                        canFormat ? curColor : context.surfaces.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: canFormat
              ? () async {
                  final hex = await showOnoteColorPicker(
                    context,
                    app,
                    initial: app.lastColor,
                  );
                  if (hex != null) app.applyTextColor(hex);
                }
              : null,
          child: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: canFormat ? null : context.surfaces.textSecondary,
          ),
        ),
        // Font — opens the searchable system-font picker.
        IconButton(
          icon: const Icon(Icons.font_download_outlined, size: 18),
          tooltip: tr(context, 'Text font…'),
          visualDensity: VisualDensity.compact,
          onPressed: canFormat
              ? () async {
                  final f = await showFontPicker(
                    context,
                    current: app.activeEditor?.block.content['font'] as String?,
                  );
                  if (f != null) app.setActiveBlockFont(f);
                }
              : null,
        ),
        // Font size (TEXT-1). Points, because that's how people think about type
        // and how OneNote/Word present it; stored as 120-dpi px.
        _FontSizeField(app: app, enabled: canFormat),
        if (!canFormat) ...[
          const SizedBox(width: 10),
          AppText(
            'Click into a text box to format',
            style: TextStyle(
              fontSize: 11,
              color: context.surfaces.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  // ── INSERT ────────────────────────────────────────────────────────────

  Widget _tabButton(ColorScheme scheme, int i, String label,
      {bool compact = false}) {
    final on = _tab == i;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      // **The one thing that writes `_tab`.** Nothing else in the app may,
      // which is the whole of the answer to "don't force any navigation".
      onTap: () => setState(() => _tab = i),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: on ? scheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: AppText(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? scheme.primary : null,
          ),
        ),
      ),
    );
  }

  /// **Insert renders the catalog** — the same list the canvas's right-click
  /// menu renders, so the two cannot say different things.
  ///
  /// Three groups separated by the bar's own hairline. No printed captions:
  /// only this tab would need them, and a command row that is taller on one
  /// tab than the others moves the layout under your pointer as you switch.
  /// **One row, thirteen buttons, each with its word** — the shape this row
  /// has always had, restored at the owner's request after a release that
  /// split it into three groups and took the words off four of them.
  ///
  /// The grouping did not go away: it is what the right-click menu shows as
  /// three short columns, which is a shape a menu can carry and a row cannot.
  /// [kRibbonOrder] is the row's own order, and a test pins it against the
  /// catalog so the two cannot drift.
  /// The width one [InsertItem] needs inline — measured, not guessed, the
  /// same rule `CompactingToolbar`'s own doc comment sets out: a
  /// `CommandButton` costs 40px plus 12px per character of its label (its
  /// fixed padding and icon against `OnoteType.small`'s own metrics — see
  /// `compacting_toolbar_test.dart`'s width-guard test for how these
  /// constants get caught if a theme change ever moves them), a label-less
  /// entry is the same 40px every compact `IconButton` in this app
  /// measures, +22 for the split button's own dropdown arrow when the item
  /// has [InsertItem.extras], +2 for `_InsertButton`'s own trailing gap.
  static double _insertItemWidth(InsertItem item) {
    // Matches the actual compact TextButton metric (18px icon, 8px icon/text
    // gap and 2 × 16px padding). The old 12px-per-character estimate reserved
    // almost twice the room a small-label glyph occupies, which is why Page
    // Link, Page Window and Template were folded despite blank ribbon space.
    final base = item.showLabel ? 52 + item.label.length * 6.8 : 40;
    return base + (item.extras.isEmpty ? 0 : 22) + 2;
  }

  Widget _insertRow(BuildContext context) {
    final controls = <ToolbarControl>[
      // These two are deliberately first: they are physical input routes,
      // not an occasional insert variant, so they remain visible on a
      // laptop-width ribbon before lower-frequency catalogue commands fold.
      ToolbarControl(
        id: 'screen-clip',
        width: 92,
        icon: Icons.screenshot_monitor_outlined,
        label: 'Screen clip',
        inline: CommandButton(
          icon: Icons.screenshot_monitor_outlined,
          label: 'Screen',
          onPressed: () => _insertScreenRegion(context),
        ),
        onPressed: () => _insertScreenRegion(context),
      ),
      ToolbarControl(
        id: 'scan-from-phone',
        width: 88,
        icon: Icons.document_scanner_outlined,
        label: 'Scan from phone',
        inline: CommandButton(
          icon: Icons.document_scanner_outlined,
          label: 'Phone',
          onPressed: () => showScannerPairingDialog(context, app),
        ),
        onPressed: () => showScannerPairingDialog(context, app),
      ),
      // Keep page links beside the everyday input
      // controls. They are not optional overflow: people use them to build
      // a page, and the corrected width calculation above lets them stay
      // visible whenever the physical ribbon has room.
      for (final item in kInsertRibbon.where(
        (item) => const {
          'pagelink',
        }.contains(item.id),
      ))
        _insertToolbarControl(context, item),
      for (final item in kInsertRibbon.where(
        (item) => !const {
          'pagelink',
        }.contains(item.id),
      ))
        _insertToolbarControl(context, item),
    ];
    return FixedToolbar(
        children: [for (final control in controls) control.inline]);
  }

  ToolbarControl _insertToolbarControl(BuildContext context, InsertItem item) =>
      ToolbarControl(
        id: item.id,
        width: _insertItemWidth(item),
        icon: item.icon,
        label: item.label,
        inline: _InsertButton(app: app, item: item),
        onPressed: () => item.run(context, app, insertAnchor(app, item)),
        submenu: item.extras.isEmpty
            ? null
            : [
                // The split button's own MAIN half, first — folding
                // must not cost the item the one action it already
                // had before it grew a dropdown arrow.
                ToolbarSubmenuItem(
                  icon: item.icon,
                  label: item.label,
                  onPressed: () =>
                      item.run(context, app, insertAnchor(app, item)),
                ),
                for (final extra in item.extras)
                  ToolbarSubmenuItem(
                    icon: extra.icon,
                    label: extra.label,
                    onPressed: () =>
                        extra.run(context, app, insertAnchor(app, extra)),
                  ),
              ],
      );

  RelativeRect _colourMenuPosition(
      BuildContext context, Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy + 18, 1, 1),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _showToolbarColourMenu(
    BuildContext context,
    Offset globalPosition,
    Tool brush,
    String hex,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: _colourMenuPosition(context, globalPosition),
      items: const [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.palette_outlined, size: 18),
              SizedBox(width: 9),
              AppText('Edit colour'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 9),
              AppText('Remove from toolbar'),
            ],
          ),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'edit':
        final edited = await showOnoteColorPicker(
          context,
          app,
          initial: hex,
          title: brush == Tool.highlighter
              ? tr(context, 'Highlighter colour')
              : tr(context, 'Pen colour'),
        );
        if (!mounted || edited == null) return;
        app.removeToolbarInkColor(hex, brush);
        app.addToolbarInkColor(edited, brush);
      case 'remove':
        app.removeToolbarInkColor(hex, brush);
    }
  }

  /// The pinned-colour target is deliberately a little larger than the dot.
  /// Apart from making it easier to right-click with a pen, the generous hit
  /// target keeps a dragged dot from being dropped in the tiny gap between two
  /// colours instead of on the colour it should precede.
  Widget _toolbarColourDot(
    Color color, {
    required bool active,
    required bool target,
    required ColorScheme scheme,
  }) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: target ? scheme.primary.withValues(alpha: .12) : null,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: target ? 20 : 18,
          height: target ? 20 : 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: target || active ? scheme.primary : Colors.transparent,
              width: target ? 2.5 : 2,
            ),
          ),
        ),
      );

  Widget _drawRow(BuildContext context, {bool vertical = false}) {
    final scheme = Theme.of(context).colorScheme;
    Widget toolButton(Tool t, IconData icon, String tip) => IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tr(context, tip),
          isSelected: app.tool == t,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor:
                app.tool == t ? scheme.primary.withValues(alpha: .14) : null,
            foregroundColor: app.tool == t ? scheme.primary : null,
          ),
          onPressed: () => app.setTool(t),
        );
    // The swatches also appear with ink selected, so a lassoed diagram can be
    // recoloured without first re-picking the pen.
    final inkActive = app.tool == Tool.pen ||
        app.tool == Tool.ballpoint ||
        app.tool == Tool.highlighter ||
        app.tool == Tool.shape ||
        app.hasInkSelection;
    final colors = OnoteColors.drawingColors(
      dark: Theme.of(context).brightness == Brightness.dark,
      highlighter: app.tool == Tool.highlighter,
    );
    final colourTool =
        app.tool == Tool.highlighter ? Tool.highlighter : Tool.pen;
    final activeColour = app.inkColorFor(colourTool);
    final activeCustomColour = app.customInkColorFor(colourTool);
    Widget gap([double size = 4]) =>
        SizedBox(width: vertical ? 0 : size, height: vertical ? size : 0);
    Widget sizeSlider({required Key key, bool eraser = false}) {
      final sizes = eraser
          ? const [4.0, 12.0, 24.0, 48.0, 80.0]
          : const [0.5, 1.5, 2.5, 6.0, 10.0];
      final width = eraser ? app.eraserSize : app.penSize;
      var closest = 0;
      for (var i = 1; i < sizes.length; i++) {
        if ((sizes[i] - width).abs() < (sizes[closest] - width).abs()) {
          closest = i;
        }
      }
      final slider = SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 7, elevation: 1, pressedElevation: 2),
          activeTrackColor: scheme.primary,
          inactiveTrackColor: scheme.outlineVariant,
          activeTickMarkColor: scheme.onPrimary,
          inactiveTickMarkColor: scheme.outline,
          valueIndicatorShape:
              _InkSizeIndicator(width, maxWidth: eraser ? 80 : 24),
        ),
        child: Slider(
          key: key,
          value: closest.toDouble(),
          min: 0,
          max: (sizes.length - 1).toDouble(),
          divisions: sizes.length - 1,
          label: '${width.toStringAsFixed(1)} px',
          semanticFormatterCallback: (value) => '${sizes[value.round()]} px',
          onChanged: (value) => eraser
              ? app.setEraserSize(sizes[value.round()])
              : app.setInkSize(sizes[value.round()]),
        ),
      );
      return vertical
          ? SizedBox(
              width: 48,
              height: 118,
              child: RotatedBox(quarterTurns: 3, child: slider),
            )
          : SizedBox(width: 118, child: slider);
    }

    void useCustomColour(String value) {
      final opaque = value.replaceFirst('#', '').substring(0, 6).toUpperCase();
      app.setCustomInkColor(opaque);
      if (app.hasInkSelection) app.recolorSelectedInk('#$opaque');
    }

    Future<void> pickCustomColour() async {
      final preset = colors[activeColour % colors.length];
      final initial = activeCustomColour ??
          (preset.toARGB32() & 0xFFFFFF)
              .toRadixString(16)
              .padLeft(6, '0')
              .toUpperCase();
      final picked = await showOnoteColorPicker(
        context,
        app,
        initial: initial,
        title: app.tool == Tool.highlighter
            ? tr(context, 'Highlighter colour')
            : tr(context, 'Pen colour'),
        onChanged: useCustomColour,
        onAddToToolbar: (hex) => app.addToolbarInkColor(hex, colourTool),
      );
      if (picked != null) useCustomColour(picked);
    }

    final children = <Widget>[
      toolButton(Tool.select, Icons.near_me_outlined, 'Select / move  (V)'),
      toolButton(Tool.pen, Icons.brush_outlined, 'Pen  (P)'),
      toolButton(Tool.ballpoint, Icons.edit, 'Ballpoint — constant width'),
      toolButton(
        Tool.highlighter,
        Icons.border_color_outlined,
        'Highlighter  (H)',
      ),
      toolButton(
        Tool.eraser,
        Icons.cleaning_services_outlined,
        'Eraser  (E)',
      ),
      toolButton(Tool.lasso, Icons.gesture_outlined, 'Lasso-select ink'),
      IconButton(
        icon: const Icon(Icons.category_outlined, size: 18),
        tooltip: 'Shape recognition — draw with the pen and hold',
        isSelected: app.shapeRecognition,
        style: IconButton.styleFrom(
          backgroundColor: app.shapeRecognition
              ? scheme.primary.withValues(alpha: .18)
              : null,
          foregroundColor: app.shapeRecognition ? scheme.primary : null,
        ),
        visualDensity: VisualDensity.compact,
        onPressed: () => app.setShapeRecognition(!app.shapeRecognition),
      ),
      IconButton(
        icon: const Icon(Icons.straighten_outlined, size: 18),
        tooltip: 'Ruler — drag the grip, pinch to resize or rotate',
        isSelected: app.rulerVisible,
        style: IconButton.styleFrom(
          backgroundColor:
              app.rulerVisible ? scheme.primary.withValues(alpha: .18) : null,
          foregroundColor: app.rulerVisible ? scheme.primary : null,
        ),
        visualDensity: VisualDensity.compact,
        onPressed: () => app.setRulerVisible(!app.rulerVisible),
      ),
      _Div(vertical: vertical),
      if (inkActive) ...[
        for (final (i, c) in colors.indexed
            .where((entry) => app.toolbarPresetVisible(colourTool, entry.$1)))
          Padding(
            padding: vertical
                ? const EdgeInsets.symmetric(vertical: 2)
                : const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              key: ValueKey('ink-preset-$i'),
              borderRadius: BorderRadius.circular(99),
              onSecondaryTapDown: (details) async {
                final remove = await showMenu<bool>(
                  context: context,
                  position:
                      _colourMenuPosition(context, details.globalPosition),
                  items: const [
                    PopupMenuItem(value: true, child: AppText('Remove colour'))
                  ],
                );
                if (remove == true) app.hideToolbarPreset(colourTool, i);
              },
              onTap: () {
                app.setInkColor(i);
                // With ink selected (typically just lassoed), a colour click
                // recolours it rather than only arming the next stroke —
                // recolouring after the fact is most of why you lasso a
                // diagram (INK-7).
                if (app.hasInkSelection) {
                  app.recolorSelectedInk(
                    '#'
                    '${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                  );
                } else {
                  app.refresh();
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    key: ValueKey('pen-swatch-$i'),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 2,
                        color: activeCustomColour == null && activeColour == i
                            ? scheme.primary
                            : i == 0 && colourTool != Tool.highlighter
                                ? scheme.outline
                                : Colors.transparent,
                      ),
                    ),
                  ),
                  if (i == 0 && colourTool != Tool.highlighter)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outline, width: 1),
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 5,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // Pinned colours are explicitly added from the picker. Recent
        // colours never appear here merely because they were sampled.
        for (final hex in app.toolbarInkColorsFor(colourTool))
          if (onoteColorFromHex(hex) case final custom?)
            Padding(
              padding: vertical
                  ? const EdgeInsets.symmetric(vertical: 2)
                  : const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: 'Use colour / right-click to remove',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => useCustomColour(hex),
                  onSecondaryTapDown: (details) => _showToolbarColourMenu(
                      context, details.globalPosition, colourTool, hex),
                  child: _toolbarColourDot(custom,
                      active: activeCustomColour == hex,
                      target: false,
                      scheme: scheme),
                ),
              ),
            ), // A quiet capsule separates "choose/mix/sample" from the fixed
        // swatches. It deliberately has no corners and keeps the pipette
        // immediately beside the mixer, where those two tools read as one.
        gap(20),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.outline.withValues(alpha: .22)),
          ),
          child: Flex(
            direction: vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                key: const ValueKey('pen-active-colour'),
                borderRadius: BorderRadius.circular(99),
                onTap: pickCustomColour,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: activeCustomColour == null
                        ? colors[activeColour % colors.length]
                        : onoteColorFromHex(activeCustomColour),
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('pen-eyedropper'),
                tooltip: app.inkEyedropperActive
                    ? 'Cancel colour sampler'
                    : 'Pick a colour from the page',
                visualDensity: VisualDensity.compact,
                isSelected: app.inkEyedropperActive,
                style: IconButton.styleFrom(
                  backgroundColor: app.inkEyedropperActive
                      ? scheme.primary.withValues(alpha: .18)
                      : null,
                  foregroundColor:
                      app.inkEyedropperActive ? scheme.primary : null,
                ),
                icon: const Icon(Icons.colorize_outlined, size: 19),
                onPressed: () =>
                    app.setInkEyedropperActive(!app.inkEyedropperActive),
              ),
              IconButton(
                key: const ValueKey('pen-colour-picker'),
                tooltip: tr(context, 'Mix a custom colour'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.palette_outlined, size: 19),
                onPressed: pickCustomColour,
              ),
            ],
          ),
        ),
        gap(6),
        sizeSlider(key: const ValueKey('ink-size')),
      ] else if (app.tool == Tool.eraser) ...[
        SizedBox(
          width: vertical ? 48 : null,
          height: vertical ? 210 : 48,
          child: RotatedBox(
            quarterTurns: vertical ? 3 : 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  hoverColor: Colors.transparent,
                  onTap: () => app.setEraserMode(EraserMode.area),
                  child: SizedBox(
                    width: 48,
                    height: 44,
                    child: Center(
                        child: AnimatedDefaultTextStyle(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      style: OnoteType.uiStrong.copyWith(
                        fontSize: app.eraserMode == EraserMode.area ? 14 : 13,
                        height: app.eraserMode == EraserMode.area
                            ? 18 / 14
                            : 18 / 13,
                        color: app.eraserMode == EraserMode.area
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      child: const AppText('Area'),
                    )),
                  ),
                ),
                OnoteSwitch(
                  key: const ValueKey('eraser-mode'),
                  compact: true,
                  value: app.eraserMode == EraserMode.stroke,
                  onChanged: (value) => app.setEraserMode(
                      value ? EraserMode.stroke : EraserMode.area),
                ),
                InkWell(
                  hoverColor: Colors.transparent,
                  onTap: () => app.setEraserMode(EraserMode.stroke),
                  child: SizedBox(
                    width: 106,
                    height: 44,
                    child: Center(
                        child: AnimatedDefaultTextStyle(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      style: OnoteType.uiStrong.copyWith(
                        fontSize: app.eraserMode == EraserMode.stroke ? 14 : 13,
                        height: app.eraserMode == EraserMode.stroke
                            ? 18 / 14
                            : 18 / 13,
                        color: app.eraserMode == EraserMode.stroke
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      child: const AppText('Whole stroke'),
                    )),
                  ),
                ),
              ],
            ),
          ),
        ),
        sizeSlider(key: const ValueKey('eraser-size'), eraser: true),
      ],
      gap(12),
      gap(),
    ];
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : FixedToolbar(children: children);
  }
}

/// `H2` / `H3` on the Home row.
///
/// Thin wrapper over [CommandTextButton] so the call sites keep their
/// positional shorthand; the colours and metrics come from the shared control,
/// which is what stops the two heading buttons rendering in the accent while
/// the bold/italic icons beside them render in ink.
class _TextBtn extends StatelessWidget {
  const _TextBtn(this.label, this.enabled, this.onTap);
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      CommandTextButton(label: label, onPressed: enabled ? onTap : null);
}

class _Div extends StatelessWidget {
  const _Div({this.vertical = false});
  final bool vertical;
  @override
  Widget build(BuildContext context) => Container(
        width: vertical ? 22 : 1,
        height: vertical ? 1 : 22,
        margin: vertical
            ? const EdgeInsets.symmetric(vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 8),
        color: Theme.of(context).dividerColor,
      );
}

/// Font-size control for the text block being edited (TEXT-1).
///
/// A dropdown of the sizes people actually use, plus the current value shown
/// even when it came from an import — OneNote pages carry per-box sizes, and
/// before this there was no way to see or change them.
class _FontSizeField extends StatelessWidget {
  const _FontSizeField({required this.app, required this.enabled});
  final AppState app;
  final bool enabled;

  static const _sizes = <double>[
    8,
    9,
    10,
    11,
    12,
    14,
    16,
    18,
    20,
    24,
    28,
    36,
    48,
  ];

  @override
  Widget build(BuildContext context) {
    // Stored px → pt for display; null means "the theme default".
    final px = app.activeBlockFontSize;
    final pt = px == null ? null : px * 72.0 / 120.0;
    final label = pt == null
        ? '–'
        : (pt % 1 == 0 ? pt.toStringAsFixed(0) : pt.toStringAsFixed(1));
    return Tooltip(
      message: enabled
          ? 'Text size (points)'
          : 'Click into a text box to change its size',
      child: MenuAnchor(
        builder: (context, controller, _) => InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: enabled
                    ? Theme.of(context).colorScheme.outline
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled ? null : context.surfaces.textSecondary,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: enabled ? null : context.surfaces.textSecondary,
                ),
              ],
            ),
          ),
        ),
        menuChildren: [
          MenuItemButton(
            onPressed: () => app.setActiveBlockFontSize(null),
            child: const AppText('Default'),
          ),
          for (final s in _sizes)
            MenuItemButton(
              onPressed: () => app.setActiveBlockFontSize(s),
              child: AppText('${s.toStringAsFixed(0)} pt'),
            ),
        ],
      ),
    );
  }
}

class _InsertButton extends StatelessWidget {
  const _InsertButton({required this.app, required this.item});

  final AppState app;
  final InsertItem item;

  Future<void> _run(BuildContext context, InsertItem which) =>
      which.run(context, app, insertAnchor(app, which));

  /// What a hover says. A labelled command adds only what the label does not
  /// already carry; a wordless one leads with its name, so nothing on the row
  /// is nameless.
  String get _tip {
    if (item.showLabel) return item.tooltip ?? '';
    return item.tooltip == null
        ? item.label
        : '${item.label} — ${item.tooltip}';
  }

  /// The button itself.
  ///
  /// [menu] is the split button's own drop-down, and pressing the main half
  /// closes it first: a file picker opening BEHIND a menu that is still
  /// sitting on top of it reads as the button having done nothing. The
  /// hand-built PDF button this replaced closed it by hand; the generic one
  /// dropped the call, for every split item at once.
  Widget _main(BuildContext context, [MenuController? menu]) {
    void press() {
      if (menu != null && menu.isOpen) menu.close();
      _run(context, item);
    }

    return Tooltip(
      message: _tip,
      child: item.showLabel
          ? CommandButton(icon: item.icon, label: item.label, onPressed: press)
          : IconButton(
              icon: Icon(item.icon, size: OnoteIcon.sm),
              visualDensity: VisualDensity.compact,
              onPressed: press,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Two pixels, not four. The run measured 970px against the 965 a 1280
    // window leaves once the navigator is open, and five pixels is the
    // difference between "Page window" being on screen and being a scroll
    // away — which, for the least familiar entry on the row, is the
    // difference between existing and not.
    const gap = EdgeInsets.only(right: 2);
    if (item.extras.isEmpty) {
      return Padding(padding: gap, child: _main(context));
    }
    return Padding(
      padding: gap,
      child: MenuAnchor(
        builder: (context, controller, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _main(context, controller),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              // A bare 16px icon leaves most of the row's height as dead
              // space around it; sized to the row so the arrow is hittable.
              child: const SizedBox(
                width: 22,
                height: 34,
                child: Icon(Icons.arrow_drop_down, size: 16),
              ),
            ),
          ],
        ),
        menuChildren: [
          for (final extra in item.extras)
            MenuItemButton(
              leadingIcon: Icon(extra.icon, size: 16),
              onPressed: () => _run(context, extra),
              child: AppText(extra.label),
            ),
        ],
      ),
    );
  }
}

/// Lets the toolbar row be dragged and wheel-scrolled when it is wider than
/// the window. Flutter's default behaviour excludes mouse and trackpad from
/// drag scrolling, and a horizontal viewport ignores a vertical wheel.

/// **What the object row is about**, shown where the contextual tab used to
/// be — and deliberately not a tab.
///
/// A pill, because the token file reserves the full radius for badges and no
/// other control in the bar is that shape. No `InkWell`, no `onTap`, no
/// underline ever: it cannot be pressed, so it cannot be misread as a fifth
/// tab, and the ambiguity is removed by removing the behaviour rather than by
/// styling around it.
class _SubjectBadge extends StatelessWidget {
  const _SubjectBadge({required this.icon, required this.label});

  final IconData icon;

  /// Always a NOUN — the thing itself. Never a verb, never "mode", never
  /// "tools".
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ExcludeFocus(
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 1, height: 18, color: context.surfaces.border),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Esc when you are done',
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(OnoteRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: accent),
                    const SizedBox(width: 4),
                    AppText(
                      label,
                      style: OnoteType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
