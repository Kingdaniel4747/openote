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

/// The notebook manager (style guide §7b) — the one place notebooks are managed.
///
/// **Why a panel and not a pointer menu.** Management used to live in the
/// notebook dropdown: right-clicking a row popped a context menu, which closed
/// the dropdown underneath it. The action worked but the surface you were
/// working in vanished, which read as broken, and deleting three notebooks meant
/// reopening the dropdown three times. Here the list is *stable*: rename in
/// place, delete with an inline confirm, restore from the trash — the list never
/// disappears, and you can do several things in a row. The dropdown keeps only
/// what it is genuinely good at: switching fast.
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

class _NotebookManager extends StatefulWidget {
  const _NotebookManager({required this.app});
  final AppState app;

  @override
  State<_NotebookManager> createState() => _NotebookManagerState();
}

class _NotebookManagerState extends State<_NotebookManager> {
  AppState get app => widget.app;

  String? _busyId;
  final _counts = <String, ({int sections, int pages})>{};
  bool _countsLoading = false;

  @override
  void initState() {
    super.initState();
    app.addListener(_changed);
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
      final result = await app.createWorkspaceBackup(
        location.path,
        onlyNotebookId: only,
      );
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
        final count = await app.restoreWorkspaceBackup(file.path);
        if (mounted) _toast('Imported $count notebooks from the backup.');
      } else if (extension == '.onote') {
        await app.openExistingNotebook(file.path);
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
        final count = await importMarkdownFolder(app,
            sourceDirectory: p.dirname(file.path));
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
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.menu_book_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 9),
          const AppText('Notebooks'),
          if (_busyId != null)
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          const Spacer(),
          Text(
            '${notebooks.length} open',
            style: TextStyle(
              fontSize: 12,
              color: context.surfaces.textSecondary,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      content: SizedBox(
        width: 980,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 680),
          child: ListView(
            children: [
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 18,
                crossAxisSpacing: 18,
                childAspectRatio: .72,
                children: [
                  for (final nb in notebooks)
                    RepaintBoundary(child: _coverCard(nb, scheme)),
                ],
              ),
              // Repeated imports of the same notebook. Shown here rather than
              // behind a button because the whole problem is that nothing ever
              // pointed them out: a real workspace was holding 586 MB, of which
              // ~380 MB was four copies of one OneNote import made while
              // getting the importer working. Each import correctly mints
              // fresh ids, so nothing can merge them automatically — only a
              // person can say they are the same thing, and only if shown.
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
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
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const AppText('New'),
              onPressed: () async {
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
                await Future<void>.delayed(const Duration(milliseconds: 16));
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
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const AppText('Import'),
              onPressed: _busyId == null ? _importFile : null,
            ),
            PopupMenuButton<String>(
              tooltip: 'Create a portable ZIP backup',
              onSelected: _createBackup,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: '__all__',
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Back up all notebooks'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                for (final nb in notebooks)
                  PopupMenuItem(value: nb.id, child: Text(nb.title)),
              ],
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.backup_outlined, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  AppText('Backup', style: TextStyle(color: scheme.primary)),
                ]),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The former inline import chooser was removed in favour of [_importFile].
  ///
  /// **Everything an import needs is captured BEFORE this dialog is popped.**
  /// The obvious spelling — pop, then call `importX(context, app)` — hands the
  /// import the context of a route that no longer exists, so every
  /// `context.mounted` guard inside it is false and the import silently does
  /// nothing at all. That is precisely how the `.onepkg` import stopped
  /// working: the file picker opened, the user chose their notebook, and the
  /// very next line returned.
  ///
  /// A `ScaffoldMessengerState` and the ROOT navigator's context both outlive
  /// this route, so neither can go stale under an import that takes a minute.
  Widget _coverCard(NotebookRef nb, ColorScheme scheme) {
    final current = nb.id == app.notebookId;
    final counts = _counts[nb.id] ?? (sections: 0, pages: 0);
    final cover = _coverColor(app.notebookColor(nb.id), nb.id);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        if (current) return;
        Navigator.pop(context);
        await app.selectNotebook(nb.id);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cover,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: current
                      ? scheme.primary
                      : Colors.black.withValues(alpha: .15),
                  width: current ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .16),
                    blurRadius: 5,
                    offset: const Offset(1, 3),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      children: [
                        Container(
                          width: 11,
                          color: Colors.black.withValues(alpha: .18),
                        ),
                        const Spacer(),
                        Container(
                          width: 7,
                          color: Colors.white.withValues(alpha: .22),
                        ),
                        Container(
                          width: 4,
                          color: Colors.white.withValues(alpha: .52),
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.menu_book_outlined,
                      size: 44,
                      color: Colors.white.withValues(alpha: .9),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 0,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      tooltip: 'Notebook options',
                      popUpAnimationStyle: AnimationStyle.noAnimation,
                      onSelected: (value) async {
                        if (value == 'rename') {
                          final title = await promptForText(
                            context,
                            title: 'Rename notebook',
                            okLabel: 'Save',
                            hintText: nb.title,
                          );
                          if (title != null)
                            await app.renameNotebook(nb.id, title);
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
                          child: Text('Rename'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Move to recycle bin'),
                        ),
                        const PopupMenuDivider(),
                        // A fixed-size Wrap, rather than a scrollable GridView
                        // inside a menu item. A popup menu supplies only tight
                        // height constraints to its child; GridView then has no
                        // viewport to paint into on some Windows layouts. The
                        // Wrap is always a visible 4 × 3 colour matrix.
                        PopupMenuItem(
                          value: '__palette',
                          height: 116,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                            width: 200,
                            height: 96,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final color
                                    in _coverTokens.whereType<String>())
                                  Tooltip(
                                    message: color,
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        app.setNotebookColor(nb.id, color);
                                      },
                                      child: Container(
                                        width: 44,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: _coverColor(color, nb.id),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: scheme.outline,
                                            width: 1.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            nb.title,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: current ? FontWeight.w700 : FontWeight.w600,
              color: current ? scheme.primary : null,
            ),
          ),
          Text(
            '${counts.sections} sections · ${counts.pages} pages',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: context.surfaces.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static const List<String?> _coverTokens = [
    null,
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
    const colors = {
      'Blue': Color(0xFF426BB2),
      'Purple': Color(0xFF7351A6),
      'Green': Color(0xFF3D8B70),
      'Orange': Color(0xFFB56D32),
      'Red': Color(0xFFAD5155),
      'Teal': Color(0xFF2C8888),
      'Pink': Color(0xFFB9507B),
      'Indigo': Color(0xFF3F548F),
      'Brown': Color(0xFF7A5847),
      'Slate': Color(0xFF4C5563),
    };
    if (token != null) return colors[token] ?? colors['Blue']!;
    return colors.values.elementAt(
      id.codeUnits.fold<int>(0, (a, b) => a + b) % colors.length,
    );
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
  // **It says what it is doing while it does it.** A vault of a few hundred
  // notes is seconds of work, and there was nothing on screen for any of it.
  final progress = ValueNotifier<String>('Reading the folder…');
  int? count;
  try {
    count = await importMarkdownFolder(
      app,
      onProgress: (done) => progress.value = 'Imported $done '
          'page${done == 1 ? '' : 's'}…',
    );
  } catch (e) {
    progress.dispose();
    _say(messenger, "That folder couldn't be imported: $e", seconds: 8);
    return;
  }
  progress.dispose();
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
    '(see rust/onote_core/INTEGRATION.md).';

/// One sentence when the parser dropped undecodable ink (~0.02 % of strokes on
/// the reference notebook). The notes LOOK complete when a stroke vanishes,
/// which is exactly why it has to be said out loud.
/// What arrived, in the switcher's own terms (P5).
String _strokeNote() => lastDroppedStrokes == 0
    ? ''
    : ' $lastDroppedStrokes ink stroke'
        '${lastDroppedStrokes == 1 ? '' : 's'} could not be decoded and '
        '${lastDroppedStrokes == 1 ? 'was' : 'were'} left out.';
