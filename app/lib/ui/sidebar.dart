import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_state.dart';

import '../theme/onote_theme.dart';

import 'inline_section_strip.dart';
import 'notebook_manager.dart';
import 'protect_dialog.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';
import 'node_context_menu.dart';
import 'page_export_menu.dart';

Color _sectionColor(String? token, bool dark) => switch (token) {
      'brass-400' => OnoteColors.brass400,
      'green' => OnoteColors.success,
      'blue' => const Color(0xFF2F6FB3),
      'violet' => const Color(0xFF6A4BC0),
      'red' => OnoteColors.danger,
      _ => dark ? OnoteColors.ink400 : OnoteColors.ink500,
    };

/// Pages use the same inline movement as sections. Visible descendants travel
/// with their parent, while each subpage can still be moved on its own.
class _PageList extends StatefulWidget {
  const _PageList(
      {super.key,
      required this.app,
      required this.section,
      this.compact = false});
  final AppState app;
  final TreeNode section;
  final bool compact;

  @override
  State<_PageList> createState() => _PageListState();
}

class _PageListState extends State<_PageList> {
  String? _renamingId;
  String? _previewMoving, _previewTarget;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final all = app.pagesOf(widget.section.id);
    final visible = <TreeNode>[];
    int? hiddenBelow;
    for (final page in all) {
      if (hiddenBelow != null) {
        if (page.level > hiddenBelow) continue;
        hiddenBelow = null;
      }
      visible.add(page);
      if (app.collapsedPages.contains(page.id)) hiddenBelow = page.level;
    }
    if (visible.isEmpty) {
      if (widget.compact) return const SizedBox.shrink();
      return Center(
          child: AppText('No pages yet',
              style: TextStyle(
                  fontSize: 12, color: context.surfaces.textSecondary)));
    }
    final byId = {for (final page in visible) page.id: page};
    List<TreeNode> branchOf(String id) {
      final at = all.indexWhere((p) => p.id == id);
      if (at < 0) return [];
      var end = at + 1;
      while (end < all.length && all[end].level > all[at].level) {
        end++;
      }
      return all.sublist(at, end);
    }

    bool canNest(String moving, String target) {
      final branch = branchOf(moving);
      final parent = byId[target];
      if (branch.isEmpty ||
          parent == null ||
          branch.any((p) => p.id == target)) {
        return false;
      }
      final delta = parent.level + 1 - branch.first.level;
      return branch.every((p) => p.level + delta <= 2);
    }

    final previewBranch =
        _previewMoving == null ? <TreeNode>[] : branchOf(_previewMoving!);
    final previewParent = byId[_previewTarget];
    final previewDelta = previewBranch.isEmpty || previewParent == null
        ? 0
        : previewParent.level + 1 - previewBranch.first.level;
    final branches = <String, List<String>>{};
    for (var i = 0; i < visible.length; i++) {
      var end = i + 1;
      while (end < visible.length && visible[end].level > visible[i].level) {
        end++;
      }
      branches[visible[i].id] =
          visible.sublist(i, end).map((p) => p.id).toList();
    }
    double height(TreeNode page) {
      if (widget.compact) return 44;
      final painter = TextPainter(
        text: TextSpan(
            text: 'Mg',
            style: DefaultTextStyle.of(context).style.copyWith(
                fontSize: 13,
                fontWeight:
                    app.pageId == page.id ? FontWeight.w600 : FontWeight.w400)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final height = painter.height.clamp(16.0, double.infinity) + 12;
      painter.dispose();
      return page.id == _renamingId ? height + 10 : height;
    }

    return InlineSectionStrip(
      axis: Axis.vertical,
      onHold: (id, position) {
        final node = app.node(id);
        if (node != null) {
          showNodeMenu(context, app, node,
              canIndent: node.kind == NodeKind.page, position: position);
        }
      },
      ids: [for (final page in visible) page.id],
      widths: [for (final page in visible) height(page)],
      disabledId: _renamingId,
      dragGroups: branches,
      allowExternalDrops: true,
      preferNextTarget: true,
      canNest: canNest,
      onNestPreview: (moving, target) => setState(() {
        _previewMoving = moving;
        _previewTarget = target;
      }),
      onNest: (moving, target) {
        app.reorderPageTree(moving, target, after: true, nest: true);
        if (app.collapsedPages.contains(target)) {
          app.togglePageCollapsed(target);
        }
      },
      canInsertBefore: (moving, next) =>
          next == null || byId[next]!.level <= byId[moving]!.level,
      trailing: const SizedBox.shrink(),
      onReorder: (moving, targetId, after) {
        final movingPage = app.node(moving)!;
        var target = app.node(targetId)!;
        // A parent goes after the whole preceding branch, preserving that
        // branch's children instead of accidentally becoming one of them.
        while (target.level > movingPage.level) {
          final at = all.indexWhere((p) => p.id == target.id);
          final parent =
              all.take(at).where((p) => p.level < target.level).lastOrNull;
          if (parent == null) break;
          target = parent;
        }
        app.reorderPageTree(moving, target.id, after: after);
      },
      children: [
        for (final page in visible)
          if (widget.compact)
            Tooltip(
              triggerMode: TooltipTriggerMode.manual,
              message: page.title,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => app.selectPage(page.id),
                  onSecondaryTapUp: (d) => showNodeMenu(context, app, page,
                      canIndent: true, position: d.globalPosition),
                  child: AnimatedContainer(
                    alignment: Alignment.center,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(
                        left: 6.0 *
                            (previewBranch.any((p) => p.id == page.id)
                                ? page.level + previewDelta
                                : page.level)),
                    decoration: BoxDecoration(
                      color: _sectionColor(page.color,
                              Theme.of(context).brightness == Brightness.dark)
                          .withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(6),
                      border: page.id == _previewTarget || app.pageId == page.id
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                    ),
                    child: Icon(
                        page.level == 0
                            ? Icons.description_outlined
                            : Icons.subdirectory_arrow_right,
                        size: 16,
                        color: app.pageId == page.id
                            ? Theme.of(context).colorScheme.primary
                            : context.surfaces.textSecondary),
                  ),
                ),
              ),
            )
          else
            _PageTile(
              app: app,
              page: page,
              hasChildren: all.indexOf(page) + 1 < all.length &&
                  all[all.indexOf(page) + 1].level > page.level,
              collapsed: app.collapsedPages.contains(page.id),
              previewLevel: previewBranch.any((p) => p.id == page.id)
                  ? page.level + previewDelta
                  : null,
              nestTarget: page.id == _previewTarget,
              onRenamingChanged: (renaming) =>
                  setState(() => _renamingId = renaming ? page.id : null),
            ),
      ],
    );
  }
}

/// Detects a double-click WITHOUT a DoubleTap recognizer. An InkWell that
/// binds `onDoubleTap` defers EVERY single tap by the double-tap window
/// (~300 ms) while the gesture arena waits to see whether a second tap
/// follows — which was the "very consistent" delay on every sidebar click
/// (pages, sections, groups all bound it for rename; hotkeys were instant
/// because they skip the pointer pipeline entirely). With this gate the
/// first click ACTS immediately and a second within the window renames —
/// the file-explorer behaviour, and the whole delay gone.
class SidebarDoubleTapGate {
  DateTime? _last;

  /// True when this tap is the second of a double-click.
  bool tap() {
    final now = sidebarNow();
    final isDouble = _last != null &&
        now.difference(_last!) < const Duration(milliseconds: 300);
    _last = isDouble ? null : now;
    return isDouble;
  }
}

/// The clock [SidebarDoubleTapGate] measures the double-click window against.
///
/// A seam, because the window is **wall-clock** and a widget test's clock is
/// not. `tester.pump(Duration)` advances the fake clock; it does not advance
/// `DateTime.now()`. So the probe that guards this affordance was really
/// measuring how fast the machine could rebuild the sidebar between two taps —
/// it passed where that took under 300 ms and failed where it did not, which is
/// a test that reports the hardware rather than the code.
///
/// Production keeps real time, because a double-click IS a real-time gesture
/// and the 300 ms window has to match the one the user's hand is aiming at.
@visibleForTesting
DateTime Function() sidebarNow = DateTime.now;

/// Navigator (style guide §7b): a notebook bar, a search/jump box, then TWO
/// COLUMNS — sections on the left, the active section's pages on the right —
/// each independently scrollable and resizable, collapsible to a 44px rail.
///
/// The OneNote shape, adopted because the previous stacked layout made
/// sections and pages fight over one column's height: with a real notebook
/// both zones scrolled, and you could never see the section list and a page
/// list at once. Beyond the shape itself, three things OneNote doesn't do:
/// a Home pane with recent pages, a remembered per-section page so
/// browsing never loses your place, and the rail.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.app});
  final AppState app;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchCtl = TextEditingController();
  String _query = '';
  String? _renamingSectionId;

  AppState get app => widget.app;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchCtl.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        child: app.navCollapsed
            ? _NavRail(app: app, dark: dark)
            : _expanded(context),
      ),
    );
  }

  Widget _expanded(BuildContext context) {
    final searching = _query.trim().isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: app.sectionTabsAbovePage
              ? app.navPagesW.clamp(128.0, 320.0)
              : app.navSectionsW + app.navPagesW,
          color: context.surfaces.chrome2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NotebookHeader(app: app),
              _searchRow(context),
              const Divider(height: 1),
              Expanded(
                child: searching
                    ? _searchResults(context)
                    : _twoColumnBody(context),
              ),
            ],
          ),
        ),
        // The navigator's own right edge resizes the pages column, so the
        // whole thing grows and shrinks from where your cursor already is.
        _VDragHandle(
          onDrag: (dx) {
            final minimum = app.sectionTabsAbovePage ? 128.0 : 80.0;
            final current = app.sectionTabsAbovePage
                ? app.navPagesW.clamp(minimum, 320.0)
                : app.navPagesW;
            app.navPagesW = (current + dx).clamp(minimum, 320.0);
            app.refresh();
          },
          onEnd: () => app.setNavPagesW(app.navPagesW),
        ),
      ],
    );
  }

  // ── Search / quick-jump ───────────────────────────────────────────────

  Widget _searchRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchCtl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  hintText: 'Search or jump to…',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  suffixIcon: _query.isEmpty
                      ? null
                      : InkWell(
                          onTap: _clearSearch,
                          child: const Icon(Icons.close, size: 16),
                        ),
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: scheme.outline.withValues(alpha: .6)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchResults(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = app.nodes
        .where((n) =>
            (n.kind == NodeKind.page || n.kind == NodeKind.section) &&
            n.title.toLowerCase().contains(q) &&
            // Titles are excluded for the same reason content is (see
            // AppState.searchContent). A page called "Therapy" leaks the thing
            // that made it worth locking, and half a search box that honours
            // the passcode while the other half does not is not a gate. The
            // tree still shows it, so a locked page is never unreachable —
            // search is where you would stumble ON it.
            !app.isLocked(n.id))
        .toList();
    // Notebook-wide content search (TEXT-7). Titles match first because a
    // title hit is almost always what you meant; content hits follow, minus
    // any page already listed above.
    final titleHits = {for (final n in results) n.id};
    final contentHits = [
      for (final h in _contentHitsFor(q))
        if (!titleHits.contains(h.pageId)) h
    ];
    if (results.isEmpty && contentHits.isEmpty) {
      return Center(
        child: Text('No matches for “${_query.trim()}”',
            style:
                TextStyle(fontSize: 12, color: context.surfaces.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final n in results)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
                n.kind == NodeKind.section
                    ? Icons.folder_outlined
                    : n.level == 0
                        ? Icons.description_outlined
                        : Icons.subdirectory_arrow_right,
                size: 16),
            title: Text(n.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            subtitle: n.kind == NodeKind.page
                ? Text(app.node(n.parentId)?.title ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11))
                : null,
            onTap: () {
              if (n.kind == NodeKind.page) {
                app.selectPage(n.id);
              } else {
                app.activateSection(n.id);
              }
              _clearSearch();
            },
          ),
        if (contentHits.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: AppText('In page content',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.surfaces.textSecondary)),
          ),
          for (final h in contentHits)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.search, size: 16),
              title: Text(app.node(h.pageId)?.title ?? 'Untitled',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
              subtitle: h.snippet.isEmpty
                  ? null
                  : Text(h.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
              onTap: () {
                app.selectPage(h.pageId);
                _clearSearch();
              },
            ),
        ],
      ],
    );
  }

  /// Content hits, cached per query so the SQLite scan doesn't re-run on every
  /// rebuild while the results are on screen.
  String? _contentQuery;
  List<({String pageId, String snippet})> _contentCache = const [];

  List<({String pageId, String snippet})> _contentHitsFor(String q) {
    // Below 3 characters the result set is everything, which is neither useful
    // nor cheap.
    if (q.length < 3) return const [];
    if (_contentQuery == q) return _contentCache;
    _contentQuery = q;
    _contentCache = app.searchContent(q);
    return _contentCache;
  }

  // ── Two columns: sections | pages (the OneNote shape) ──────────────────
  //
  // Side by side rather than stacked, because the old stack made sections and
  // pages fight over one column's HEIGHT: with a real notebook both zones
  // scrolled, the split handle needed constant fiddling, and you could never
  // see the section list and a page list at the same time — which is the
  // thing that makes OneNote's navigator effortless to scan.

  Widget _twoColumnBody(BuildContext context) {
    final sections =
        app.nodes.where((n) => n.kind == NodeKind.section).toList();
    if (sections.isEmpty) {
      return _EmptyHint(
        icon: Icons.folder_outlined,
        text: 'No sections yet.\nCreate one to get started.',
        actionLabel: 'New section',
        onAction: app.addSection,
      );
    }
    final active = app.activeSection ?? sections.first;
    // In the tabbed layout the section chooser lives immediately above the
    // page. Keeping this navigator to one pages column avoids showing the
    // same sections twice while retaining search, notebook controls and page
    // drag/drop in their familiar place.
    if (app.sectionTabsAbovePage) {
      return Container(
        color: context.surfaces.chrome,
        child: app.navHome ? _HomePane(app: app) : _pagesZone(context, active),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: app.navSectionsW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionActions(context),
              const Divider(height: 1),
              Expanded(child: _sectionsColumn(context)),
            ],
          ),
        ),
        _VDragHandle(
          onDrag: (dx) {
            app.navSectionsW = (app.navSectionsW + dx).clamp(80.0, 220.0);
            app.refresh();
          },
          onEnd: () => app.setNavSectionsW(app.navSectionsW),
        ),
        // The pages pane sits on the lighter surface colour — the same
        // two-tone depth cue the canvas already uses, no new tokens.
        Expanded(
          child: Container(
            color: context.surfaces.chrome,
            child:
                app.navHome ? _HomePane(app: app) : _pagesZone(context, active),
          ),
        ),
      ],
    );
  }

  Widget _pagesZone(BuildContext context, TreeNode section) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = _sectionColor(section.color, dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 2),
          child: Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: dark ? OnoteColors.moon300 : OnoteColors.graphite500,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: 'New page in ${section.title}',
                onPressed: () => app.addPage(sectionId: section.id),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              _PageList(key: ValueKey(section.id), app: app, section: section),
        ),
      ],
    );
  }
  // ── Section list (groups → sections) ──────────────────────────────────

  Widget _sectionsColumn(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final groups = app.nodes
        .where((n) => n.kind == NodeKind.sectionGroup && n.parentId == null)
        .toList();
    final looseSections = app.nodes
        .where((n) => n.kind == NodeKind.section && n.parentId == null)
        .toList();

    if (groups.isEmpty && looseSections.isEmpty) {
      return _EmptyHint(
        icon: Icons.folder_outlined,
        text: 'No sections yet.\nCreate one to get started.',
        actionLabel: 'New section',
        onAction: app.addSection,
      );
    }

    // Headers and the boundary to ungrouped sections participate in layout,
    // while only sections can be grabbed. This keeps group destinations inline.
    const looseBoundary = 'section-list-ungrouped';
    final entries = <TreeNode>[
      for (final group in groups) ...[
        group,
        if (!app.collapsedGroups.contains(group.id))
          ...app.nodes.where(
              (n) => n.kind == NodeKind.section && n.parentId == group.id),
      ],
      ...looseSections,
    ];
    final ids = <String>[
      for (final entry in entries)
        if (entry.parentId == null &&
            entry.kind == NodeKind.section &&
            looseSections.first.id == entry.id &&
            groups.isNotEmpty) ...[
          looseBoundary,
          entry.id,
        ] else
          entry.id,
      if (looseSections.isEmpty && groups.isNotEmpty) looseBoundary,
    ];
    double textHeight(double size, FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
            text: 'Mg',
            style: DefaultTextStyle.of(context)
                .style
                .copyWith(fontSize: size, fontWeight: weight)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final sectionHeight =
        textHeight(12, FontWeight.w600).clamp(16.0, double.infinity) + 14;
    final groupHeight =
        textHeight(13, FontWeight.w600).clamp(16.0, double.infinity) + 12;

    return InlineSectionStrip(
      axis: Axis.vertical,
      onHold: (id, position) {
        final node = app.node(id);
        if (node != null) {
          showNodeMenu(context, app, node,
              canIndent: node.kind == NodeKind.page, position: position);
        }
      },
      ids: ids,
      widths: [
        for (final id in ids)
          id == looseBoundary
              ? 8
              : app.node(id)!.kind == NodeKind.sectionGroup
                  ? groupHeight
                  : id == _renamingSectionId
                      ? 48
                      : sectionHeight
      ],
      fixedIds: {looseBoundary, for (final group in groups) group.id},
      disabledId: _renamingSectionId,
      trailing: const SizedBox.shrink(),
      onReorder: (moving, target, after) {
        final targetNode = app.node(target);
        final groupId = target == looseBoundary
            ? null
            : targetNode?.kind == NodeKind.sectionGroup
                ? target
                : targetNode?.parentId;
        if (app.node(moving)?.parentId != groupId) {
          app.moveSectionToGroup(moving, groupId);
        }
        if (targetNode?.kind == NodeKind.section) {
          app.reorderNode(moving, target, after: after);
        } else {
          final siblings = app.nodes.where((n) =>
              n.kind == NodeKind.section &&
              n.parentId == groupId &&
              n.id != moving);
          if (siblings.isNotEmpty) {
            app.reorderNode(moving, siblings.first.id, after: false);
          }
        }
      },
      children: [
        for (final id in ids)
          if (id == looseBoundary)
            const SizedBox.shrink()
          else if (app.node(id)!.kind == NodeKind.sectionGroup)
            _GroupHeader(app: app, group: app.node(id)!)
          else
            Padding(
              padding: EdgeInsets.only(
                  left: app.node(id)!.parentId == null ? 0 : 13),
              child: DecoratedBox(
                decoration: BoxDecoration(
                    border: app.node(id)!.parentId == null
                        ? null
                        : Border(
                            left: BorderSide(
                                color: dark
                                    ? OnoteColors.night300
                                    : OnoteColors.paper300))),
                child: _SectionHeader(
                  app: app,
                  section: app.node(id)!,
                  dark: dark,
                  active: app.activeSectionId == id,
                  onRenamingChanged: (renaming) =>
                      setState(() => _renamingSectionId = renaming ? id : null),
                ),
              ),
            ),
      ],
    );
  }
  // ── Footer toolbar ────────────────────────────────────────────────────

  Widget _sectionActions(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'New section',
              visualDensity: VisualDensity.compact,
              onPressed: app.addSection,
              style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              constraints: const BoxConstraints.tightFor(width: 32, height: 36),
              padding: EdgeInsets.zero,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.topic_outlined, size: 18),
              tooltip: 'New section group',
              visualDensity: VisualDensity.compact,
              onPressed: app.addSectionGroup,
              style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              constraints: const BoxConstraints.tightFor(width: 32, height: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      );
}

class _GroupHeader extends StatefulWidget {
  const _GroupHeader({required this.app, required this.group});
  final AppState app;
  final TreeNode group;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _renaming = false;
  final _taps = SidebarDoubleTapGate();

  /// This row's place in the keyboard, handed to its `InkWell` so there is one
  /// focus node rather than two — see [_nodeDeleteKey].
  late final FocusNode _rowFocus = FocusNode(
      debugLabel: 'nav-group',
      onKeyEvent: (n, e) => _nodeDeleteKey(context, app, group, n, e));

  AppState get app => widget.app;
  TreeNode get group => widget.group;

  @override
  void dispose() {
    _rowFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = app.collapsedGroups.contains(group.id);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Drop a section ONTO a group → move it into the group (ORG-1).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        final moving = app.node(d.data);
        // Its current group cannot be a destination: it already contains the
        // section, so showing it as a drop target would suggest a move that
        // changes nothing.
        return moving?.kind == NodeKind.section && moving?.parentId != group.id;
      },
      onAcceptWithDetails: (d) => app.moveSectionToGroup(d.data, group.id),
      builder: (ctx, cand, rej) {
        final target = cand.isNotEmpty;
        const labelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
        return InkWell(
          focusNode: _rowFocus,
          onFocusChange: (has) {
            if (has) _keyboardEnteredRow(app);
          },
          // No onDoubleTap — it deferred every click (see SidebarDoubleTapGate).
          onTap: _renaming
              ? null
              : () {
                  if (_taps.tap()) {
                    setState(() => _renaming = true);
                    return;
                  }
                  // The click is what aims the keyboard at this row; an InkWell
                  // does not take focus on tap of its own accord.
                  _rowFocus.requestFocus();
                  app.toggleGroupCollapsed(group.id);
                },
          onSecondaryTapUp: (d) => showNodeMenu(context, app, group,
              canIndent: false, position: d.globalPosition),
          child: Container(
            // A foreground border paints over the row instead of taking up
            // layout space, so its title and icons stay perfectly still.
            foregroundDecoration: target
                ? BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(6))
                : null,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
            child: Row(
              children: [
                Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 16, color: context.surfaces.textSecondary),
                const SizedBox(width: 4),
                Icon(Icons.topic_outlined,
                    size: 16, color: _sectionColor(group.color, dark)),
                const SizedBox(width: 6),
                Expanded(
                  child: _renaming
                      ? NodeInlineRename(
                          initial: group.title,
                          style: labelStyle,
                          onSubmit: (v) {
                            app.renameNode(group.id, v);
                            if (mounted) setState(() => _renaming = false);
                          },
                          onCancel: () {
                            if (mounted) setState(() => _renaming = false);
                          },
                        )
                      : Text(group.title,
                          overflow: TextOverflow.ellipsis, style: labelStyle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A vertical grab strip for resizing a navigator column.
///
/// 5px wide and visually just the divider line — the affordance is the cursor
/// change, which is how every two-pane app on the desktop does it.
class _VDragHandle extends StatelessWidget {
  const _VDragHandle({required this.onDrag, required this.onEnd});
  final void Function(double dx) onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        child: Container(
          width: 5,
          alignment: Alignment.center,
          child: Container(width: 1, color: Theme.of(context).dividerColor),
        ),
      ),
    );
  }
}

/// The Home pane: recently visited pages. A springboard, not a place — any
/// page tap returns the pane to that page's section.
class _HomePane extends StatelessWidget {
  const _HomePane({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final recents = app.recentPages(max: 8);

    Widget label(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(s,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: context.surfaces.textSecondary)),
        );

    Widget row(TreeNode page, IconData icon, {Color? iconColor}) => InkWell(
          onTap: () => app.selectPage(page.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Icon(icon,
                  size: 16, color: iconColor ?? context.surfaces.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(page.title.isEmpty ? 'Untitled' : page.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    Text(app.node(page.parentId)?.title ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: context.surfaces.textSecondary)),
                  ],
                ),
              ),
            ]),
          ),
        );

    if (recents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'Nothing here yet.\n\nPages you visit show up under Recent.',
          style: TextStyle(fontSize: 12, height: 1.45),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        if (recents.isNotEmpty) ...[
          label('RECENT'),
          for (final p in recents) row(p, Icons.history),
        ],
      ],
    );
  }
}

/// The collapsed navigator: a 44px rail that keeps every destination one
/// click away — expand, notebooks, Home, and a chip per section.
class _NavRail extends StatelessWidget {
  const _NavRail({required this.app, required this.dark});
  final AppState app;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = app.notebooks.firstWhere((n) => n.id == app.notebookId);
    final sections =
        app.nodes.where((n) => n.kind == NodeKind.section).toList();
    // Section tabs already provide section navigation above the canvas.
    // Keep page switching available without expanding the navigator.
    final activeSection = app.node(app.activeSectionId ?? '');
    return Container(
      width: 44,
      color: context.surfaces.chrome2,
      child: Column(
        children: [
          const SizedBox(height: 6),
          IconButton(
            icon: const Icon(Icons.keyboard_double_arrow_right, size: 18),
            tooltip: 'Expand the navigator  (Ctrl+\\)',
            visualDensity: VisualDensity.compact,
            onPressed: app.toggleNavCollapsed,
          ),
          Tooltip(
            message: current.title,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showNotebookManager(context, app),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  current.title.isEmpty
                      ? '?'
                      : current.title.characters.first.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary),
                ),
              ),
            ),
          ),
          const Divider(height: 10, indent: 10, endIndent: 10),
          // Page icons complement the section tabs. In the two-column layout,
          // section initials remain scannable even without section colours.
          Expanded(
            child: app.sectionTabsAbovePage
                ? Column(children: [
                    Expanded(
                      child: activeSection == null
                          ? const SizedBox.shrink()
                          : _PageList(
                              key: ValueKey(activeSection.id),
                              app: app,
                              section: activeSection,
                              compact: true),
                    ),
                    IconButton(
                      tooltip: tr(context, 'New page'),
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: activeSection == null
                          ? null
                          : () => app.addPage(sectionId: activeSection.id),
                    ),
                  ])
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      for (final s in sections)
                        NavigatorDragEntry(
                            app: app,
                            node: s,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Center(
                                child: Tooltip(
                                  triggerMode: TooltipTriggerMode.manual,
                                  message: s.title,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () {
                                      app.toggleNavCollapsed();
                                      app.activateSection(s.id);
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _sectionColor(s.color, dark)
                                            .withValues(alpha: .18),
                                        borderRadius: BorderRadius.circular(6),
                                        border: app.activeSectionId == s.id
                                            ? Border.all(color: scheme.primary)
                                            : null,
                                      ),
                                      child: Text(
                                        s.title.isEmpty
                                            ? '·'
                                            : s.title.characters.first
                                                .toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: dark
                                                ? OnoteColors.moon100
                                                : OnoteColors.graphite700),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )),
                      IconButton(
                        tooltip: tr(context, 'New page'),
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: app.activeSectionId == null
                            ? null
                            : () =>
                                app.addPage(sectionId: app.activeSectionId!),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shared drag/drop and context-menu behavior for rail icons and section tabs.
/// Mouse dragging stays immediate; holding a touch opens the existing node menu.
class NavigatorDragEntry extends StatefulWidget {
  const NavigatorDragEntry(
      {super.key,
      required this.app,
      required this.node,
      required this.child,
      this.horizontal = false,
      this.draggable = true});
  final AppState app;
  final TreeNode node;
  final Widget child;
  final bool horizontal;
  final bool draggable;
  @override
  State<NavigatorDragEntry> createState() => _NavigatorDragEntryState();
}

class _NavigatorDragEntryState extends State<NavigatorDragEntry> {
  bool after = false;
  bool accepts(String id) {
    final moving = widget.app.node(id);
    return id != widget.node.id &&
        moving != null &&
        (moving.kind == widget.node.kind ||
            moving.kind == NodeKind.page &&
                widget.node.kind == NodeKind.section);
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
        onWillAcceptWithDetails: (d) => accepts(d.data),
        onMove: (d) {
          final box = context.findRenderObject() as RenderBox;
          final point = box.globalToLocal(d.offset);
          final next = widget.horizontal
              ? point.dx > box.size.width / 2
              : point.dy > box.size.height / 2;
          if (next != after) setState(() => after = next);
        },
        onAcceptWithDetails: (d) {
          if (widget.app.node(d.data)?.kind == NodeKind.page &&
              widget.node.kind == NodeKind.section) {
            widget.app.movePageToSection(d.data, widget.node.id);
          } else {
            widget.app.reorderNode(d.data, widget.node.id, after: after);
          }
        },
        builder: (context, candidates, rejected) {
          final color = candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primary;
          final line = BorderSide(color: color, width: 2);
          final entry = NavigatorHoldMenu(
            onHold: (position) => showNodeMenu(context, widget.app, widget.node,
                canIndent: widget.node.kind == NodeKind.page,
                position: position),
            child: GestureDetector(
              onSecondaryTapUp: (d) => showNodeMenu(
                  context, widget.app, widget.node,
                  canIndent: widget.node.kind == NodeKind.page,
                  position: d.globalPosition),
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      border: widget.horizontal
                          ? Border(
                              left: after ? BorderSide.none : line,
                              right: after ? line : BorderSide.none)
                          : Border(
                              top: after ? BorderSide.none : line,
                              bottom: after ? line : BorderSide.none)),
                  child: widget.child),
            ),
          );
          return Draggable<String>(
            data: widget.node.id,
            maxSimultaneousDrags: widget.draggable ? 1 : 0,
            feedback: dragChip(
                context,
                widget.node.title,
                widget.node.kind == NodeKind.page
                    ? Icons.description_outlined
                    : Icons.folder_outlined),
            childWhenDragging: Opacity(opacity: .4, child: widget.child),
            child: entry,
          );
        },
      );
}

/// The notebook bar: shows the current notebook and opens the notebook manager.
///
/// **One surface, not two.** This used to be a dropdown for switching plus a
/// manager panel for everything else, which read as two different menus for one
/// job. The manager now does both — its rows switch notebooks *and* carry the
/// per-notebook actions — so there is a single place notebooks are dealt with,
/// and switching still takes the same two clicks it did through the dropdown.
class _NotebookHeader extends StatelessWidget {
  const _NotebookHeader({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = app.notebooks.firstWhere((n) => n.id == app.notebookId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 4),
      child: Tooltip(
        message: 'Notebooks — switch, rename, backup, import',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showNotebookManager(context, app),
          onSecondaryTapUp: (_) => showNotebookManager(context, app),
          onLongPress: () => showNotebookManager(context, app),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: LayoutBuilder(
                builder: (context, constraints) => Row(
                      children: [
                        Icon(Icons.menu_book_outlined,
                            size: 18, color: scheme.primary),
                        if (constraints.maxWidth >= 130) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(current.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ] else ...[
                          const Spacer(),
                        ],
                        if (constraints.maxWidth >= 180)
                          const Icon(Icons.unfold_more, size: 16),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          tooltip: 'Recycle bin',
                          style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => showRecycleBin(context, app),
                          constraints: const BoxConstraints.tightFor(
                              width: 32, height: 36),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.keyboard_double_arrow_left,
                              size: 16),
                          tooltip: 'Collapse the navigator  (Ctrl+)',
                          style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          visualDensity: VisualDensity.compact,
                          onPressed: app.toggleNavCollapsed,
                          constraints: const BoxConstraints.tightFor(
                              width: 32, height: 36),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    )),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatefulWidget {
  const _SectionHeader({
    required this.app,
    required this.section,
    required this.dark,
    required this.active,
    required this.onRenamingChanged,
  });
  final AppState app;
  final TreeNode section;
  final bool dark;
  final bool active;
  final ValueChanged<bool> onRenamingChanged;

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  bool _renaming = false;

  final _taps = SidebarDoubleTapGate();

  /// This row's place in the keyboard, handed to its `InkWell` so there is one
  /// focus node rather than two — see [_nodeDeleteKey].
  late final FocusNode _rowFocus = FocusNode(
      debugLabel: 'nav-section',
      onKeyEvent: (n, e) => _nodeDeleteKey(context, app, section, n, e));

  AppState get app => widget.app;
  TreeNode get section => widget.section;
  bool get dark => widget.dark;

  @override
  void dispose() {
    _rowFocus.dispose();
    super.dispose();
  }

  void _setRenaming(bool value) {
    setState(() => _renaming = value);
    widget.onRenamingChanged(value);
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
        onWillAcceptWithDetails: (d) => app.node(d.data)?.kind == NodeKind.page,
        onAcceptWithDetails: (d) => app.movePageToSection(d.data, section.id),
        builder: (context, candidates, rejected) =>
            _header(context, pageTarget: candidates.isNotEmpty),
      );
  Widget _header(BuildContext context, {bool pageTarget = false}) {
    final color = _sectionColor(section.color, dark);
    final scheme = Theme.of(context).colorScheme;
    final active = widget.active;
    final emphasised = pageTarget || active;
    // Plain 12px rows, not tracked small-caps: a narrow sections column has
    // to fit real course names, and the caps identity now lives on the pages
    // pane's header where there is room for it.
    final labelStyle = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        fontStyle: pageTarget ? FontStyle.italic : FontStyle.normal,
        color: emphasised
            ? scheme.primary
            : dark
                ? OnoteColors.moon100
                : OnoteColors.graphite700);
    return InkWell(
      focusNode: _rowFocus,
      onFocusChange: (has) {
        if (has) _keyboardEnteredRow(app);
      },
      // No onDoubleTap — it deferred every click (see SidebarDoubleTapGate).
      onTap: _renaming
          ? null
          : () {
              if (_taps.tap()) {
                _setRenaming(true);
                return;
              }
              // The click is what aims the keyboard at this row; an InkWell
              // does not take focus on tap of its own accord.
              _rowFocus.requestFocus();
              app.activateSection(section.id);
            },
      onSecondaryTapUp: (d) => showNodeMenu(context, app, section,
          canIndent: false, position: d.globalPosition),
      child: Container(
        decoration: pageTarget
            ? BoxDecoration(color: scheme.primary.withValues(alpha: .06))
            : active
                ? BoxDecoration(
                    color: scheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(6))
                : null,
        // Paint the drop frame over the row. A border in [decoration] takes
        // layout space and made the “move here” row jump under the pointer.
        foregroundDecoration: pageTarget
            ? BoxDecoration(
                border: Border.all(color: scheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(6))
            : null,
        padding: const EdgeInsets.fromLTRB(6, 7, 6, 7),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Container(
              width: 3.5,
              height: 16,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _renaming
                  ? NodeInlineRename(
                      initial: section.title,
                      style: labelStyle.copyWith(letterSpacing: 0),
                      onSubmit: (v) {
                        app.renameNode(section.id, v);
                        if (mounted) _setRenaming(false);
                      },
                      onCancel: () {
                        if (mounted) _setRenaming(false);
                      },
                    )
                  : Text(
                      pageTarget ? 'move here' : section.title,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How long until a trashed item (deleted at [deletedAt]) is auto-purged.
String _retentionSubtitle(int deletedAt, int retentionDays) {
  final expireMs = deletedAt + Duration(days: retentionDays).inMilliseconds;
  final remaining = expireMs - DateTime.now().millisecondsSinceEpoch;
  final days = (remaining / const Duration(days: 1).inMilliseconds).ceil();
  if (days <= 0) return 'Deletes soon';
  return 'Deletes in $days day${days == 1 ? '' : 's'}';
}

/// Recycle bin (ORG-7): restore or permanently delete soft-deleted notebooks
/// and, within the current notebook, sections/pages/groups. Items are
/// auto-purged after the retention window (swept on open).
Future<void> showRecycleBin(BuildContext context, AppState app) async {
  await app.purgeExpiredTrash();
  if (!context.mounted) return;
  final retention = app.recycleRetentionDays;
  await showOnoteDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final notebooks = app.trashedNotebooks;
        final items = app.deletedNodes();
        return AlertDialog(
          title: const AppText('Recycle bin'),
          content: SizedBox(
            width: 400,
            child: (notebooks.isEmpty && items.isEmpty)
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: AppText('Nothing deleted.'))
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                          child: Text(
                              'Items here are permanently deleted after $retention days.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.surfaces.textSecondary)),
                        ),
                        if (notebooks.isNotEmpty) ...[
                          const _BinSectionLabel('Notebooks'),
                          for (final nb in notebooks)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.menu_book_outlined,
                                  size: 16),
                              title: Text(nb.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(
                                  _retentionSubtitle(
                                      nb.deletedAt ?? 0, retention),
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await app.restoreNotebook(nb.id);
                                        setLocal(() {});
                                      } catch (error) {
                                        if (!ctx.mounted) return;
                                        await _showRecycleBinError(ctx, error);
                                      }
                                    },
                                    child: const AppText('Restore'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever,
                                        size: 16, color: OnoteColors.danger),
                                    tooltip: 'Delete permanently',
                                    onPressed: () async {
                                      final ok =
                                          await _confirmPurgeNotebook(ctx, nb);
                                      if (ok) {
                                        await app.purgeNotebook(nb.id);
                                        setLocal(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (items.isNotEmpty) const _BinSectionLabel('Items'),
                        ],
                        for (final it in items)
                          ListTile(
                            dense: true,
                            leading: Icon(
                                it.kind == 'page'
                                    ? Icons.description_outlined
                                    : it.kind == 'section'
                                        ? Icons.folder_outlined
                                        : Icons.topic_outlined,
                                size: 16),
                            title: Text(it.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                _retentionSubtitle(it.deletedAt, retention),
                                style: const TextStyle(fontSize: 11)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    await app.restoreDeleted(it.id);
                                    setLocal(() {});
                                  },
                                  child: const AppText('Restore'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever,
                                      size: 16, color: OnoteColors.danger),
                                  tooltip: 'Delete permanently',
                                  onPressed: () async {
                                    final ok = await _confirmPurgeDeleted(
                                      ctx,
                                      it.title,
                                    );
                                    if (ok) {
                                      app.purgeDeleted(it.id);
                                      setLocal(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const AppText('Close')),
          ],
        );
      },
    ),
  );
}

Future<bool> _confirmPurgeNotebook(BuildContext context, NotebookRef nb) async {
  final ok = await showOnoteDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const AppText('Delete permanently?'),
      content: Text(
          '“${nb.title}” and all its pages will be removed for good. This can\'t '
          'be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const AppText('Delete forever'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<void> _showRecycleBinError(BuildContext context, Object error) =>
    showOnoteDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('Could not restore notebook'),
        content: Text(error.toString().replaceFirst('Bad state: ', '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('Close'),
          ),
        ],
      ),
    );

Future<bool> _confirmPurgeDeleted(BuildContext context, String title) async {
  final ok = await showOnoteDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const AppText('Delete permanently?'),
      content:
          Text('“$title” will be removed for good. This can\'t be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const AppText('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const AppText('Delete forever'),
        ),
      ],
    ),
  );
  return ok == true;
}

class _BinSectionLabel extends StatelessWidget {
  const _BinSectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: context.surfaces.textSecondary)),
      );
}

/// Inline rename field (§7a: rename is a direct-manipulation action, no
/// dialog). Autofocuses, selects all, commits on Enter or blur, cancels on
/// Escape or an empty/unchanged value.
class NodeInlineRename extends StatefulWidget {
  const NodeInlineRename({
    super.key,
    required this.initial,
    required this.style,
    required this.onSubmit,
    required this.onCancel,
  });
  final String initial;
  final TextStyle style;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<NodeInlineRename> createState() => _NodeInlineRenameState();
}

class _NodeInlineRenameState extends State<NodeInlineRename> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);
  late final FocusNode _focus = FocusNode(onKeyEvent: (_, e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    });
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _commit() {
    if (_done) return;
    _done = true;
    final v = _c.text.trim();
    if (v.isNotEmpty && v != widget.initial) {
      widget.onSubmit(v);
    } else {
      widget.onCancel();
    }
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _c,
      focusNode: _focus,
      style: widget.style,
      cursorColor: scheme.primary,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}

/// A floating label used as drag feedback in the navigator.
Widget dragChip(BuildContext context, String label, IconData icon) {
  return Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        AppText(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    ),
  );
}

class _PageTile extends StatefulWidget {
  const _PageTile({
    required this.app,
    required this.page,
    this.hasChildren = false,
    this.collapsed = false,
    required this.onRenamingChanged,
    this.previewLevel,
    this.nestTarget = false,
  });
  final AppState app;
  final TreeNode page;
  final bool hasChildren;
  final bool collapsed;
  final ValueChanged<bool> onRenamingChanged;
  final int? previewLevel;
  final bool nestTarget;

  @override
  State<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<_PageTile> {
  bool _renaming = false;
  final _taps = SidebarDoubleTapGate();

  /// This row's place in the keyboard, handed to its `InkWell` so there is one
  /// focus node rather than two — see [_nodeDeleteKey].
  late final FocusNode _rowFocus = FocusNode(
      debugLabel: 'nav-page',
      onKeyEvent: (n, e) => _nodeDeleteKey(context, app, page, n, e));

  AppState get app => widget.app;
  TreeNode get page => widget.page;

  @override
  void dispose() {
    _rowFocus.dispose();
    super.dispose();
  }

  void _setRenaming(bool value) {
    setState(() => _renaming = value);
    widget.onRenamingChanged(value);
  }

  @override
  Widget build(BuildContext context) => _tile(context);
  Widget _tile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = app.pageId == page.id;
    final level = widget.previewLevel ?? page.level;
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      color: selected ? scheme.primary : null,
    );
    return Material(
      color:
          selected ? scheme.primary.withValues(alpha: .10) : Colors.transparent,
      child: InkWell(
        focusNode: _rowFocus,
        onFocusChange: (has) {
          if (has) _keyboardEnteredRow(app);
        },
        // No onDoubleTap — it deferred every click (see SidebarDoubleTapGate).
        onTap: _renaming
            ? null
            : () {
                if (_taps.tap()) {
                  _setRenaming(true);
                  return;
                }
                // The click is what aims the keyboard at this row; an InkWell
                // does not take focus on tap of its own accord.
                _rowFocus.requestFocus();
                app.selectPage(page.id);
              },
        onSecondaryTapUp: (d) => showNodeMenu(context, app, page,
            canIndent: true, position: d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          foregroundDecoration: widget.nestTarget
              ? BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(6))
              : null,
          padding: EdgeInsets.only(
              left: 8.0 + level * 15, right: 4, top: 6, bottom: 6),
          child: Row(
            children: [
              // Collapse chevron (only when the page has subpages)
              SizedBox(
                width: 16,
                child: widget.hasChildren
                    ? InkWell(
                        onTap: () => app.togglePageCollapsed(page.id),
                        child: Icon(
                            widget.collapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            size: 16,
                            color: context.surfaces.textSecondary),
                      )
                    : null,
              ),
              Icon(
                  level == 0
                      ? Icons.description_outlined
                      : Icons.subdirectory_arrow_right,
                  size: 16,
                  color: selected
                      ? scheme.primary
                      : context.surfaces.textSecondary),
              const SizedBox(width: 7),
              Expanded(
                child: _renaming
                    ? NodeInlineRename(
                        initial: page.title,
                        style: labelStyle,
                        onSubmit: (v) {
                          app.renameNode(page.id, v);
                          if (mounted) _setRenaming(false);
                        },
                        onCancel: () {
                          if (mounted) _setRenaming(false);
                        },
                      )
                    : Text(
                        page.title,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(
      {required this.icon,
      required this.text,
      required this.actionLabel,
      required this.onAction});
  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: OnoteIcon.xl, color: context.surfaces.textSecondary),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: context.surfaces.textSecondary)),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

// ── Delete from the keyboard ──────────────────────────────────────────────
//
// Eric: "Pressing 'Del' when clicking on a page or group doesnt delete it -
// only way to delete is right click and press delete." Kept beside
// [showNodeMenu] on purpose: these are two routes to one soft delete, and
// they drift apart the moment they stop being read together.

/// The keyboard's answer to right-click ▸ Delete, for the row that holds focus.
///
/// **Why focus, and not a `selectedNodeId` on [AppState].** The navigator had
/// no notion of "the row you are on": a page row highlights off `app.pageId`
/// and section and group rows carried no selection state at all. A field on
/// [AppState] would be a second source of truth to invalidate on every delete,
/// notebook switch and tree reload — and it still would not say whether the
/// KEYBOARD is aimed here rather than at the canvas. Flutter's focus answers
/// both questions, every row is already an `InkWell` carrying a focus node, and
/// hanging the handler off that node is the shape [NodeInlineRename] already uses.
///
/// **No confirmation**, because right-click ▸ Delete does not confirm either
/// and two routes to the same recoverable action must not disagree about how
/// dangerous it is — `AppState.deleteNode` soft-deletes into the 30-day recycle
/// bin. The snackbar is the acknowledgement instead: a whole page leaving the
/// tree on one keystroke with nothing said is the failure to avoid.
KeyEventResult _nodeDeleteKey(BuildContext context, AppState app, TreeNode node,
    FocusNode row, KeyEvent e) {
  if (e is! KeyDownEvent) return KeyEventResult.ignored;
  // Both keys, because the key people reach for depends on the keyboard in
  // front of them: Del on Windows and Linux, Backspace on a Mac laptop, which
  // has no Del at all. A `KeyRepeatEvent` is not a `KeyDownEvent`, so holding
  // the key down does not walk the list deleting everything under it.
  if (e.logicalKey != LogicalKeyboardKey.delete &&
      e.logicalKey != LogicalKeyboardKey.backspace) {
    return KeyEventResult.ignored;
  }
  if (_textFieldHasKeyboard()) return KeyEventResult.ignored;
  // A passcode is a standing "not by accident" mark on this node. The menu
  // still offers Delete on a locked one — that is aimed, you opened a menu and
  // chose the red row — but a bare Del is precisely the slip a passcode exists
  // to catch, on a row that may have been clicked only to look at it. Both
  // halves matter: [AppState.protectionFor] is a passcode ON this node, and
  // [AppState.isLocked] catches a page sitting inside a section that is still
  // locked.
  if (app.protectionFor(node.id) != null || app.isLocked(node.id)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('“${node.title}” is locked. Remove its passcode before '
            'deleting it.')));
    return KeyEventResult.handled;
  }
  _deleteNodeFromKey(context, app, node, row);
  return KeyEventResult.handled;
}

Future<void> _deleteNodeFromKey(
    BuildContext context, AppState app, TreeNode node, FocusNode row) async {
  final messenger = ScaffoldMessenger.of(context);
  final title = node.title;
  // Hand the keyboard on BEFORE this row is destroyed, and before the await:
  // once the tile leaves the tree its focus node is detached and focus falls
  // back to the root scope, leaving the navigator keyboard-dead until the next
  // mouse click. Downwards, because that is where a file explorer leaves you
  // and it puts the row that slid up into this one's place under the keyboard.
  row.nextFocus();
  await app.deleteNode(node.id);
  // Ask the TREE whether it went, rather than assuming the keypress did
  // something. `deleteNode` returns without doing anything on a read-only
  // notebook (see [AppState.notebookIsReadOnly]), and "Deleted X" while X is
  // still sitting in the list is worse than saying nothing at all.
  if (app.node(node.id) != null) return;
  messenger.showSnackBar(SnackBar(
      content: Text('Deleted “$title” — restore it from the recycle bin.')));
}

/// Is a TEXT FIELD holding the keyboard?
///
/// The gate that keeps Del and Backspace out of the inline rename. A row sits
/// ABOVE its own rename field in the focus chain and Flutter walks that chain
/// upwards from the focused node — so a row's handler runs BEFORE the text
/// editing shortcuts, which live at the `WidgetsApp` root above the whole
/// navigator. Without this, backspacing a typo out of a page's new name deleted
/// the page.
///
/// The same rule the shell stands its own bare keys down on
/// (`AppShell._editableFocused`), minus that one's `MathField` arm: no equation
/// field is ever built inside the navigator.
bool _textFieldHasKeyboard() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  var found = false;
  ctx.visitAncestorElements((el) {
    if (el.widget is EditableText) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// The keyboard has just landed on a navigator row.
///
/// Clearing the page's block selection is what stops ONE Del deleting TWO
/// things. The shell's global Delete handler (`app_shell.dart`) runs before
/// focus dispatch and cannot see that the navigator now owns the key, so with a
/// block still selected — click a block, click the header of the section you
/// are already in, press Del — the block AND the section both went. Clicking a
/// PAGE row never showed it, because `selectPage` clears the selection on the
/// way past; a section or group row does not go near it.
void _keyboardEnteredRow(AppState app) {
  if (app.selectedIds.isNotEmpty) app.select(null);
}

/// Pop-out node menu (§7a.1): a compact menu anchored at the pointer, focused
/// on actions that can *only* be done here. Rename lives inline (double-click
/// the title) so it's not in this list; reorder + structural moves are.
Future<void> showNodeMenu(BuildContext context, AppState app, TreeNode node,
    {required bool canIndent, required Offset position}) async {
  final isPage = node.kind == NodeKind.page;
  final isSection = node.kind == NodeKind.section;
  final isGroup = node.kind == NodeKind.sectionGroup;
  final action = await showNodeContextMenu(context, position, (select) {
    Widget item(String value, IconData icon, String label,
            {bool danger = false}) =>
        MenuItemButton(
          closeOnActivate: false,
          leadingIcon:
              Icon(icon, size: 16, color: danger ? OnoteColors.danger : null),
          onPressed: () => select(value),
          child: AppText(label,
              style: TextStyle(
                  fontSize: 13, color: danger ? OnoteColors.danger : null)),
        );
    return [
      item('rename', Icons.edit_outlined, 'Rename'),

      if (isSection || isGroup) ...[
        const Divider(height: 6),
        // The colour chip is the obvious thing to right-click, so this is
        // where people look for it — a row of swatches rather than a submenu,
        // because picking a colour is one glance and one click.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: _SectionColorRow(app: app, section: node),
        ),
        const Divider(height: 6),
      ],
      if (isSection)
        item('togroup', Icons.drive_file_move_outline, 'Move to group…'),
      // A page can always indent (make subpage) or outdent (promote) at some
      // level in 0..2, so the separator is shown whenever those items are.
      if (canIndent) const Divider(height: 6),
      if (canIndent && node.level < 2)
        item('indent', Icons.subdirectory_arrow_right, 'Make subpage'),
      if (canIndent && node.level > 0)
        item('outdent', Icons.arrow_back, 'Move back out'),
      if (isPage) ...[
        const Divider(height: 6),
        SubmenuButton(
          leadingIcon: const Icon(Icons.ios_share_outlined, size: 16),
          menuStyle: const MenuStyle(
              maximumSize: WidgetStatePropertyAll(Size(380, double.infinity))),
          menuChildren:
              pageExportMenuItems((format) => select('export:${format.name}')),
          child: const AppText('Export'),
        ),
        item('copylink', Icons.link, 'Copy link to page'),
      ],
      const Divider(height: 6),
      // Available on every kind, because the ask was "a page ... a section, or
      // a section group" and protection is resolved by walking up from a page
      // to whichever of those carries it.
      if (app.protectionFor(node.id) != null)
        item('unprotect', Icons.lock_open_outlined, 'Remove passcode…')
      else
        item('protect', Icons.lock_outline, 'Lock with a passcode…'),
      const Divider(height: 6),
      item('delete', Icons.delete_outline, 'Delete', danger: true),
    ];
  });
  if (!context.mounted) return;
  if (action != null && action.startsWith('export:')) {
    await exportPageFromMenu(context, app, node.id,
        PageExportFormat.values.byName(action.substring(7)));
    return;
  }
  switch (action) {
    case 'rename':
      final title = await promptForText(context,
          title: 'Rename', okLabel: 'Save', hintText: node.title);
      if (title != null && title.trim().isNotEmpty) {
        app.renameNode(node.id, title.trim());
      }
    case 'protect':
      final set = await askNewPasscode(context, node.title);
      if (set == null) return;
      app.protectNode(node.id, set.passcode, set.policy);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('“${node.title}” is locked. It is hidden inside '
                'Openote, not encrypted in the file.')));
      }
    case 'unprotect':
      final ok = await askToUnlock(
          context, node.title, (pw) => app.unprotectNode(node.id, pw));
      if (ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Passcode removed from “${node.title}”.')));
      }
    case 'copylink':
      // The wiki-link form the editor already resolves. Copying it means
      // cross-referencing is paste, not retype-and-hope.
      await Clipboard.setData(
          ClipboardData(text: '[[${node.title}|${node.id}]]'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: AppText('Link copied — paste it into any page')));
      }
    case 'togroup':
      final groups =
          app.nodes.where((n) => n.kind == NodeKind.sectionGroup).toList();
      final choice = await showOnoteDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const AppText('Move section to…'),
          children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const AppText('(No group — top level)')),
            for (final g in groups)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, g.id),
                  child: Text(g.title)),
          ],
        ),
      );
      if (choice != null) {
        app.moveSectionToGroup(node.id, choice.isEmpty ? null : choice);
      }
    case 'indent':
      app.indentPage(node.id, 1);
    case 'outdent':
      app.indentPage(node.id, -1);
    case 'delete':
      await app.deleteNode(node.id);
  }
}

/// The colour swatches inside a section's context menu.
///
/// The row is not a menu action;
/// each swatch closes the menu on its own. That keeps the picker inline
/// (one glance, one click) instead of behind a submenu, which is what you
/// want from something you reached by right-clicking the colour chip.
class _SectionColorRow extends StatefulWidget {
  const _SectionColorRow({required this.app, required this.section});
  final AppState app;
  final TreeNode section;

  @override
  State<_SectionColorRow> createState() => _SectionColorRowState();
}

class _SectionColorRowState extends State<_SectionColorRow> {
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final current = widget.app.node(widget.section.id)?.color;
    return Row(children: [
      for (final token in AppState.sectionColorTokens)
        Padding(
          padding: const EdgeInsets.only(right: 5),
          child: Tooltip(
            message: token ?? 'Default',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                widget.app.setNodeColor(widget.section.id, token);
                Navigator.of(context).pop();
              },
              child: Container(
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  color: _sectionColor(token, dark),
                  shape: BoxShape.circle,
                  border: token == current
                      ? Border.all(color: scheme.onSurface, width: 2)
                      : null,
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
