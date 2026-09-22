import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart'; // ThemeMode + widgets
import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart'
    show Formats, SystemClipboard;

import '../canvas/align_guides.dart';
import '../canvas/canvas_controller.dart';
import '../core/engine.dart';
import '../core/ids.dart';
import '../core/onote_ffi.dart';
import '../editor/onote_text_editor.dart';
import '../export/md_common.dart' show plainLine;
import '../export/onenote_import.dart' show oneNoteLineHeight;
import '../math/active_math.dart';
import '../math/evaluate.dart';
import '../math/linear_math.dart';
import '../model/models.dart';
import '../store/database.dart' show NotebookFileProblem, notebookFileProblem;
import '../store/media_store.dart';
import '../ink/ink_codec.dart';
import '../ink/ink_storage.dart';
import '../editor/list_editing.dart';
import '../markdown/md_syntax.dart';
import '../update/app_update.dart';
import '../store/repository.dart';
import '../math/math_editor.dart';
import '../theme/tokens.dart';
import 'page_protection.dart';
import '../model/tags.dart';
import '../spell/spell_checker.dart';
import '../study/flashcards.dart';
import 'planner_state.dart';
import 'study_state.dart';

/// Archive encoding reads every snapshot byte. It must not share the UI
/// isolate with drawing and scrolling just because the resulting ZIP is local.
Future<int> _encodeWorkspaceBackupZip(
    (String source, String destination) job) async {
  final output = File(job.$2);
  if (output.existsSync()) await output.delete();
  final encoder = ZipFileEncoder();
  // PDFs and images are already compressed. Storing them directly is much
  // faster than recompressing a whole school archive.
  encoder.create(output.path, level: ZipFileEncoder.store);
  await encoder.addDirectory(
    Directory(job.$1),
    includeDirName: false,
    level: ZipFileEncoder.store,
  );
  await encoder.close();
  return output.length();
}

enum Tool { select, text, pen, ballpoint, highlighter, eraser, lasso, shape }

class WorkspaceBackupResult {
  const WorkspaceBackupResult({required this.notebooks, required this.bytes});
  final int notebooks;
  final int bytes;
}

/// How the eraser removes ink (INK-6).
enum EraserMode {
  /// Rub points out; surviving runs split into new strokes. The precise mode.
  area,

  /// Any touched stroke is removed whole — OneNote's default, and the fast way
  /// to delete a scribbled-out word.
  stroke;

  String get label => switch (this) {
        EraserMode.area => 'Area',
        EraserMode.stroke => 'Whole stroke',
      };
}

/// Whether a finger draws when an ink tool is selected (INK-1 / INK-4).
enum TouchDrawing {
  /// Draw with touch, unless a stylus is in use — then touch pans so a resting
  /// palm can't mark the page. The default: it gives pen users OneNote's palm
  /// rejection while leaving ink reachable on a touch-only tablet.
  auto,

  /// Always draw with touch, even with a stylus present.
  always,

  /// Never draw with touch; fingers only pan and pinch. OneNote's strict
  /// behaviour, and what Openote used to do unconditionally.
  never;

  String get label => switch (this) {
        TouchDrawing.auto => 'Auto (pen takes over)',
        TouchDrawing.always => 'Always',
        TouchDrawing.never => 'Never',
      };
}

/// The panels that can occupy the right-hand slot (style guide §7c).
///
/// An enum rather than five booleans, so "which panel is open" has exactly one
/// answer and cannot be five contradictory ones.
enum SidePanelKind {
  study('Study'),
  planner('Planner'),
  outline('Outline'),
  links('Links');

  const SidePanelKind(this.label);

  /// What the toggle's tooltip and the panel's header both say, so they cannot
  /// drift apart.
  final String label;
}

/// One tagged line, as the rollup and the planner both need it.
///
/// A typedef over a record rather than a class: it carries no behaviour, and
/// three call sites had already written the field list out by hand — which is
/// how [blockId] came to be missing from it for as long as nothing needed to
/// write back to the tag. Naming it means adding a field is one edit.
typedef TaggedLine = ({
  String pageId,
  String pageTitle,
  String blockId,
  NoteTag tag,
  String text,
});

/// What came of being handed a notebook file from outside the app — the
/// command line, or a double-click in the file manager.
enum OpenNotebookOutcome {
  /// It is on screen now.
  opened,

  /// It was already the notebook on screen. Nothing to do but come to the
  /// front.
  alreadyOpen,

  /// It came from outside the workspace, so Openote took a copy — and the
  /// user has to be told, because their edits now go to the copy.
  copiedIn,

  /// Nothing at that path.
  notFound,

  /// Something at that path, but not one of our notebooks.
  notANotebook,

  /// It should have worked and didn't. [OpenNotebookResult.details] carries
  /// the technical reason.
  failed,
}

/// The answer to "open this notebook", in the words the app will actually use.
///
/// Two fields on purpose. [message] is the whole story for the person reading
/// it and contains no path, no exception and no jargon; [details] is the path
/// and the raw error, which the UI puts behind an Advanced fold. A stack trace
/// on screen is the failure mode this type exists to prevent.
class OpenNotebookResult {
  const OpenNotebookResult(this.outcome, this.message, {this.details});

  final OpenNotebookOutcome outcome;

  /// One or two plain sentences. Safe to show to anybody.
  final String message;

  /// The path, and the exception when there was one. Never shown unless asked
  /// for.
  final String? details;

  /// True when the notebook the user named is now the open one.
  bool get ok =>
      outcome == OpenNotebookOutcome.opened ||
      outcome == OpenNotebookOutcome.alreadyOpen ||
      outcome == OpenNotebookOutcome.copiedIn;
}

/// Something Openote could not write down, in the words it will actually use.
///
/// The same three-part split as [OpenNotebookResult], for the same reason: a
/// student reading `FileSystemException: ... errno = 13` learns nothing they
/// can act on. [short] is the status-bar chip, [message] says what happened
/// and what to do about it, and [details] is the raw error — behind an
/// Advanced fold, never on the bar.
///
/// [toString] deliberately returns [message], so that any surface which
/// interpolates a problem into a string still cannot leak an exception.
class SaveProblem {
  const SaveProblem({required this.short, required this.message, this.details});

  /// A few words for the status bar. No path, no exception.
  final String short;

  /// One to three plain sentences: what happened, what it costs, what to do.
  final String message;

  /// The exception, for the Advanced fold and for a bug report.
  final String? details;

  @override
  String toString() => message;
}

/// App-wide state. Deliberately simple (ChangeNotifier) for the MVP; the
/// domain layer beneath it is what carries forward.
class AppState extends ChangeNotifier
    implements StudyDocument, PlannerDocument {
  AppState(this._repo, {DocumentEngine? documentEngine})
      : engine = documentEngine ?? _selectEngine(_repo) {
    // Forwarded, not replaced. Every surface listens to `AppState`, so the
    // extraction must not change who wakes up when a card is graded — the
    // point of E3 is to give state an owner, not to renegotiate rebuilds in
    // the same pass. Narrowing a listener to `app.study` is now possible and
    // is a separate, checkable change.
    study.addListener(notifyListeners);
  }

  final Repository _repo;
  final DocumentEngine engine;

  // Split editors own their selection, undo stack and camera, but share one
  // repository.
  AppState? _editorOwner;
  final List<AppState> _editors = [];
  VoidCallback? activateEditor;
  VoidCallback? toggleSplitView;
  bool splitViewEnabled = false;

  Future<AppState> createSplitEditor() async {
    final owner = _editorOwner ?? this;
    await owner.flushSave();
    final editor = AppState(_repo)
      .._editorOwner = owner
      ..spellCheckEnabled = spellCheckEnabled
      ..tool = tool
      ..penColor = penColor
      ..highlighterColor = highlighterColor
      ..penCustomColor = penCustomColor
      ..highlighterCustomColor = highlighterCustomColor
      ..penSize = penSize;
    editor.penToolbarColors.addAll(penToolbarColors);
    editor.highlighterToolbarColors.addAll(highlighterToolbarColors);
    editor.hiddenPenPresets.addAll(hiddenPenPresets);
    editor.hiddenHighlighterPresets.addAll(hiddenHighlighterPresets);
    owner._editors.add(editor);
    if (notebookId != null) await editor.selectNotebook(notebookId!);
    return editor;
  }

  AppState? _editorDisplaying(String? nb, String? page) {
    if (nb == null || page == null) return null;
    final owner = _editorOwner ?? this;
    return [owner, ...owner._editors]
        .where((editor) =>
            editor != this && editor.notebookId == nb && editor.pageId == page)
        .firstOrNull;
  }

  /// Use the Rust core when its native library is linked, else the pure-Dart
  /// engine. Chosen once at construction — the app depends only on the seam.
  static DocumentEngine _selectEngine(Repository repo) {
    final core = OnoteCore.instance;
    return core != null ? RustEngine(repo, core) : MirrorEngine(repo);
  }

  // ── Storage facade ───────────────────────────────────────────────────
  //
  // `_repo` is private, and these are the only ways into it from outside this
  // class. That is not tidiness. ADR-0006 puts an append-only operation log
  // underneath persistence, and a log is only correct if it observes *every*
  // mutation — the failure mode of a second write path is not a crash but a
  // log that is quietly incomplete, which surfaces much later as a device that
  // won't converge. One funnel now is what makes "rebuild the container from
  // the log and compare" a usable check later.
  //
  // Widgets previously reached `app.repo` directly for blob reads inside
  // `build()`, and both importers wrote through it and then hand-patched
  // `app.nodes` — so any invariant on `nodes` was silently bypassed by import.

  /// Bytes of a blob in the current notebook, or null.
  Uint8List? blob(String hash) =>
      notebookId == null ? null : _repo.getBlob(notebookId!, hash);

  /// Store bytes in the current notebook, returning the content hash.
  String addBlob(Uint8List bytes, String mime) =>
      importBlob(notebookId!, bytes, mime);

  /// [addBlob] for the interactive routes — paste, drag-and-drop, the Insert
  /// menu — returning null instead of throwing when the bytes could not be
  /// written.
  ///
  /// `writeBlob` throws synchronously on a full disk, a read-only folder or a
  /// cloud directory that is offline, and every one of those used to escape
  /// into a fire-and-forget async gap: the paste simply did nothing, with not
  /// a word on screen. Losing the thing the user just added is the one
  /// failure that must be VISIBLE, so it surfaces through [saveError] — the
  /// same plain-words status-bar chip every other write failure uses — and
  /// the caller skips creating a block that would reference bytes nothing
  /// holds.
  String? tryAddBlob(Uint8List bytes, String mime) {
    try {
      final hash = addBlob(bytes, mime);
      if (_blobWriteError != null) {
        // The write path works again; a stale notice would outlive the
        // problem it described.
        _blobWriteError = null;
        notifyListeners();
      }
      return hash;
    } catch (e) {
      debugPrint('[openote] could not store pasted/dropped bytes: $e');
      _blobWriteError = SaveProblem(
        short: "That didn't get added",
        message: 'Openote could not save the picture or file you just added, '
            'so it is not in your notebook.\n\n'
            'Check that the disk is not full and that the notebook\'s folder '
            'is not set to read-only, then paste or drop it again.',
        details: '$e',
      );
      notifyListeners();
      return null;
    }
  }

  /// The last failed paste/drop, until one succeeds. See [tryAddBlob].
  SaveProblem? _blobWriteError;

  /// Every notebook in the workspace (registry order).
  List<NotebookRef> get notebooks => _repo.notebooks;

  /// The open notebook's registry entry.
  NotebookRef get currentNotebook =>
      _repo.notebooks.firstWhere((n) => n.id == notebookId);

  /// Imports temporarily own their target file; ordinary notebooks are local
  /// and writable whenever the filesystem permits it.
  bool notebookIsReadOnly(String id) => false;

  /// Read a page of the current notebook without making it the active page —
  /// used by exporters, which walk every page in turn.
  PageData readPage(String id) => _repo.readPage(notebookId!, id);

  PageData readPageShared(String id) => _repo.readPageShared(notebookId!, id);

  Set<String> pageIdsWithTags() => notebookId == null
      ? const {}
      : _repo.pageIdsWithTags(notebookId!).toSet();

  Set<String> allBlockIds() =>
      notebookId == null ? const {} : _repo.allBlockIds(notebookId!);

  /// Pages in this notebook whose *content* matches [query] (TEXT-7).
  /// The navigator searches titles itself; this is the other half.
  ///
  /// **Locked pages are excluded.** Without this the passcode gate would be
  /// bypassed by typing a word from the page into the search box, which would
  /// make even its modest promise — "Openote will not show you this page" —
  /// untrue. The gate makes no claim about the FILE (see page_protection.dart),
  /// but it has to be coherent inside the app that offers it.
  List<({String pageId, String snippet})> searchContent(String query) {
    if (notebookId == null) return const [];
    final hits = _repo.searchPageContent(notebookId!, query);
    if (!_anyProtection) return hits;
    return [
      for (final h in hits)
        if (!isLocked(h.pageId)) h,
    ];
  }

  /// Re-read the tree from storage into [nodes], bumping [nodesRevision].
  /// Replaces the `app.nodes = repo.loadNodes(id)` line that used to be copied
  /// at every mutation site, importers included.
  void reloadNodes() {
    if (notebookId != null) nodes = _repo.loadNodes(notebookId!);
  }

  // ── Read access to ANY notebook, for the external API (spec 14) ───────
  //
  // The API resolves ids across the whole workspace; the open notebook is
  // answered from live state by the tools layer, these read the store.

  List<TreeNode> readNodesOf(String nb) => _repo.loadNodes(nb);

  PageData readPageOf(String nb, String pageId) => _repo.readPage(nb, pageId);

  List<({String pageId, String snippet})> searchPagesOf(
    String nb,
    String query,
  ) =>
      _repo.searchPageContent(nb, query);

  // ── The MCP server (spec 14): AI tools reading and writing notes ──────

  /* McpServer? _mcpServer;
  bool mcpEnabled = false;
  String? mcpToken;
  int? mcpPort;
  String? mcpError;

  /// Turn the local MCP server on or off. Off is the default forever; on
  /// generates a bearer token once and binds 127.0.0.1 (spec 14 §4). The
  /// chosen port persists so pasted client configs stay valid.
  Future<void> setMcpEnabled(bool on) async {
    mcpError = null;
    if (!on) {
      mcpEnabled = false;
      await _mcpServer?.stop();
      _repo.setSetting('mcp', {'enabled': false, 'token': mcpToken});
      notifyListeners();
      return;
    }
    mcpToken ??= '${newId()}${newId()}'.replaceAll('-', '');
    _mcpServer ??= McpServer(this);
    try {
      mcpPort = await _mcpServer!.start(
        token: mcpToken!,
        preferredPort: mcpPort ?? 27191,
      );
      mcpEnabled = true;
      _repo.setSetting('mcp', {
        'enabled': true,
        'token': mcpToken,
        'port': mcpPort,
      });
      // Keep any connection the user made current — the port can move
      // when another app holds it. No-op for everyone who never pressed
      // Connect.
      refreshConnectedClients(port: mcpPort!, token: mcpToken!);
    } catch (e) {
      mcpEnabled = false;
      mcpError = '$e';
    }
    notifyListeners();
  }

  /// Update-through-app: set when launch found a newer release. The
  /// command bar shows its button off this; null means current or the
  /// check failed (offline etc.), which deliberately look identical.
  */
  UpdateInfo? updateAvailable;

  Future<void> checkForAppUpdate() async {
    final u = await fetchLatestUpdate();
    if (u == null) return;
    updateAvailable = u;
    notifyListeners();
  }

  /// Restore the server on launch when the user left it on.
  /* Future<void> _restoreMcp() async {
    final s = _repo.getSetting('mcp');
    if (s is! Map) return;
    mcpToken = s['token'] as String?;
    mcpPort = (s['port'] as num?)?.toInt();
    if (s['enabled'] == true) await setMcpEnabled(true);
  }

  // ── Passcode gating (interim; ADR-0008 designs the real thing) ────────
  //
  // A lock on the app's doors, NOT on the file. See page_protection.dart for
  // what that does and does not mean; the wording there is the wording the
  // user is shown.

  */
  String _protectKey(String nodeId) => 'protect:${notebookId ?? ''}:$nodeId';

  /// Cheap "is anything protected at all" check, so the common notebook pays
  /// nothing on the search and page-open paths.
  bool get _anyProtection => _protectedIds.isNotEmpty;
  final Set<String> _protectedIds = {};

  /// Unlocked subtree roots → when the unlock expires (null = this session).
  final Map<String, DateTime?> _unlocked = {};

  /// Bumped whenever the set of locked nodes could have changed. Caches that
  /// filter on [isLocked] must include it in their key, or they answer from
  /// before the lock.
  int _gateRevision = 0;

  int get gateRevision => _gateRevision;

  bool isPageLocked(String pageId) => isLocked(pageId);

  /// Re-read which nodes are protected, for the notebook that is open now.
  ///
  /// **Every entry point that changes which notebook is open must call this.**
  /// It shipped in 0.4.2 with no caller in the app at all — only tests — so
  /// `_protectedIds` was empty on every cold start, `_anyProtection` was false,
  /// and the gate evaporated: locked pages opened with no prompt, their titles
  /// and content came back in search, and the context menu offered to lock the
  /// page *again*, overwriting the stored record without ever asking for the
  /// old passcode. The record was in workspace.json the whole time; nothing
  /// read it. The test that was supposed to catch this built a fresh AppState
  /// and then called this method BY HAND, which is exactly the line production
  /// was missing — so it passed while the feature did not work.
  ///
  /// The unlock cache is cleared too: unlocks are keyed by node id, ids are
  /// unique per notebook, and carrying them across a notebook switch would
  /// mean an unlock granted in one notebook silently applying in another.
  void reloadProtection() {
    _protectedIds.clear();
    _unlocked.clear();
    if (notebookId == null) return;
    final prefix = 'protect:${notebookId!}:';
    for (final k in _repo.settingKeys()) {
      if (k.startsWith(prefix)) _protectedIds.add(k.substring(prefix.length));
    }
    _gateRevision++;
  }

  ProtectionRecord? protectionFor(String nodeId) =>
      _protectedIds.contains(nodeId)
          ? ProtectionRecord.fromJson(_repo.getSetting(_protectKey(nodeId)))
          : null;

  /// The nearest protected ancestor of [nodeId], itself included — the node
  /// whose passcode actually governs it. Null when nothing above it is
  /// protected.
  ///
  /// Walking UP rather than marking descendants is what makes protection apply
  /// to pages added to a locked section later, without any bookkeeping.
  String? governingNode(String nodeId) {
    if (!_anyProtection) return null;
    final byId = {for (final n in nodes) n.id: n};
    String? cur = nodeId;
    // Bounded: a corrupt parent cycle must not hang the page-open path.
    for (var i = 0; cur != null && i < 64; i++) {
      if (_protectedIds.contains(cur)) return cur;
      cur = _protectionParent(byId[cur]);
    }
    return null;
  }

  /// The node one step up the hierarchy the USER sees.
  ///
  /// For everything except a sub-page that is `parentId`. A sub-page is the
  /// exception, and it is why locking a page did not lock the pages indented
  /// beneath it: sub-pages are not children in the data model at all. Every
  /// page's `parentId` is its SECTION — `makeSubpageOf` sets
  /// `parentId = target.parentId` — and the nesting the navigator draws is
  /// [TreeNode.level] plus position order. So walking `parentId` from a
  /// sub-page steps straight past its parent page to the section, and a
  /// passcode on the parent governs nothing.
  ///
  /// The rule here is the one the rest of the app already uses for exactly
  /// this relationship (`sidebar._pageEntriesFor`, `sortSection`): a page's
  /// parent is the nearest PRECEDING page in the section, in position order,
  /// with a strictly smaller level.
  String? _protectionParent(TreeNode? n) {
    if (n == null) return null;
    if (n.kind != NodeKind.page || n.level == 0) return n.parentId;
    final siblings = pagesOf(n.parentId ?? '');
    final i = siblings.indexWhere((p) => p.id == n.id);
    // Not found: an id from another notebook, or nodes mid-reload. Falling
    // back to parentId keeps the walk terminating on something real.
    if (i < 0) return n.parentId;
    for (var j = i - 1; j >= 0; j--) {
      if (siblings[j].level < n.level) return siblings[j].id;
    }
    // Indented with nothing shallower above it — malformed, but a real state
    // an import can produce. The section still governs it.
    return n.parentId;
  }

  /// Is [nodeId] currently hidden behind a passcode?
  bool isLocked(String nodeId) {
    final root = governingNode(nodeId);
    if (root == null) return false;
    if (!_unlocked.containsKey(root)) return true;
    final until = _unlocked[root];
    if (until == null) return false; // session-length unlock
    if (DateTime.now().isBefore(until)) return false;
    _unlocked.remove(root); // expired
    _gateRevision++;
    return true;
  }

  /// Try [passcode] against the node governing [nodeId]. Returns false — and
  /// changes nothing — when it does not match.
  bool unlockNode(String nodeId, String passcode) {
    final root = governingNode(nodeId);
    if (root == null) return true;
    final rec = protectionFor(root);
    if (rec == null || !rec.matches(passcode)) return false;
    final d = rec.policy.duration;
    // `always` is not cached at all: the next open asks again.
    if (rec.policy != UnlockPolicy.always) {
      _unlocked[root] = d == null ? null : DateTime.now().add(d);
    }
    _gateRevision++;
    notifyListeners();
    return true;
  }

  /// Put a passcode on [nodeId]. Everything beneath it inherits.
  void protectNode(String nodeId, String passcode, UnlockPolicy policy) {
    _repo.setSetting(
      _protectKey(nodeId),
      newProtection(passcode, policy).toJson(),
    );
    _protectedIds.add(nodeId);
    _unlocked.remove(nodeId);
    _gateRevision++;
    notifyListeners();
  }

  /// Take the passcode off [nodeId] — only for someone who can supply it.
  bool unprotectNode(String nodeId, String passcode) {
    final rec = protectionFor(nodeId);
    if (rec == null) return true;
    if (!rec.matches(passcode)) return false;
    _repo.setSetting(_protectKey(nodeId), null);
    _protectedIds.remove(nodeId);
    _unlocked.remove(nodeId);
    _gateRevision++;
    notifyListeners();
    return true;
  }

  /// Forget every unlock now — the "Lock now" action, and what shutdown does.
  void lockAll() {
    if (_unlocked.isEmpty) return;
    _unlocked.clear();
    _gateRevision++;
    notifyListeners();
  }

  // ── Import ownership and manual backups ──────────────────────────────

  /// The import worker owns the target database while it runs. Closing our
  /// cached handle before and after the job keeps SQLite single-writer.
  void beginExclusiveImport(String notebookId) =>
      _repo.closeNotebook(notebookId);

  void endExclusiveImport(String notebookId) => _repo.closeNotebook(notebookId);

  void abandonExclusiveImport(String notebookId) =>
      _repo.closeNotebook(notebookId);
  Future<WorkspaceBackupResult> createWorkspaceBackup(
    String destination, {
    String? onlyNotebookId,
  }) async {
    await flushSave();
    await _repo.flushWorkspace();
    final temporary = await Directory.systemTemp.createTemp(
      'openote-backup-build-',
    );
    final root = Directory(p.join(temporary.path, 'Openote'));
    await root.create(recursive: true);
    try {
      // Preserve the familiar Documents/Openote layout as well as the
      // portable manifest used by the Restore button.
      if (onlyNotebookId == null) {
        await _copyBackupDirectory(
          _repo.workspaceDir,
          root,
          skipNotebookContainers: true,
        );
      }
      final selected = notebooks
          .where((n) => onlyNotebookId == null || n.id == onlyNotebookId)
          .toList();
      if (selected.isEmpty) throw StateError('No notebook was selected.');
      final manifest = <Map<String, Object?>>[];
      final usedNames = <String>{};
      for (final ref in selected) {
        var stem = ref.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
        if (stem.isEmpty) stem = 'Notebook';
        var uniqueStem = stem;
        var suffix = 2;
        while (!usedNames.add(uniqueStem.toLowerCase())) {
          uniqueStem = '$stem $suffix';
          suffix++;
        }
        final relativeFile = p.isWithin(_repo.workspaceDir.path, ref.file)
            ? p.relative(ref.file, from: _repo.workspaceDir.path)
            : '$uniqueStem.onote';
        final snapshot = File(p.join(root.path, relativeFile));
        await snapshot.parent.create(recursive: true);
        if (!_repo.snapshotContainer(ref.id, snapshot.path)) {
          throw FileSystemException(
            'Could not create a safe snapshot of ${ref.title}',
            ref.file,
          );
        }
        final media = MediaStore.dirFor(ref);
        final legacyMedia = MediaStore.legacyDirFor(ref);
        final relativeMedia = '${p.withoutExtension(relativeFile)}.media';
        final mediaToBackup = media.existsSync() ? media : legacyMedia;
        if (mediaToBackup.existsSync() &&
            (onlyNotebookId != null ||
                !p.isWithin(_repo.workspaceDir.path, mediaToBackup.path))) {
          await _copyBackupDirectory(
            mediaToBackup,
            Directory(p.join(root.path, relativeMedia)),
          );
        }
        manifest.add({
          'id': ref.id,
          'title': ref.title,
          'file': 'Openote/$relativeFile',
          'media': 'Openote/$relativeMedia',
        });
      }
      await File(p.join(temporary.path, 'backup.json')).writeAsString(
        jsonEncode({
          'format': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'notebooks': manifest,
        }),
      );
      // The consistent snapshots above are intentionally made before the
      // isolate starts. SQLite belongs to this isolate; ZIP encoding does not.
      final bytes = await Isolate.run(
        () => _encodeWorkspaceBackupZip((temporary.path, destination)),
      );
      return WorkspaceBackupResult(
        notebooks: selected.length,
        bytes: bytes,
      );
    } finally {
      try {
        await temporary.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _copyBackupDirectory(
    Directory source,
    Directory destination, {
    bool skipNotebookContainers = false,
  }) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final parts = p.split(relative);
      final name = parts.last.toLowerCase();
      if (parts.any((part) => part == '.git' || part == '.DS_Store') ||
          name == '.instance-lock' ||
          name == '.open-request') {
        continue;
      }
      final lower = entity.path.toLowerCase();
      if ((skipNotebookContainers && lower.endsWith('.onote')) ||
          lower.endsWith('-wal') ||
          lower.endsWith('-shm') ||
          lower.endsWith('.tmp')) {
        continue;
      }
      final target = p.join(destination.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }

  Future<int> restoreWorkspaceBackup(String archivePath) async {
    final temporary = await Directory.systemTemp.createTemp(
      'openote-backup-restore-',
    );
    try {
      final archive = ZipDecoder().decodeBytes(
        await File(archivePath).readAsBytes(),
      );
      for (final entry in archive) {
        final normal = p.normalize(entry.name.replaceAll('/', p.separator));
        if (p.isAbsolute(normal) || normal.startsWith('..')) {
          throw const FormatException('The backup contains an unsafe path.');
        }
        final target = p.join(temporary.path, normal);
        if (entry.isFile) {
          await File(target).parent.create(recursive: true);
          await File(target).writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(target).create(recursive: true);
        }
      }
      final manifestFile = File(p.join(temporary.path, 'backup.json'));
      final candidates = <({String path, String? title, String? media})>[];
      if (manifestFile.existsSync()) {
        final json = jsonDecode(await manifestFile.readAsString());
        if (json is Map && json['notebooks'] is List) {
          for (final raw in json['notebooks'] as List) {
            if (raw is! Map || raw['file'] is! String) continue;
            candidates.add((
              path: p.join(
                temporary.path,
                (raw['file'] as String).replaceAll('/', p.separator),
              ),
              title: raw['title'] as String?,
              media: raw['media'] is String
                  ? p.join(
                      temporary.path,
                      (raw['media'] as String).replaceAll('/', p.separator),
                    )
                  : null,
            ));
          }
        }
      }
      if (candidates.isEmpty) {
        await for (final entity in temporary.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File && p.extension(entity.path) == '.onote') {
            candidates.add((path: entity.path, title: null, media: null));
          }
        }
      }
      var restored = 0;
      for (final candidate in candidates) {
        if (!File(candidate.path).existsSync()) continue;
        var stem =
            (candidate.title ?? p.basenameWithoutExtension(candidate.path))
                .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
                .trim();
        if (stem.isEmpty) stem = 'Restored notebook';
        var destination = p.join(_repo.workspaceDir.path, '$stem.onote');
        var suffix = 2;
        while (File(destination).existsSync()) {
          destination = p.join(_repo.workspaceDir.path, '$stem $suffix.onote');
          suffix++;
        }
        await File(candidate.path).copy(destination);
        final sourceMedia =
            candidate.media == null ? null : Directory(candidate.media!);
        if (sourceMedia != null && sourceMedia.existsSync()) {
          await _copyBackupDirectory(
            sourceMedia,
            Directory('${p.withoutExtension(destination)}.media'),
          );
        }
        final result = await _repo.adoptWorkspaceNotebook(
          destination,
          title: candidate.title,
        );
        restored++;
        notebookId = result.id;
      }
      if (restored == 0) {
        throw const FormatException('No Openote notebooks were found.');
      }
      await _loadNotebook();
      notifyListeners();
      return restored;
    } finally {
      try {
        await temporary.delete(recursive: true);
      } catch (_) {}
    }
  }

  TreeNode _putNode(String notebookId, TreeNode node) {
    return _repo.upsertNode(notebookId, node);
  }
  // ── Import write path ────────────────────────────────────────────────
  //
  // Importers write in bulk, into a notebook that may not be the open one, and
  // outside the interactive edit path. They still go through here rather than
  // touching the repository, for the reason above. The `import` prefix marks
  // them as the bulk path — an interactive edit must never use them, because
  // they deliberately skip autosave, undo and selection handling.

  /// Create a node during import. Returns the stored node.
  TreeNode importNode(String nb, TreeNode n) => _putNode(nb, n);

  /// Write a page's blocks during import.
  void importPage(String nb, String pageId, List<Block> blocks, PageProps p) =>
      _repo.writePage(nb, pageId, blocks, p);

  /// Store a blob during import (images pulled out of a `.one` file).
  String importBlob(String nb, Uint8List bytes, String mime) {
    return _repo.putBlob(nb, bytes, mime);
  }

  /// Hard-delete a node during import — used to clear a partially seeded
  /// notebook before re-seeding it, never on user data.
  void importPurgeNode(String nb, String id) {
    _repo.purgeNode(nb, id);
  }

  /// The tree of any notebook, open or not.
  List<TreeNode> importNodes(String nb) => _repo.loadNodes(nb);

  /// Run [body] as ONE transaction. Import writes hundreds of pages; without
  /// this each would pay its own commit.
  T importBatch<T>(String nb, T Function() body) =>
      _repo.runInTransaction(nb, body);

  /// Create the notebook an import targets. Unlike [createNotebook] this does
  /// not switch to it or flush the current page: the importer builds the whole
  /// notebook first and only then calls [selectNotebook], which flushes. The
  /// asymmetry is deliberate — switching mid-import would show the user a
  /// half-built notebook — and it is safe only because of that later switch.
  Future<NotebookRef> importCreateNotebook(String title) =>
      _repo.createNotebook(title);

  /// Shared so toolbar/shortcuts can drive zoom (style guide §8.2).
  final canvas = CanvasController();

  /// RepaintBoundary key for whole-page capture (PDF export).
  final canvasKey = GlobalKey();

  // Workspace / navigation
  @override
  String? notebookId;

  List<TreeNode> _nodes = [];

  /// The current notebook's tree, ordered by position.
  @override
  List<TreeNode> get nodes => _nodes;
  set nodes(List<TreeNode> v) {
    _nodes = v;
    nodesRevision++;
  }

  /// Bumped whenever the tree changes shape *or* a node's rendered fields
  /// change. The navigator memoises its widget subtree on this, so typing in a
  /// page no longer rebuilds every section and page tile (§7a.6).
  @override
  int nodesRevision = 0;

  /// Call after mutating a [TreeNode] in place (rename, indent) — those don't
  /// replace the list, so the setter above wouldn't notice.
  void bumpNodes() => nodesRevision++;

  String? pageId;
  final Set<String> collapsedGroups = {};

  // Navigator (§7b, two-column): the focused section fills the pages pane.
  @override
  String? activeSectionId;

  TreeNode? get activeSection => node(activeSectionId);

  // ── Navigator layout state ──────────────────────────────────────────
  //
  // Two independent widths rather than one split: sections and pages are
  // separate columns now (the OneNote shape), so each keeps its own size and
  // neither steals from the other when resized.

  double navSectionsW = 120; // sections column, px
  double navPagesW = 168; // pages column, px
  bool navCollapsed = false; // the whole navigator as a 44px rail

  /// The Home surface (favourites + recents) shown in the pages pane.
  /// Transient by design: selecting any page returns the pane to that page's
  /// section, so Home behaves like a springboard rather than a place you can
  /// get stuck in. Deliberately a BOOLEAN beside a real [activeSectionId], not
  /// a sentinel section id — every consumer of activeSectionId (study scoping,
  /// exam plans, deck counts) stays correct with zero special-casing.
  bool navHome = false;

  /// Bumped when navigator-only state changes that nothing else observes —
  /// favourites, collapse toggles, Home. The navigator memo in AppShell keys
  /// on it; leaving one of these out is how a stale (not broken, just frozen)
  /// navigator ships.
  int navRevision = 0;

  void setNavSectionsW(double v) {
    navSectionsW = v.clamp(96, 220);
    _repo.setSetting('navSectionsW', navSectionsW);
    notifyListeners();
  }

  void setNavPagesW(double v) {
    navPagesW = v.clamp(140, 320);
    _repo.setSetting('navPagesW', navPagesW);
    notifyListeners();
  }

  void toggleNavCollapsed() {
    navCollapsed = !navCollapsed;
    _repo.setSetting('navCollapsed', navCollapsed);
    notifyListeners();
  }

  void openHome() {
    navHome = true;
    navRevision++;
    notifyListeners();
  }

  /// Which page each section was last on, so browsing sections never loses
  /// your place. Keys are '<notebookId>:<sectionId>' because settings are
  /// workspace-scoped (same reasoning as favourites).
  final Map<String, String> _sectionLastPage = {};

  void _rememberSectionPage(String sectionId, String pageId) {
    _sectionLastPage['$notebookId:$sectionId'] = pageId;
    _repo.setSetting('sectionLastPage', _sectionLastPage);
  }

  /// A section's pages, in navigator order.
  ///
  /// One query rather than the same `where` written out at each call site — it
  /// was open-coded in three places, and "the pages of a section, in the order
  /// the navigator shows them" is exactly the thing a section-wide export or
  /// sort has to agree with the navigator about.
  List<TreeNode> pagesOf(String sectionId) => [
        for (final n in nodes)
          if (n.kind == NodeKind.page && n.parentId == sectionId) n,
      ];

  /// Focus a section (the pages pane shows its pages). When the current page
  /// isn't inside the section, return to the page you were last on THERE —
  /// falling back to the first page only for a section never visited.
  ///
  /// The remembered page is what makes flicking between sections
  /// non-destructive: jumping to the *first* page every time meant merely
  /// looking at another section threw away your place in it, which OneNote
  /// gets right and users notice immediately.
  /// Awaitable, because `selectPage` only commits `pageId` after an awaited
  /// flush — fire-and-forget here let two quick section clicks interleave
  /// their page loads and land on the loser's page.
  Future<void> activateSection(String id) async {
    navHome = false;
    activeSectionId = id;
    final cur = node(pageId);
    if (cur == null || cur.parentId != id) {
      final remembered = node(_sectionLastPage['$notebookId:$id']);
      final target = (remembered != null && remembered.parentId == id)
          ? remembered
          : pagesOf(id).firstOrNull;
      if (target != null) {
        await selectPage(target.id); // sets activeSectionId + notifies
        return;
      }
    }
    notifyListeners();
  }

  // Page content
  List<Block> blocks = [];
  PageProps pageProps = PageProps();

  // Selection (CANVAS-7: single + multi)
  final Set<String> selectedIds = {};
  String? selectedBlockId; // primary (gets handles/chrome)
  String? editingBlockId;

  /// The block a click just created — or opened — with nothing in it and
  /// nothing typed since: OneNote-style, a caret is live and ready to type,
  /// but the box's own chrome (border, move bar, resize handles) stays
  /// hidden until the first keystroke, and arrow keys slide the box itself
  /// around the page instead of moving a caret through content that
  /// doesn't exist yet. Set at the CLICK that opens the block
  /// (`BlockView._tap` / `PageCanvas._createTextAt`), before `select()`
  /// notifies, so the very first build already sees it; cleared on the
  /// first edit, or when editing ends.
  String? pendingEmptyBlockId;

  /// Move the selected block(s) by a step in one direction — the canvas's
  /// own Ctrl+arrow nudge, reused so a [pendingEmptyBlockId] block's PLAIN
  /// arrow keys slide it around the page (there is no content yet for
  /// Ctrl to distinguish "move" from). Wired once by AppShell; returns
  /// false when there is nothing selected to move.
  bool Function(double dx, double dy, {required bool fine})? navigateNudge;

  /// Bumped when block content changes from OUTSIDE its own editor widgets
  /// (undo/redo, page load) so views rebuild from model state.
  @override
  int docRevision = 0;

  /// Measured render sizes of auto-height blocks (runtime only; used for
  /// culling, marquee hit-testing, and content bounds).
  final Map<String, Size> renderSizes = {};

  /// A two-finger canvas gesture is in progress. Object views consult this
  /// live flag before acting on their one-finger touch drag, so a PDF/image
  /// can never keep moving underneath a pinch gesture.
  bool touchCanvasGesture = false;

  /// Pointer ids claimed by block widgets this gesture, so the canvas-level
  /// handler ignores them (see BlockView / PageCanvas).
  final Set<int> claimedPointers = {};

  /// A touch that began on an object can be handed back to the page before a
  /// hold has picked that object up. The initial claim keeps a short tap from
  /// also becoming a canvas tap; this one-shot marker lets a normal swipe
  /// still scroll the page.
  final Set<int> relinquishedTouchPointers = {};

  // Canvas settings
  Tool tool = Tool.select;
  bool writingMode = false;
  bool shapeRecognition = true;
  bool rulerVisible = false;

  void setWritingMode(bool value) {
    writingMode = value;
    if (value) {
      requestDrawTab();
    }
    notifyListeners();
  }

  void setShapeRecognition(bool value) {
    if (shapeRecognition == value) return;
    shapeRecognition = value;
    _repo.setSetting('shapeRecognition', value);
    notifyListeners();
  }

  void setRulerVisible(bool value) {
    if (rulerVisible == value) return;
    rulerVisible = value;
    notifyListeners();
  }

  bool snapToGrid = true; // on by default; the grid only shows while dragging

  /// Held down mid-drag to invert [snapToGrid] for THIS drag only.
  ///
  /// "if im in grid mode, holding down ctrl while moving puts that one in free
  /// form and leaves the rest in their grid pattern, but as soon as i release
  /// it it goes back to grid, and vice versa."
  ///
  /// Set by the canvas from the live keyboard on every pointer move, so a
  /// modifier pressed or released PART WAY through a drag takes effect
  /// immediately rather than at the moment the drag began. It is deliberately
  /// a plain flag rather than a keyboard read in here: the state layer has no
  /// business knowing about hardware, and a settable flag is what makes the
  /// behaviour testable without simulating key events.
  bool snapOverride = false;

  /// Whether placement snaps right now — the mode plus any live override.
  /// Every drag-time decision reads THIS, never [snapToGrid] directly.
  bool get effectiveSnap => snapOverride ? !snapToGrid : snapToGrid;
  int penColor = 0;
  int highlighterColor = 0;

  /// A mixed pen colour from the colour picker. Null means one of the fixed
  /// toolbar swatches (including the theme-aware automatic first swatch).
  String? penCustomColor;
  String? highlighterCustomColor;

  /// Colours the person deliberately pins beside the pen/highlighter. These
  /// are separate from [customColors], which is only a non-destructive recent
  /// history for the picker; opening a recent colour must never silently add
  /// buttons to the drawing toolbar.
  final List<String> penToolbarColors = [];
  final List<String> highlighterToolbarColors = [];

  final Set<int> hiddenPenPresets = {};
  final Set<int> hiddenHighlighterPresets = {};

  bool toolbarPresetVisible(Tool brush, int index) =>
      !(brush == Tool.highlighter ? hiddenHighlighterPresets : hiddenPenPresets)
          .contains(index);

  void hideToolbarPreset(Tool brush, int index) {
    final hidden =
        brush == Tool.highlighter ? hiddenHighlighterPresets : hiddenPenPresets;
    if (!hidden.add(index)) return;
    _repo.setSetting(
        brush == Tool.highlighter
            ? 'hiddenHighlighterPresets'
            : 'hiddenPenPresets',
        hidden.toList());
    notifyListeners();
  }

  List<String> toolbarInkColorsFor(Tool value) =>
      value == Tool.highlighter ? highlighterToolbarColors : penToolbarColors;

  void addToolbarInkColor(String value, Tool brush) {
    final clean = value.replaceFirst('#', '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) return;
    final colors = toolbarInkColorsFor(brush);
    colors.remove(clean);
    colors.add(clean);
    _repo.setSetting(
      brush == Tool.highlighter
          ? 'highlighterToolbarColors'
          : 'penToolbarColors',
      colors,
    );
    notifyListeners();
  }

  void removeToolbarInkColor(String value, Tool brush) {
    final colors = toolbarInkColorsFor(brush);
    if (!colors.remove(value)) return;
    _repo.setSetting(
      brush == Tool.highlighter
          ? 'highlighterToolbarColors'
          : 'penToolbarColors',
      colors,
    );
    notifyListeners();
  }

  /// One-shot canvas colour sampler. The canvas consumes the next pen or mouse
  /// release and writes that exact visible colour into the active ink tool.
  bool inkEyedropperActive = false;

  void setInkEyedropperActive(bool active) {
    if (inkEyedropperActive == active) return;
    inkEyedropperActive = active;
    notifyListeners();
  }

  double penSize = 2.5;

  /// The pen, ballpoint and highlighter deliberately remember different
  /// widths. [penSize] remains the width of the currently selected ink tool
  /// for compatibility with the rendering code.
  final Map<Tool, double> _inkToolSizes = {
    Tool.pen: 2.5,
    Tool.ballpoint: 2.5,
    Tool.highlighter: 6,
    Tool.shape: 2.5,
  };

  bool _hasInkSize(Tool value) =>
      value == Tool.pen ||
      value == Tool.ballpoint ||
      value == Tool.highlighter ||
      value == Tool.shape;

  double inkSizeFor(Tool value) => _inkToolSizes[value] ?? penSize;

  double minInkSizeFor(Tool value) => 0.1;

  double maxInkSizeFor(Tool value) => 10.0;

  void setInkSize(double value) {
    if (!value.isFinite) return;
    final size = value.clamp(minInkSizeFor(tool), maxInkSizeFor(tool));
    penSize = size;
    if (_hasInkSize(tool)) _inkToolSizes[tool] = size;
    _repo.setSetting('inkToolSizes', {
      for (final entry in _inkToolSizes.entries) entry.key.name: entry.value,
    });
    notifyListeners();
  }

  void setCustomPenColor(String? value) {
    final raw = value?.replaceFirst('#', '').toUpperCase();
    penCustomColor =
        raw != null && RegExp(r'^[0-9A-F]{6}$').hasMatch(raw) ? raw : null;
    _repo.setSetting('penCustomColor', penCustomColor);
    notifyListeners();
  }

  int inkColorFor(Tool value) =>
      value == Tool.highlighter ? highlighterColor : penColor;

  String? customInkColorFor(Tool value) =>
      value == Tool.highlighter ? highlighterCustomColor : penCustomColor;

  /// Colour choices belong to their brush. Switching to the highlighter must
  /// never borrow the pen colour, and switching back must restore the pen.
  void setInkColor(int value) {
    if (tool == Tool.highlighter) {
      highlighterColor = value;
      highlighterCustomColor = null;
      _repo.setSetting('highlighterColor', value);
      _repo.setSetting('highlighterCustomColor', null);
    } else {
      penColor = value;
      penCustomColor = null;
      _repo.setSetting('penColor', value);
      _repo.setSetting('penCustomColor', null);
    }
    notifyListeners();
  }

  void setCustomInkColor(String? value) {
    final raw = value?.replaceFirst('#', '').toUpperCase();
    final clean =
        raw != null && RegExp(r'^[0-9A-F]{6}$').hasMatch(raw) ? raw : null;
    if (tool == Tool.highlighter) {
      highlighterCustomColor = clean;
      _repo.setSetting('highlighterCustomColor', clean);
    } else {
      penCustomColor = clean;
      _repo.setSetting('penCustomColor', clean);
    }
    notifyListeners();
  }

  // ── Tags (TEXT-5) ────────────────────────────────────────────────────

  /// Apply or remove [kind] on the line the caret is in, for the block being
  /// edited (or the selected one).
  ///
  /// Toggling is per (line, kind): applying the same tag to the same line
  /// removes it, which is what a toolbar button that shows its own state has
  /// to do.
  void toggleTagOnSelection(TagKind kind, {int? line}) {
    final b = blocks
        .where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    final idx = line ?? _caretLine(b);
    pushUndo();
    final tags = [...NoteTag.listFrom(b.content)];
    final at = tags.indexWhere((t) => t.line == idx && t.kind == kind);
    if (at >= 0) {
      tags.removeAt(at);
    } else {
      tags.add(
        NoteTag(
          kind: kind,
          line: idx,
          checked: kind == TagKind.todo ? false : null,
        ),
      );
    }
    NoteTag.writeInto(b.content, tags);
    updateBlock(b);
    // **No `docRevision++`.** Every block widget is keyed by it, so bumping it
    // threw the text box away and built a new one — with a fresh controller,
    // an invalid selection, and the caret at the very END of the paragraph.
    // A student who pressed Ctrl+1 mid-sentence to mark the line asked for a
    // tag, not to be moved. The same fix, for the same reason, as the
    // degrees/radians button above; a tag lives in `content['tags']`, not in
    // the text, so a plain notify redraws the gutter marker.
    notifyListeners();
  }

  /// Flip a to-do tag's completion.
  void setTagChecked(String blockId, int line, bool checked) {
    final b = blocks.where((x) => x.id == blockId).firstOrNull;
    if (b == null) return;
    pushUndo();
    final tags = [
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == line && t.kind == TagKind.todo)
          t.copyWith(checked: checked)
        else
          t,
    ];
    NoteTag.writeInto(b.content, tags);
    updateBlock(b);
    docRevision++;
    notifyListeners();
  }

  /// Change one tag, on any page of the open notebook.
  ///
  /// **Not open-page-only, and that is the point.** The planner lists tasks
  /// from the whole notebook, so ticking one or re-dating it must not depend on
  /// which page happens to be loaded. Routing it through `selectPage` instead
  /// was the first attempt and it is worse twice over: it yanks the reader to
  /// another page for a checkbox, and — because `selectPage` reloads the block
  /// list from storage — an edit made in the same turn is thrown away by the
  /// load that follows it.
  ///
  /// [change] is given the matching tag and returns its replacement, so the
  /// caller says *what* changes and this says *where*. Returns whether anything
  /// did.
  bool _updateTag(
    String pageId_,
    String blockId,
    int line,
    TagKind kind,
    NoteTag Function(NoteTag) change,
  ) {
    final nb = notebookId;
    if (nb == null) return false;

    List<NoteTag>? apply(Block b) {
      final tags = NoteTag.listFrom(b.content);
      if (!tags.any((t) => t.line == line && t.kind == kind)) return null;
      return [
        for (final t in tags)
          if (t.line == line && t.kind == kind) change(t) else t,
      ];
    }

    if (pageId_ == pageId) {
      final b = blocks.where((x) => x.id == blockId).firstOrNull;
      if (b == null) return false;
      final next = apply(b);
      if (next == null) return false;
      pushUndo();
      NoteTag.writeInto(b.content, next);
      updateBlock(b);
      docRevision++;
      notifyListeners();
      return true;
    }

    // A closed page: read it, change it, write it back through the bulk path —
    // the same route `repairWholeNotebook` takes. No undo entry, because undo
    // is scoped to the open page and pushing one here would make Ctrl+Z restore
    // a page the user is not looking at.
    final data = readPage(pageId_);
    final b = data.blocks.where((x) => x.id == blockId).firstOrNull;
    if (b == null) return false;
    final next = apply(b);
    if (next == null) return false;
    NoteTag.writeInto(b.content, next);
    importBatch(nb, () => importPage(nb, pageId_, data.blocks, data.props));
    docRevision++;
    notifyListeners();
    return true;
  }

  /// Give a tag a due day, or (with null) take it away (v0.5 stage 2).
  @override
  bool setTagDue(
    String blockId,
    int line,
    TagKind kind,
    DateTime? day, {
    String? pageId,
  }) =>
      _updateTag(
        pageId ?? this.pageId ?? '',
        blockId,
        line,
        kind,
        (t) => t.withDue(day),
      );

  /// Tick a to-do off, wherever in the notebook it lives.
  bool setTagCheckedOn(
    String pageId_,
    String blockId,
    int line,
    bool checked,
  ) =>
      _updateTag(
        pageId_,
        blockId,
        line,
        TagKind.todo,
        (t) => t.copyWith(checked: checked),
      );

  /// Tags on the caret's line, so the toolbar can show which are active.
  Set<TagKind> tagsAtCaret() {
    final b = blocks
        .where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    if (b == null || b.type != BlockType.text) return const {};
    final idx = _caretLine(b);
    return {
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == idx) t.kind,
    };
  }

  /// The text block a tag action applies to: the one being edited, else the
  /// one selected. Public because the tag menu needs to ask what is under the
  /// caret before it can offer to change it — the same block [tagsAtCaret]
  /// already answers about.
  Block? caretBlock() {
    final b = blocks
        .where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    return b != null && b.type == BlockType.text ? b : null;
  }

  /// Which line of [caretBlock] the caret is on. 0 when nothing is being
  /// edited, matching where a tag would land.
  int caretLineIndex() {
    final b = caretBlock();
    return b == null ? 0 : _caretLine(b);
  }

  /// Which line the caret sits on, so a tag lands where the user is looking.
  /// Falls back to line 0 when nothing is being edited (a tag applied to a
  /// merely-selected block is a tag on its first line).
  int _caretLine(Block b) {
    final ctl =
        activeEditor?.block.id == b.id ? activeEditor?.controller : null;
    final text = b.content['text'] as String? ?? '';
    if (ctl == null || !ctl.selection.isValid) return 0;
    final at = ctl.selection.baseOffset.clamp(0, text.length);
    return '\n'.allMatches(text.substring(0, at)).length;
  }

  /// Turn the caret's line into a flashcard, picking the tag that fits it.
  ///
  /// Tagging is the on-ramp — you mark a line while taking notes and it becomes
  /// a card — but "tag it Question or Definition and remember which one" is a
  /// rule the student has to learn before anything happens, and getting it
  /// wrong produces nothing at all with no explanation. So: one action, and it
  /// reads the line.
  ///
  /// Returns what a caller should tell the user, or null if there was no line
  /// to work with.
  String? makeCardAtCaret() {
    final b = blocks
        .where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    if (b == null || b.type != BlockType.text) return null;
    final lines = (b.content['text'] as String? ?? '').split('\n');
    final idx = _caretLine(b);
    if (idx >= lines.length) return null;
    final line = lines[idx].trim();
    if (line.isEmpty) return 'Put the caret on a line with something on it.';

    final kind = line.endsWith('?') ? TagKind.question : TagKind.definition;
    if (!tagsAtCaret().contains(kind)) toggleTagOnSelection(kind);

    // Say whether it actually produced a card. Silence is what made tagging
    // feel like it did nothing.
    final made = cardsFromBlock(
      b,
      pageId ?? '',
      '',
    ).where((c) => c.line == idx).isNotEmpty;
    if (made) return '${kind.label} card created.';
    return kind == TagKind.question
        ? 'Tagged as a Question — now indent the answer on the line below.'
        : 'Tagged as a Definition — write it as “term — meaning” to make a card.';
  }

  /// Blank out the selected words on a tagged line, making it a fill-in-the-
  /// blank. Returns false when there is no selection to blank.
  bool blankOutSelection() {
    final ed = activeEditor;
    if (ed == null) return false;
    final sel = ed.controller.selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final text = ed.controller.text;
    final a = sel.start, z = sel.end;
    final word = text.substring(a, z);
    if (word.trim().isEmpty) return false;
    pushUndo();
    ed.controller.value = ed.controller.value.copyWith(
      text: text.replaceRange(a, z, '==$word=='),
      selection: TextSelection.collapsed(offset: z + 4),
      composing: TextRange.empty,
    );
    // COMMIT it. This wrote the blank into the controller and stopped,
    // so the block still held the old text and the next rebuild threw the
    // edit away — the feature looked like it worked and then undid itself.
    _commitActiveEditor();
    // Blanking only means something on a line that is already a card.
    if (tagsAtCaret().isEmpty) toggleTagOnSelection(TagKind.question);
    markDirty();
    notifyListeners();
    return true;
  }

  /// Every tagged line in the notebook, for the find-tags rollup.
  ///
  /// Scans page mirrors rather than a maintained index: same reasoning as
  /// notebook-wide search — one source of truth beats an index that can drift.
  /// "Until it measurably hurts" arrived, though, with the first big imported
  /// notebook — so the scan is now narrowed twice *without* becoming an index:
  /// a SQL prefilter finds the pages that can possibly carry a tag (most
  /// cannot), and a decoded-page cache in the repository means a rebuild
  /// re-decodes only pages that changed. See `Repository.readPageShared`.
  ({String key, List<TaggedLine> tags})? _allTagsCache;

  @override
  List<TaggedLine> allTags() {
    if (notebookId == null) return const [];
    // `_gateRevision` is in the key because the answer depends on which pages
    // are locked, and locking or unlocking changes neither the document nor
    // the node revision. Without it, a page unlocked mid-session would keep
    // its tags hidden until some unrelated edit happened to bump the key.
    final key =
        '$notebookId#$docRevision#$nodesRevision#$pageId#$_gateRevision';
    final cached = _allTagsCache;
    if (cached != null && cached.key == key) return cached.tags;
    final tagged = _repo.pageIdsWithTags(notebookId!).toSet();
    final out = <TaggedLine>[];
    for (final n in nodes.where((n) => n.kind == NodeKind.page)) {
      // The rollup quotes the text of every tagged line, so an unguarded scan
      // reprints a locked page's contents in the tags panel and the planner's
      // agenda — the gate walked around by the app that offers it.
      if (isLocked(n.id)) continue;
      // The open page's in-memory blocks are fresher than the container — and
      // it is also the one page the prefilter must not exclude, since its
      // unsaved edits may carry tags the stored JSON does not.
      if (n.id != pageId && !tagged.contains(n.id)) continue;
      final blocksOf = n.id == pageId
          ? blocks
          : _repo.readPageShared(notebookId!, n.id).blocks;
      for (final b in blocksOf) {
        if (b.type != BlockType.text) continue;
        final tags = NoteTag.listFrom(b.content);
        if (tags.isEmpty) continue;
        final lines = (b.content['text'] as String? ?? '').split('\n');
        for (final t in tags) {
          out.add((
            pageId: n.id,
            pageTitle: n.title,
            blockId: b.id,
            tag: t,
            // Plain, not raw: every consumer of this is a SUMMARY — the
            // tags rollup and the planner's agenda — and neither runs the
            // Markdown renderer, so a to-do written as a bullet showed up
            // as "- Finish tutorial 4", dash included.
            text: t.line < lines.length ? plainLine(lines[t.line]) : '',
          ));
        }
      }
    }
    _allTagsCache = (key: key, tags: out);
    return out;
  }

  // ── Study: flashcards, scheduling, stats (E3 — see study_state.dart) ──

  /// Cards, schedules, streaks and the exam countdown.
  ///
  /// Extracted in the E3 pass. `AppState` still forwards its notifications
  /// (see the constructor), so every existing listener keeps working exactly
  /// as it did — but the state itself now has an owner, and the next study
  /// feature has somewhere to go that is not this file.
  late final StudyState study = StudyState(
    this,
    readSetting: _repo.getSetting,
    writeSetting: _repo.setSetting,
  );

  bool get showStudyPanel => openPanel == SidePanelKind.study;
  void toggleStudyPanel() => togglePanel(SidePanelKind.study);

  // ── The planner: dates, reminders, timetable (v0.5) ──────────────────

  /// Everything you have a date for, in one place.
  ///
  /// Owns the reminder store and the calendar subscription; **borrows**
  /// everything else. Exam dates stay in [study] and a task's deadline stays on
  /// its tag, because the agenda is a lens rather than a second store — see
  /// `planner_state.dart`.
  late final PlannerState planner = PlannerState(
    this,
    study,
    readSetting: _repo.getSetting,
    writeSetting: _repo.setSetting,
  )..addListener(notifyListeners);

  // ── The right-hand panel slot (style guide §7c) ──────────────────────

  /// Which panel occupies the single right-hand slot, or null for none.
  ///
  /// **One slot, one panel** — the five panels were independent booleans, so
  /// all five could be open at once: 1,360px of chrome on a Row, which leaves
  /// the canvas nothing on a 1366px laptop. No workflow was found that needs
  /// two at a time, and one-at-a-time is also the task-pane model a OneNote
  /// switcher already expects.
  ///
  /// The old `show*Panel` fields are now getters over this, so every existing
  /// call site keeps working and there is only one piece of state to be wrong.
  SidePanelKind? openPanel;

  /// Open [kind], replacing whatever was there. Idempotent.
  void showPanel(SidePanelKind kind) {
    if (openPanel == kind) return;
    openPanel = kind;
    notifyListeners();
  }

  void closePanel() {
    if (openPanel == null) return;
    openPanel = null;
    notifyListeners();
  }

  /// Open [kind], or close it if it is already the open one — what a toolbar
  /// toggle does.
  void togglePanel(SidePanelKind kind) =>
      openPanel == kind ? closePanel() : showPanel(kind);

  bool get showPlannerPanel => openPanel == SidePanelKind.planner;
  void togglePlannerPanel() => togglePanel(SidePanelKind.planner);

  /// Open the planner (idempotent) from its summary in the sidebar.
  void openPlanner() => showPanel(SidePanelKind.planner);

  // ── Favourites & recents (ORG-10) ────────────────────────────────────
  //
  // Keys are '<notebookId>:<pageId>'. Settings are WORKSPACE-scoped, so a bare
  // page id would collide across notebooks and dangle after one is deleted.

  final Set<String> _favourites = {};
  final List<String> _recents = [];

  static const _recentsCap = 20;

  String _pageKey(String pageId, [String? nb]) => '${nb ?? notebookId}:$pageId';

  bool isFavourite(String pageId) => _favourites.contains(_pageKey(pageId));

  /// Favourite page ids in THIS notebook, in tree order.
  List<TreeNode> favouritePages() => [
        for (final n in nodes)
          if (n.kind == NodeKind.page && _favourites.contains(_pageKey(n.id)))
            n,
      ];

  void toggleFavourite(String pageId) {
    final k = _pageKey(pageId);
    _favourites.contains(k) ? _favourites.remove(k) : _favourites.add(k);
    _repo.setSetting('favourites', _favourites.toList());
    navRevision++; // the Home pane renders favourites; nothing else changes
    notifyListeners();
  }

  /// Recently visited pages in this notebook, most recent first.
  List<TreeNode> recentPages({int max = 8}) {
    final out = <TreeNode>[];
    for (final k in _recents) {
      final parts = k.split(':');
      if (parts.length != 2 || parts[0] != notebookId) continue;
      final n = node(parts[1]);
      if (n != null) out.add(n);
      if (out.length >= max) break;
    }
    return out;
  }

  void _recordRecent(String pageId) {
    final k = _pageKey(pageId);
    _recents.remove(k);
    _recents.insert(0, k);
    if (_recents.length > _recentsCap) {
      _recents.removeRange(_recentsCap, _recents.length);
    }
    _repo.setSetting('recentPages', _recents);
  }

  /// Sort a section's pages by title or by last edit (ORG-8).
  ///
  /// Subpages move WITH their parent: a page carries the deeper-level pages
  /// that follow it, or sorting would silently reparent every subpage in the
  /// section to whatever landed above it.
  void sortSection(String sectionId, {required bool byTitle}) {
    final pages = pagesOf(sectionId);
    if (pages.length < 2) return;
    // Group each top-level page with its contiguous deeper-level run.
    final groups = <List<TreeNode>>[];
    for (final p in pages) {
      if (p.level == 0 || groups.isEmpty) {
        groups.add([p]);
      } else {
        groups.last.add(p);
      }
    }
    groups.sort(
      (a, b) => byTitle
          ? a.first.title.toLowerCase().compareTo(b.first.title.toLowerCase())
          : b.first.updatedAt.compareTo(a.first.updatedAt),
    );
    var seq = nowMs();
    for (final g in groups) {
      for (final n in g) {
        n.position = 'a${(seq++).toString().padLeft(15, '0')}';
        _putNode(notebookId!, n);
      }
    }
    reloadNodes();
    notifyListeners();
  }

  /// English uses the bundled word list; German uses local Windows services.
  bool spellCheckEnabled = true;
  String interfaceLanguage = 'en';
  String writingLanguage = 'en-US';
  bool handwritingSpellCheck = true;

  bool get ankiShortcutEnabled =>
      _repo.getSetting('ankiShortcutEnabled') == true;
  String? get ankiExecutablePath =>
      _repo.getSetting('ankiExecutablePath') as String?;

  void setAnkiShortcutEnabled(bool value) {
    _repo.setSetting('ankiShortcutEnabled', value);
    notifyListeners();
  }

  void setAnkiExecutablePath(String? path) {
    final value = path?.trim();
    _repo.setSetting(
        'ankiExecutablePath', value == null || value.isEmpty ? null : value);
    notifyListeners();
  }

  /// Dismissed handwriting-recognition warnings. The key includes the page,
  /// recognised word and its local bounds, so ignoring one occurrence does not
  /// hide every identical word in every notebook.
  final Set<String> ignoredHandwritingMarks = {};

  bool isHandwritingMarkIgnored(String key) =>
      ignoredHandwritingMarks.contains(key);

  void ignoreHandwritingMark(String key) {
    if (!ignoredHandwritingMarks.add(key)) return;
    // Retain a generous but finite history; this is UI preference data, never
    // part of the notebook document itself.
    while (ignoredHandwritingMarks.length > 1000) {
      ignoredHandwritingMarks.remove(ignoredHandwritingMarks.first);
    }
    _repo.setSetting(
      'ignoredHandwritingMarks',
      ignoredHandwritingMarks.toList(),
    );
    notifyListeners();
  }

  String? writingServiceProblem;

  void setInterfaceLanguage(String value) {
    if (value != 'en' && value != 'de') return;
    interfaceLanguage = value;
    _repo.setSetting('interfaceLanguage', value);
    notifyListeners();
  }

  void setWritingLanguage(String value) {
    if (value != 'en-US' && value != 'de-DE') return;
    writingLanguage = value;
    writingServiceProblem = null;
    _repo.setSetting('writingLanguage', value);
    docRevision++;
    notifyListeners();
  }

  void setHandwritingSpellCheck(bool value) {
    handwritingSpellCheck = value;
    _repo.setSetting('handwritingSpellCheck', value);
    notifyListeners();
  }

  /// Degrees or radians, for every equation in the app.
  ///
  /// Degrees by default, which is what a school calculator does and what the
  /// year-10 bar asks for; a university student flips it once and it stays
  /// flipped. In DEGREES an angle carrying a π is still read as radians,
  /// because nobody writes `sin(π/6)` meaning degrees — see [AngleMode].
  AngleMode get angleMode => mathAngleMode;

  void setAngleMode(AngleMode v) {
    if (v == mathAngleMode) return;
    final was = mathAngleMode;
    mathAngleMode = v;
    _repo.setSetting('angleMode', v == AngleMode.radians ? 'rad' : 'deg');
    // **Every answer on the page is worked out again.**
    //
    // It used to leave them alone, and the owner accepted that — but what it
    // actually leaves behind is a number that is simply WRONG, in a grey
    // panel that says the app worked it out, directly under a button that now
    // says the opposite. `sin(30)= ` answers 0.5; press RAD and the panel
    // still reads 0.5, which is the degrees answer.
    //
    // Pressing the button IS the command, so this is not the app changing
    // something nobody asked for. Only answers whose value actually depends
    // on the mode move, it takes one undo step, and answers on other pages
    // are re-worked when those pages are opened and edited.
    reworkAnswersForAngleMode(writtenIn: was);
    // **And the equation being written, which that pass deliberately skips.**
    //
    // Its editor holds the live tree and would write the old one back on the
    // next keystroke; a paragraph treats a rewrite from outside as a foreign
    // edit and closes the equation. So the open one is asked to do its own —
    // and, for one inside a sentence, its neighbours in the same paragraph,
    // which nothing else can reach. Here rather than in the row that has the
    // button, so every route to this method behaves the same.
    activeMath?.rework?.call(was);
    // **A plain notify, and deliberately NOT `docRevision++`.**
    //
    // `docRevision` means "the stored content was replaced wholesale" —
    // a page load or an undo. Every block on the canvas is keyed
    // by it (`page_canvas.dart`), so bumping it destroys and rebuilds the
    // whole page. Pressing DEG while writing an equation therefore disposed
    // the equation editor mid-edit and took the caret with it: the owner,
    // *"it kicks me out of the equation and i have to click on it again to
    // start editing again"*. A notify redraws the page perfectly well, and
    // the equation you are writing keeps the keyboard.
    //
    // Proved by `math_angle_focus_test.dart`: with the bump in place, an
    // equation being written INSIDE A SENTENCE is torn out from under the
    // student — the paragraph's editing session goes with the block, so the
    // equation, the caret and the next keystroke are all lost. A block
    // equation survived only because it re-autofocuses on the way back,
    // which is luck rather than design.
    notifyListeners();
  }

  /// Work out every answer on this page again. Returns how many changed.
  ///
  /// Deliberately a whole-page pass at the moment of the press rather than a
  /// check on every repaint: it is one command, it is undoable, and the
  /// alternative is asking the calculator the same question of every answer
  /// sixty times a second for ever.
  ///
  /// [writtenIn] is the mode the answers ON THE PAGE were worked out in.
  /// It is needed to READ them: an answer showing three figures is recognised
  /// by asking the working what it comes to and seeing which rounding matches,
  /// and asking in the new mode gets a different number, so nothing matches
  /// and the student's choice of figures is thrown away by the very pass that
  /// exists to keep the page honest.
  int reworkAnswersForAngleMode({AngleMode? writtenIn}) {
    var changed = 0;
    var undone = false;
    void once() {
      if (undone) return;
      pushUndo();
      undone = true;
    }

    for (final b in blocks) {
      // **Never the block being edited.** Its editor holds the live tree and
      // would write the old one back on the next keystroke; a text block's
      // session treats a rewrite from outside as a foreign edit and closes
      // the equation. The open equation refreshes ITSELF, through
      // `ActiveMathEditor.refresh` — which is also what keeps the caret,
      // the whole point of not bumping `docRevision` here.
      if (b.id == editingBlockId) continue;
      if (b.type == BlockType.math) {
        final latex = b.content['latex'] as String? ?? '';
        if (!latex.contains('boxed')) continue;
        final e = _openWritten(latex, writtenIn);
        if (e == null) continue;
        if (!e.refreshAnswers()) continue;
        once();
        b.content['latex'] = e.latex;
        b.content.remove('linearSource');
        b.updatedAt = nowMs();
        changed++;
      } else if (b.type == BlockType.text) {
        final text = b.content['text'] as String? ?? '';
        if (!text.contains('boxed')) continue;
        var out = text;
        // Backwards, so an earlier run's offsets are still good after a
        // later one has been rewritten.
        for (final run in mathRunsIn(text).toList().reversed) {
          if (!run.latex.contains('boxed')) continue;
          final e = _openWritten(run.latex, writtenIn);
          if (e == null || !e.refreshAnswers()) continue;
          out = replaceMathRun(out, run, e.latex);
          changed++;
        }
        if (out == text) continue;
        once();
        b.content['text'] = out;
        b.updatedAt = nowMs();
      }
    }
    if (changed > 0) {
      markDirty();
      // NO `docRevision++`: every block widget is keyed by it, so bumping it
      // would destroy the equation being written and take the caret with it
      // — the defect this release opened with. A notify is enough, because
      // every block reads its content on every build.
      notifyListeners();
    }
    return changed;
  }

  /// Read an equation as it stood in [writtenIn], then hand it back.
  ///
  /// `MathEditor.open` works out how many figures each answer is showing by
  /// evaluating the working, so it has to evaluate it in the mode the digits
  /// were written in. Swapped and restored on the spot, with nothing awaited
  /// in between.
  MathEditor? _openWritten(String latex, AngleMode? writtenIn) {
    if (writtenIn == null) return MathEditor.open(latex);
    final now = mathAngleMode;
    mathAngleMode = writtenIn;
    try {
      return MathEditor.open(latex);
    } finally {
      mathAngleMode = now;
    }
  }

  void setSpellCheck(bool v) {
    spellCheckEnabled = v;
    _repo.setSetting('spellCheck', v);
    // Re-open the editing session so the change is visible immediately rather
    // than at the next block.
    docRevision++;
    notifyListeners();
  }

  /// Eraser behaviour is stored with the other drawing preferences.
  EraserMode eraserMode = EraserMode.area;

  /// Diameter in logical screen pixels (independent of zoom and pen width).
  double eraserSize = 20;

  void setEraserSize(double value) {
    if (!value.isFinite) return;
    eraserSize = value.clamp(4.0, 80.0);
    _repo.setSetting('eraserSize', eraserSize);
    notifyListeners();
  }

  /// A real ink contact requests Draw once, without stealing tabs on hover.
  int drawTabRequest = 0;
  void requestDrawTab() {
    drawTabRequest++;
    notifyListeners();
  }

  void setEraserMode(EraserMode m) {
    if (eraserMode == m) return;
    eraserMode = m;
    _repo.setSetting('eraserMode', m.name);
    notifyListeners();
  }

  /// Whether a finger draws (INK-1). Until 2026-07-27 every touch was routed to
  /// pan unconditionally, which meant ink was unreachable on a touch-only
  /// tablet — palm rejection implemented as "fingers never draw" rather than
  /// "fingers don't draw *while a pen is in use*".
  TouchDrawing touchDrawing = TouchDrawing.auto;

  void setTouchDrawing(TouchDrawing v) {
    touchDrawing = v;
    _repo.setSetting('touchDrawing', v.name);
    notifyListeners();
  }

  // Retained for older plug-ins and tests which assign this setting directly.
  // Hover no longer reads it: switching to ink is now strictly contact-based.
  bool penProximitySwitch = false;

  bool startMaximized = true;

  void setStartMaximized(bool value) {
    startMaximized = value;
    _repo.setSetting('startMaximized', value);
    notifyListeners();
  }

  /// True when the selection is ink and can therefore be recoloured (INK-7).
  bool get hasInkSelection =>
      blocks.any((b) => selectedIds.contains(b.id) && b.type == BlockType.ink);

  /// Recolour every stroke in the selected ink blocks.
  ///
  /// Completes the lasso story: gathering, moving and deleting worked, but a
  /// lassoed diagram couldn't be changed — and recolouring after the fact is
  /// most of why you'd lasso a diagram at all. Resizing came free once blocks
  /// gained ink-scaling handles.
  void recolorSelectedInk(String hex) {
    if (!hasInkSelection) return;
    pushUndo();
    for (final b in blocks) {
      if (!selectedIds.contains(b.id) || b.type != BlockType.ink) continue;
      final strokes = b.content['strokes'];
      if (strokes is! List) continue;
      for (final raw in strokes) {
        if (raw is Map) raw['color'] = hex;
      }
      invalidateInkStorage(b);
      b.updatedAt = nowMs();
    }
    markDirty();
    docRevision++;
    notifyListeners();
  }

  /// Guides to draw while dragging (CANVAS-7), and the snap they imply.
  List<AlignGuide> alignGuides = const [];
  Offset _pendingSnap = Offset.zero;

  /// Recompute guides for the current selection against its neighbours.
  ///
  /// [scale] converts the fixed screen-pixel tolerance into page units, so the
  /// guide feels equally sticky at every zoom — a fixed page-unit threshold is
  /// unreachable zoomed out and glue-like zoomed in.
  void updateAlignGuides(double scale) {
    if (selectedIds.isEmpty || snapToGrid) {
      // Snap-to-grid already decides placement; two competing snaps fight.
      if (alignGuides.isNotEmpty) {
        alignGuides = const [];
        _pendingSnap = Offset.zero;
      }
      return;
    }
    final moving = _unionRect(selectedIds);
    if (moving == null) return;
    final others = [
      for (final b in blocks)
        if (!selectedIds.contains(b.id)) _rectOf(b),
    ];
    final r = findAlignment(moving, others, threshold: 7.0 / scale);
    alignGuides = r.guides;
    _pendingSnap = r.offset;
  }

  /// Apply the snap the guides promised, on drag end.
  ///
  /// Deliberately at the END rather than live: nudging mid-drag makes the
  /// block jitter against the pointer, which reads as the app fighting you.
  void applyAlignSnap() {
    if (_pendingSnap != Offset.zero) {
      moveSelectedBy(_pendingSnap.dx, _pendingSnap.dy);
      _pendingSnap = Offset.zero;
    }
    alignGuides = const [];
  }

  Rect _rectOf(Block b) =>
      Rect.fromLTWH(b.x, b.y, b.w, b.h ?? renderSizes[b.id]?.height ?? 60);

  Rect? _unionRect(Set<String> ids) {
    Rect? out;
    for (final b in blocks.where((b) => ids.contains(b.id))) {
      final r = _rectOf(b);
      out = out == null ? r : out.expandToInclude(r);
    }
    return out;
  }

  // True while a block is being dragged — the canvas shows a faint grid then.
  bool draggingBlock = false;
  void setDragging(bool v) {
    if (draggingBlock == v) return;
    draggingBlock = v;
    notifyListeners();
  }

  // Collapse state (OneNote-style hierarchy folding). Sections no longer
  // collapse — the stacked navigator shows one section's pages at a time, so
  // the old per-section collapse set had no readers once the tree layout went.
  final Set<String> collapsedPages = {};

  void togglePageCollapsed(String id) {
    collapsedPages.contains(id)
        ? collapsedPages.remove(id)
        : collapsedPages.add(id);
    navRevision++; // lengths can alias (one collapse + one expand); this can't
    notifyListeners();
  }

  // ── UI chrome state (Phase 2) ──────────────────────────────────────────

  ThemeMode themeMode = ThemeMode.system;
  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _repo.setSetting('themeMode', m.name); // persist (§7a.5)
    notifyListeners();
  }

  /// The text/code editor currently mounted & editing, registered by its view
  /// so command-bar formatting can act on the live selection.
  ({
    TextEditingController controller,
    Block block,
    String contentKey
  })? activeEditor;

  /// The same editor as [activeEditor], through the engine seam.
  ///
  /// The canvas needs two things a bare controller can't give it: where a
  /// screen point lands in the text, and a way to extend the selection. Both
  /// live on the session, so the pointer handling in `block_view.dart` can
  /// place the caret where you clicked and drag-select from the first gesture
  /// without knowing how the engine lays text out.
  OnoteEditSession? activeSession;

  void setActiveEditor(
    TextEditingController c,
    Block b,
    String key, {
    OnoteEditSession? session,
  }) {
    activeEditor = (controller: c, block: b, contentKey: key);
    if (session != null) activeSession = session;
    // Watch the caret so the toolbar can light up. Nothing rebuilt when the
    // selection moved, so any caret-derived state was stale by construction —
    // which is why there was never any point computing it before.
    if (!identical(c, _watchedEditor)) {
      _watchedEditor?.removeListener(_onEditorChanged);
      _watchedEditor = c..addListener(_onEditorChanged);
      _lastMarks = null;
    }
    // No notify: called during build; enablement rides the select() notify.
  }

  TextEditingController? _watchedEditor;
  Set<MdInline>? _lastMarks;

  /// Notify ONLY when the set of active marks actually changed. A rebuild of
  /// the shell per keystroke would be far more expensive than the one-line
  /// scan that decides whether it is needed.
  void _onEditorChanged() {
    final now = marksAtCaret();
    final was = _lastMarks;
    if (was != null && was.length == now.length && was.containsAll(now)) return;
    _lastMarks = now;
    // Post-frame: this fires from inside the controller's own notification,
    // which can land during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      notifyListeners();
    });
  }

  void clearActiveEditor(String blockId) {
    if (activeEditor?.block.id == blockId) {
      activeEditor = null;
      activeSession = null;
      _watchedEditor?.removeListener(_onEditorChanged);
      _watchedEditor = null;
      _lastMarks = null;
    }
  }

  /// Give the registration back when [c] is about to be disposed.
  ///
  /// **Keyed on the controller, not the block id**, and that difference is the
  /// bug it fixes. [clearActiveEditor] is called from the editing → not-editing
  /// transition in `build`, where the block id is the right question. A page or
  /// notebook switch never reaches that transition: `BlockView` is keyed
  /// `'<id>#<docRevision>'` and `selectPage` bumps `docRevision`, so every
  /// block's element is thrown away wholesale and only `State.dispose` runs.
  /// The session — and the `TextEditingController` inside it — was disposed
  /// there while `activeEditor` and `_watchedEditor` went on pointing at it.
  ///
  /// A disposed controller reads fine ([marksAtCaret] only looks at `value`),
  /// so nothing complained; the WRITERS are where it bites. Insert ▸ Image and
  /// the card button gate on `activeEditor != null` alone, so either one,
  /// pressed after switching notebooks and before clicking into a new box,
  /// called `notifyListeners` on a dead controller: "A TextEditingController
  /// was used after being disposed".
  ///
  /// Identity also settles the ordering. Flutter builds the new page's editor
  /// (which registers) BEFORE it disposes the old page's, so by the time the
  /// old one lets go the registration has already moved on — matching on the
  /// block id would have been checking the wrong question, and matching on
  /// "something is registered" would clear the live editor. `identical` cannot
  /// be wrong either way.
  void releaseEditor(TextEditingController c) {
    if (identical(_watchedEditor, c)) {
      // Safe on a disposed notifier: `removeListener` is explicitly allowed
      // after dispose, precisely so a listener's owner can outlive it.
      c.removeListener(_onEditorChanged);
      _watchedEditor = null;
      _lastMarks = null;
    }
    if (identical(activeEditor?.controller, c)) {
      activeEditor = null;
      activeSession = null;
    }
  }

  /// Where the click that is about to open an editor landed. Consumed once by
  /// the session on its first build.
  Offset? pendingCaretGlobal;

  void _commitActiveEditor() {
    final ae = activeEditor;
    if (ae == null) return;
    ae.block.content[ae.contentKey] = ae.controller.text;
    ae.block.updatedAt = nowMs();
    markDirty();
  }

  /// True when the block being edited is a text box (enables the Home-tab
  /// formatting buttons immediately, independent of child build order).
  bool get canFormatText {
    final id = editingBlockId;
    if (id == null) return false;
    return blocks.where((b) => b.id == id).firstOrNull?.type == BlockType.text;
  }

  /// Insert text at the caret of the active editor (e.g. a page link inline).
  void insertTextAtActiveCursor(String s) {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    final at = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    pushUndo();
    c.text = c.text.replaceRange(at, end, s);
    c.selection = TextSelection.collapsed(offset: at + s.length);
    _commitActiveEditor();
    notifyListeners();
  }

  // ── Text colour (inline {{#RRGGBB text}}) ──────────────────────────────

  String lastColor = 'C63838'; // last-used ink colour; default red
  final List<String> customColors = []; // recent/custom, persisted
  final Map<String, String> notebookColors = {};

  String? notebookColor(String notebookId) => notebookColors[notebookId];

  void setNotebookColor(String notebookId, String? color) {
    if (color == null) {
      notebookColors.remove(notebookId);
    } else {
      notebookColors[notebookId] = color;
    }
    _repo.setSetting('notebookColors', notebookColors);
    notifyListeners();
  }

  void rememberCustomColor(String hex) {
    customColors.remove(hex);
    customColors.insert(0, hex);
    if (customColors.length > 12) customColors.removeLast();
    _repo.setSetting('customColors', customColors);
    notifyListeners();
  }

  static final _colorOpenRe = RegExp(
    r'\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) $',
  );
  // Matches a whole wrapper as the entire selection: {{#hex inner}}.
  static final _colorWholeRe = RegExp(
    r'^\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) (.*)\}\}$',
    dotAll: true,
  );

  void applyTextColor(String hex) {
    final ae = activeEditor;
    if (ae == null) return;
    lastColor = hex;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) {
      notifyListeners();
      return;
    }
    final t = c.text;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);

    // Re-colour, don't nest (user report): if the selection is already the
    // inner content of an existing {{#hex …}} wrapper, or the selection spans
    // a whole wrapper, replace the existing colour in place.

    // Case A: selection is the INNER content of an existing wrapper —
    //   …{{#oldhex |selected|}}…  → swap oldhex for the new hex.
    final openBefore = _colorOpenRe.firstMatch(t.substring(0, s));
    if (openBefore != null &&
        e + 2 <= t.length &&
        t.substring(e, e + 2) == '}}') {
      pushUndo();
      final openLen = openBefore.group(0)!.length;
      const newOpenPrefix = '{{#';
      final newOpen = '$newOpenPrefix$hex ';
      c.text = t.replaceRange(s - openLen, s, newOpen);
      final shift = newOpen.length - openLen;
      c.selection = TextSelection(
        baseOffset: s + shift,
        extentOffset: e + shift,
      );
      _commitActiveEditor();
      notifyListeners();
      return;
    }

    // Case B: the selection spans an ENTIRE wrapper — {{#oldhex inner}} —
    // e.g. selecting the coloured word including its markers. Rewrite it.
    final whole = _colorWholeRe.firstMatch(t.substring(s, e));
    if (whole != null) {
      pushUndo();
      final inner = whole.group(2)!;
      c.text = t.replaceRange(s, e, '{{#$hex $inner}}');
      final openLen = hex.length + 4; // '{{#' + hex + ' '
      c.selection = TextSelection(
        baseOffset: s + openLen,
        extentOffset: s + openLen + inner.length,
      );
      _commitActiveEditor();
      notifyListeners();
      return;
    }

    // Case C: fresh selection — wrap it.
    pushUndo();
    final selText = t.substring(s, e);
    c.text = t.replaceRange(s, e, '{{#$hex $selText}}');
    final openLen = hex.length + 4; // '{{#' + hex + ' '
    c.selection = TextSelection(
      baseOffset: s + openLen,
      extentOffset: s + openLen + selText.length,
    );
    _commitActiveEditor();
    notifyListeners();
  }

  /// The "flick" hotkey: colour the selection with the last colour, or strip
  /// the colour if it's already coloured (back to default).
  void toggleTextColor() {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);
    final t = c.text;
    final m = _colorOpenRe.firstMatch(t.substring(0, s));
    if (m != null && e + 2 <= t.length && t.substring(e, e + 2) == '}}') {
      pushUndo();
      final openLen = m.group(0)!.length;
      c.text = t.replaceRange(e, e + 2, '').replaceRange(s - openLen, s, '');
      c.selection = TextSelection(
        baseOffset: s - openLen,
        extentOffset: e - openLen,
      );
      _commitActiveEditor();
      notifyListeners();
    } else {
      applyTextColor(lastColor);
    }
  }

  // ── Text-box font family (box-level) ───────────────────────────────────

  void setActiveBlockFont(String font) {
    final id = editingBlockId;
    if (id == null) return;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    pushUndo();
    // Any system family name; '' or 'sans' = default. Legacy 'serif'/'mono'
    // map in the view.
    if (font.isEmpty || font == 'sans') {
      b.content.remove('font');
    } else {
      b.content['font'] = font;
    }
    updateBlock(b);
  }

  /// The font size of the text block being edited, in logical px, or null when
  /// it uses the default. Imported OneNote boxes carry an explicit size.
  double? get activeBlockFontSize {
    final id = editingBlockId;
    if (id == null) return null;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return null;
    return (b.content['fontSize'] as num?)?.toDouble();
  }

  /// Set (or clear, with null) the font size of the text block being edited
  /// (TEXT-1). Sizes are offered in points and stored in the page's 120-dpi px.
  void setActiveBlockFontSize(double? pt) {
    final id = editingBlockId;
    if (id == null) return;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    pushUndo();
    if (pt == null) {
      b.content.remove('fontSize');
      b.content.remove('lineHeight');
    } else {
      b.content['fontSize'] = pt * 120.0 / 72.0;
      // Keep OneNote's pitch so a resized box still lines up with its
      // neighbours (see `oneNoteLineHeight`).
      b.content['lineHeight'] = oneNoteLineHeight;
    }
    updateBlock(b);
  }

  // ── New-page title flow ────────────────────────────────────────────────

  String? pendingTitleEdit; // page whose title should auto-focus on show

  /// Enter pressed in the title → drop into the first body text box.
  void startBodyFromTitle() {
    final pos = smartTextPosition(const Offset(pageLeftMargin, contentTop));
    final b = addBlock(
      Block(
        type: BlockType.text,
        x: pos.dx,
        y: pos.dy,
        w: 320,
        content: {'text': ''},
      ),
    );
    select(b.id, edit: true);
  }

  /// The word surrounding [at], or null when the caret is not in one.
  ///
  /// "Word" is deliberately generous — letters, digits, apostrophes and
  /// hyphens — so `don't` and `well-known` bold whole rather than in pieces.
  static ({int start, int end})? _wordAt(String t, int at) {
    // Apostrophes are in (so `don't` bolds whole) but hyphens are NOT: with
    // the caret at the start of `- item`, a hyphen-inclusive word would
    // reach back and bold the bullet marker itself.
    bool isWord(int i) =>
        i >= 0 && i < t.length && RegExp(r"[\w']").hasMatch(t[i]);
    var s = at, e = at;
    while (isWord(s - 1)) {
      s--;
    }
    while (isWord(e)) {
      e++;
    }
    return s == e ? null : (start: s, end: e);
  }

  /// Toggle-wrap the live selection with markers (Ctrl+B/I, command bar).
  ///
  /// Three behaviours, and the first two are the reported bug:
  ///
  /// * **A caret with no selection formats the WORD it sits in.** It used to
  ///   insert a bare `****` at the caret — which no renderer matches, so the
  ///   asterisks stayed visible in the note forever, and one Backspace ate a
  ///   single marker and left `***` behind.
  /// * **Toggling off works from INSIDE a run**, not only when the selection
  ///   exactly equals it. Before, a caret inside bold text and Ctrl+B nested
  ///   a second empty pair and everything typed after came out un-bold.
  /// * A code cell is left alone: Markdown markers are not source code.
  void wrapSelection(String mark, [String? closeMark]) {
    final ae = activeEditor;
    if (ae == null) return;
    // `**` means multiplication in a code cell, not bold. This used to inject
    // literal Markdown into somebody's source.
    if (ae.block.type != BlockType.text) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    final close = closeMark ?? mark;
    final t = c.text;
    var s = math.min(sel.baseOffset, sel.extentOffset);
    var e = math.max(sel.baseOffset, sel.extentOffset);

    if (s == e) {
      // Ask about the CARET first, before expanding to a word. `_` is a word
      // character, so the word around the caret in `__bold__` is the whole
      // thing INCLUDING its markers — which no longer sits inside the run,
      // so the toggle missed and wrapped it again as `**__bold__**`.
      final atCaret = _runAround(t, s, s, mark);
      if (atCaret != null) {
        pushUndo();
        final inner = t.substring(atCaret.open + atCaret.strip, atCaret.close);
        c.value = TextEditingValue(
          text: t.replaceRange(
            atCaret.open,
            atCaret.close + atCaret.strip,
            inner,
          ),
          selection: TextSelection.collapsed(
            offset: (s - atCaret.strip).clamp(0, t.length),
          ),
          composing: TextRange.empty,
        );
        _commitActiveEditor();
        notifyListeners();
        return;
      }
      final w = _wordAt(t, s);
      // Nothing to format and nothing to un-format: better to do nothing
      // than to write markers into the file and hope the user types.
      if (w == null) return;
      s = w.start;
      e = w.end;
    } else {
      // Shrink the selection off its own whitespace and newlines. A marker
      // may not sit against a space (that is the flanking rule that keeps
      // `2 * 3 * 4` literal), and the grammar is line-based, so wrapping
      // " word " or a selection spanning two lines would emit markers no
      // renderer can ever match — permanently visible asterisks, which is
      // the bug this whole command was rewritten to stop producing.
      while (s < e && RegExp(r'\s').hasMatch(t[s])) {
        s++;
      }
      while (e > s && RegExp(r'\s').hasMatch(t[e - 1])) {
        e--;
      }
      final nl = t.substring(s, e).indexOf('\n');
      if (nl >= 0) {
        // Multi-line: format each line's own text, so every marker pair
        // opens and closes on one line.
        _wrapEachLine(c, s, e, mark, close);
        return;
      }
      if (s == e) return;
    }

    // Sub and super are mutually exclusive on the same text. Nesting them
    // would emit `~^x^~`, which the grammar reads as neither (the inner run
    // is never re-scanned), so the markers would be visible forever — the
    // same failure the whole command was rewritten to stop producing.
    // Applying one over the other therefore SWAPS the run's markers, which is
    // also what a student means by "no, make it the other one".
    final opposite = _oppositeMark[mark];
    if (opposite != null) {
      final other = _runAround(t, s, e, opposite);
      if (other != null) {
        pushUndo();
        final inner = t.substring(other.open + other.strip, other.close);
        c.value = TextEditingValue(
          text: t.replaceRange(
            other.open,
            other.close + other.strip,
            '$mark$inner$close',
          ),
          selection: TextSelection(
            baseOffset: other.open + mark.length,
            extentOffset: other.open + mark.length + inner.length,
          ),
          composing: TextRange.empty,
        );
        _commitActiveEditor();
        notifyListeners();
        return;
      }
    }

    pushUndo();
    // Ask the GRAMMAR what encloses this range rather than searching for the
    // marker characters. `*` is a prefix of `**`, so a plain string search
    // found the inner asterisk of a bold run and "un-italicised" it — the
    // caret inside `**word**` plus Ctrl+I produced `*word*`.
    final run = _runAround(t, s, e, mark);
    if (run != null) {
      final inner = t.substring(run.open + run.strip, run.close);
      c.value = TextEditingValue(
        text: t.replaceRange(run.open, run.close + run.strip, inner),
        selection: TextSelection(
          baseOffset: (s - run.strip).clamp(0, t.length),
          extentOffset: (e - run.strip).clamp(0, t.length),
        ),
        composing: TextRange.empty,
      );
    } else {
      final wrapped = _wrapRun(t.substring(s, e), mark, close);
      c.value = TextEditingValue(
        text: t.replaceRange(s, e, wrapped),
        selection: TextSelection(
          baseOffset: s + mark.length,
          extentOffset: s + wrapped.length - close.length,
        ),
        composing: TextRange.empty,
      );
    }
    _commitActiveEditor();
    notifyListeners();
  }

  /// Wrap each line of a multi-line selection separately, skipping blanks
  /// and keeping each line's own leading/trailing space outside the markers.
  void _wrapEachLine(
    TextEditingController c,
    int s,
    int e,
    String mark,
    String close,
  ) {
    final t = c.text;
    final region = t.substring(s, e);
    final out = <String>[];
    for (final line in region.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        out.add(line);
        continue;
      }
      final lead = line.substring(0, line.indexOf(trimmed[0]));
      final tail = line.substring(lead.length + trimmed.length);
      out.add('$lead${_wrapRun(trimmed, mark, close)}$tail');
    }
    final next = out.join('\n');
    c.value = TextEditingValue(
      text: t.replaceRange(s, e, next),
      selection: TextSelection(baseOffset: s, extentOffset: s + next.length),
      composing: TextRange.empty,
    );
    _commitActiveEditor();
    notifyListeners();
  }

  static const _markKinds = <String, MdInline>{
    '**': MdInline.bold,
    '*': MdInline.italic,
    '++': MdInline.underline,
    '~~': MdInline.strike,
    '`': MdInline.code,
    '==': MdInline.highlight,
    '~': MdInline.subscript,
    '^': MdInline.superscript,
  };

  /// The mark that must come OFF when this one goes on. Only sub/superscript
  /// have one: nothing else in the grammar is mutually exclusive.
  static const _oppositeMark = <String, String>{'~': '^', '^': '~'};

  /// Marks whose grammar forbids whitespace between the markers — see the
  /// long note on `_sub`/`_sup` in markdown/md_syntax.dart.
  static const _noSpaceMarks = <String>{'~', '^'};

  /// Wrap [s] in [mark]…[close], one pair per WORD when the mark cannot span
  /// a space.
  ///
  /// Selecting two words and pressing Ctrl+= would otherwise write
  /// `~hello world~`, which no renderer matches — permanently visible tildes,
  /// exactly the bug class this command exists to avoid. `~hello~ ~world~`
  /// looks identical on the page and actually renders.
  static String _wrapRun(String s, String mark, String close) => _noSpaceMarks
          .contains(mark)
      ? s.replaceAllMapped(RegExp(r'\S+'), (m) => '$mark${m.group(0)}$close')
      : '$mark$s$close';

  /// The run of [mark]'s kind enclosing [s]..[e], with how many characters to
  /// strip from each end to remove exactly that mark.
  ///
  /// Stripping is kind-aware: turning bold off inside `***word***` removes
  /// two asterisks a side and leaves `*word*` still italic, rather than
  /// removing the lot.
  static ({int open, int close, int strip})? _runAround(
    String t,
    int s,
    int e,
    String mark,
  ) {
    final want = _markKinds[mark];
    if (want == null) return null;
    final lineStart = lineStartOf(t, s);
    final lineEnd = math.max(lineStart, lineEndOf(t, e));
    var scan = t.substring(lineStart, lineEnd);
    var base = lineStart;
    var lo = s - lineStart, hi = e - lineStart;
    // DESCEND. `allMatches` only yields outermost runs, so with the caret in
    // the `it` of `**bold *it* end**` the italic was never seen: the bold run
    // was skipped for being the wrong kind and the toggle wrapped `it` a
    // second time, producing `**bold **it** end**` — which then re-reads as
    // one bold run with a literal `**` inside it and two visible asterisks.
    // Re-scanning the enclosing match's inner text finds the nested one.
    for (var depth = 0; depth < 8; depth++) {
      MdMatch? enclosing;
      RegExpMatch? enclosingMatch;
      for (final m in mdInlineRe.allMatches(scan)) {
        final c = classifyInline(m);
        final isBoth = c.kind == MdInline.boldItalic &&
            (want == MdInline.bold || want == MdInline.italic);
        final innerStart = m.start + c.openLen, innerEnd = m.end - c.closeLen;
        if (lo < innerStart || hi > innerEnd) continue;
        if (c.kind == want || isBoth) {
          // `***` minus bold is `*`; minus italic is `**`.
          final strip = isBoth ? (want == MdInline.bold ? 2 : 1) : c.openLen;
          return (
            open: base + m.start + (isBoth ? c.openLen - strip : 0),
            close: base + innerEnd,
            strip: strip,
          );
        }
        enclosing = c;
        enclosingMatch = m;
        break;
      }
      if (enclosing == null || enclosingMatch == null) return null;
      // Step inside it and look again.
      final innerStart = enclosingMatch.start + enclosing.openLen;
      base += innerStart;
      lo -= innerStart;
      hi -= innerStart;
      scan = enclosing.inner;
      if (lo < 0 || hi > scan.length) return null;
    }
    return null;
  }

  // ── Ctrl + a marker character ─────────────────────────────────────────────

  /// Which characters the marker chord accepts, and how far each one goes.
  ///
  /// The keys are the characters `cycleMarker` answers to; the value is every
  /// marker WIDTH the grammar will accept for that character, smallest first.
  ///
  /// It is MEASURED, not typed out. For every printable ASCII character we
  /// wrap a probe word in one to four copies and keep the widths that come
  /// back from [mdInlineRe] as a single run covering the whole string with
  /// markers exactly that wide. So the chord's alphabet and its ceiling come
  /// from the same grammar both renderers use, and a branch added to
  /// markdown/md_syntax.dart reaches this chord in the commit that adds it —
  /// which is the entire reason that file exists (it replaced two hand-kept
  /// copies of the grammar that had drifted apart in four places).
  ///
  /// What it measures today, and why each ladder stops where it does:
  ///
  /// * `*` → 1, 2, 3 — italic, bold, bold+italic. A fourth is refused because
  ///   `****x****` cannot match: `_bi`'s `(?![\s*])` sees a fourth asterisk
  ///   and fails at offset 0, so the leftmost match starts at offset 1 and
  ///   leaves a stray asterisk at each end. That is the product owner's own
  ///   "it won't accept the last one".
  /// * `_` → 1, 2 — the underscore spelling of italic and bold. No `___`
  ///   branch exists, and `_bU`'s `(?<![\w\\])` refuses to start on the
  ///   second underscore of a run.
  /// * `~` → 1, 2 — the interesting one: the ladder crosses TWO marks,
  ///   subscript then strikethrough. That is not a compromise, it is what
  ///   "add one more marker" literally does — `~x~` plus a tilde a side IS
  ///   `~~x~~`. A third is refused (`~~~x~~~` closes one tilde early).
  /// * `^` → 1 superscript, `` ` `` → 1 code, `$` → 1 inline maths. Each
  ///   caps at one because its inner class excludes its own marker.
  /// * `=` → 2 highlight and `+` → 2 underline: ladders that START at two,
  ///   because `=x=` and `+x+` are not marks at all. One press therefore has
  ///   to write both characters, or none.
  static final Map<String, List<int>> markerChordLadders = _measureLadders();

  static Map<String, List<int>> _measureLadders() {
    // One word character. Short enough that the match either covers the whole
    // probe or obviously does not, and word-shaped so the flanking guards
    // (`(?![\s*])`) and the no-whitespace rule on `~`/`^` are both satisfied —
    // a probe with a space in it would report `~` as having no ladder at all.
    const probe = 'x';
    final out = <String, List<int>>{};
    for (var code = 0x21; code <= 0x7e; code++) {
      final ch = String.fromCharCode(code);
      final widths = <int>[];
      // Four, so the width ABOVE the highest legal one is always tried: the
      // ceiling has to be observed failing, not assumed.
      for (var n = 1; n <= 4; n++) {
        final mark = ch * n;
        final s = '$mark$probe$mark';
        final m = mdInlineRe.firstMatch(s);
        // `firstMatch` is leftmost, so `m.start != 0` is exactly the
        // `****x****` failure — the grammar found emphasis, but one asterisk
        // in, with punctuation left over on both sides.
        if (m == null || m.start != 0 || m.end != s.length) continue;
        final c = classifyInline(m);
        // …and these three are the rest of the ceilings: `~~~x~~~` matches
        // `~~~x~~` so `m.end` is short, `` ``x`` `` closes on the second
        // backtick, and a link or colour match has mismatched marker widths.
        if (c.openLen == n && c.closeLen == n && c.inner == probe) {
          widths.add(n);
        }
      }
      if (widths.isNotEmpty) out[ch] = widths;
    }
    return out;
  }

  /// The outermost run around [s]..[e] whose markers are made of [ch], plus
  /// the TOTAL marker width of every enclosing run made of [ch].
  ///
  /// The total, and not just the outermost run's own width, is what makes the
  /// ladder safe. The caret inside the `it` of `**bold *it* end**` already
  /// carries three asterisks a side, and a fourth would write
  /// `**bold **it** end**` — which the grammar re-reads as one bold run with a
  /// literal `**` inside it, i.e. two asterisks the student can see and cannot
  /// get rid of. Counting three there is what refuses that press.
  ///
  /// Separate from [_runAround] on purpose: that one answers "is this exact
  /// MARK on", using the `_markKinds` table, and has no entry for `_` at all;
  /// this one answers "how many of this CHARACTER am I inside", which is the
  /// only question a ladder can be built from.
  static ({int start, int end, int openLen, int closeLen, int total})?
      _markerRunAround(String t, int s, int e, String ch) {
    final lineStart = lineStartOf(t, s);
    final lineEnd = math.max(lineStart, lineEndOf(t, e));
    var scan = t.substring(lineStart, lineEnd);
    var base = lineStart;
    var lo = s - lineStart, hi = e - lineStart;
    int? outStart, outEnd, outOpen, outClose;
    var total = 0;
    // Descend exactly as _runAround and marksAtCaret do: `allMatches` yields
    // only outermost runs, so a nested one is invisible without re-scanning
    // the enclosing match's inner text.
    for (var depth = 0; depth < 8; depth++) {
      MdMatch? enclosing;
      RegExpMatch? em;
      for (final m in mdInlineRe.allMatches(scan)) {
        final c = classifyInline(m);
        if (lo < m.start + c.openLen || hi > m.end - c.closeLen) continue;
        enclosing = c;
        em = m;
        break;
      }
      if (enclosing == null || em == null) break;
      final open = enclosing.openLen;
      // Symmetric markers only, and made of this character: a link's `](url)`
      // tail and a colour's `{{#rrggbb ` head are not ladders.
      if (open > 0 &&
          open == enclosing.closeLen &&
          scan.substring(em.start, em.start + open) == ch * open) {
        total += open;
        outStart ??= base + em.start;
        outEnd ??= base + em.end;
        outOpen ??= open;
        outClose ??= enclosing.closeLen;
      }
      final innerStart = em.start + open;
      base += innerStart;
      lo -= innerStart;
      hi -= innerStart;
      scan = enclosing.inner;
      if (lo < 0 || hi > scan.length) break;
    }
    if (outStart == null) return null;
    return (
      start: outStart,
      end: outEnd!,
      openLen: outOpen!,
      closeLen: outClose!,
      total: total,
    );
  }

  /// Ctrl + a Markdown marker character: wrap the word at the caret in that
  /// marker, and press it again to add a layer, as far as the grammar goes.
  ///
  /// Returns **false** when [ch] is not a marker character the grammar uses,
  /// which is how the shell knows to leave that keystroke completely alone.
  /// A chord that swallowed every Ctrl+punctuation would take Ctrl+letter
  /// accelerators and dead keys away from the field.
  ///
  /// The progression is deliberately NOT read from the text on screen: the
  /// markers are invisible in the editor, so "press again for bold" has to be
  /// decided from the grammar's own view of what encloses the caret, the same
  /// way [marksAtCaret] lights the toolbar.
  bool cycleMarker(String ch) {
    final ladder = markerChordLadders[ch];
    if (ladder == null) return false;
    final ae = activeEditor;
    // Recognised, but nowhere to put it. Still handled: the alternative is a
    // stray marker character landing in a code cell, where `**` is
    // multiplication and not bold — the same reason wrapSelection refuses.
    if (ae == null || ae.block.type != BlockType.text) return true;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid) return true;
    final t = c.text;
    final run = _markerRunAround(t, sel.start, sel.end, ch);
    final have = run?.total ?? 0;
    var next = -1;
    for (final w in ladder) {
      if (w > have) {
        next = w;
        break;
      }
    }
    // Top of the ladder: do nothing, and specifically do not write the
    // markers anyway. A marker pair no renderer matches is punctuation the
    // student can see and cannot delete in one press — the whole bug class
    // wrapSelection was rewritten to stop producing.
    if (next < 0) return true;
    if (run == null) {
      // Nothing on yet. Hand it to wrapSelection, which already owns
      // word-at-caret (apostrophes in, hyphens out), selection trimming, the
      // multi-line case, the per-word wrap for marks that cannot span a space
      // and the sub/superscript swap. A second copy of "which word is the
      // caret in" is precisely how this chord would drift away from Ctrl+B.
      wrapSelection(ch * next);
      return true;
    }
    pushUndo();
    final inner = t.substring(run.start + run.openLen, run.end - run.closeLen);
    final mark = ch * next;
    final text = t.replaceRange(run.start, run.end, '$mark$inner$mark');
    // The caret keeps its own character. Only the OPENING marker grew ahead of
    // it — the run encloses the selection, so the caret is always past that
    // marker and never inside it.
    final shift = next - run.openLen;
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: (sel.baseOffset + shift).clamp(0, text.length),
        extentOffset: (sel.extentOffset + shift).clamp(0, text.length),
      ),
      composing: TextRange.empty,
    );
    _commitActiveEditor();
    notifyListeners();
    return true;
  }

  /// Which inline marks apply at the caret — what lights the toolbar up.
  ///
  /// With markers collapsed to nothing, the buttons are the ONLY thing that
  /// can tell a student whether the next thing they type will be bold, which
  /// is why "just have it appear in the toolbar as on" is the whole ask.
  Set<MdInline> marksAtCaret() {
    final ae = activeEditor;
    if (ae == null || ae.block.type != BlockType.text) return const {};
    final sel = ae.controller.selection;
    if (!sel.isValid) return const {};
    final t = ae.controller.text;
    final lineStart =
        t.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0) + 1;
    var lineEnd = t.indexOf('\n', sel.end);
    if (lineEnd < 0) lineEnd = t.length;
    if (lineStart > lineEnd) return const {};
    var scan = t.substring(lineStart, lineEnd);
    var lo = sel.start - lineStart, hi = sel.end - lineStart;
    final out = <MdInline>{};
    // Descend, so a mark NESTED inside another still lights its button — the
    // italic in `**bold *it* end**` read as off the instant you applied it.
    for (var depth = 0; depth < 8; depth++) {
      MdMatch? inner;
      var innerAt = -1;
      for (final m in mdInlineRe.allMatches(scan)) {
        final c = classifyInline(m);
        final s0 = m.start + c.openLen, e0 = m.end - c.closeLen;
        if (lo < s0 || hi > e0) continue;
        out.add(c.kind);
        inner = c;
        innerAt = s0;
        break;
      }
      if (inner == null) break;
      lo -= innerAt;
      hi -= innerAt;
      scan = inner.inner;
      if (lo < 0 || hi > scan.length) break;
    }
    // Bold+italic lights BOTH buttons — it is both, and a student pressing
    // Ctrl+B on it expects the bold to come off.
    if (out.contains(MdInline.boldItalic)) {
      out
        ..add(MdInline.bold)
        ..add(MdInline.italic);
    }
    return out;
  }

  /// Turn the selected lines into a list of [kind], or back into prose.
  ///
  /// Routed through the list engine rather than pasting a literal prefix, so
  /// it keeps indentation (`  item` became `-   item` before, losing the
  /// level), swaps a marker instead of stacking one (the bullet button used
  /// to destroy a checkbox), numbers a new ordered list 1, 2, 3 instead of
  /// writing `1. ` onto every line, and leaves the caret with its words
  /// instead of teleporting it to the end of the region.
  void toggleList(ListKind kind) {
    final ae = activeEditor;
    if (ae == null || ae.block.type != BlockType.text) return;
    final c = ae.controller;
    if (!c.selection.isValid) return;
    pushUndo();
    c.value = toggleListOverSelection(c.value, kind);
    _commitActiveEditor();
    notifyListeners();
  }

  /// Toggle a line prefix (headings, quotes) on the selected lines.
  void toggleLinePrefix(String prefix, {bool exclusive = true}) {
    final ae = activeEditor;
    if (ae == null || ae.block.type != BlockType.text) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    pushUndo();
    final t = c.text;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);
    // `lineStartOf`, not a hand-rolled lastIndexOf: with the caret at offset
    // 0 of text beginning with a newline, the old arithmetic produced a start
    // AFTER the end and `substring` threw a RangeError on the spot.
    final lineStart = lineStartOf(t, s);
    final lineEnd = math.max(lineStart, lineEndOf(t, e));
    final region = t.substring(lineStart, lineEnd);
    final stripRe = exclusive
        ? RegExp(r'^(#{1,3} |- \[[ xX]\] |[-*] |\d+\. |> )')
        : RegExp('^${RegExp.escape(prefix)}');
    final lines = region.split('\n');
    final allHave = lines.every((l) => l.startsWith(prefix));
    final out = [
      for (final l in lines)
        allHave
            ? l.substring(prefix.length)
            : '$prefix${l.replaceFirst(stripRe, '')}',
    ].join('\n');
    c.text = t.replaceRange(lineStart, lineEnd, out);
    c.selection = TextSelection.collapsed(
      offset: math.min(lineStart + out.length, c.text.length),
    );
    _commitActiveEditor();
    notifyListeners();
  }

  // ── Block clipboard (internal, Ctrl+C/X/V when not typing) ────────────

  String? _blockClipboard;
  bool get canPasteBlocks => _blockClipboard != null;

  /// When the block clipboard was filled (ms since epoch), and what the
  /// SYSTEM clipboard's plain text was at that same moment. Together they
  /// let a canvas Ctrl+V answer "which clipboard is newer?" — the OS cannot
  /// be asked when its text arrived, but if at paste time it still holds the
  /// very text it held when the blocks were copied, that text is the OLDER
  /// of the two. Without this, cutting an equation block and pressing Ctrl+V
  /// resurrected the `$…$` its own Ctrl+C had left on the system clipboard
  /// earlier, instead of bringing back the block just cut.
  int _blockClipboardAt = 0;
  Future<String?>? _systemTextWhenCopied;

  /// Reads the system clipboard's plain text for the newer-clipboard check.
  /// A function field so tests can stand in a fake — the test harness has no
  /// real clipboard to read.
  @visibleForTesting
  Future<String?> Function() readSystemClipboardText = _systemPlainText;

  static Future<String?> _systemPlainText() async {
    // Defensive to the bone: this runs as a side effect of COPYING, and a
    // clipboard that cannot be read (a headless test, a platform channel not
    // yet up, another app holding the clipboard open on Windows) must never
    // turn Ctrl+C into an error. A null snapshot only means the
    // newer-clipboard check stands down and the old paste order applies.
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return null; // unsupported platform
      final reader = await clipboard.read();
      if (!reader.canProvide(Formats.plainText)) return null;
      return await reader.readValue(Formats.plainText);
    } catch (_) {
      return null;
    }
  }

  void copySelectedBlocks() {
    if (selectedIds.isEmpty) return;
    _blockClipboard = jsonEncode([
      for (final b in blocks.where((b) => selectedIds.contains(b.id)))
        b.toJson(),
    ]);
    _blockClipboardAt = DateTime.now().millisecondsSinceEpoch;
    // Kept as a Future rather than its value: Ctrl+X → Ctrl+V can land
    // before a clipboard read completes, and the paste decision awaits the
    // snapshot instead of racing it.
    _systemTextWhenCopied = readSystemClipboardText();
    notifyListeners();
  }

  /// Should a canvas Ctrl+V paste OUR copied blocks instead of the plain
  /// text the system clipboard offers right now?
  ///
  /// True only when the blocks are the newer of the two: the system still
  /// holds exactly what it held when the blocks were copied, so nothing has
  /// been copied since and a paste means the blocks. Text that differs from
  /// the snapshot must have arrived AFTER the copy, and fresh text — like a
  /// fresh screenshot — is what the person most recently chose, so it wins.
  Future<bool> blockClipboardIsNewer(String? systemTextNow) async {
    if (_blockClipboard == null || _blockClipboardAt == 0) return false;
    final snapshot = _systemTextWhenCopied;
    if (snapshot == null) return false;
    return systemTextNow == await snapshot;
  }

  void cutSelectedBlocks() {
    copySelectedBlocks();
    removeSelected();
  }

  void pasteBlocks({Offset? at}) {
    final raw = _blockClipboard;
    if (raw == null) return;
    pushUndo();
    final list = (jsonDecode(raw) as List)
        .map((j) => Block.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
    // Fresh identities (Data Model §2 rule 3), offset placement. The clone
    // goes THROUGH toJson/fromJson rather than a hand-picked constructor
    // call: rebuilding field-by-field silently dropped everything the
    // hand-picking forgot — rotation, z, frameId, and worst, `rawType` +
    // `unknownFields`, so pasting a block a NEWER build had written
    // destroyed its type on the spot (the exact loss Block.rawType exists
    // to prevent). The format is the copy, the way it is the API.
    final newIds = <String>[];
    final oldToNew = <String, String>{};
    for (final src in list) {
      final fresh = Block.fromJson({
        ...jsonDecode(jsonEncode(src.toJson())) as Map<String, dynamic>,
        'id': newId(),
      });
      fresh.x = at?.dx ?? src.x + 28;
      fresh.y = at?.dy ?? src.y + 28;
      if (fresh.type == BlockType.ink) {
        final dx = fresh.x - src.x, dy = fresh.y - src.y;
        for (final sj in (fresh.content['strokes'] as List)) {
          final m = (sj as Map);
          m['id'] = newId();
          m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
          m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
        }
        invalidateInkStorage(fresh);
      }
      clampBlockToPage(fresh);
      blocks.add(fresh);
      newIds.add(fresh.id);
      oldToNew[src.id] = fresh.id;
    }
    _relinkGraphs(oldToNew);
    selectMany(newIds);
    markDirty();
  }

  /// Keeps a graph or substitute block pointing at the equation it was made
  /// from when that equation is copied or cut.
  ///
  /// Two cases that want opposite answers. COPY an equation together with its
  /// graph and the copy must follow the COPY — otherwise changing the new
  /// numbers moves nothing, and changing the old ones quietly rewrites the new
  /// graph as well. CUT an equation and paste it back and its graph, still
  /// sitting on the page, is pointing at an id that no longer exists, so the
  /// paste adopts it. Copying a graph on its OWN is left alone on purpose:
  /// two windows onto one equation is a thing people do want. A substitute
  /// block follows the exact same rule — it is the graph's sibling for one
  /// point rather than a curve.
  void _relinkGraphs(Map<String, String> oldToNew) {
    if (oldToNew.isEmpty) return;
    final live = {for (final b in blocks) b.id};
    final pasted = oldToNew.values.toSet();
    for (final b in blocks) {
      if (b.type != BlockType.graph && b.type != BlockType.substitute) {
        continue;
      }
      final from = b.content['from'];
      if (from is! String) continue;
      final now = oldToNew[from];
      if (now == null) continue;
      if (pasted.contains(b.id) || !live.contains(from)) {
        b.content['from'] = now;
      }
    }
  }

  // ── Z-order (context menu) ─────────────────────────────────────────────

  void bringToFront(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null || blocks.isEmpty) return;
    pushUndo();
    b.z = blocks.map((e) => e.z).reduce(math.max) + 1;
    updateBlock(b);
  }

  void sendToBack(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null || blocks.isEmpty) return;
    pushUndo();
    b.z = blocks.map((e) => e.z).reduce(math.min) - 1;
    updateBlock(b);
  }

  // True while the in-page title field is focused (suppresses tool shortcuts).
  bool titleEditing = false;
  void setTitleEditing(bool v) {
    titleEditing = v;
    notifyListeners();
  }

  // Find (TEXT-7)
  bool findOpen = false;
  String findQuery = '';
  List<String> findMatches = [];
  int findIndex = 0;

  // Save & undo
  Timer? _saveDebounce;
  // A save can still be awaiting disk I/O when a widget test tears its app
  // down. The generation prevents that old save from arming a fresh workspace
  // debounce after the test has cancelled every timer it knew about.
  int _saveCancellationGeneration = 0;
  bool _dirty = false;
  int _dirtyRevision = 0;
  bool get hasUnsavedChanges => _dirty;
  final List<String> _undo = [];
  final List<String> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ── Document engine (Rust core, optional) ─────────────────────────────

  /// Human-readable label for the active engine, shown in the status bar
  /// ("Rust core vX" or "Dart engine").
  String get engineLabel => engine.label;

  /// Content hash of the most recently saved page (Rust core only); drives the
  /// status-bar chip. Null on the pure-Dart engine.
  String? get pageContentHash => engine.lastSavedHash;

  /// Bring the workspace up.
  ///
  /// [notebookPath], when given, is the notebook Openote was launched to open
  /// — `openote Physics.onote`, or a double-click on it in the file manager.
  /// It is resolved HERE, in front of the last-session restore, rather than by
  /// opening the last notebook and switching afterwards: switching would open
  /// two notebooks' worth of pages to show one of them, and the user would
  /// watch the wrong notebook appear first.
  Future<void> init({String? notebookPath}) async {
    // Session restore (§7a.5): theme, custom colours, per-page views, last loc.
    final tm = _repo.getSetting('themeMode') as String?;
    if (tm != null) themeMode = ThemeMode.values.asNameMap()[tm] ?? themeMode;
    final nsw = _repo.getSetting('navSectionsW');
    if (nsw is num) navSectionsW = nsw.toDouble().clamp(96, 220);
    final npw = _repo.getSetting('navPagesW');
    if (npw is num) navPagesW = npw.toDouble().clamp(140, 320);
    final nc = _repo.getSetting('navCollapsed');
    if (nc is bool) navCollapsed = nc;
    final slp = _repo.getSetting('sectionLastPage');
    if (slp is Map) {
      slp.forEach((k, v) {
        if (k is String && v is String) _sectionLastPage[k] = v;
      });
    }
    final sc = _repo.getSetting('spellCheck');
    if (sc is bool) spellCheckEnabled = sc;
    interfaceLanguage =
        _repo.getSetting('interfaceLanguage') == 'de' ? 'de' : 'en';
    writingLanguage =
        _repo.getSetting('writingLanguage') == 'de-DE' ? 'de-DE' : 'en-US';
    handwritingSpellCheck = _repo.getSetting('handwritingSpellCheck') != false;
    final ignoredMarks = _repo.getSetting('ignoredHandwritingMarks');
    if (ignoredMarks is List) {
      ignoredHandwritingMarks.addAll(ignoredMarks.whereType<String>());
    }
    final am = _repo.getSetting('angleMode');
    mathAngleMode = am == 'rad' ? AngleMode.radians : AngleMode.degrees;
    // Personal dictionary: workspace-scoped.
    final lw = _repo.getSetting('learnedWords');
    if (lw is List) loadLearnedWords(lw.cast<String>());
    onLearnedChanged = (words) => _repo.setSetting('learnedWords', words);
    study.load();
    planner.load();
    // Armed only once state is restored: the scheduler's first act is to catch
    // up on what came due while Openote was closed, and it can only know that
    // after the reminders have been read.
    planner.startScheduler();
    final fav = _repo.getSetting('favourites');
    if (fav is List) _favourites.addAll(fav.cast<String>());
    final rec = _repo.getSetting('recentPages');
    if (rec is List) _recents.addAll(rec.cast<String>());
    final td = _repo.getSetting('touchDrawing') as String?;
    if (td != null) {
      touchDrawing = TouchDrawing.values.asNameMap()[td] ?? touchDrawing;
    }
    final maximized = _repo.getSetting('startMaximized') ??
        _repo.getSetting('startFullscreen');
    if (maximized is bool) startMaximized = maximized;
    final eraser = _repo.getSetting('eraserSize');
    if (eraser is num && eraser.isFinite) {
      eraserSize = eraser.toDouble().clamp(4.0, 80.0);
    }
    final storedEraserMode = _repo.getSetting('eraserMode');
    if (storedEraserMode is String) {
      eraserMode =
          EraserMode.values.asNameMap()[storedEraserMode] ?? eraserMode;
    }
    final retention = _repo.getSetting('recycleRetentionDays');
    if (retention is num) {
      _recycleRetentionDays = retention.toInt().clamp(1, 3650).toInt();
    }
    final storedInkSizes = _repo.getSetting('inkToolSizes');
    if (storedInkSizes is Map) {
      for (final entry in storedInkSizes.entries) {
        if (entry.key is! String || entry.value is! num) continue;
        final storedTool = Tool.values.asNameMap()[entry.key];
        if (storedTool != null && _hasInkSize(storedTool)) {
          _inkToolSizes[storedTool] = entry.value.toDouble().clamp(
                minInkSizeFor(storedTool),
                maxInkSizeFor(storedTool),
              );
        }
      }
      if (_hasInkSize(tool)) penSize = inkSizeFor(tool);
    }
    // Detached: binding a port must never gate the app opening.
    unawaited(checkForAppUpdate());
    final cc = _repo.getSetting('customColors');
    if (cc is List) customColors.addAll(cc.cast<String>());
    void loadToolbarColors(String key, List<String> target) {
      final stored = _repo.getSetting(key);
      if (stored is! List) return;
      for (final value in stored) {
        if (value is String && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(value)) {
          target.add(value.toUpperCase());
        }
      }
    }

    loadToolbarColors('penToolbarColors', penToolbarColors);
    loadToolbarColors('highlighterToolbarColors', highlighterToolbarColors);
    for (final entry in {
      'hiddenPenPresets': hiddenPenPresets,
      'hiddenHighlighterPresets': hiddenHighlighterPresets
    }.entries) {
      final stored = _repo.getSetting(entry.key);
      if (stored is List)
        entry.value.addAll(stored.whereType<int>().where((i) => i >= 0));
    }
    final penColour = _repo.getSetting('penCustomColor');
    if (penColour is String &&
        RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(penColour)) {
      penCustomColor = penColour.toUpperCase();
    }
    final storedPenColor = _repo.getSetting('penColor');
    if (storedPenColor is int && storedPenColor >= 0) {
      penColor = storedPenColor;
    }
    final storedHighlighterColor = _repo.getSetting('highlighterColor');
    if (storedHighlighterColor is int && storedHighlighterColor >= 0) {
      highlighterColor = storedHighlighterColor;
    }
    final highlighterColour = _repo.getSetting('highlighterCustomColor');
    if (highlighterColour is String &&
        RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(highlighterColour)) {
      highlighterCustomColor = highlighterColour.toUpperCase();
    }
    final storedShapeRecognition = _repo.getSetting('shapeRecognition');
    if (storedShapeRecognition is bool) {
      shapeRecognition = storedShapeRecognition;
    }
    final notebookColourSettings = _repo.getSetting('notebookColors');
    if (notebookColourSettings is Map) {
      notebookColourSettings.forEach((key, value) {
        if (key is String && value is String) notebookColors[key] = value;
      });
    }
    final vm = _repo.getSetting('viewMemory');
    if (vm is Map) {
      vm.forEach((k, v) {
        if (v is List && v.length == 3) {
          _viewMemory[k as String] = [for (final x in v) (x as num).toDouble()];
        }
      });
    }
    final lastNb = _repo.getSetting('lastNotebook') as String?;
    // A workspace with no notebooks at all shouldn't happen — Repository.open
    // seeds one — but `first` on an empty list throws, which would turn an
    // odd registry into a startup that shows only an error screen. Making one
    // is always better than refusing to start.
    if (_repo.notebooks.isEmpty) await _repo.createNotebook('My notebook');
    // A notebook named on the command line beats the last session's.
    String? asked;
    if (notebookPath != null && notebookPath.trim().isNotEmpty) {
      // Through [_resolveHandedPath], NOT [_resolveNotebookFile]: cold start
      // must open exactly what a double-click into a running app would.
      // Feeding the raw path to the container sniff is how launching Openote
      // by double-clicking a notebook folder's pointer file — the association
      // Windows actually has — was told "That file isn't an Openote notebook"
      // about the user's own notebook, while a running app opened it fine.
      final resolved = await _resolveHandedPath(notebookPath);
      asked = resolved.ref?.id;
      // A path that could not be opened must not end the launch: the app comes
      // up on the last notebook, and the shell says what happened to the one
      // that was asked for. Refusing to start because a shortcut points at a
      // moved file is the silent-no-op's louder cousin.
      pendingOpenNotice = resolved.problem ??
          (resolved.copied
              ? _copiedInNotice(resolved.ref!, notebookPath)
              : null);
    }
    notebookId = asked ??
        (_repo.notebooks.any((n) => n.id == lastNb)
            ? lastNb!
            : _repo.notebooks.first.id);
    // Clear out anything that has outlived the recycle-bin retention window.
    await _repo.purgeExpiredNotebooks(retentionDays: _recycleRetentionDays);
    _repo.purgeExpiredNodes(notebookId!, retentionDays: _recycleRetentionDays);
    reloadNodes();
    // Startup does NOT go through _loadNotebook — it opens the last notebook
    // inline — so the gate has to be rehydrated here as well. Both paths, or
    // the lock is only as good as which door you came in by.
    reloadProtection();
    final lastPage = _repo.getSetting('lastPage') as String?;
    final target = nodes.any((n) => n.id == lastPage && n.kind == NodeKind.page)
        ? lastPage
        : nodes.where((n) => n.kind == NodeKind.page).firstOrNull?.id;
    await selectPage(target);
  }

  // ── Per-page view memory (§7a.5) ───────────────────────────────────────

  final Map<String, List<double>> _viewMemory = {};

  List<double>? viewFor(String id) => _viewMemory[id];

  void _rememberView() {
    final id = pageId;
    if (id == null) return;
    _viewMemory[id] = [canvas.scale, canvas.offset.dx, canvas.offset.dy];
    if (_viewMemory.length > 300) _viewMemory.remove(_viewMemory.keys.first);
  }

  void _persistSession() {
    if (_editorOwner != null) return;
    _repo.setSetting('viewMemory', _viewMemory);
    _repo.setSetting('lastNotebook', notebookId);
    _repo.setSetting('lastPage', pageId);
  }

  Future<void> _loadNotebook() async {
    reloadNodes();
    if (_editorOwner != null) {
      reloadProtection();
      activeSectionId =
          nodes.where((n) => n.kind == NodeKind.section).firstOrNull?.id;
      final first = nodes
          .where((n) =>
              n.kind == NodeKind.page &&
              _editorDisplaying(notebookId, n.id) == null)
          .firstOrNull;
      await selectPage(first?.id);
      return;
    }
    // The single funnel every notebook-open goes through — startup, switching,
    // creating, joining — which is why the gate is rehydrated HERE rather than
    // in init(). Before any page is selected: `selectPage` below loads a
    // page's blocks, and it must not load a locked one into an app that has
    // forgotten the lock exists.
    reloadProtection();
    // Reset the focused section for the new notebook (selectPage refines it).
    activeSectionId =
        nodes.where((n) => n.kind == NodeKind.section).firstOrNull?.id;
    final firstPage = nodes
        .where((n) =>
            n.kind == NodeKind.page &&
            _editorDisplaying(notebookId, n.id) == null)
        .firstOrNull;
    await selectPage(firstPage?.id);
  }

  Future<void> selectNotebook(String id) async {
    await flushSave();
    notebookId = id;
    await _loadNotebook();
    notifyListeners();
  }

  Future<void> createNotebook(String title) async {
    await flushSave();
    final ref = await _repo.createNotebook(title);
    await selectNotebook(ref.id);
  }

  // ── Opening a notebook Openote was HANDED (task 43) ───────────────────
  //
  // Two doors, one funnel: `openote path/to/notebook.onote` from a terminal,
  // and a double-click on a `.onote` in the file manager. The second is the
  // one the audience uses — "a year 10 student wont know … how to run a
  // command in their terminal" — so every answer below is a sentence, not an
  // exception. The technical half (which path, which error) goes in
  // [OpenNotebookResult.details], which the UI keeps behind an Advanced fold.

  /// The notice the shell still has to show about a notebook we were handed:
  /// null on the happy path, because a notebook that opened is its own
  /// confirmation. Cleared by whoever displays it.
  OpenNotebookResult? pendingOpenNotice;

  /// Open the notebook stored at [path], switching to it if it is one of ours
  /// and adopting it if it is not.
  ///
  /// Never throws for a bad path: the caller is a command line or a
  /// double-click, and both deserve an answer rather than a crash.
  Future<OpenNotebookResult> openNotebookFile(String path) async {
    final resolved = await _resolveHandedPath(path);
    final problem = resolved.problem;
    if (problem != null) {
      pendingOpenNotice = problem;
      notifyListeners();
      return problem;
    }
    final ref = resolved.ref!;
    if (ref.id == notebookId) {
      // Not a failure and not worth a dialog — the notebook they asked for is
      // the one already on screen. Raising the window (the caller's job) is
      // the whole of the right response.
      return OpenNotebookResult(
        OpenNotebookOutcome.alreadyOpen,
        '"${ref.title}" is already open.',
      );
    }
    await selectNotebook(ref.id);
    if (!resolved.copied) {
      notifyListeners();
      return OpenNotebookResult(
        OpenNotebookOutcome.opened,
        'Opened "${ref.title}".',
      );
    }
    final result = _copiedInNotice(ref, path);
    pendingOpenNotice = result;
    notifyListeners();
    return result;
  }

  /// The one place this sentence is written.
  ///
  /// Both entry points — launch and hand-off — have to say it, and two copies
  /// of a user-facing sentence is two copies that drift. It is not decoration:
  /// a notebook opened from outside the workspace is COPIED in, so from that
  /// moment the file the user double-clicked stops receiving their edits.
  /// Saying nothing is how somebody emails a friend the original a week later
  /// and wonders where their work went.
  OpenNotebookResult _copiedInNotice(NotebookRef ref, String from) =>
      OpenNotebookResult(
        OpenNotebookOutcome.copiedIn,
        'Openote made a copy of "${ref.title}" in your notebooks. Changes '
        'you make are saved to the copy, not to the file you opened.',
        details: 'Opened: $from\nCopy: ${ref.file}',
      );

  /// Resolve a notebook file handed in at startup or by a second process.
  Future<({NotebookRef? ref, OpenNotebookResult? problem, bool copied})>
      _resolveHandedPath(String path) => _resolveNotebookFile(path);

  /// Turn a container path into a registry entry, registering or copying as
  /// required.
  ///
  /// `copied` says the notebook was taken INTO the workspace rather than found
  /// there, which is a fact the user has to be told: their edits stop going to
  /// the file they double-clicked.
  Future<({NotebookRef? ref, OpenNotebookResult? problem, bool copied})>
      _resolveNotebookFile(String path) async {
    // Absolute and normalised before anything compares it. `p.equals` against
    // the registry, `p.isWithin` against the workspace and the sniff below all
    // want a real path, and a relative one reaches here whenever the request
    // came from the hand-off file rather than from `notebookPathFromArgs`.
    final abs = p.normalize(p.absolute(path));

    // Ours already? Then nothing is copied, nothing is validated and nothing
    // is created — we just go there. This branch is the common case (the
    // user's notebooks live in the workspace folder), and it has to come
    // FIRST: the notebook that is open right now has its header change
    // sitting in an un-checkpointed WAL, so sniffing it would be the one
    // reading that could call a real notebook a stranger.
    final known = _repo.notebookAt(abs);
    if (known != null) {
      if (_repo.trashedNotebooks.any((n) => n.id == known.id)) {
        // Double-clicking a notebook you deleted is a restore request. The
        // alternative — "that notebook is in the recycle bin" — is a dead end
        // for a user who has the file right in front of them.
        await _repo.restoreNotebook(known.id);
      }
      return (ref: known, problem: null, copied: false);
    }

    final problem = notebookFileProblem(abs);
    if (problem != null) {
      return (
        ref: null,
        problem: _describeProblem(problem, abs),
        copied: false,
      );
    }

    try {
      if (p.isWithin(_repo.workspaceDir.path, abs)) {
        return (
          ref: await _repo.adoptWorkspaceNotebook(abs),
          problem: null,
          copied: false,
        );
      }
      final ref = await _repo.openExistingNotebook(abs);
      return (ref: ref, problem: null, copied: true);
    } catch (e) {
      return (
        ref: null,
        problem: OpenNotebookResult(
          OpenNotebookOutcome.failed,
          "Openote couldn't open that notebook.",
          details: '$abs\n\n$e',
        ),
        copied: false,
      );
    }
  }

  /// One sentence per way this can go wrong, in the words the app will say.
  OpenNotebookResult _describeProblem(
    NotebookFileProblem problem,
    String path,
  ) {
    final (outcome, message) = switch (problem) {
      NotebookFileProblem.missing => (
          OpenNotebookOutcome.notFound,
          "Openote couldn't find that notebook. It may have been moved, "
              'renamed or deleted since you last opened it.',
        ),
      NotebookFileProblem.notAFile => (
          OpenNotebookOutcome.notANotebook,
          "That's a folder, not a notebook, so there is nothing to open.",
        ),
      NotebookFileProblem.unreadable => (
          OpenNotebookOutcome.failed,
          "Openote couldn't read that file. Another program may have it open, "
              'or it may be somewhere you do not have permission to read.',
        ),
      NotebookFileProblem.notANotebook => (
          OpenNotebookOutcome.notANotebook,
          "That file isn't an Openote notebook, so there is nothing to open.",
        ),
    };
    return OpenNotebookResult(outcome, message, details: path);
  }

  /// Import a `.onote` that already exists on disk.
  Future<void> openExistingNotebook(String path) async {
    await flushSave();
    final ref = await _repo.openExistingNotebook(path);
    await selectNotebook(ref.id);
  }

  Future<void> renameNotebook(String id, String title) async {
    await flushSave();
    final saving = _repo.renameNotebook(id, title);
    navRevision++;
    notifyListeners();
    await saving;
    notifyListeners();
  }

  ({int sections, int pages}) notebookCounts(String id) =>
      _repo.notebookCounts(id);

  /// Soft-delete a notebook to the recycle bin. Refuses the last one (there's
  /// always somewhere to be). Returns false if it couldn't (only notebook).
  Future<bool> deleteNotebook(String id) async {
    if (_repo.notebooks.length <= 1) return false;
    await flushSave();
    final wasCurrent = id == notebookId;
    await _repo.trashNotebook(id);
    if (wasCurrent) {
      notebookId = _repo.notebooks.first.id;
      await _loadNotebook();
    }
    notifyListeners();
    return true;
  }

  List<NotebookRef> get trashedNotebooks => _repo.trashedNotebooks;

  /// How long trashed items live before auto-deletion (recycle-bin retention).
  int _recycleRetentionDays = Repository.recycleRetentionDays;
  int get recycleRetentionDays => _recycleRetentionDays;

  void setRecycleRetentionDays(int days) {
    final value = days.clamp(1, 3650).toInt();
    if (value == _recycleRetentionDays) return;
    _recycleRetentionDays = value;
    _repo.setSetting('recycleRetentionDays', value);
    notifyListeners();
  }

  /// Sweep expired recycle-bin entries (notebooks + the current notebook's
  /// nodes). Runs at startup and whenever the recycle bin is opened.
  Future<void> purgeExpiredTrash() async {
    await _repo.purgeExpiredNotebooks(retentionDays: _recycleRetentionDays);
    if (notebookId != null) {
      _repo.purgeExpiredNodes(notebookId!,
          retentionDays: _recycleRetentionDays);
    }
    notifyListeners();
  }

  Future<void> restoreNotebook(String id) async {
    await _repo.restoreNotebook(id);
    notifyListeners();
  }

  Future<void> purgeNotebook(String id) async {
    await _repo.purgeNotebook(id);
    notifyListeners();
  }

  /// Throw away a notebook that was never the user's — the half-built target of
  /// a cancelled or crashed import. Not the recycle bin: see
  /// [Repository.discardNotebook].
  Future<void> discardImportedNotebook(String id) async {
    await _repo.discardNotebook(id);
    notifyListeners();
  }

  Future<void> selectPage(String? id) async {
    final other = _editorDisplaying(notebookId, id);
    if (other != null) {
      other.activateEditor?.call();
      return;
    }
    _rememberView(); // keep your place when flicking between pages (§7a.5)
    await flushSave();
    pageId = id;
    select(null);
    _undo.clear();
    _redo.clear();
    renderSizes.clear();
    findMatches = [];
    findQuery = '';
    if (id == null) {
      blocks = [];
      pageProps = PageProps();
    } else {
      final data = await engine.loadPage(notebookId!, id);
      blocks = data.blocks;
      pageProps = data.props;
      _repairImportedFieldCodes();
      // Heal a page whose content sits under the title band (§7f). Marked
      // dirty only when something actually moved, so merely opening pages
      // does not rewrite the notebook.
      if (repairTitleBandOverlap() > 0) markDirty();
      // Keep the navigator's focused section in sync with the open page, and
      // remember it as the section's place so activateSection can come back
      // here. Selecting a page also leaves Home — the pane shows the
      // destination's siblings, which is what "I went somewhere" looks like.
      navHome = false;
      final parent = nodes.where((n) => n.id == id).firstOrNull?.parentId;
      if (parent != null) {
        activeSectionId = parent;
        _rememberSectionPage(parent, id);
      }
      _recordRecent(id);
    }
    docRevision++;
    _persistSession();
    notifyListeners();
  }

  /// Heal Word/OneNote field codes left in an already-imported page.
  ///
  /// The importer emitted a hyperlink as raw Word field scaffolding —
  /// `﷟HYPERLINK "https://…"` sitting next to the words it was attached to,
  /// unclickable. Fixing the importer does nothing for notes imported before
  /// the fix, and asking a student to re-import a term's notes to get their
  /// links back is not a fix. So a page repairs itself the first time it is
  /// opened.
  ///
  /// Cost on a clean page is one substring test per text block over text that
  /// is already in memory — no database read, no allocation, nothing written.
  /// The conversion itself is the Rust importer's own, over FFI, so there is
  /// exactly one parser rather than two that drift apart.
  /// Heal one page's blocks in place. Returns how many blocks changed.
  ///
  /// Shared by the on-open repair and the whole-notebook one so the two can
  /// never diverge — an imported page must end up identical whichever route
  /// reached it.
  int _healBlocks(List<Block> blocks, OnoteCore core) {
    String? repair(String text) {
      if (!textNeedsFieldRepair(text)) return null;
      final fixed = core.repairFieldCodes(text);
      return (fixed == text || fixed.isEmpty) ? null : fixed;
    }

    var changed = 0;
    for (final b in blocks) {
      if (b.type == BlockType.table) {
        final rows = b.content['cells'];
        if (rows is! List) continue;
        var touched = false;
        final out = <List<String>>[];
        for (final row in rows) {
          final cells = <String>[];
          for (final c in (row is List ? row : const [])) {
            final text = c?.toString() ?? '';
            final fixed = repair(text);
            if (fixed != null) touched = true;
            cells.add(fixed ?? text);
          }
          out.add(cells);
        }
        if (touched) {
          b.content['cells'] = out;
          b.updatedAt = nowMs();
          changed++;
        }
        continue;
      }
      final text = b.content['text'];
      if (text is! String) continue;
      final fixed = repair(text);
      if (fixed != null) {
        b.content['text'] = fixed;
        b.updatedAt = nowMs();
        changed++;
      }
    }
    return changed;
  }

  /// Heal EVERY page in the notebook, not just the ones you happen to open.
  ///
  /// The on-open repair is lazy by design — it costs nothing on a clean page
  /// — but on a notebook imported before the importer was fixed that means
  /// hundreds of pages keep their `﷟HYPERLINK "…"` junk and their needless
  /// `$…$` until the day you next visit them. This is the "just fix all of
  /// it" button, and it is worth having as an explicit action rather than a
  /// startup cost nobody asked for.
  ///
  /// Yields between chunks so a 300-page notebook doesn't freeze the window,
  /// and commits per chunk so an interruption keeps what it already fixed.
  Future<({int pages, int blocks})> repairWholeNotebook({
    void Function(int done, int total)? onProgress,
  }) async {
    final core = OnoteCore.instance;
    final nb = notebookId;
    if (core == null || nb == null) return (pages: 0, blocks: 0);
    await flushSave();

    final pages = nodes.where((n) => n.kind == NodeKind.page).toList();
    var healedPages = 0, healedBlocks = 0, done = 0;
    const chunk = 12;

    for (var start = 0; start < pages.length; start += chunk) {
      final end = (start + chunk).clamp(0, pages.length);
      importBatch(nb, () {
        for (var i = start; i < end; i++) {
          final n = pages[i];
          // The open page is already in memory and owns unsaved edits.
          final data =
              n.id == pageId ? PageData(blocks, pageProps) : readPage(n.id);
          final changed = _healBlocks(data.blocks, core);
          if (changed == 0) continue;
          healedPages++;
          healedBlocks += changed;
          importPage(nb, n.id, data.blocks, data.props);
        }
      });
      done = end;
      onProgress?.call(done, pages.length);
      // Real delay: UI-isolate loop; a zero timer never lets the Windows
      // message loop go idle, and idle is when input gets through.
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    // The open page's blocks may have been rewritten in place above.
    docRevision++;
    notifyListeners();
    return (pages: healedPages, blocks: healedBlocks);
  }

  void _repairImportedFieldCodes() {
    final core = OnoteCore.instance;
    if (core == null) return; // Dart-only build: leave the text untouched.

    // Worked out on a COPY first, so the undo checkpoint below captures the
    // page as it was on disk rather than as it will be.
    final before = [for (final b in blocks) Block.fromJson(b.toJson())];
    if (_healBlocks(before, core) == 0) return;

    // Undoable. This is the one automatic path that rewrites text the user
    // already owns, and it runs the moment a page opens — without a checkpoint
    // there is no way back if the conversion reads a paragraph wrong. The
    // stack was cleared by `selectPage` just above, so this becomes its first
    // entry: one Ctrl+Z restores exactly what was on disk.
    pushUndo();
    _healBlocks(blocks, core);
    // Save through the normal funnel so cache invalidation and persistence use
    // the same path as an ordinary edit.
    markDirty();
  }

  void _translateInk(Block b, double dy) {
    for (final sj in (b.content['strokes'] as List? ?? const [])) {
      final m = sj as Map;
      final ys = m['y'];
      if (ys is List) m['y'] = [for (final v in ys) (v as num) + dy];
    }
    invalidateInkStorage(b);
    // The canvas caches decoded strokes by `id#updatedAt`.
    b.updatedAt = nowMs();
  }

  // ── Page-surface geometry (CANVAS-1 v0.3) ──────────────────────────────

  static const double defaultPageHeight = 1400;
  static const double pageGrowMargin = 240;
  // In-page title band + left writing margin (OneNote-like page).
  static const double pageLeftMargin = 44;
  static const double titleBandHeight = 84; // title + date live here
  static const double contentTop = titleBandHeight + 8;

  /// Content-only extent (right & bottom edges), for page growth & fit.
  ({double right, double bottom}) contentExtent() {
    var right = pageLeftMargin, bottom = contentTop;
    for (final b in blocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? estimatedHeight(b);
      if (b.x + b.w > right) right = b.x + b.w;
      if (b.y + bh > bottom) bottom = b.y + bh;
    }
    return (right: right, bottom: bottom);
  }

  /// A height for a block that has neither a stored one nor a measured one.
  ///
  /// `renderSizes` is only written by blocks that actually built, and the
  /// canvas culls everything outside the viewport — so a long note further
  /// down the page reports nothing at all. A flat 60px guess for it made
  /// [contentExtent] report a bottom edge ABOVE the real content, which is the
  /// wrong direction for every caller: the page stops growing early, fit-to-
  /// content clips, and anything that appends "below the last box" lands on
  /// top of the user's writing.
  ///
  /// Estimating from the text is coarse — it ignores wrapping, so it can still
  /// undershoot a long unwrapped paragraph — but it is far closer than a
  /// constant, and it errs low only where a constant erred catastrophically.
  double estimatedHeight(Block b) {
    if (b.type != BlockType.text) return 60;
    final text = b.content['text'] as String? ?? '';
    if (text.isEmpty) return 60;
    final size = (b.content['fontSize'] as num?)?.toDouble() ?? 15;
    final lh = (b.content['lineHeight'] as num?)?.toDouble() ?? 1.5;
    // Very rough wrap estimate: characters that fit across the box, at ~0.5em
    // per character for a proportional face.
    final perLine = ((b.w - 20) / (size * 0.5)).clamp(8, 400);
    var lines = 0;
    for (final l in text.split('\n')) {
      lines += l.isEmpty ? 1 : (l.length / perLine).ceil();
    }
    return (lines * size * lh + 16).clamp(36, 20000);
  }

  /// Content-based page size (used off-view, e.g. export). The on-screen page
  /// additionally grows to fill the viewport — computed in the canvas widget.
  Size pageSize() {
    if (pageProps.pdfOnly)
      return Size(pageProps.pageWidth, pageProps.pdfPageHeight);
    final e = contentExtent();
    if (pageProps.isPaged) {
      // A sheet does not grow sideways, ever — that is what makes it a sheet.
      // It grows DOWNWARD by whole sheets, so the surface is always a whole
      // number of pages and a page break never lands in the middle of nothing.
      final paper = pageProps.paper;
      final sheets = math.max(1, (e.bottom / paper.height).ceil());
      return Size(paper.width, paper.height * sheets);
    }
    return Size(
      math.max(pageProps.pageWidth, e.right + pageGrowMargin),
      math.max(defaultPageHeight, e.bottom + pageGrowMargin),
    );
  }

  /// How many sheets the current page occupies. 1 in canvas mode, where the
  /// idea does not apply.
  int get sheetCount {
    if (!pageProps.isPaged) return 1;
    return math.max(
      1,
      (contentExtent().bottom / pageProps.paper.height).ceil(),
    );
  }

  /// The writing area of a sheet: the paper minus its margins.
  ///
  /// The left margin matches the canvas's own [pageLeftMargin] so text sits in
  /// the same place in both modes and switching does not shift a word.
  static const double sheetMargin = 64;

  ({double left, double top, double width}) sheetTextArea() {
    final paper = pageProps.paper;
    return (
      left: sheetMargin,
      top: contentTop,
      width: paper.width - sheetMargin * 2,
    );
  }

  /// Turn the current page into a sheet, or back into open canvas.
  ///
  /// Switching TO paged does the thing that makes page mode usable at all:
  /// "in page mode i think text boxes shouldnt be the default, it should be
  /// like a regular text/md editor. Basically ends up being just one really
  /// big box." So a page with nothing on it gets that one box, and a page with
  /// existing boxes keeps them — reflowing somebody's freeform layout into a
  /// column is a destructive guess, and the boxes are still theirs to move.
  void setPageLayout(String layout, {String? paper, bool? landscape}) {
    pushUndo();
    pageProps.layout = layout;
    if (paper != null) pageProps.paperSize = paper;
    if (landscape != null) pageProps.landscape = landscape;
    if (pageProps.isPaged) {
      _ensureSheetBody();
      // Every box is pulled inside the sheet: one left outside the paper is
      // content the user cannot see and will not find.
      for (final b in blocks) {
        clampBlockToPage(b);
      }
    }
    docRevision++;
    markDirty();
    notifyListeners();
  }

  /// The one big box a paged page writes into, created if it is not there.
  ///
  /// Recognised by geometry rather than by a flag: it is the full-width text
  /// block at the top of the sheet. That means an imported or hand-made page
  /// that already looks like a document is treated as one, and it means
  /// nothing new has to be stored to know which box is "the body".
  Block? _ensureSheetBody() {
    final area = sheetTextArea();
    final existing = sheetBody();
    if (existing != null) return existing;
    if (blocks.isNotEmpty) return null; // their layout, not ours to replace
    final b = Block(
      type: BlockType.text,
      x: area.left,
      y: area.top,
      w: area.width,
      // The width is the sheet's, not the text's — a document body is a
      // column, and auto-width would shrink it to the longest line.
      content: {'text': '', 'autoWidth': false},
    );
    blocks.add(b);
    return b;
  }

  /// The body box of a paged page, or null when the page is a free layout.
  Block? sheetBody() {
    if (!pageProps.isPaged) return null;
    final area = sheetTextArea();
    for (final b in blocks) {
      if (b.type != BlockType.text) continue;
      if ((b.x - area.left).abs() > 24) continue;
      if ((b.w - area.width).abs() > 24) continue;
      return b;
    }
    return null;
  }

  /// OneNote-style intelligent placement: create near the click, but align to
  /// the writing margin and to nearby content instead of landing pixel-exact.
  Offset smartTextPosition(Offset click) {
    const alignX = 56.0; // snap-to-left-edge threshold
    const alignY = 22.0; // snap-to-neighbour threshold
    final contentBlocks = blocks.where((b) => b.type != BlockType.ink).toList();

    // Empty page, clicked anywhere up top → the standard top-left spot.
    if (contentBlocks.isEmpty && click.dy < contentTop + 220) {
      return const Offset(pageLeftMargin, contentTop);
    }

    // X: snap to the writing margin or a nearby block's left edge.
    final xs = <double>[pageLeftMargin, ...contentBlocks.map((b) => b.x)];
    var x = click.dx;
    var bestX = double.infinity;
    for (final cx in xs) {
      if ((cx - click.dx).abs() < (bestX - click.dx).abs()) bestX = cx;
    }
    x = (bestX - click.dx).abs() < alignX
        ? bestX
        : math.max(click.dx, pageLeftMargin);

    // Y: snap just under a nearby block, or align with a block's top.
    var y = math.max(click.dy - 12, contentTop);
    final ys = <double>[];
    for (final b in contentBlocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? 60;
      ys
        ..add(b.y)
        ..add(b.y + bh + 14);
    }
    var bestY = double.infinity;
    for (final cy in ys) {
      if ((cy - y).abs() < (bestY - y).abs()) bestY = cy;
    }
    if (bestY.isFinite && (bestY - y).abs() < alignY) y = bestY;

    return Offset(math.max(x, pageLeftMargin), math.max(y, contentTop));
  }

  Rect contentBounds() {
    if (blocks.isEmpty) return Rect.fromLTWH(0, 0, pageProps.pageWidth, 400);
    var r = Rect.zero;
    var first = true;
    for (final b in blocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? 60;
      final br = Rect.fromLTWH(b.x, b.y, b.w, bh);
      r = first ? br : r.expandToInclude(br);
      first = false;
    }
    return r;
  }

  /// Content never above/left of the page origin (CANVAS-1 v0.3), and never
  /// underneath the title band (style guide §7f).
  ///
  /// The band is drawn as a `Positioned` overlay in the same coordinate space
  /// as the blocks, so a block placed above [contentTop] renders *through* the
  /// page title — the two strike each other out and neither is readable. The
  /// band already declared its height ([titleBandHeight]); nothing enforced it.
  /// The title is part of the page's layout, so the layout is where it is
  /// reserved.
  void clampBlockToPage(Block b) {
    if (b.x < 0) b.x = 0;
    if (b.y < contentTop) b.y = contentTop;
    if (!pageProps.isPaged) return;
    // On a sheet the right edge is real. A box dragged past it is content the
    // user cannot see and will not print, so it is pulled back inside — and
    // narrowed first if it is simply too wide to fit at all.
    final paper = pageProps.paper;
    final maxW = paper.width - sheetMargin * 2;
    if (b.w > maxW) b.w = maxW;
    final maxX = paper.width - sheetMargin - b.w;
    if (b.x > maxX) b.x = math.max(sheetMargin, maxX);
    if (b.x < sheetMargin) b.x = sheetMargin;
  }

  /// Push imported or legacy blocks out from under the title band.
  ///
  /// [clampBlockToPage] only runs on blocks the user moves. A page that
  /// arrived from the OneNote importer — or that was written before the band
  /// reserved its space — can already have content up there, and healing it on
  /// open is the same shape as `_repairImportedFieldCodes`.
  ///
  /// Returns how many blocks moved, so the caller can decide whether the page
  /// is dirty. The whole page shifts **together** when anything is above the
  /// band, rather than each stray block being clamped onto the same line: a
  /// note's blocks are positioned relative to each other, and collapsing two of
  /// them onto one y would destroy that.
  int repairTitleBandOverlap() {
    var top = double.infinity;
    for (final b in blocks) {
      // **Ink never triggers this.** A stroke's coordinates are page-absolute
      // and its block's box is DERIVED from them (`_refitInkBounds`), so a
      // pen mark anywhere near the top of the page was dragging every text
      // box, picture and equation down with it — up to 92px, saved before
      // anybody saw it, and out of reach of Ctrl+Z because opening a page
      // clears the undo stack. Drawing at the top of a page is not a defect
      // to heal; it is drawing.
      if (b.type == BlockType.ink) continue;
      if (b.y < top) top = b.y;
    }
    if (top == double.infinity || top >= contentTop) return 0;
    final shift = contentTop - top;
    var moved = 0;
    for (final b in blocks) {
      if (b.type == BlockType.ink) {
        // If ink IS moved it must be moved properly: the strokes are absolute,
        // so shifting only the box walks the selection away from the drawing.
        _translateInk(b, shift);
      }
      b.y += shift;
      moved++;
    }
    return moved;
  }

  // ── Tree ops ───────────────────────────────────────────────────────────

  static const _sectionColors = [
    'ink-500',
    'brass-400',
    'green',
    'blue',
    'violet',
    'red',
  ];

  Future<void> addSection({String? groupId}) async {
    final count = nodes.where((n) => n.kind == NodeKind.section).length;
    final n = _putNode(
      notebookId!,
      TreeNode(
        kind: NodeKind.section,
        parentId: groupId,
        title: 'Section ${count + 1}',
        color: _sectionColors[count % _sectionColors.length],
        position: _nextPosition(),
      ),
    );
    reloadNodes();
    await addPage(sectionId: n.id);
  }

  void addSectionGroup() {
    final count = nodes.where((n) => n.kind == NodeKind.sectionGroup).length;
    _putNode(
      notebookId!,
      TreeNode(
        kind: NodeKind.sectionGroup,
        title: 'Group ${count + 1}',
        position: _nextPosition(),
      ),
    );
    reloadNodes();
    notifyListeners();
  }

  /// A new page beside the one you are on — never one of its children, and
  /// never above them.
  ///
  /// It used to append at the end of the section with `level: 0`, which went
  /// wrong in two ways. Positions are lexicographic keys, and the importer
  /// mints them from a millisecond base (`onenote_import.dart`), so a new
  /// page's key is not reliably after an imported page's — land between a
  /// parent and its sub-pages at level 0 and those sub-pages become YOURS,
  /// because nesting is "the contiguous following run of deeper pages". That
  /// is the reported "it transfers the sub pages to this new page". And a page
  /// made while reading page 3 of 50 belongs near page 3, not at the bottom.
  ///
  /// So the position is not guessed. The section's pages are put in the order
  /// they should be in and renumbered — the same thing `sortSection` does, and
  /// bounded the same way, by the number of pages in one section.
  Future<void> addPage({String? sectionId}) async {
    sectionId ??= sectionOf(pageId) ??
        nodes.where((n) => n.kind == NodeKind.section).firstOrNull?.id;
    if (sectionId == null) return;

    final siblings = pagesOf(sectionId);
    final at = siblings.indexWhere((p) => p.id == pageId);
    final current = at < 0 ? null : siblings[at];

    final n = TreeNode(
      kind: NodeKind.page,
      parentId: sectionId,
      title: 'Untitled page',
      // A sibling of what you are on: from a sub-page you get another
      // sub-page, at the same indent, under the same parent.
      level: current?.level ?? 0,
      position: _nextPosition(),
    );

    if (current == null) {
      _putNode(notebookId!, n);
    } else {
      // Skip past everything indented BENEATH the current page, so the new
      // page lands after its whole subtree and cannot come between a parent
      // and its children.
      var after = at;
      while (after + 1 < siblings.length &&
          siblings[after + 1].level > current.level) {
        after++;
      }
      final ordered = [...siblings]..insert(after + 1, n);
      var seq = nowMs();
      for (final p in ordered) {
        p.position = 'a${(seq++).toString().padLeft(15, '0')}';
        _putNode(notebookId!, p);
      }
    }

    // Inherit the shape of the page you were on BEFORE it is replaced by the
    // new one's props. A notebook you are writing an essay in should not drop
    // back to open canvas every time you start the next page.
    final inherit = pageProps.isPaged
        ? (paper: pageProps.paperSize, landscape: pageProps.landscape)
        : null;
    reloadNodes();
    await selectPage(n.id);
    if (inherit != null) {
      setPageLayout(
        'paged',
        paper: inherit.paper,
        landscape: inherit.landscape,
      );
    }
    pendingTitleEdit = n.id; // cursor lands in the title (OneNote behaviour)
    notifyListeners();
  }

  /// A new page indented one level UNDER the one you are on.
  ///
  /// The deliberate version of what [addPage] must never do by accident. It
  /// takes no children from the current page — it is inserted directly beneath
  /// it, ahead of any existing sub-pages, so those stay where they were.
  Future<void> addSubpage() async {
    final current = pageId == null ? null : node(pageId!);
    if (current == null || current.kind != NodeKind.page) return addPage();
    final sectionId = current.parentId;
    if (sectionId == null) return addPage();

    final siblings = pagesOf(sectionId);
    final at = siblings.indexWhere((p) => p.id == current.id);
    if (at < 0) return addPage();

    final n = TreeNode(
      kind: NodeKind.page,
      parentId: sectionId,
      title: 'Untitled page',
      // Clamped to the same 0..2 the indent action allows; a page already at
      // the deepest level gets a sibling rather than an illegal fourth level.
      level: (current.level + 1).clamp(0, 2),
      position: _nextPosition(),
    );
    final ordered = [...siblings]..insert(at + 1, n);
    var seq = nowMs();
    for (final p in ordered) {
      p.position = 'a${(seq++).toString().padLeft(15, '0')}';
      _putNode(notebookId!, p);
    }
    reloadNodes();
    await selectPage(n.id);
    pendingTitleEdit = n.id;
    notifyListeners();
  }

  void renameNode(String id, String title) {
    final n = node(id);
    if (n == null) return; // deleted while a menu was open
    n.title = title;
    _putNode(notebookId!, n);
    bumpNodes();
    notifyListeners();
  }

  /// The colour tokens a section can be given, in picker order. `null` is the
  /// unset default, which renders in the app's own ink.
  static const List<String?> sectionColorTokens = [
    null,
    'brass-400',
    'green',
    'blue',
    'violet',
    'red',
  ];

  /// Recolour a section.
  ///
  /// The colour chip has always been rendered but only ever *written* by the
  /// OneNote importer, so on a notebook you started yourself every section was
  /// the same colour with no way to change it — a control that looks
  /// interactive and isn't.
  void setNodeColor(String id, String? token) {
    final n = node(id);
    if (n == null) return; // deleted while a menu was open
    n.color = token;
    _putNode(notebookId!, n);
    bumpNodes();
    notifyListeners();
  }

  /// Subpage indent (ORG-6): level 0..2.
  void indentPage(String id, int delta) {
    final n = node(id);
    if (n == null || n.kind != NodeKind.page) return;
    n.level = (n.level + delta).clamp(0, 2);
    _putNode(notebookId!, n);
    bumpNodes();
    notifyListeners();
  }

  /// Reorder among siblings (ORG-2, menu-driven for MVP).
  /// Drop [movingId] immediately before or after [targetId] among its siblings
  /// (ORG-2).
  ///
  /// Rebuilds every sibling's position rather than inventing a key between two
  /// neighbours: the position scheme is `'a' + padded-ms`, so there is no
  /// guaranteed gap between adjacent keys, and manufacturing one would collide
  /// eventually. Rewriting the run is O(siblings) and always correct.
  ///
  /// Subpages travel with their parent, for the same reason section sorting
  /// does it: the navigator renders hierarchy from contiguous runs, so moving
  /// a page without its children silently reparents them.
  void reorderNode(String movingId, String targetId, {required bool after}) {
    final moving = node(movingId), target = node(targetId);
    if (moving == null || target == null || movingId == targetId) return;
    if (moving.kind != target.kind) return;

    final siblings = nodes
        .where((s) => s.kind == moving.kind && s.parentId == target.parentId)
        .toList();
    if (siblings.isEmpty) return;

    // Group each top-level entry with the deeper-level run that follows it.
    final groups = <List<TreeNode>>[];
    for (final s in siblings) {
      if (s.level == 0 || groups.isEmpty) {
        groups.add([s]);
      } else {
        groups.last.add(s);
      }
    }
    final movingGroup =
        groups.where((g) => g.any((n) => n.id == movingId)).firstOrNull;
    if (movingGroup == null) return;
    // Dropping a page onto its own subpage would try to nest it inside itself.
    if (movingGroup.any((n) => n.id == targetId) &&
        movingGroup.first.id != targetId) {
      return;
    }
    groups.remove(movingGroup);
    final targetGroup =
        groups.where((g) => g.any((n) => n.id == targetId)).firstOrNull;
    final at = targetGroup == null
        ? groups.length
        : groups.indexOf(targetGroup) + (after ? 1 : 0);
    groups.insert(at.clamp(0, groups.length), movingGroup);

    pushUndo();
    // Re-parent in case the page came from another section.
    if (moving.parentId != target.parentId) {
      moving.parentId = target.parentId;
    }
    final levelDelta = target.level - moving.level;
    for (final n in movingGroup) {
      n.level = (n.level + levelDelta).clamp(0, 2);
    }
    var seq = nowMs();
    for (final g in groups) {
      for (final n in g) {
        n.position = 'a${(seq++).toString().padLeft(15, '0')}';
        _putNode(notebookId!, n);
      }
    }
    reloadNodes();
    notifyListeners();
  }

  void moveNode(String id, int delta) {
    final n = node(id);
    if (n == null) return;
    final siblings = nodes
        .where((s) => s.kind == n.kind && s.parentId == n.parentId)
        .toList();
    final i = siblings.indexWhere((s) => s.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= siblings.length) return;
    final other = siblings[j];
    final tmp = n.position;
    n.position = other.position;
    other.position = tmp;
    _putNode(notebookId!, n);
    _putNode(notebookId!, other);
    reloadNodes();
    notifyListeners();
  }

  void moveSectionToGroup(String sectionId, String? groupId) {
    final n = node(sectionId);
    if (n == null || n.kind != NodeKind.section) return;
    n.parentId = groupId;
    _putNode(notebookId!, n);
    reloadNodes();
    notifyListeners();
  }

  TreeNode? node(String? id) =>
      id == null ? null : nodes.where((n) => n.id == id).firstOrNull;

  // ── Recycle bin (ORG-7) ────────────────────────────────────────────────

  List<({String id, String kind, String title, int deletedAt})>
      deletedNodes() => _repo.loadDeletedNodes(notebookId!);

  Future<void> restoreDeleted(String id) async {
    _repo.restoreNode(notebookId!, id);
    reloadNodes();
    notifyListeners();
  }

  void purgeDeleted(String id) {
    _repo.purgeNode(notebookId!, id);
    notifyListeners();
  }

  // ── Backlinks (TEXT-8) ─────────────────────────────────────────────────

  /// Page outline panel (TEXT-10).
  bool get showTocPanel => openPanel == SidePanelKind.outline;
  void toggleTocPanel() => togglePanel(SidePanelKind.outline);

  /// Headings on the current page, in reading order, for the outline panel.
  ///
  /// Cached on the same key as the links panel: without it, the panel rescans
  /// every block's Markdown on each notify — i.e. per keystroke — which is the
  /// exact cost the memoised navigator exists to avoid.
  ({
    String key,
    List<({String blockId, int level, String text})> items
  })? _tocCache;

  List<({String blockId, int level, String text})> pageOutline() {
    final key = '$pageId#$docRevision';
    final cached = _tocCache;
    if (cached != null && cached.key == key) return cached.items;
    final items = <({String blockId, int level, String text})>[];
    final ordered = [...blocks.where((b) => b.type == BlockType.text)]
      ..sort((a, b) => a.y.compareTo(b.y));
    for (final b in ordered) {
      final text = b.content['text'];
      if (text is! String) continue;
      for (final line in text.split('\n')) {
        final m = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line.trimLeft());
        if (m == null) continue;
        items.add((
          blockId: b.id,
          level: m.group(1)!.length,
          text: m.group(2)!.trim(),
        ));
      }
    }
    _tocCache = (key: key, items: items);
    return items;
  }

  bool get showLinksPanel => openPanel == SidePanelKind.links;
  void toggleLinksPanel() => togglePanel(SidePanelKind.links);

  // The links panel is rebuilt on every notify while it's open, and both of
  // these are expensive: one is a synchronous SQLite query on the UI thread, the
  // other scans every text block. Cache them against (page, docRevision,
  // nodesRevision) so a keystroke doesn't re-run either.
  ({String key, List<TreeNode> back, List<TreeNode> out})? _linkCache;
  static final _outgoingLinkRe = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');

  void _ensureLinks() {
    final key = '$pageId#$docRevision#$nodesRevision#${_dirty ? 1 : 0}';
    if (_linkCache?.key == key) return;
    final back = pageId == null
        ? <TreeNode>[]
        : _repo
            .backlinkPageIds(notebookId!, pageId!)
            .map(node)
            .whereType<TreeNode>()
            .toList();
    // Outgoing: `[[Title|id]]` resolves by id, a bare `[[Title]]` by title —
    // the panel used to ignore the bare form entirely.
    final out = <String, TreeNode>{};
    for (final b in blocks.where((b) => b.type == BlockType.text)) {
      for (final m in _outgoingLinkRe.allMatches(
        b.content['text'] as String? ?? '',
      )) {
        final target =
            m.group(2) != null ? node(m.group(2)) : pageByTitle(m.group(1)!);
        if (target != null) out[target.id] = target;
      }
    }
    _linkCache = (key: key, back: back, out: out.values.toList());
  }

  List<TreeNode> backlinksForCurrent() {
    _ensureLinks();
    return _linkCache!.back;
  }

  /// Outgoing wiki-links found in the current page's text blocks.
  List<TreeNode> outgoingLinksForCurrent() {
    _ensureLinks();
    return _linkCache!.out;
  }

  List<TreeNode> get pages =>
      nodes.where((n) => n.kind == NodeKind.page).toList();

  TreeNode? pageByTitle(String title) {
    final t = title.trim().toLowerCase();
    return pages.where((p) => p.title.trim().toLowerCase() == t).firstOrNull;
  }

  /// Resolve a wiki-link target (EMBED-1): prefer the stable id, fall back to
  /// title match, and navigate.
  void openWikiLink(String label, String? id) {
    final target =
        (id != null && node(id) != null) ? id : pageByTitle(label)?.id;
    if (target != null) selectPage(target);
  }

  /// Insert a page-link (EMBED-1) as a new text block referencing the target
  /// by stable id: `[[Title|id]]`.
  void insertPageLink(String targetPageId) {
    final target = node(targetPageId);
    if (target == null) return;
    final pos = smartTextPosition(const Offset(pageLeftMargin, contentTop));
    final b = addBlock(
      Block(
        type: BlockType.text,
        x: pos.dx,
        y: pos.dy,
        w: 320,
        content: {'text': '[[${target.title}|${target.id}]]'},
      ),
    );
    select(b.id);
  }

  /// Drag a page into another section (ORG-2): reparent, level 0, append.
  void movePageToSection(String pageId, String sectionId) {
    final n = node(pageId);
    final s = node(sectionId);
    if (n == null || n.kind != NodeKind.page || s?.kind != NodeKind.section) {
      return;
    }
    n
      ..parentId = sectionId
      ..level = 0
      ..position = _nextPosition();
    _putNode(notebookId!, n);
    reloadNodes();
    notifyListeners();
  }

  /// Drag a page onto another page → make it a subpage (ORG-6): same section,
  /// indented one level deeper, positioned right after the target.
  void makeSubpageOf(String pageId, String targetPageId) {
    if (pageId == targetPageId) return;
    final n = node(pageId);
    final target = node(targetPageId);
    if (n == null || target == null || target.kind != NodeKind.page) return;
    n
      ..parentId = target.parentId
      ..level = (target.level + 1).clamp(0, 2)
      // Sorts after the target (target.position is a prefix) and before its
      // next sibling; the full-millisecond suffix keeps repeated drops unique.
      ..position = '${target.position}m${nowMs().toString().padLeft(15, '0')}';
    _putNode(notebookId!, n);
    reloadNodes();
    notifyListeners();
  }

  void toggleGroupCollapsed(String id) {
    collapsedGroups.contains(id)
        ? collapsedGroups.remove(id)
        : collapsedGroups.add(id);
    navRevision++;
    notifyListeners();
  }

  Future<void> deleteNode(String id) async {
    final at = nowMs();
    _repo.softDeleteNode(notebookId!, id, at: at);
    reloadNodes();
    if (pageId == id || !nodes.any((n) => n.id == pageId)) {
      await selectPage(
        nodes.where((n) => n.kind == NodeKind.page).firstOrNull?.id,
      );
    }
    notifyListeners();
  }

  String? sectionOf(String? page) =>
      nodes.where((n) => n.id == page).firstOrNull?.parentId;

  // Append-ordered position key. Time-based (siblings sort by creation), padded
  // to a fixed width so lexicographic == numeric order. NOT the CRDT
  // fractional-index of Data Model Spec §1 — that lands with the Loro engine;
  // until then reorder is swap-based ([moveNode]) and insert-after-target uses a
  // suffix ([makeSubpageOf]), neither of which needs true between-key insertion.
  // (The old `% 1e8` truncation wrapped every ~28h, letting new nodes sort
  // before old ones — fixed by keeping the full millisecond value.)
  String _nextPosition() => 'a${nowMs().toString().padLeft(15, '0')}';

  // ── Undo / redo (page-scoped snapshots) ────────────────────────────────

  String _snapshot() => jsonEncode({
        'page': pageProps.toJson(),
        'blocks': [for (final b in blocks) b.toJson()],
      });

  void _restore(String snap) {
    final j = jsonDecode(snap) as Map<String, dynamic>;
    pageProps = PageProps.fromJson(
      (j['page'] as Map?)?.cast<String, dynamic>(),
    );
    blocks = [
      for (final b in (j['blocks'] as List))
        Block.fromJson((b as Map).cast<String, dynamic>()),
    ];
    selectedIds.clear();
    selectedBlockId = null;
    editingBlockId = null;
    docRevision++;
    markDirty();
    notifyListeners();
  }

  void pushUndo() {
    _undo.add(_snapshot());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  // ── Selection & block ops ──────────────────────────────────────────────

  // Snap step comes from the page's own grid (Data Model Spec §3), so a page's
  // stored gridSize actually drives placement instead of being dead state.
  double get gridSize => pageProps.gridSize;
  double snap(double v) =>
      effectiveSnap ? (v / gridSize).round() * gridSize : v;

  /// The equation editor that has the keyboard, so the toolbar's **Maths** tab
  /// can drive it (v0.18 §5.2, revised).
  ///
  /// The palette began docked inside the equation's own box. The owner's
  /// verdict — *"this isnt great. I want them in the bar up the top like it is
  /// in onenote"* — and they are right for a reason worth writing down: a
  /// palette inside the box competes with the equation for the space the
  /// student is actually looking at, and it moves every time the equation
  /// grows. A contextual toolbar tab stays put.
  ///
  /// Both placements register here: an equation block on the page, and the
  /// in-place editor an equation inside a sentence opens as.
  ActiveMathEditor? activeMath;

  /// Symbols reached for lately, newest first, at most twelve. Shown at the top
  /// of the symbol panel so the θ a student used a minute ago is one click
  /// away rather than eight categories away.
  ///
  /// Session-scoped on purpose for now: it is a convenience, and persisting it
  /// would put a new key in the workspace file for something nobody misses
  /// across a restart. Seeded with what a student reaches for first.
  final List<String> recentMathIds = ['pi', 'degree', 'pm', 'leq', 'theta'];

  void noteMathUse(String id) {
    recentMathIds.remove(id);
    recentMathIds.insert(0, id);
    if (recentMathIds.length > 12) recentMathIds.removeLast();
  }

  /// Registered from the equation editor's `build`, so — like [setActiveEditor]
  /// — it must NOT notify. The rebuild that reveals the tab rides the
  /// `select(edit: true)` notify that opened the editor in the first place.
  void setActiveMath(ActiveMathEditor m) => activeMath = m;

  /// Called when an equation editor closes. [owner] identifies the caller so a
  /// teardown arriving *after* the next editor has already registered cannot
  /// unregister its successor — the classic dispose-order bug.
  void clearActiveMath(Object owner) {
    if (activeMath?.owner == owner) {
      activeMath = null;
      notifyListeners();
    }
  }

  /// Put a new equation on the page, open for editing (task #79).
  ///
  /// THE way an equation is created. It existed in three copies — Alt+= in the
  /// shell, Insert ▸ Equation in the command bar, and the right-click menu —
  /// each with its own idea of the box's size and its own literal content map.
  /// One of them already carried a `linearSource` the others didn't, which is
  /// the kind of drift that ends with two routes producing subtly different
  /// blocks.
  ///
  /// [at] is the block's top-left in page coordinates. [seed] is text the
  /// student had selected when they pressed Alt+= — the words come WITH them
  /// rather than being left behind.
  /// A card on the page, in a box of its own, opened ready to be written.
  ///
  /// The fallback for the Home row's card button when there is no line to
  /// turn into a card. It used to live on the Insert ribbon as its own
  /// entry, which meant two buttons with the same icon on two different tabs
  /// doing two different things; the ribbon's copy is gone and this is where
  /// its one unique behaviour went.
  ///
  /// `BlockType.flashcard` is still read and rendered — pages already have
  /// them — it is simply no longer the thing this makes.
  Block insertFlashcard({Offset? at}) {
    const line = '?[Question](Answer)';
    final where = at ??
        canvas.screenToPage(
          Offset(canvas.viewport.width / 2, canvas.viewport.height / 2),
        );
    final pos = smartTextPosition(where);
    final b = addBlock(
      Block(
        type: BlockType.text,
        x: pos.dx,
        y: pos.dy,
        w: 460,
        // A card is 420 wide and the auto-width measurement reads the RAW
        // markdown, which is far narrower than the card it stands for — the box
        // would size itself to the text and clip the card.
        content: {'text': '$line\n', 'autoWidth': false},
      ),
    );
    select(b.id, edit: true);
    return b;
  }

  // ── Graphs (v0.23 §5) ────────────────────────────────────────

  /// **Draw this equation.**
  ///
  /// The owner: *"have it insert a graph, not touching the written equation
  /// but inserting a new graph element on the page which i can move around
  /// seperatley but is still tied to that equation."*
  ///
  /// So: a new block beside the equation, carrying its own copy of the latex
  /// AND a note of where the latex came from. [from] is the id of the maths
  /// BLOCK it follows; leave it null for an equation that has no id of its
  /// own — one inside a sentence — and the graph is simply a graph of what
  /// it was given.
  /// [fromLatex] marks an equation INSIDE A SENTENCE, which has no id of its
  /// own. The link is anchored to what the equation SAYS rather than to where
  /// it sits, because where it sits is a character offset that every
  /// keystroke in the paragraph moves. See [pushInlineEquationToGraphs].
  Block insertGraph({
    required String latex,
    String? from,
    String? fromLatex,
    Offset? at,
  }) {
    final near =
        from == null ? null : blocks.where((b) => b.id == from).firstOrNull;
    // Beside the equation, not on top of it: to its right if there is room on
    // the page, underneath it otherwise.
    final where = at ??
        (near == null
            ? canvas.screenToPage(
                Offset(canvas.viewport.width / 2, canvas.viewport.height / 2),
              )
            : Offset(near.x + near.w + 24, near.y));
    final b = addBlock(
      Block(
        type: BlockType.graph,
        x: where.dx,
        y: where.dy,
        w: 360,
        h: 260,
        content: {
          'latex': latex.trim(),
          if (from != null) 'from': from,
          if (fromLatex != null) 'fromLatex': fromLatex.trim(),
          'fitY': true,
        },
      ),
    );
    select(b.id);
    return b;
  }

  /// Every graph on this page that follows the maths BLOCK [equationId].
  Iterable<Block> graphsFollowing(String equationId) => blocks.where(
        (b) =>
            b.type == BlockType.graph &&
            b.content['from'] == equationId &&
            b.content['fromLatex'] == null,
      );

  /// Every graph that follows one particular equation inside a sentence.
  Iterable<Block> graphsFollowingInline(String blockId, String latex) {
    final want = latex.trim();
    return blocks.where(
      (b) =>
          b.type == BlockType.graph &&
          b.content['from'] == blockId &&
          b.content['fromLatex'] == want,
    );
  }

  /// **Keep the graphs in step with an equation inside a sentence.**
  ///
  /// Anchored to the equation's own text, not to its position: a paragraph's
  /// offsets shift on every keystroke, and an index into "the nth equation"
  /// drifts the moment one is added or removed. [was] is what the graph is
  /// currently following, [now] is what it should follow from here.
  bool pushInlineEquationToGraphs(String blockId, String was, String now) {
    if (was.trim() == now.trim()) return false;
    // **Two graphs following the same words in the same sentence cannot both
    // be this equation's.**
    //
    // A link into a sentence is anchored to the equation's TEXT, because a
    // paragraph's offsets shift on every keystroke; the price is that two
    // equations reading the same thing are the same thing as far as the link
    // can tell. Moving both would rewrite a graph the student never touched,
    // so neither moves. The other half of this — an equation that has
    // TRANSIENTLY grown into another one's text — is caught in the engine,
    // which is the only place that can see the sentence as it stands this
    // keystroke.
    final following = graphsFollowingInline(blockId, was).toList();
    if (following.length > 1) return false;
    var changed = false;
    for (final g in following) {
      g.content['latex'] = now.trim();
      g.content['fromLatex'] = now.trim();
      g.updatedAt = nowMs();
      _refitGraph(g);
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// **Auto-fit whenever the equation actually changes**, not just when the
  /// graph is first drawn. Reported: "the scale in the graph doesnt auto
  /// update to better fit the graph when it changes" — `fitY` goes false
  /// (see [GraphBlockView._setView]) the moment a student pans or zooms by
  /// hand, which is correct for *looking around a stable curve*, but it also
  /// meant the window they chose for `y=3x+10` stayed put, unrefitted, once
  /// they rewrote it as `y=x^2` or `y=\sin x` — often showing nothing
  /// recognisable at all. The equation changing is exactly the moment a
  /// fixed window stops being a choice and starts being stale, so this is
  /// the same reset `GraphBlockView._reset` makes on a double-tap, run
  /// automatically the instant a followed equation is edited. A student who
  /// re-pans afterwards keeps that window until the NEXT edit, same as ever.
  void _refitGraph(Block g) {
    g.content.remove('view');
    g.content['fitY'] = true;
  }

  /// The link colour for one equation inside a sentence, or null.
  ///
  /// Same rule as [graphLinkHighlight]: there must be a link, and one end of
  /// it must be the thing being looked at. Here that means the graph is
  /// selected, or this is the equation currently open for editing.
  Color? inlineGraphTint(String blockId, String latex, {bool editing = false}) {
    final linked = graphsFollowingInline(blockId, latex);
    if (linked.isEmpty) return null;
    if (editing) return kGraphLinkColour;
    return linked.any((g) => selectedIds.contains(g.id))
        ? kGraphLinkColour
        : null;
  }

  /// **Keep the graphs in step with the equation they follow.**
  ///
  /// Called from the maths block's own commit, so a graph redraws as the
  /// equation is typed — which is what the owner asked for: *"if i then
  /// update it to y = 2x+6 that change is reflected in the graph."*
  ///
  /// Redraws only when something actually moved: a keystroke that changes no
  /// graph must not rebuild the page.
  bool pushEquationToGraphs(String equationId, String latex) {
    var changed = false;
    for (final g in graphsFollowing(equationId)) {
      if (g.content['latex'] == latex) continue;
      g.content['latex'] = latex;
      g.updatedAt = nowMs();
      _refitGraph(g);
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// **The colour that says these two are the same thing**, or null when
  /// there is nothing to say.
  ///
  /// The owner: *"when i click on the graph, it has a border of some colour
  /// … and the linked equation gets its background highlighted to that
  /// colour … This should work both ways … however should ONLY EVER be
  /// visible when one is clicked AND there is a linked graph."*
  ///
  /// Both halves are in the condition: there must be a link, and one END of
  /// it must be selected. DERIVED, never stored — a tint written into
  /// `content['bg']` is the student's own chosen fill, and would be
  /// permanent and would dirty the page.
  Color? graphLinkHighlight(Block b) {
    final selected = selectedIds;
    if (selected.isEmpty) return null;
    if (b.type == BlockType.graph) {
      final from = b.content['from'];
      if (from is! String) return null;
      final eq = blocks.where((x) => x.id == from).firstOrNull;
      if (eq == null) return null; // the equation is gone: no link to show
      return (selected.contains(b.id) || selected.contains(eq.id))
          ? kGraphLinkColour
          : null;
    }
    if (b.type == BlockType.math) {
      final linked = graphsFollowing(b.id).toList();
      if (linked.isEmpty) return null;
      if (selected.contains(b.id)) return kGraphLinkColour;
      return linked.any((g) => selected.contains(g.id))
          ? kGraphLinkColour
          : null;
    }
    return null;
  }

  // ── Substitutions ────────────────────────────────────────────

  /// **Plug a number into this equation.**
  ///
  /// The graph's sibling for a single point rather than a curve: a small
  /// block beside the equation, carrying its own copy of the latex and a
  /// note of where it came from — the same shape [insertGraph] uses, so
  /// "draw the graph" and "evaluate at a value" behave identically to a
  /// student, and a substitute block keeps itself in step with its equation
  /// the same way a graph does.
  Block insertSubstitute({
    required String latex,
    String? from,
    String? fromLatex,
    Offset? at,
  }) {
    final near =
        from == null ? null : blocks.where((b) => b.id == from).firstOrNull;
    final where = at ??
        (near == null
            ? canvas.screenToPage(
                Offset(canvas.viewport.width / 2, canvas.viewport.height / 2),
              )
            : Offset(near.x + near.w + 24, near.y));
    final b = addBlock(
      Block(
        type: BlockType.substitute,
        x: where.dx,
        y: where.dy,
        w: 260,
        content: {
          'latex': latex.trim(),
          if (from != null) 'from': from,
          if (fromLatex != null) 'fromLatex': fromLatex.trim(),
          'value': '',
        },
      ),
    );
    select(b.id);
    return b;
  }

  /// Every substitute block on this page that follows the maths BLOCK
  /// [equationId]. See [graphsFollowing] — same rule, other block type.
  Iterable<Block> substitutesFollowing(String equationId) => blocks.where(
        (b) =>
            b.type == BlockType.substitute &&
            b.content['from'] == equationId &&
            b.content['fromLatex'] == null,
      );

  /// Every substitute block that follows one particular equation inside a
  /// sentence. See [graphsFollowingInline] — same rule, other block type.
  Iterable<Block> substitutesFollowingInline(String blockId, String latex) {
    final want = latex.trim();
    return blocks.where(
      (b) =>
          b.type == BlockType.substitute &&
          b.content['from'] == blockId &&
          b.content['fromLatex'] == want,
    );
  }

  /// **Keep the substitute blocks in step with an equation inside a
  /// sentence.** See [pushInlineEquationToGraphs] — same rule, other block
  /// type: no window to refit, just the latex the value gets plugged into.
  bool pushInlineEquationToSubstitutes(String blockId, String was, String now) {
    if (was.trim() == now.trim()) return false;
    final following = substitutesFollowingInline(blockId, was).toList();
    if (following.length > 1) return false;
    var changed = false;
    for (final s in following) {
      s.content['latex'] = now.trim();
      s.content['fromLatex'] = now.trim();
      s.updatedAt = nowMs();
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// **Keep the substitute blocks in step with the equation they follow.**
  /// See [pushEquationToGraphs] — same rule, other block type.
  bool pushEquationToSubstitutes(String equationId, String latex) {
    var changed = false;
    for (final s in substitutesFollowing(equationId)) {
      if (s.content['latex'] == latex) continue;
      s.content['latex'] = latex;
      s.updatedAt = nowMs();
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  Block insertEquation({required Offset at, String seed = ''}) {
    final b = addBlock(
      Block(
        type: BlockType.math,
        x: at.dx,
        y: at.dy,
        w: 360,
        content: {
          'latex': seed.isEmpty ? '' : linearToLatex(seed),
          'linearSource': seed,
        },
      ),
    );
    select(b.id, edit: true);
    return b;
  }

  Block addBlock(Block b, {bool recordUndo = true}) {
    if (recordUndo) pushUndo();
    b
      ..x = snap(b.x)
      ..y = snap(b.y)
      ..placement = snapToGrid ? 'snapped' : 'free'
      ..z = (blocks.isEmpty
          ? 0
          : blocks.map((e) => e.z).reduce((a, c) => a > c ? a : c) + 1);
    clampBlockToPage(b);
    blocks.add(b);
    markDirty();
    notifyListeners();
    return b;
  }

  void updateBlock(Block b) {
    invalidateInkStorage(b);
    b.updatedAt = nowMs();
    markDirty();
    notifyListeners();
  }

  /// Forget a stale binary-ink reference before edited working geometry is
  /// persisted. Bulk operations use this and notify only once at the end.
  void invalidateInkStorage(Block b) {
    if (b.type == BlockType.ink) {
      InkStorage.markWorkingChanged(b.content);
    }
  }

  void removeBlock(String id, {bool recordUndo = true}) {
    if (recordUndo) pushUndo();
    blocks.removeWhere((b) => b.id == id);
    selectedIds.remove(id);
    if (selectedBlockId == id) selectedBlockId = selectedIds.firstOrNull;
    if (editingBlockId == id) editingBlockId = null;
    markDirty();
    notifyListeners();
  }

  void removeSelected() {
    if (selectedIds.isEmpty) return;
    pushUndo();
    blocks.removeWhere((b) => selectedIds.contains(b.id));
    selectedIds.clear();
    selectedBlockId = null;
    editingBlockId = null;
    markDirty();
    notifyListeners();
  }

  /// Duplicate with FRESH ids (Data Model Spec §2 rule 3).
  void duplicateBlock(String id, {bool recordUndo = true}) {
    final src = blocks.where((b) => b.id == id).firstOrNull;
    if (src == null) return;
    if (recordUndo) pushUndo();
    final fresh = Block(
      id: newId(),
      type: src.type,
      x: src.x + 24,
      y: src.y + 24,
      w: src.w,
      h: src.h,
      placement: src.placement,
      content: jsonDecode(jsonEncode(src.content)) as Map<String, dynamic>,
    );
    if (fresh.type == BlockType.ink) {
      for (final sj in (fresh.content['strokes'] as List)) {
        (sj as Map)['id'] = newId();
      }
    }
    addBlock(fresh, recordUndo: false); // snaps + clamps fresh.x/y to final pos
    if (fresh.type == BlockType.ink) {
      // Translate strokes to the block's FINAL (snapped/clamped) position so the
      // duplicate's ink renders under its new rect, not on top of the original.
      final dx = fresh.x - src.x, dy = fresh.y - src.y;
      for (final sj in (fresh.content['strokes'] as List)) {
        final m = (sj as Map);
        m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
        m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
      }
      invalidateInkStorage(fresh);
      fresh.updatedAt = nowMs(); // refresh the canvas stroke cache key
    }
    select(fresh.id);
  }

  void duplicateSelectedBlocks() {
    final ids = selectedIds.toList();
    if (ids.isEmpty) return;
    pushUndo();
    final copies = <String>[];
    for (final id in ids) {
      duplicateBlock(id, recordUndo: false);
      if (selectedBlockId != null && selectedBlockId != id)
        copies.add(selectedBlockId!);
    }
    selectMany(copies);
  }

  void select(String? id, {bool edit = false, bool additive = false}) {
    // The caret token is for the selection being made RIGHT NOW. Expiring it
    // here rather than trusting one widget type to consume it means a click
    // that never opens a text editor can't leave it lying around for the next
    // one — which showed up as a caret landing at a point on another block.
    if (!edit) pendingCaretGlobal = null;
    if (id == null) {
      selectedIds.clear();
      selectedBlockId = null;
      editingBlockId = null;
    } else if (additive) {
      if (!selectedIds.add(id)) selectedIds.remove(id);
      selectedBlockId = selectedIds.contains(id) ? id : selectedIds.firstOrNull;
      editingBlockId = null;
    } else {
      selectedIds
        ..clear()
        ..add(id);
      selectedBlockId = id;
      editingBlockId = edit ? id : null;
    }
    notifyListeners();
  }

  void selectMany(Iterable<String> ids) {
    selectedIds
      ..clear()
      ..addAll(ids);
    selectedBlockId = selectedIds.firstOrNull;
    editingBlockId = null;
    notifyListeners();
  }

  /// Move every selected block by a page-space delta (ink blocks translate
  /// their stroke coordinates — Ink Spec §3, coordinates are page-absolute).
  void moveSelectedBy(double dx, double dy) {
    for (final b in blocks.where((b) => selectedIds.contains(b.id))) {
      b.x += dx;
      b.y += dy;
      if (b.type == BlockType.ink) {
        for (final sj in (b.content['strokes'] as List)) {
          final m = (sj as Map);
          m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
          m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
        }
        invalidateInkStorage(b);
        // The canvas caches decoded strokes by `id#updatedAt`; bump it so the
        // painted ink follows the block instead of lagging until a reload.
        b.updatedAt = nowMs();
      }
    }
    markDirty();
    notifyListeners();
  }

  bool get selectedAreLocked {
    final selected = blocks.where((b) => selectedIds.contains(b.id)).toList();
    return selected.isNotEmpty &&
        selected.every((b) => b.content['locked'] == true);
  }

  void toggleSelectedLock() {
    final selected = blocks.where((b) => selectedIds.contains(b.id)).toList();
    if (selected.isEmpty) return;
    pushUndo();
    final lock = !selected.every((b) => b.content['locked'] == true);
    for (final b in selected) {
      if (lock) {
        b.content['locked'] = true;
      } else {
        b.content.remove('locked');
      }
      b.updatedAt = nowMs();
    }
    markDirty();
    notifyListeners();
  }

  /// Snap + clamp all selected at drag end. Ongoing left-margin alignment:
  /// if a block lands near the invisible writing margin, tuck it to the
  /// margin so everything stays neat (matches the smart initial placement).
  void settleSelected() {
    for (final b in blocks.where((b) => selectedIds.contains(b.id))) {
      if (b.type != BlockType.ink) {
        if ((b.x - pageLeftMargin).abs() < 26) {
          b.x = pageLeftMargin;
        } else if (effectiveSnap) {
          b.x = snap(b.x);
        }
        if (effectiveSnap) b.y = snap(b.y);
        // The block records the mode it was actually DROPPED in, so one box
        // pulled out of the grid stays out and everything else stays in.
        b.placement = effectiveSnap ? 'snapped' : 'free';
      }
      clampBlockToPage(b);
    }
    markDirty();
    notifyListeners();
  }

  int toolChoiceRevision = 0;

  void setTool(Tool t, {bool temporary = false}) {
    if (!temporary) toolChoiceRevision++;
    if (t == tool) {
      notifyListeners();
      return;
    }
    // Sampling belongs to the ink tool that armed it. Changing tools makes
    // the one-shot action unambiguous instead of leaving the canvas blocked.
    inkEyedropperActive = false;
    if (_hasInkSize(tool)) _inkToolSizes[tool] = penSize;
    tool = t;
    if (_hasInkSize(t)) penSize = inkSizeFor(t);
    if (t != Tool.select) select(null);
    notifyListeners();
  }

  void toggleSnap() {
    snapToGrid = !snapToGrid;
    notifyListeners();
  }

  void setBackground(String bg) {
    pushUndo();
    pageProps.background = bg;
    markDirty();
    notifyListeners();
  }

  void refresh() => notifyListeners();

  // ── Find (TEXT-7, current page) ────────────────────────────────────────

  void toggleFind() {
    findOpen = !findOpen;
    if (!findOpen) {
      findQuery = '';
      findMatches = [];
    }
    notifyListeners();
  }

  void setFindQuery(String q) {
    findQuery = q;
    final needle = q.toLowerCase();
    findMatches = needle.isEmpty
        ? []
        : [
            for (final b in blocks)
              if (_blockText(b).toLowerCase().contains(needle)) b.id,
          ];
    findIndex = 0;
    if (findMatches.isNotEmpty) _jumpToMatch();
    notifyListeners();
  }

  void findNext(int dir) {
    if (findMatches.isEmpty) return;
    findIndex = (findIndex + dir) % findMatches.length;
    if (findIndex < 0) findIndex += findMatches.length;
    _jumpToMatch();
    notifyListeners();
  }

  void _jumpToMatch() => jumpToBlock(findMatches[findIndex]);

  /// Replace text in the matched blocks (TEXT-7).
  ///
  /// Replaces in the *text-bearing* content field per block type, so replacing
  /// in a code block edits its source and not its language tag. Case-sensitive
  /// matching is deliberately not offered yet — find is case-insensitive, and a
  /// replace that matched differently from the find that found it would be a
  /// trap.
  ///
  /// Returns the number of occurrences replaced.
  int replaceAll(String find, String replacement, {bool onlyCurrent = false}) {
    if (find.isEmpty) return 0;
    final targets = onlyCurrent
        ? (findMatches.isEmpty
            ? const <String>[]
            : [findMatches[findIndex.clamp(0, findMatches.length - 1)]])
        : findMatches;
    if (targets.isEmpty) return 0;
    pushUndo();
    final needle = find.toLowerCase();
    var count = 0;
    for (final id in targets) {
      final b = blocks.where((x) => x.id == id).firstOrNull;
      if (b == null) continue;
      final key = switch (b.type) {
        BlockType.text => 'text',
        BlockType.code => 'source',
        _ => null,
      };
      if (key == null) continue;
      final src = b.content[key] as String? ?? '';
      final out = StringBuffer();
      var i = 0;
      while (i < src.length) {
        final at = src.toLowerCase().indexOf(needle, i);
        if (at < 0) {
          out.write(src.substring(i));
          break;
        }
        out
          ..write(src.substring(i, at))
          ..write(replacement);
        i = at + find.length;
        count++;
      }
      if (count > 0) b.content[key] = out.toString();
    }
    if (count > 0) {
      markDirty();
      docRevision++;
      // Re-run the search: the replaced text may no longer match, and leaving
      // stale matches would let a second Replace All hit blocks that no longer
      // contain the needle.
      setFindQuery(findQuery);
    }
    return count;
  }

  /// Select a block and centre the view on it. Shared by find and the page
  /// outline so both behave identically.
  void jumpToBlock(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null) return;
    selectedIds
      ..clear()
      ..add(id);
    selectedBlockId = id;
    editingBlockId = null;
    final h = b.h ?? renderSizes[id]?.height ?? 60;
    canvas.centerOn(Offset(b.x + b.w / 2, b.y + h / 2));
    notifyListeners();
  }

  String _blockText(Block b) => switch (b.type) {
        BlockType.text => b.content['text'] as String? ?? '',
        BlockType.code => b.content['source'] as String? ?? '',
        BlockType.math =>
          '${b.content['latex'] ?? ''} ${b.content['linearSource'] ?? ''}',
        _ => '',
      };

  // ── Persistence ────────────────────────────────────────────────────────

  void markDirty() {
    _dirty = true;
    _dirtyRevision++;
    // Cheap counter, not a rebuild: it lets the open page's flashcards be
    // rederived once per edit, so tagging a line produces a card immediately
    // instead of only after you navigate away.
    study.noteContentChanged();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), flushSave);
    notifyListeners();
  }

  /// The last local write failure, surfaced in the status bar.
  SaveProblem? get saveError {
    final locked = _repo.registryReadOnly;
    return _pageSaveError ??
        _blobWriteError ??
        (locked == null
            ? null
            : SaveProblem(
                short: 'Your notebook list is locked',
                message: locked.message,
                details: locked.details,
              ));
  }

  SaveProblem? _pageSaveError;

  SaveProblem _pageSaveFailed(Object error) => SaveProblem(
        short: 'Changes not saved',
        message: 'Openote could not save the latest changes. Check that the '
            'disk is not full and try again.',
        details: '$error',
      );

  Future<void> flushSave({bool closing = false}) async {
    for (final editor in _editors.toList()) {
      if (!editor._disposed) await editor.flushSave(closing: closing);
    }
    final saveCancellationGeneration = _saveCancellationGeneration;
    _saveDebounce?.cancel();
    if (!_dirty || pageId == null || notebookId == null) return;

    final id = pageId!;
    final notebook = notebookId!;
    final savingRevision = _dirtyRevision;
    try {
      final toSave = InkStorage.persistAll(
        blocks,
        (bytes) => importBlob(notebook, bytes, inkMimeType),
      );
      await engine.savePage(notebook, id, toSave, pageProps);
      _dirty = _dirtyRevision != savingRevision;
      _pageSaveError = null;
    } catch (e) {
      _pageSaveError = _pageSaveFailed(e);
      notifyListeners();
      return;
    }

    if (saveCancellationGeneration != _saveCancellationGeneration) return;
    _rememberView();
    _persistSession();
    notifyListeners();
  }

  /// Persist everything before the process goes away (window close, logout).
  /// Awaited by the app's [AppLifecycleListener]; without it, up to one debounce
  /// interval of edits was silently lost on every close.
  Future<void> shutdown() async {
    _saveDebounce?.cancel();
    final neededPageSave = _dirty;
    try {
      await flushSave(closing: true);
      // If an editor changed while the first flush was awaiting the disk, the
      // revision guard deliberately left it dirty. Closing gets one
      // immediate second pass instead of abandoning that last keystroke.
      if (_dirty) await flushSave(closing: true);
    } catch (_) {
      // flushSave recorded the problem and left _dirty set. The lifecycle
      // handler keeps the app open so unsaved notes can still be recovered.
    }
    // A successful dirty-page flush already persisted the session. Avoid
    // scheduling the same workspace write twice on the hottest exit path.
    if (!neededPageSave || _dirty) {
      _rememberView();
      _persistSession();
    }
    await _repo.flushWorkspace(); // settle the debounced registry write
  }

  /// Drop a pending debounced save without writing it.
  ///
  /// Only for tests: a widget test runs in a fake-async zone where the save's
  /// disk I/O would never complete, and leaving the timer armed fails the
  /// test's own "no pending timers" invariant.
  @visibleForTesting
  void cancelPendingSave() {
    _saveCancellationGeneration++;
    _saveDebounce?.cancel();
    // And navigating (selectPage → _persistSession) arms the repository's
    // debounced workspace write, which is the same shape of pending timer.
    _repo.cancelPendingWorkspaceWrite();
  }

  /// Set by [dispose] so split editors cannot save after teardown.
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final editor in _editors.toList()) {
      editor.dispose();
    }
    _editorOwner?._editors.remove(this);
    _saveCancellationGeneration++;
    // The caret watcher outlives nothing. A widget test builds and tears down
    // an AppState per case, and a listener left on a controller from the last
    // one is a leak that only shows up as a confusing failure in the next.
    _watchedEditor?.removeListener(_onEditorChanged);
    _watchedEditor = null;
    _saveDebounce?.cancel();
    // The planner owns a Timer. A `late final` touched here is constructed
    // just to be torn down, which costs nothing; a live timer left behind
    // keeps the isolate awake, which does.
    planner.dispose();
    canvas.dispose();
    if (_editorOwner == null) _repo.dispose();
    super.dispose();
  }
}
