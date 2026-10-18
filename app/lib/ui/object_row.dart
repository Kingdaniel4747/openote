/// Contextual controls for the object currently being edited.
///
/// Ordinary page controls live in the View tab, so this row is absent during
/// normal writing and only appears while an equation needs its own controls.
///
/// ## Hard rules for anything added here
///
///  * **No `Spacer`, `Expanded` or `Flexible` children.** A flex child under
///    the unbounded constraint a horizontal scroll view offers is a hard
///    layout assertion — it is what once killed the entire Draw row. Push
///    things apart with a `SizedBox`.
///  * **Nothing may reach through `FocusManager`.** Every control here acts on
///    something the student is in the middle of writing; taking the caret
///    away to run a command is the bug this release opened with.
///  * **Opacity only when the face changes.** A slide says "a new thing
///    arrived from elsewhere"; a fade says "this row is now about that".
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';

import '../math/active_math.dart';
import '../math/evaluate.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'math_bar.dart';
import 'object_face.dart';
import 'fixed_toolbar.dart';

/// The row's height, everywhere. `OnoteSize.button` plus two above and below.
const double kObjectRowHeight = 36;

class ObjectRow extends StatelessWidget {
  const ObjectRow({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final face = objectFaceOf(app);
    // Page controls live under View. Keep this contextual strip only while an
    // equation needs it, so ordinary writing gets the space back.
    if (face == ObjectFace.page) return const SizedBox.shrink();
    return Container(
      height: kObjectRowHeight,
      decoration: BoxDecoration(
        // `chrome2` — the "insets within chrome" role — so the row reads as a
        // different layer and is never mistaken for a second command row.
        color: s.chrome2,
        border: Border(top: BorderSide(color: s.border)),
      ),
      child: ScrollConfiguration(
        behavior: const _RowScroll(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: AnimatedSwitcher(
            duration: kMathMenuFade,
            // Keyed on the FACE, not on the widget, so moving between two
            // equations does not re-animate a row that is about to be
            // identical.
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(
              key: ValueKey(face),
              child: _face(context, face),
            ),
          ),
        ),
      ),
    );
  }

  Widget _face(BuildContext context, ObjectFace face) {
    switch (face) {
      case ObjectFace.equation:
        final m = app.activeMath;
        // One frame at most: the face is derived from `editingBlockId`, which
        // is true before the equation editor has built and registered itself.
        // Empty, NEVER the page face — falling back would flash the page
        // controls for a frame every time an equation opened.
        if (m == null) return const SizedBox(height: kObjectRowHeight);
        return EquationFace(
          math: m,
          onDrawGraph: m.drawGraph,
          onEvaluateAtValue: m.evaluateAtValue,
          angleMode: app.angleMode,
          onToggleAngleMode: () {
            // The open equation and its neighbours are worked out by
            // `setAngleMode` itself — every route to it behaves the same,
            // and only it knows which mode the page was written in.
            app.setAngleMode(app.angleMode == AngleMode.degrees
                ? AngleMode.radians
                : AngleMode.degrees);
          },
          recentIds: app.recentMathIds,
        );
      case ObjectFace.page:
        return PageFace(app: app);
    }
  }
}

/// The palette, while an equation is being written.
///
/// **The parity rule, made mechanical.** This takes an [ActiveMathEditor] and
/// primitives — no `AppState`, no `Block`, no `BlockType`, no block id, no
/// placement. A standalone equation and one inside a sentence therefore
/// produce the same row in the same pixels, because nothing here is given
/// anything it could tell them apart with. The owner: *"A regular user is not
/// going to think a standalone maths box is any different to one in a text
/// box, so they must have exact feature and behaviour parrody."*
///
/// Keeping that a compile error rather than a review catch is the point;
/// `EquationPlacement` exists two files away, and discipline is what wore out
/// last time.
class EquationFace extends StatelessWidget {
  const EquationFace({
    super.key,
    required this.math,
    required this.angleMode,
    required this.onToggleAngleMode,
    this.onDrawGraph,
    this.onEvaluateAtValue,
    this.recentIds = const [],
  });

  final ActiveMathEditor math;

  /// Draw this equation, or null when it cannot be drawn from here.
  final VoidCallback? onDrawGraph;

  /// Plug a value into this equation, or null when it cannot be from here.
  final VoidCallback? onEvaluateAtValue;
  final AngleMode angleMode;
  final VoidCallback onToggleAngleMode;
  final List<String> recentIds;

  @override
  Widget build(BuildContext context) => MathBar(
        onInsert: math.insert,
        onDrawGraph: onDrawGraph,
        onEvaluateAtValue: onEvaluateAtValue,
        latexMode: math.latexMode,
        latexAvailable: math.latexAvailable,
        onToggleLatex: math.toggleLatex,
        angleMode: angleMode,
        onToggleAngleMode: onToggleAngleMode,
        recentIds: recentIds,
      );
}

/// The page's own controls, when nothing else is being written.
///
/// These controls sit in the View tab because they change the current page.
class PageFace extends StatelessWidget {
  const PageFace({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = context.surfaces;
    Widget bg(String v, IconData icon, String tip) => IconButton(
          icon: Icon(icon, size: OnoteIcon.md),
          tooltip: 'Background: $tip',
          isSelected: app.pageProps.background == v,
          visualDensity: VisualDensity.compact,
          color: app.pageProps.background == v ? scheme.primary : null,
          onPressed: () => app.setBackground(v),
        );
    final paged = app.pageProps.isPaged;
    return FixedToolbar(children: [
      TextButton.icon(
        key: const ValueKey('split-screen'),
        style: TextButton.styleFrom(
          foregroundColor:
              app.splitViewEnabled ? scheme.primary : surfaces.textPrimary,
        ),
        icon: Icon(
            app.splitViewEnabled
                ? Icons.view_agenda_outlined
                : Icons.vertical_split_outlined,
            size: 18),
        label:
            Text(app.splitViewEnabled ? 'Close split screen' : 'Split screen'),
        onPressed: app.toggleSplitView,
      ),
      if (app.hasPdfSlideContent)
        TextButton.icon(
          key: const ValueKey('pdf-view-toggle'),
          style: TextButton.styleFrom(
            foregroundColor:
                app.pageProps.pdfOnly ? scheme.primary : surfaces.textPrimary,
          ),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(app.pageProps.pdfOnly ? 'PDF slides' : 'PDF editor'),
          onPressed: () => app.setPdfEditorView(!app.pageProps.pdfOnly),
        ),
      PopupMenuButton<bool>(
        tooltip: tr(context, 'Arrange selected images and PDFs'),
        enabled: app.blocks
                .where((b) =>
                    app.selectedIds.contains(b.id) && b.type == BlockType.image)
                .length >
            1,
        onSelected: (horizontal) =>
            app.arrangeSelectedMedia(horizontal: horizontal),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: false,
            child: Row(children: [
              Icon(Icons.view_agenda_outlined, size: 18),
              SizedBox(width: 9),
              AppText('Arrange vertically'),
            ]),
          ),
          PopupMenuItem(
            value: true,
            child: Row(children: [
              Icon(Icons.view_week_outlined, size: 18),
              SizedBox(width: 9),
              AppText('Arrange horizontally'),
            ]),
          ),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.view_module_outlined, size: 18),
            SizedBox(width: 5),
            AppText('Arrange'),
          ]),
        ),
      ),
      const SizedBox(width: 2),
      Container(
        padding: const EdgeInsets.only(left: 7, right: 2),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outline.withValues(alpha: .22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const AppText('Background', style: TextStyle(fontSize: 11)),
          bg('blank', Icons.crop_din, 'blank'),
          bg('grid', Icons.grid_4x4, 'grid'),
          bg('dotted', Icons.apps, 'dotted'),
          bg('ruled', Icons.notes, 'ruled'),
        ]),
      ),
      const _Sep(),
      // Canvas or paper. Per page, not per notebook: one notebook holds the
      // lecture you scribble on and the essay you hand in, and making you
      // choose once for both is why people keep two apps.
      if (!app.pageProps.pdfOnly)
        Tooltip(
          message: paged
              ? 'Page mode: ${app.pageProps.paper.name}'
                  '${app.pageProps.landscape ? ' landscape' : ''} '
                  '— click for canvas'
              : 'Canvas mode: boundless — click for pages',
          child: TextButton.icon(
            icon: Icon(paged ? Icons.description : Icons.dashboard_customize,
                size: OnoteIcon.md),
            label: AppText(paged ? 'Pages' : 'Canvas'),
            style: TextButton.styleFrom(
              foregroundColor: paged ? scheme.primary : null,
              backgroundColor:
                  paged ? scheme.primary.withValues(alpha: .14) : null,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => app.setPageLayout(paged ? 'canvas' : 'paged'),
          ),
        ),
      // At the END of its group, so its arrival displaces nothing.
      if (paged)
        PopupMenuButton<String>(
          tooltip: 'Paper size',
          icon: const Icon(Icons.aspect_ratio, size: OnoteIcon.md),
          onSelected: (v) => v == '_rotate'
              ? app.setPageLayout('paged', landscape: !app.pageProps.landscape)
              : app.setPageLayout('paged', paper: v),
          itemBuilder: (_) => [
            for (final p in PaperSize.all)
              CheckedPopupMenuItem(
                value: p.name,
                checked: app.pageProps.paperSize == p.name,
                child: Text(p.name),
              ),
            const PopupMenuDivider(),
            CheckedPopupMenuItem(
              value: '_rotate',
              checked: app.pageProps.landscape,
              child: const Text('Landscape'),
            ),
          ],
        ),
      const _Sep(),
      IconButton(
        icon: Icon(app.snapToGrid ? Icons.grid_goldenratio : Icons.grid_off,
            size: OnoteIcon.md),
        tooltip: app.snapToGrid
            ? 'Snap to grid: ON (grid shows while dragging)'
            : 'Snap to grid: OFF — free placement',
        isSelected: app.snapToGrid,
        visualDensity: VisualDensity.compact,
        color: app.snapToGrid ? scheme.primary : null,
        onPressed: app.toggleSnap,
      ),
      const _Sep(),
      IconButton(
        icon: Icon(
            Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            size: OnoteIcon.md),
        tooltip: Theme.of(context).brightness == Brightness.dark
            ? 'Switch to light mode'
            : 'Switch to dark mode',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.setThemeMode(
            Theme.of(context).brightness == Brightness.dark
                ? ThemeMode.light
                : ThemeMode.dark),
      ),
      const _Sep(),
      IconButton(
        icon: const Icon(Icons.remove, size: OnoteIcon.md),
        tooltip: 'Zoom out  (Ctrl+-)',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.setZoom(app.canvas.scale / 1.2),
      ),
      // **A button, and it says so before you press it.** It was the only
      // control on this row with no tooltip, sitting between a minus and a
      // plus, reading as the number those two were changing — and pressing
      // it resets the OFFSET as well as the scale, so somebody at the bottom
      // of a long page was thrown back to the top with no warning.
      Tooltip(
        message: 'Back to 100% and the top of the page  (Ctrl+0)',
        child: AnimatedBuilder(
          animation: app.canvas,
          builder: (context, _) => TextButton(
            onPressed: app.canvas.reset,
            child: Text('${(app.canvas.scale * 100).round()}%',
                style: OnoteType.small),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.add, size: OnoteIcon.md),
        tooltip: 'Zoom in  (Ctrl+=)',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.setZoom(app.canvas.scale * 1.2),
      ),
      IconButton(
        icon: const Icon(Icons.fit_screen_outlined, size: OnoteIcon.md),
        tooltip: 'Zoom to fit content',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.fitTo(app.contentBounds().inflate(24)),
      ),
      const SizedBox(width: 4),
    ]);
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: context.surfaces.border,
      );
}

/// A row wider than the window must SCROLL, not clip: clipped pixels do not
/// hit-test, so on a narrow window the rightmost controls simply stop
/// responding with no visible reason. Mouse and trackpad are added to the drag
/// devices for the same reason the toolbar's own scroller adds them.
class _RowScroll extends MaterialScrollBehavior {
  const _RowScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
