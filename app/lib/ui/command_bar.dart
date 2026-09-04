import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';

import '../export/markdown_export.dart';
import '../export/open_export.dart';
import '../export/pdf_export.dart';
import '../export/pdf_vector_export.dart';
import '../export/print_page.dart';
import '../editor/list_editing.dart';
import '../markdown/md_syntax.dart';
import '../model/tags.dart';
import '../planner/agenda.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'color_picker.dart';
import 'command_button.dart';
import 'compacting_toolbar.dart';
import 'font_picker.dart';
import 'insert_catalog.dart';
import 'object_face.dart';
import 'object_row.dart';
import 'settings_dialog.dart';
import 'update_dialog.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';
import 'windows_window_frame.dart';

/// The tabbed command bar (style guide §7 revised): Home · Insert · Draw ·
/// View. OneNote's few-clicks accessibility in Openote's calm language — a
/// slim tab row over a single command row of grouped icon buttons.
class CommandBar extends StatefulWidget {
  const CommandBar({
    super.key,
    required this.app,
    this.titlebarOnly = false,
    this.drawOnly = false,
  });
  final AppState app;
  final bool titlebarOnly;
  final bool drawOnly;

  @override
  State<CommandBar> createState() => _CommandBarState();
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
              // PLANNING.md. Exists only when launch found a newer
              // release, and leads with the version so the tooltip
              // answers "to what?" before the click.
              if (app.updateAvailable != null)
                ToolbarControl(
                  width: 40,
                  icon: Icons.system_update_alt,
                  label: 'Update to ${app.updateAvailable!.version}…',
                  onPressed: () => showUpdateDialog(context, app),
                  inline: IconButton(
                    icon: Icon(Icons.system_update_alt,
                        size: 18, color: scheme.primary),
                    tooltip: 'Update to ${app.updateAvailable!.version}…',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showUpdateDialog(context, app),
                  ),
                ),
              // Planner and quick homework capture stay beside the app-wide
              // controls, so a due task is reachable from every page.
              ToolbarControl(
                width: 40,
                icon: Icons.event_note_outlined,
                label: 'Homework & reminders',
                selected: app.showPlannerPanel,
                onPressed: app.togglePlannerPanel,
                inline: _PlannerButton(app: app),
              ),
              ToolbarControl(
                width: 40,
                icon: Icons.add_task_outlined,
                label: 'Add homework',
                onPressed: () => _addQuickHomework(context, app),
                inline: IconButton(
                  icon: const Icon(Icons.add_task_outlined, size: 18),
                  tooltip: 'Add homework for this page',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _addQuickHomework(context, app),
                ),
              ),
              ToolbarControl(
                width: 40,
                icon: Icons.label_outline,
                label: 'Find tags',
                selected: app.showTagsPanel,
                onPressed: app.toggleTagsPanel,
                inline: IconButton(
                  icon: const Icon(Icons.label_outline, size: 18),
                  tooltip: tr(context, 'Find tags'),
                  isSelected: app.showTagsPanel,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleTagsPanel,
                ),
              ),
              ToolbarControl(
                width: 40,
                icon: Icons.account_tree_outlined,
                label: 'Links & backlinks',
                selected: app.showLinksPanel,
                onPressed: app.toggleLinksPanel,
                inline: IconButton(
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  tooltip: tr(context, 'Links & backlinks'),
                  isSelected: app.showLinksPanel,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleLinksPanel,
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
              ToolbarControl(
                width: 40,
                icon: Icons.ios_share_outlined,
                label: 'Export',
                inline: MenuAnchor(
                  builder: (context, controller, _) => IconButton(
                    icon: const Icon(Icons.ios_share_outlined, size: 18),
                    tooltip: tr(context, 'Export page…'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: _exportMenuItems(context),
                ),
                submenu: [
                  ToolbarSubmenuItem(
                    icon: Icons.description_outlined,
                    label: 'Markdown (.md)',
                    onPressed: () => _export(context, exportPageMarkdown),
                  ),
                  // Vector by default: the shared/printed artefact
                  // should be searchable, selectable and small. The
                  // raster capture stays available for the rare page
                  // whose look matters more than its text.
                  ToolbarSubmenuItem(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'PDF (.pdf)',
                    onPressed: () => _export(context, exportPagePdfVector),
                  ),
                  ToolbarSubmenuItem(
                    icon: Icons.print_outlined,
                    label: 'Print…',
                    onPressed: () => printCurrentPage(app),
                  ),
                  ToolbarSubmenuItem(
                    icon: Icons.image_outlined,
                    label: 'PDF — picture of the page',
                    onPressed: () => _export(context, exportPagePdf),
                  ),
                  ToolbarSubmenuItem(
                    icon: Icons.hub_outlined,
                    label: 'For Obsidian Canvas (.canvas)',
                    onPressed: () => _export(context, exportPageJsonCanvas),
                  ),
                  ToolbarSubmenuItem(
                    icon: Icons.gesture,
                    label: 'Just the drawing (.inkml)',
                    onPressed: () => _export(context, exportPageInkML),
                  ),
                  // Say what lands on disk. "Materialize" is this
                  // codebase's own architecture vocabulary
                  // (`sync/materializer.dart`) and appears in no
                  // other user-visible string in the app.
                  ToolbarSubmenuItem(
                    icon: Icons.folder_zip_outlined,
                    label: 'Save the whole notebook as folders and files…',
                    onPressed: () => _exportWithProgress(
                        context,
                        'Saving the notebook…',
                        (report) => materializeNotebook(app,
                            onProgress: (done, total) =>
                                report('Page $done of $total…'))),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        child: SizedBox(
          height: 48,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _drawRow(context),
          ),
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
                      child: AppText('Openote')),
                ),
              )),
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 18),
                tooltip: tr(context, 'Settings…'),
                visualDensity: VisualDensity.compact,
                onPressed: () => showSettingsDialog(context, app),
              ),
              const WindowsCaptionButtons(),
            ])),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          // ── Tab row ──
          SizedBox(
            height: 32,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.fullscreen, size: 18),
                  tooltip: tr(context, 'Writing mode'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => app.setWritingMode(true),
                ),
                IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  tooltip: tr(context, 'Undo  (Ctrl+Z)'),
                  visualDensity: VisualDensity.compact,
                  onPressed: app.canUndo ? app.undo : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 18),
                  tooltip: tr(context, 'Redo  (Ctrl+Y)'),
                  visualDensity: VisualDensity.compact,
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
                  _tabButton(scheme, i, _tabs[i]),
                // **A badge, not a tab.** It says what the row below is
                // about and it cannot be pressed, so there is nothing here to
                // be moved onto and nothing to be moved back from. It sits
                // where the old Maths tab sat, deliberately: same place,
                // opposite kind.
                if (objectFaceOf(app) == ObjectFace.equation)
                  const _SubjectBadge(icon: Icons.functions, label: 'Equation'),
                const Spacer(),
                if (WindowsWindowFrame.of(context)?.customChrome != true)
                  ..._utilityControls(context, scheme),
              ],
            ),
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
                          begin: const Offset(0, 0.15), end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              // Insert COMPACTS (`CompactingToolbar` needs the real, bounded
              // window width to decide what folds, which a `Scrollable`
              // never offers its child — that axis is unbounded on
              // purpose, it's what lets content wider than the viewport
              // scroll). Home and Draw still scroll: both mix dividers,
              // split buttons and a live text field with no single "this
              // control folds into a menu item" shape the way Insert's
              // uniform ribbon of commands does — see the doc comment on
              // `CompactingToolbar` itself for why Insert was the tractable
              // one to convert first.
              //
              // A horizontal `Scrollable` reads `scrollDelta.dx`, which a
              // mouse wheel does not produce, and there was no scrollbar
              // anywhere in the subtree — so a row wider than the window was
              // simply unreachable. Measured on Insert too (1217 px against
              // 965) before it compacted instead.
              child: _tab == 1
                  ? KeyedSubtree(
                      key: const ValueKey(1), child: _insertRow(context))
                  : KeyedSubtree(
                      key: ValueKey(_tab),
                      child: ScrollConfiguration(
                        behavior: const _ToolbarScroll(),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _tab == 2
                              ? _drawRow(context)
                              : _tab == 3
                                  ? PageFace(app: app)
                                  : _homeRow(context),
                        ),
                      )),
            ),
          ),
        ],
      ),
    );
  }

  /// Every item in the Export menu comes through here.
  ///
  /// **The failure has a face.** There was no `try`: a full disk, a read-only
  /// USB stick, an offline OneDrive folder or a filename the OS refuses threw
  /// into an unhandled Future and, with no global handler in the app, into a
  /// console no student will ever read. The menu closed, nothing happened, and
  /// they believed the work they were about to hand in was on the desktop.
  ///
  /// The messenger is taken BEFORE the await, because by the time the write
  /// fails the menu route that owned the context is gone.
  /// An export long enough to need a face, with a live count on it.
  ///
  /// The same shape as the PDF import's dialog: modal and undismissable while
  /// it runs, because half a written folder tree is not a thing anybody wants
  /// to be given quietly.
  Future<void> _exportWithProgress(
    BuildContext context,
    String opening,
    Future<String?> Function(void Function(String) report) fn,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final progress = ValueNotifier<String>(opening);
    var open = true;
    unawaited(showOnoteDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, text, __) => Text(text),
            ),
          ),
        ]),
      ),
    ).then((_) => open = false));
    String? path;
    Object? failed;
    try {
      path = await fn((text) => progress.value = text);
    } catch (e) {
      failed = e;
    }
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      open = false;
    }
    progress.dispose();
    if (failed != null) {
      messenger?.showSnackBar(SnackBar(
        content: Text("That couldn't be saved: $failed"),
        duration: const Duration(seconds: 6),
      ));
      return;
    }
    if (path != null) {
      messenger?.showSnackBar(SnackBar(content: AppText('Exported to $path')));
    }
  }

  /// The Export menu's own items — pulled out so the inline `MenuAnchor`
  /// (shown while there's room) and the folded `ToolbarSubmenuItem` list
  /// (shown once Export itself has to fold into the command bar's own
  /// "More" menu) can share one definition rather than drifting apart.
  List<Widget> _exportMenuItems(BuildContext context) => [
        MenuItemButton(
          leadingIcon: const Icon(Icons.description_outlined, size: 18),
          onPressed: () => _export(context, exportPageMarkdown),
          child: const AppText('Markdown (.md)'),
        ),
        // Vector by default: the shared/printed artefact should be
        // searchable, selectable and small. The raster capture stays
        // available for the rare page whose look matters more than its text.
        MenuItemButton(
          leadingIcon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          onPressed: () => _export(context, exportPagePdfVector),
          child: const AppText('PDF (.pdf)'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.print_outlined, size: 18),
          shortcut:
              const SingleActivator(LogicalKeyboardKey.keyP, control: true),
          onPressed: () => printCurrentPage(app),
          child: const AppText('Print…'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.image_outlined, size: 18),
          onPressed: () => _export(context, exportPagePdf),
          child: const AppText('PDF — picture of the page'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.hub_outlined, size: 18),
          onPressed: () => _export(context, exportPageJsonCanvas),
          child: const AppText('For Obsidian Canvas (.canvas)'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.gesture, size: 18),
          onPressed: () => _export(context, exportPageInkML),
          child: const AppText('Just the drawing (.inkml)'),
        ),
        const Divider(height: 6),
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_zip_outlined, size: 18),
          onPressed: () => _exportWithProgress(
              context,
              'Saving the notebook…',
              (report) => materializeNotebook(app,
                  onProgress: (done, total) =>
                      report('Page $done of $total…'))),
          // Say what lands on disk. "Materialize" is this codebase's own
          // architecture vocabulary (`sync/materializer.dart`) and appears
          // in no other user-visible string in the app.
          child: const AppText('Save the whole notebook as folders and files…'),
        ),
      ];

  Future<void> _export(
      BuildContext context, Future<String?> Function(AppState) fn) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final path = await fn(app);
      if (path != null) {
        messenger
            ?.showSnackBar(SnackBar(content: AppText('Exported to $path')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text("That couldn't be saved: $e"),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  // ── HOME: history + text formatting ──────────────────────────────────

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
    return Row(children: [
      IconButton(
        icon: const Icon(Icons.undo, size: 18),
        tooltip: tr(context, 'Undo  (Ctrl+Z)'),
        visualDensity: VisualDensity.compact,
        onPressed: app.canUndo ? app.undo : null,
      ),
      IconButton(
        icon: const Icon(Icons.redo, size: 18),
        tooltip: tr(context, 'Redo  (Ctrl+Y)'),
        visualDensity: VisualDensity.compact,
        onPressed: app.canRedo ? app.redo : null,
      ),
      const _Div(),
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
      fmt(Icons.format_bold, 'Bold  (Ctrl+B)', () => app.wrapSelection('**'),
          MdInline.bold),
      fmt(Icons.format_italic, 'Italic  (Ctrl+I)', () => app.wrapSelection('*'),
          MdInline.italic),
      fmt(Icons.format_underlined, 'Underline  (Ctrl+U)',
          () => app.wrapSelection('++'), MdInline.underline),
      fmt(Icons.strikethrough_s, 'Strikethrough', () => app.wrapSelection('~~'),
          MdInline.strike),
      fmt(Icons.code, 'Inline code', () => app.wrapSelection('`'),
          MdInline.code),
      fmt(Icons.border_color, 'Highlight', () => app.wrapSelection('=='),
          MdInline.highlight),
      const _Div(),
      fmt(Icons.title, 'Heading 1', () => app.toggleLinePrefix('# ')),
      _TextBtn('H2', canFormat, () => app.toggleLinePrefix('## ')),
      _TextBtn('H3', canFormat, () => app.toggleLinePrefix('### ')),
      const _Div(),
      fmt(Icons.format_list_bulleted, 'Bullet list',
          () => app.toggleList(ListKind.bullet)),
      fmt(Icons.format_list_numbered, 'Numbered list',
          () => app.toggleList(ListKind.numbered)),
      fmt(Icons.check_box_outlined, 'Checkbox',
          () => app.toggleList(ListKind.checkbox)),
      fmt(Icons.format_quote, 'Quote', () => app.toggleLinePrefix('> ')),
      const _Div(),
      // Tags (TEXT-5). OneNote users organise around these, so they get a
      // first-class place on Home rather than a submenu. The button shows the
      // caret line's active tags, which is why it reads state on every build.
      _TagButton(app: app),
      _MakeCardButton(app: app),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.format_color_text,
                  size: 18,
                  color: canFormat ? null : context.surfaces.textSecondary),
              Container(
                  width: 18,
                  height: 3,
                  margin: const EdgeInsets.only(top: 1),
                  color: canFormat ? curColor : context.surfaces.textSecondary),
            ]),
          ),
        ),
      ),
      InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: canFormat
            ? () async {
                final hex = await showOnoteColorPicker(context, app,
                    initial: app.lastColor);
                if (hex != null) app.applyTextColor(hex);
              }
            : null,
        child: Icon(Icons.arrow_drop_down,
            size: 18, color: canFormat ? null : context.surfaces.textSecondary),
      ),
      // Font — opens the searchable system-font picker.
      IconButton(
        icon: const Icon(Icons.font_download_outlined, size: 18),
        tooltip: tr(context, 'Text font…'),
        visualDensity: VisualDensity.compact,
        onPressed: canFormat
            ? () async {
                final f = await showFontPicker(context,
                    current:
                        app.activeEditor?.block.content['font'] as String?);
                if (f != null) app.setActiveBlockFont(f);
              }
            : null,
      ),
      // Font size (TEXT-1). Points, because that's how people think about type
      // and how OneNote/Word present it; stored as 120-dpi px.
      _FontSizeField(app: app, enabled: canFormat),
      if (!canFormat) ...[
        const SizedBox(width: 10),
        AppText('Click into a text box to format',
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      ],
    ]);
  }

  // ── INSERT ────────────────────────────────────────────────────────────

  Widget _tabButton(ColorScheme scheme, int i, String label) {
    final on = _tab == i;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      // **The one thing that writes `_tab`.** Nothing else in the app may,
      // which is the whole of the answer to "don't force any navigation".
      onTap: () => setState(() => _tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
    final base = item.showLabel ? 40 + item.label.length * 12 : 40;
    return base + (item.extras.isEmpty ? 0 : 22) + 2;
  }

  Widget _insertRow(BuildContext context) => CompactingToolbar(
        controls: [
          for (final item in kInsertRibbon)
            ToolbarControl(
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
            ),
        ],
      );
  Widget _drawRow(BuildContext context) {
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
    return Row(children: [
      toolButton(Tool.select, Icons.near_me_outlined, 'Select / move  (V)'),
      toolButton(Tool.text, Icons.text_fields, 'Text  (T)'),
      toolButton(Tool.pen, Icons.brush_outlined, 'Pen  (P)'),
      toolButton(Tool.ballpoint, Icons.edit, 'Ballpoint — constant width'),
      toolButton(
          Tool.highlighter, Icons.border_color_outlined, 'Highlighter  (H)'),
      toolButton(Tool.eraser, Icons.cleaning_services_outlined, 'Eraser  (E)'),
      toolButton(Tool.lasso, Icons.gesture_outlined, 'Lasso-select ink'),
      IconButton(
        icon: const Icon(Icons.category_outlined, size: 18),
        tooltip: 'Shape recognition — draw with the pen and hold',
        isSelected: app.shapeRecognition,
        visualDensity: VisualDensity.compact,
        onPressed: () => app.setShapeRecognition(!app.shapeRecognition),
      ),
      IconButton(
        icon: const Icon(Icons.straighten_outlined, size: 18),
        tooltip: 'Ruler — drag the grip, pinch to resize or rotate',
        isSelected: app.rulerVisible,
        visualDensity: VisualDensity.compact,
        onPressed: () => app.setRulerVisible(!app.rulerVisible),
      ),
      const _Div(),
      if (inkActive) ...[
        for (final (i, c) in colors.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () {
                app.penColor = i;
                app.setCustomPenColor(null);
                // With ink selected (typically just lassoed), a colour click
                // recolours it rather than only arming the next stroke —
                // recolouring after the fact is most of why you lasso a
                // diagram (INK-7).
                if (app.hasInkSelection) {
                  app.recolorSelectedInk('#'
                      '${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}');
                } else {
                  app.refresh();
                }
              },
              child: Container(
                key: ValueKey('pen-swatch-$i'),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    width: 2,
                    color: app.penCustomColor == null && app.penColor == i
                        ? scheme.primary
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          key: const ValueKey('pen-colour-picker'),
          tooltip: tr(context, 'Mix a custom colour'),
          visualDensity: VisualDensity.compact,
          icon: app.penCustomColor == null
              ? const Icon(Icons.palette_outlined, size: 19)
              : Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: onoteColorFromHex(app.penCustomColor),
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
          onPressed: () async {
            final preset = colors[app.penColor % colors.length];
            final initial = app.penCustomColor ??
                (preset.toARGB32() & 0xFFFFFF)
                    .toRadixString(16)
                    .padLeft(6, '0')
                    .toUpperCase();
            final picked = await showOnoteColorPicker(context, app,
                initial: initial, title: 'Pen colour');
            if (picked == null) return;
            final opaque = picked.replaceFirst('#', '').substring(0, 6);
            app.setCustomPenColor(opaque);
            if (app.hasInkSelection) app.recolorSelectedInk('#$opaque');
          },
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 110,
          child: Slider(
            value: app.penSize,
            min: 1,
            max: 10,
            onChanged: (v) {
              app.penSize = v;
              app.refresh();
            },
          ),
        ),
      ] else if (app.tool == Tool.eraser) ...[
        SizedBox(
            width: 135,
            child: Slider(
              key: const ValueKey('eraser-size'),
              value: app.eraserSize,
              min: 4,
              max: 100,
              divisions: 48,
              label: '${app.eraserSize.round()} px',
              onChanged: app.setEraserSize,
            )),
        AppText('${app.eraserSize.round()} px',
            style: const TextStyle(fontSize: 11)),
        SegmentedButton<EraserMode>(
          segments: [
            for (final m in EraserMode.values)
              ButtonSegment(
                  value: m,
                  label:
                      AppText(m.label, style: const TextStyle(fontSize: 11))),
          ],
          selected: {app.eraserMode},
          onSelectionChanged: (s) => app.setEraserMode(s.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
        const SizedBox(width: 8),
        Text(
            app.eraserMode == EraserMode.area
                ? 'Splits strokes where you rub'
                : 'Removes any stroke you touch',
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      ] else if (app.tool == Tool.lasso)
        AppText('Draw a loop around ink to select it — then drag or delete',
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary))
      else
        AppText('Pick the pen or highlighter to draw',
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      const SizedBox(width: 12),
      const SizedBox(width: 4),
    ]);
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
  Widget build(BuildContext context) => CommandTextButton(
        label: label,
        onPressed: enabled ? onTap : null,
      );
}

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 8),
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
    48
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
                      : Colors.transparent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppText(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: enabled ? null : context.surfaces.textSecondary)),
              Icon(Icons.arrow_drop_down,
                  size: 16,
                  color: enabled ? null : context.surfaces.textSecondary),
            ]),
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

/// The tag button on Home: applies a tag to the caret's line, and shows which
/// tags that line already carries.
///
/// A menu rather than a row of buttons because the set is open-ended (nine
/// built-ins plus, later, user-defined ones) and the toolbar is already dense.
class _TagButton extends StatelessWidget {
  const _TagButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = app.tagsAtCaret();
    final enabled = app.canFormatText;
    return MenuAnchor(
      builder: (context, controller, _) => Tooltip(
        message: active.isEmpty
            ? 'Tag this line (To Do, Important, Question…)'
            : 'Tagged: ${active.map((k) => k.label).join(', ')}',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(active.isEmpty ? Icons.label_outline : active.first.icon,
                  size: 18,
                  color: !enabled
                      ? context.surfaces.textSecondary
                      : active.isEmpty
                          ? null
                          : active.first.color),
              Icon(Icons.arrow_drop_down,
                  size: 16,
                  color: enabled ? null : context.surfaces.textSecondary),
            ]),
          ),
        ),
      ),
      menuChildren: [
        for (final k in TagKind.pickable)
          MenuItemButton(
            leadingIcon: Icon(k.icon, size: 16, color: k.color),
            trailingIcon: active.contains(k)
                ? Icon(Icons.check, size: 16, color: scheme.primary)
                : null,
            onPressed: () => app.toggleTagOnSelection(k),
            child: AppText(k.label),
          ),
        // Dating a tag belongs here, beside applying one — a deadline you could
        // only set from a separate panel would be a feature most people never
        // found, and the line you want to date is the line you are on.
        if (active.isNotEmpty) ...[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.event_outlined, size: 16),
            onPressed: () => _setDue(context),
            child:
                Text(_dueOfCaret() == null ? 'Due date…' : 'Change due date…'),
          ),
          if (_dueOfCaret() != null)
            MenuItemButton(
              leadingIcon: const Icon(Icons.event_busy_outlined, size: 16),
              onPressed: _clearDue,
              child: const AppText('Clear the due date'),
            ),
        ],
      ],
    );
  }

  /// The dated tag on the caret's line, if any. One date per line rather than
  /// one per tag: a line tagged both To Do and Important has one deadline, and
  /// asking which of the two icons owns it is a question nobody wants.
  NoteTag? _dueOfCaret() {
    final b = app.caretBlock();
    if (b == null) return null;
    final line = app.caretLineIndex();
    for (final t in NoteTag.listFrom(b.content)) {
      if (t.line == line && t.due != null) return t;
    }
    return null;
  }

  Future<void> _setDue(BuildContext context) async {
    final b = app.caretBlock();
    if (b == null) return;
    final line = app.caretLineIndex();
    final tags = [
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == line) t
    ];
    if (tags.isEmpty) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final existing = _dueOfCaret()?.dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing != null && !existing.isBefore(today)
          ? existing
          : DateTime(today.year, today.month, today.day + 7),
      firstDate: DateTime(today.year, today.month, today.day - 365),
      lastDate: DateTime(today.year + 5, today.month, today.day),
      helpText: 'Due date',
      confirmText: 'Set',
    );
    if (picked == null) return;
    // Onto the first tag on the line, and any other dated tag there is cleared,
    // so the line keeps exactly one deadline however it was tagged.
    app.setTagDue(b.id, line, tags.first.kind, picked);
    for (final t in tags.skip(1)) {
      if (t.due != null) app.setTagDue(b.id, line, t.kind, null);
    }
  }

  void _clearDue() {
    final b = app.caretBlock();
    if (b == null) return;
    final line = app.caretLineIndex();
    for (final t in NoteTag.listFrom(b.content)) {
      if (t.line == line && t.due != null) {
        app.setTagDue(b.id, line, t.kind, null);
      }
    }
  }
}

/// One button that turns the caret's line into a flashcard.
///
/// Tags remain the underlying mechanism — a card is a *view* of a tagged line,
/// which is what makes editing the note edit the card. But "tag it Question or
/// Definition, and remember which one, and get the shape right" is a rule the
/// student has to learn before anything happens, and getting it wrong produced
/// nothing with no explanation. This reads the line, picks the tag, and says
/// what it did.
class _MakeCardButton extends StatelessWidget {
  const _MakeCardButton({required this.app});
  final AppState app;

  void _say(BuildContext context, String? msg) {
    if (msg == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    // **Never disabled.** With a caret on a line it turns THAT line into a
    // card, which is the good form; with no caret it makes a new card in a
    // box of its own. That second behaviour used to be a separate Insert
    // ribbon entry with the same icon, on a different tab, doing a different
    // thing — one button, two ways of arriving at it.
    final onLine = app.canFormatText;
    return MenuAnchor(
      builder: (context, controller, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: onLine ? 'Make this line a flashcard' : 'New flashcard',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                if (onLine) {
                  _say(context, app.makeCardAtCaret());
                } else {
                  app.insertFlashcard();
                }
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Icon(Icons.style_outlined, size: 18),
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: const Icon(Icons.arrow_drop_down, size: 16),
          ),
        ],
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(TagKind.question.icon,
              size: 16, color: TagKind.question.color),
          shortcut:
              const SingleActivator(LogicalKeyboardKey.digit3, control: true),
          onPressed: () => app.toggleTagOnSelection(TagKind.question),
          child: const AppText('Question card'),
        ),
        MenuItemButton(
          leadingIcon: Icon(TagKind.definition.icon,
              size: 16, color: TagKind.definition.color),
          shortcut:
              const SingleActivator(LogicalKeyboardKey.digit5, control: true),
          onPressed: () => app.toggleTagOnSelection(TagKind.definition),
          child: const AppText('Definition card'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_underlined, size: 16),
          onPressed: () {
            if (!app.blankOutSelection()) {
              _say(context, 'Select the words to blank out first.');
            }
          },
          child: const AppText('Blank out selection'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.school_outlined, size: 16),
          onPressed: () {
            if (!app.showStudyPanel) app.toggleStudyPanel();
          },
          child: const AppText('Open study panel'),
        ),
      ],
    );
  }
}

/// Opens the planner, and says what is on today without opening it.
///
/// The badge counts **today's and overdue** rows, not everything dated. A
/// number that included next month's exam would be permanently non-zero, and a
/// badge that is always lit stops being read — the same reasoning that keeps
/// the study badge on cards *due* rather than on the whole deck.
class _PlannerButton extends StatelessWidget {
  const _PlannerButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sections = app.planner.sections(now: now);
    var count = 0;
    var overdue = false;
    for (final s in sections) {
      if (s.bucket == AgendaBucket.overdue) {
        overdue = true;
        count += s.items.length;
      } else if (s.bucket == AgendaBucket.today) {
        count += s.items.length;
      }
    }
    final alerts = app.planner.pendingAlerts.length;
    return Tooltip(
      message: alerts > 0
          ? '$alerts reminder${alerts == 1 ? '' : 's'} waiting'
          : count == 0
              ? 'Homework & reminders — every date in one place'
              : overdue
                  ? 'Homework & reminders — $count today or overdue'
                  : 'Homework & reminders — $count today',
      child: Stack(clipBehavior: Clip.none, children: [
        IconButton(
          icon: const Icon(Icons.event_note_outlined, size: 18),
          isSelected: app.showPlannerPanel,
          visualDensity: VisualDensity.compact,
          onPressed: app.togglePlannerPanel,
        ),
        if (count > 0 || alerts > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  // Red only for something already late; a waiting reminder is
                  // brass, and an ordinary "3 today" is the primary accent.
                  // Colour never carries this alone (style guide §3.5) — the
                  // tooltip says which it is.
                  color: overdue
                      ? OnoteColors.danger
                      : alerts > 0
                          ? OnoteColors.brass500
                          : Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AppText('${alerts > 0 ? alerts : count}',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: overdue || alerts > 0
                            ? Colors.white
                            : Theme.of(context).colorScheme.onPrimary)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Fast capture for a homework task while the student is already on the page
/// it belongs to. The planner remains the place to review everything; this is
/// deliberately only the three decisions needed to avoid losing a task.
Future<void> _addQuickHomework(BuildContext context, AppState app) async {
  final result = await showOnoteDialog<({String subject, String task, DateTime due})>(
    context: context,
    builder: (_) => const _QuickHomeworkDialog(),
  );
  if (result == null || !context.mounted) return;
  final title = result.subject.trim().isEmpty
      ? result.task.trim()
      : '${result.subject.trim()} — ${result.task.trim()}';
  app.planner.reminders.add(
    text: title,
    at: result.due,
    notebookId: app.notebookId,
    // A reminder with this page id becomes a direct jump back to the exact
    // worksheet/note that created it in the Planner.
    pageId: app.pageId,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Homework added and linked to this page.')));
}

class _QuickHomeworkDialog extends StatefulWidget {
  const _QuickHomeworkDialog();

  @override
  State<_QuickHomeworkDialog> createState() => _QuickHomeworkDialogState();
}

class _QuickHomeworkDialogState extends State<_QuickHomeworkDialog> {
  final _subject = TextEditingController();
  final _task = TextEditingController();
  late DateTime _due;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _due = DateTime(now.year, now.month, now.day + 1, 17);
  }

  @override
  void dispose() {
    _subject.dispose();
    _task.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
      helpText: 'Homework due date',
    );
    if (chosen == null || !mounted) return;
    setState(() => _due = DateTime(
        chosen.year, chosen.month, chosen.day, _due.hour, _due.minute));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add homework'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _subject,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Subject', hintText: 'For example: Chemistry'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _task,
              maxLines: 2,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                  labelText: 'Homework', hintText: 'What needs to be done?'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(MaterialLocalizations.of(context)
                    .formatMediumDate(_due)),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Linked to the page currently open.',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Add')),
        ],
      );

  void _submit() {
    final task = _task.text.trim();
    if (task.isEmpty) return;
    Navigator.of(context)
        .pop((subject: _subject.text.trim(), task: task, due: _due));
  }
}

/// One entry on the Insert ribbon, and its arrow when it has one.
///
/// Generic, because the catalog is: the PDF import used to be a hand-built
/// split button and everything else a plain one, so an item that grew a
/// second choice needed a new widget. Now it needs a list entry.
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
          ? CommandButton(
              icon: item.icon,
              label: item.label,
              onPressed: press,
            )
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
      return Padding(
        padding: gap,
        child: _main(context),
      );
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
class _ToolbarScroll extends MaterialScrollBehavior {
  const _ToolbarScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
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
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 4),
                AppText(label,
                    style: OnoteType.caption
                        .copyWith(fontWeight: FontWeight.w600, color: accent)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
