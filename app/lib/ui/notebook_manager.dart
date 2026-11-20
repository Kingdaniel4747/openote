import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../l10n/app_strings.dart';
import 'package:path/path.dart' as p;

import '../export/import_job.dart';
import '../export/md_import.dart';
import '../export/onenote_import.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';
import 'transfer_progress.dart';

/// The shared surface for switching, managing and backing up notebooks.
Future<void> showNotebookManager(
  BuildContext context,
  AppState app,
) async {
  // Cleanup runs with workspace housekeeping, never on the dialog-open path.
  if (!context.mounted) return;
  await showOnoteDialog<void>(
    context: context,
    builder: (_) => _NotebookManager(app: app),
  );
}

// Pick the higher-contrast foreground, including for pale notebook colours.
Color _coverInk(Color color) =>
    color.computeLuminance() > .179 ? Colors.black : Colors.white;

class _NotebookBackupDialog extends StatefulWidget {
  const _NotebookBackupDialog(
      {required this.notebooks, required this.colorFor});

  final List<NotebookRef> notebooks;
  final Color Function(NotebookRef) colorFor;

  @override
  State<_NotebookBackupDialog> createState() => _NotebookBackupDialogState();
}

class _NotebookBackupDialogState extends State<_NotebookBackupDialog> {
  final _search = TextEditingController();
  String _selected = '__all__';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _choice(
      {required String id,
      required Widget leading,
      required String title,
      String? subtitle}) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected == id;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: OnoteAlpha.selected)
            : context.surfaces.chrome,
        shape: RoundedRectangleBorder(
          borderRadius: OnoteRadius.lgAll,
          side: BorderSide(
              color: selected ? scheme.primary : context.surfaces.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _selected = id),
          child: Padding(
            padding: const EdgeInsets.all(OnoteSpace.x5),
            child: Row(children: [
              ExcludeSemantics(child: leading),
              const SizedBox(width: OnoteSpace.x5),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: OnoteType.uiStrong),
                    if (subtitle != null)
                      Text(subtitle,
                          style: OnoteType.small
                              .copyWith(color: context.surfaces.textSecondary)),
                  ])),
              const SizedBox(width: OnoteSpace.x5),
              Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: OnoteIcon.lg,
                  color: selected
                      ? scheme.primary
                      : context.surfaces.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = widget.notebooks
        .where((nb) => nb.title.toLowerCase().contains(query))
        .toList();
    final selected =
        widget.notebooks.where((nb) => nb.id == _selected).firstOrNull;
    return AlertDialog(
      title: const AppText('Backup', style: OnoteType.headline),
      content: SizedBox(
        width: 540,
        height: 460,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr(context, 'Search notebooks'),
              prefixIcon: const Icon(Icons.search, size: OnoteIcon.lg),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr(context, 'Clear search'),
                      icon: const Icon(Icons.close, size: OnoteIcon.md),
                      onPressed: () => setState(() => _search.clear()),
                    ),
            ),
          ),
          const SizedBox(height: OnoteSpace.x5),
          Expanded(
              child: ListView.separated(
            itemCount: 3 + (visible.isEmpty ? 1 : visible.length),
            separatorBuilder: (_, __) => const SizedBox(height: OnoteSpace.x4),
            itemBuilder: (_, index) {
              if (index == 0) {
                return AppText(
                    'Choose what to save. You’ll choose the ZIP file location next.',
                    style: OnoteType.ui
                        .copyWith(color: context.surfaces.textSecondary));
              }
              if (index == 1) {
                return _choice(
                  id: '__all__',
                  leading: const Icon(Icons.inventory_2_outlined,
                      size: OnoteIcon.lg),
                  title: tr(context, 'Back up all notebooks'),
                  subtitle:
                      '${widget.notebooks.length} ${tr(context, 'notebooks')}',
                );
              }
              if (index == 2) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: OnoteSpace.x4),
                  child: AppText('Or choose one notebook',
                      style: OnoteType.uiStrong),
                );
              }
              if (visible.isEmpty) {
                return const AppText('No notebooks found.');
              }
              final nb = visible[index - 3];
              final cover = widget.colorFor(nb);
              return _choice(
                  id: nb.id,
                  title: nb.title,
                  leading: Container(
                    width: 32,
                    height: 40,
                    decoration: BoxDecoration(
                        color: cover,
                        borderRadius: OnoteRadius.smAll,
                        border:
                            Border.all(color: context.surfaces.textSecondary)),
                    child: Icon(Icons.menu_book_outlined,
                        size: OnoteIcon.sm, color: _coverInk(cover)),
                  ));
            },
          )),
          const SizedBox(height: OnoteSpace.x5),
          Text(
              '${tr(context, 'Selected')}: ${selected?.title ?? tr(context, 'Back up all notebooks')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: OnoteType.uiStrong),
        ]),
      ),
      actions: [
        TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context),
            child: const AppText('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, _selected),
          icon: const Icon(Icons.save_alt, size: OnoteIcon.md),
          label: const AppText('Choose location…'),
        ),
      ],
    );
  }
}

class _NotebookManager extends StatefulWidget {
  const _NotebookManager({required this.app});
  final AppState app;

  @override
  State<_NotebookManager> createState() => _NotebookManagerState();
}

class _NotebookManagerState extends State<_NotebookManager> {
  AppState get app => widget.app;

  String? _busyId;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _counts = <String, ({int sections, int pages})>{};
  bool _countsLoading = false;

  @override
  void initState() {
    super.initState();
    app.addListener(_changed);
    unawaited(app.refreshNotebooks());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!_countsLoading) _loadCounts();
  }

  Future<void> _loadCounts() async {
    if (_countsLoading) return;
    _countsLoading = true;
    try {
      for (final nb in app.notebooks.toList()) {
        if (!mounted) return;
        if (_counts.containsKey(nb.id)) continue;
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!mounted) return;
        final counts = app.notebookCounts(nb.id);
        setState(() => _counts[nb.id] = counts);
      }
    } finally {
      _countsLoading = false;
    }
  }

  @override
  void dispose() {
    app.removeListener(_changed);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _delete(NotebookRef nb) async {
    setState(() {
      _busyId = nb.id;
    });
    final ok = await app.deleteNotebook(nb.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!ok) {
      _toast("That's your only notebook — create another one first.");
    }
  }

  Future<void> _confirmDeleteCard(NotebookRef nb) async {
    final confirmed = await showOnoteDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('Move to recycle bin?'),
        content: Text('“${nb.title}” can be restored from the recycle bin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const AppText('Move to recycle bin'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _delete(nb);
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _chooseBackup() async {
    final choice = await showOnoteDialog<String>(
      context: context,
      builder: (_) => _NotebookBackupDialog(
        notebooks: app.notebooks.toList(),
        colorFor: (nb) => _coverColor(app.notebookColor(nb.id), nb.id),
      ),
    );
    if (choice != null && mounted) await _createBackup(choice);
  }

  Future<void> _createBackup(String choice) async {
    final only = choice == '__all__' ? null : choice;
    final notebook = only == null
        ? null
        : app.notebooks.where((n) => n.id == only).firstOrNull;
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final location = await getSaveLocation(
      suggestedName: '${notebook?.title ?? 'Openote'} Backup $stamp.zip',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Openote backup', extensions: ['zip']),
      ],
    );
    if (location == null || !mounted) return;
    setState(() => _busyId = only ?? '__all__');
    try {
      final result =
          await runTransfer(context, 'Export backup', (progress) async {
        progress.update(detail: 'Saving backup');
        final result = await app.createWorkspaceBackup(
          location.path,
          onlyNotebookId: only,
          onProgress: (done, total, detail) => progress.update(
              done: done, total: total, detail: detail, unit: 'steps'),
        );
        return result;
      });
      if (mounted) {
        _toast(
          'Backup saved: ${result.notebooks} notebook'
          '${result.notebooks == 1 ? '' : 's'}.',
        );
      }
    } catch (e) {
      if (mounted) _toast('Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// One entry point for files users reasonably call an import. The extension
  /// is enough to select the existing importer; there is no intermediate menu
  /// to make the user classify a backup before opening it.
  Future<void> _importFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Notebook or backup',
          extensions: ['zip', 'onote', 'one', 'onepkg', 'md'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    final extension = p.extension(file.path).toLowerCase();
    setState(() => _busyId = '__import__');
    try {
      if (extension == '.zip') {
        final count =
            await runTransfer(context, 'Import backup', (progress) async {
          progress.update(detail: file.name);
          final count = await app.restoreWorkspaceBackup(file.path);
          progress.update(done: 1);
          return count;
        });
        if (mounted) _toast('Imported $count notebooks from the backup.');
      } else if (extension == '.onote') {
        await runTransfer(context, 'Import notebook', (progress) async {
          progress.update(detail: file.name);
          await app.openExistingNotebook(file.path);
          progress.update(done: 1);
        });
      } else if (extension == '.onepkg') {
        final job = ImportJob.start(app, p.basename(file.name), file.path);
        if (job == null && mounted) _toast('An import is already running.');
      } else if (extension == '.one') {
        final count = await importOneNoteFile(app,
            progressContext: context, source: file);
        if (mounted && count != null) {
          _toast('Imported $count page${count == 1 ? '' : 's'} from OneNote.');
        }
      } else if (extension == '.md') {
        final count =
            await runTransfer(context, 'Import Markdown', (progress) async {
          progress.update(total: 0, unit: 'pages', detail: file.name);
          return importMarkdownFolder(app,
              sourceDirectory: p.dirname(file.path),
              onBatchProgress: (done, total) =>
                  progress.update(done: done, total: total));
        });
        if (mounted && count != null) {
          _toast('Imported $count Markdown page${count == 1 ? '' : 's'}.');
        }
      }
    } catch (e) {
      if (mounted) _toast('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notebooks = app.notebooks;
    final query = _searchController.text.trim().toLowerCase();
    final visibleNotebooks = notebooks
        .where((nb) => nb.title.toLowerCase().contains(query))
        .toList();
    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                  child: AppText('Notebooks', style: OnoteType.headline)),
              if (_busyId != null)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                tooltip: tr(context, 'Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: OnoteIcon.lg),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr(context, 'Search notebooks'),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: tr(context, 'Clear search'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() => _searchController.clear());
                          _searchFocus.requestFocus();
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: OnoteSpace.x5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                query.isEmpty
                    ? '${notebooks.length} ${tr(context, 'notebooks')}'
                    : '${visibleNotebooks.length} / ${notebooks.length} ${tr(context, 'notebooks')}',
                style: OnoteType.small
                    .copyWith(color: context.surfaces.textSecondary),
              ),
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      content: SizedBox(
        width: 980,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 680),
          child: LayoutBuilder(builder: (context, constraints) {
            // Give names room before adding another column; larger system
            // text also gets taller cards rather than clipping the footer.
            final columns = (constraints.maxWidth / 210).floor().clamp(1, 4);
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            return CustomScrollView(
              slivers: [
                if (visibleNotebooks.isEmpty)
                  const SliverToBoxAdapter(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: AppText('No notebooks found.',
                        textAlign: TextAlign.center),
                  )),
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: OnoteSpace.x6),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: OnoteSpace.x6,
                      crossAxisSpacing: OnoteSpace.x6,
                      mainAxisExtent: 208 + 76 * textScale,
                    ),
                    itemCount: visibleNotebooks.length,
                    itemBuilder: (_, index) => RepaintBoundary(
                      child: _coverCard(visibleNotebooks[index], scheme),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      // ONE Row as the single action, because `AlertDialog.actions` is an
      // OverflowBar — a `Spacer` there throws ("applying parent data"), since
      // Spacer needs a Flex parent.
      actions: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add, size: 18),
              label: const AppText('New'),
              onPressed: _busyId != null
                  ? null
                  : () async {
                      // Through the shared prompt, which owns the field's controller in
                      // the dialog's own State. This used to build the field and
                      // dispose its controller in a `finally` right after the await —
                      // 150 ms before the route's exit transition had finished
                      // unmounting the field. That is what crashed the app on Enter;
                      // see [promptForText].
                      final title = await promptForText(
                        context,
                        title: 'New notebook',
                        okLabel: 'Create',
                        hintText: 'Notebook name',
                      );
                      if (title == null || !mounted) return;
                      setState(() => _busyId = '__new__');
                      // Let the pressed state paint before SQLite creates the first
                      // section and page, so a slow folder never reads as a dead tap.
                      await Future<void>.delayed(
                          const Duration(milliseconds: 16));
                      try {
                        await app.createNotebook(title);
                      } catch (e) {
                        if (mounted) _toast('Could not create notebook: $e');
                      } finally {
                        if (mounted) setState(() => _busyId = null);
                      }
                    },
            ),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const AppText('Import'),
              onPressed: _busyId == null ? _importFile : null,
            ),
            Tooltip(
              message: tr(context, 'Create a portable ZIP backup'),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _busyId == null ? _chooseBackup : null,
                icon: const Icon(Icons.backup_outlined, size: OnoteIcon.md),
                label: const AppText('Backup'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _coverCard(NotebookRef nb, ColorScheme scheme) {
    final current = nb.id == app.notebookId;
    final counts = _counts[nb.id] ?? (sections: 0, pages: 0);
    final cover = _coverColor(app.notebookColor(nb.id), nb.id);
    final coverForeground = _coverInk(cover);
    return Semantics(
      selected: current,
      child: Material(
        color: current
            ? scheme.primary.withValues(alpha: OnoteAlpha.selected)
            : context.surfaces.chrome,
        shape: RoundedRectangleBorder(
          borderRadius: OnoteRadius.xlAll,
          side: BorderSide(
              color: current ? scheme.primary : context.surfaces.border,
              width: current ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busyId != null
              ? null
              : () async {
                  Navigator.pop(context);
                  if (current) return;
                  await app.selectNotebook(nb.id);
                },
          child: Padding(
            padding: const EdgeInsets.all(OnoteSpace.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Ink(
                    decoration: BoxDecoration(
                      color: cover,
                      borderRadius: OnoteRadius.lgAll,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: OnoteSpace.x4,
                          top: OnoteSpace.x4,
                          bottom: OnoteSpace.x4,
                          child: Container(
                              width: 2,
                              color: coverForeground.withValues(
                                  alpha: OnoteAlpha.borderOnTint)),
                        ),
                        Positioned(
                          left: OnoteSpace.x8,
                          top: OnoteSpace.x6,
                          child: Icon(
                            Icons.menu_book_outlined,
                            size: OnoteIcon.lg,
                            color: coverForeground,
                          ),
                        ),
                        Positioned(
                          left: OnoteSpace.x8,
                          right: OnoteSpace.x6,
                          bottom: OnoteSpace.x7,
                          child: Tooltip(
                            message: nb.title,
                            child: Text(nb.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: OnoteType.headline
                                    .copyWith(color: coverForeground)),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 0,
                          child: _notebookOptions(nb, scheme, coverForeground),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: OnoteSpace.x4, horizontal: OnoteSpace.x2),
                  child: Row(children: [
                    if (current) ...[
                      Icon(Icons.check_circle,
                          size: OnoteIcon.sm, color: scheme.primary),
                      const SizedBox(width: OnoteSpace.x2),
                    ],
                    Expanded(
                        child: AppText(
                            current ? 'Current notebook' : 'Open notebook',
                            style: OnoteType.uiStrong.copyWith(
                                color: current
                                    ? scheme.primary
                                    : context.surfaces.textPrimary))),
                    if (!current)
                      Icon(Icons.arrow_forward,
                          size: OnoteIcon.sm,
                          color: context.surfaces.textSecondary),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(
                    _counts.containsKey(nb.id)
                        ? '${counts.sections} ${tr(context, counts.sections == 1 ? 'section' : 'sections')} · ${counts.pages} ${tr(context, counts.pages == 1 ? 'page' : 'pages')}'
                        : tr(context, 'Loading…'),
                    style: OnoteType.small
                        .copyWith(color: context.surfaces.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notebookOptions(
      NotebookRef nb, ColorScheme scheme, Color coverForeground) {
    final selectedColor =
        app.notebookColor(nb.id) ?? _automaticCoverToken(nb.id);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: coverForeground),
      tooltip: tr(context, 'Notebook options'),
      enabled: _busyId == null,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      onSelected: (value) async {
        if (value == 'rename') {
          final title = await promptForText(
            context,
            title: 'Rename notebook',
            okLabel: 'Save',
            hintText: nb.title,
          );
          if (title != null) {
            await app.renameNotebook(nb.id, title);
          }
        }
        if (value == 'delete') {
          await _confirmDeleteCard(nb);
        }
        if (value.startsWith('color:')) {
          app.setNotebookColor(nb.id, value.substring(6));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'rename',
          child: AppText('Rename'),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: AppText('Move to recycle bin'),
        ),
        const PopupMenuDivider(),
        // A fixed-size Wrap keeps all sixteen colours visible
        // inside the popup without a nested scroll viewport.
        PopupMenuItem(
          value: '__palette',
          height: 218,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: 202,
            height: 202,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final color in _coverColors.keys)
                  Tooltip(
                    message: color,
                    child: Semantics(
                      button: true,
                      selected: selectedColor == color,
                      child: InkWell(
                        borderRadius: OnoteRadius.mdAll,
                        onTap: () {
                          Navigator.of(context).pop();
                          app.setNotebookColor(nb.id, color);
                        },
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _coverColor(color, nb.id),
                            borderRadius: OnoteRadius.mdAll,
                            border: Border.all(
                              color: selectedColor == color
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: selectedColor == color ? 2 : 1,
                            ),
                          ),
                          child: selectedColor == color
                              ? Icon(Icons.check,
                                  size: OnoteIcon.md,
                                  color: _coverInk(_coverColor(color, nb.id)))
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const Map<String, Color> _coverColors = {
    'Red': Color(0xFFC4424B),
    'Coral': Color(0xFFE57258),
    'Orange': Color(0xFFCF852E),
    'Yellow': Color(0xFFE8C547),
    'Lime': Color(0xFF9ABF46),
    'Green': Color(0xFF3D8B70),
    'Teal': Color(0xFF2C8888),
    'Cyan': Color(0xFF399DBB),
    'Blue': Color(0xFF426BB2),
    'Indigo': Color(0xFF3F548F),
    'Purple': Color(0xFF7351A6),
    'Pink': Color(0xFFD45D99),
    'Brown': Color(0xFF7A5847),
    'Slate': Color(0xFF4C5563),
    'White': Color(0xFFF7F7F2),
    'Black': Color(0xFF20242B),
  };

  // Keep the same automatic colour for notebooks that have no saved choice.
  static const List<String> _automaticCoverTokens = [
    'Blue',
    'Purple',
    'Green',
    'Orange',
    'Red',
    'Teal',
    'Pink',
    'Indigo',
    'Brown',
    'Slate',
  ];

  static Color _coverColor(String? token, String id) {
    return _coverColors[token ?? _automaticCoverToken(id)] ??
        _coverColors['Blue']!;
  }

  static String _automaticCoverToken(String id) {
    final index = id.codeUnits.fold<int>(0, (a, b) => a + b) %
        _automaticCoverTokens.length;
    return _automaticCoverTokens[index];
  }
}
// ── Import entry points ────────────────────────────────────────────────────
// These live here because the notebook manager is the single surface that owns
// notebook-level actions, importing included.

/// Import a `.onepkg` as a new notebook — as a background job.
///
/// This used to be a modal that owned the app for the whole import; the job
/// (see `import_job.dart`) is the same work, chunked, with a floating card
/// for progress and honesty about partial imports at the end. The completion
/// message lives on the card now, so nothing here waits for anything.
/// **Takes a messenger, not a `BuildContext`, on purpose.** The background job
/// needs no context, so there is nothing here that a dead route can stop —
/// which is the structural half of the fix for the import that silently did
/// nothing. `ScaffoldMessengerState` lives above the navigator, so it is still
/// good long after whichever dialog started the import has gone.
Future<void> importOneNotePackageWithFeedback(
  ScaffoldMessengerState messenger,
  AppState app, {
  Future<XFile?> Function()? pickFile,
}) async {
  final file = await (pickFile?.call() ??
      openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'OneNote notebook package',
            extensions: ['onepkg'],
          ),
        ],
      ));
  if (file == null) return;
  try {
    final job = ImportJob.start(app, p.basename(file.name), file.path);
    _say(
      messenger,
      job == null
          ? 'An import is already running — one at a time.'
          : 'Importing in the background — keep working, the card in the '
              "corner will say when it's done.",
    );
  } on OneNoteUnavailable {
    _say(messenger, _coreMissing, seconds: 8);
  } catch (e) {
    _say(messenger, "Couldn't read that file: $e");
  }
}

/// Import a single `.one` section into the current notebook.
///
/// Still modal: a section is small, and its parse now happens in an isolate
/// with the decode work, so the dialog is short-lived. [context] must be one
/// that outlives the caller — the root navigator's, not a dialog's — or the
/// progress dialog silently does not appear. [messenger] carries the result
/// even if that context has gone by the time the import finishes.
Future<void> importOneNoteSectionWithFeedback(
  BuildContext context,
  AppState app, {
  ScaffoldMessengerState? messenger,
}) async {
  final m = messenger ?? ScaffoldMessenger.of(context);
  try {
    final count = await importOneNoteFile(app, progressContext: context);
    if (count == null) return;
    _say(
      m,
      count == 0
          ? "Couldn't read any content from that .one file."
          : 'Imported '
              '${importArrivalNote(count, lastImportedImages, lastImportedStrokes, lastImportedTags)}'
              ' from OneNote.${_strokeNote()}',
    );
  } on OneNoteUnavailable {
    _say(m, _coreMissing, seconds: 8);
  }
}

/// Import a folder of Markdown (Obsidian-style) as a new section.
Future<void> importMarkdownWithFeedback(
  ScaffoldMessengerState messenger,
  AppState app,
) async {
  int? count;
  try {
    count = await runTransfer(messenger.context, 'Import Markdown',
        (progress) async {
      progress.update(total: 0, unit: 'pages', detail: 'Reading the folder…');
      return importMarkdownFolder(app,
          onBatchProgress: (done, total) =>
              progress.update(done: done, total: total));
    });
  } catch (e) {
    _say(messenger, "That folder couldn't be imported: $e", seconds: 8);
    return;
  }
  if (count == null) return;
  _say(
    messenger,
    count == 0
        ? 'No Markdown files found in that folder.'
        : 'Imported $count page${count == 1 ? '' : 's'}.',
  );
}

/// Show a snackbar through a messenger that cannot go stale.
void _say(ScaffoldMessengerState m, String msg, {int seconds = 4}) =>
    m.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: Duration(seconds: seconds),
      ),
    );

const _coreMissing =
    'OneNote import needs the Rust core — build onote_core.dll '
    '(see README.md: Windows starten).';

/// One sentence when the parser dropped undecodable ink (~0.02 % of strokes on
/// the reference notebook). The notes LOOK complete when a stroke vanishes,
/// which is exactly why it has to be said out loud.
/// What arrived, in the switcher's own terms (P5).
String _strokeNote() => lastDroppedStrokes == 0
    ? ''
    : ' $lastDroppedStrokes ink stroke'
        '${lastDroppedStrokes == 1 ? '' : 's'} could not be decoded and '
        '${lastDroppedStrokes == 1 ? 'was' : 'were'} left out.';
