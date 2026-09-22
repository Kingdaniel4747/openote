import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/ids.dart';
import '../ink/ink_storage.dart';
import '../model/models.dart';
import 'database.dart';
import 'media_store.dart';
import 'notebook_writer.dart';

/// The `workspace.json` layout this build writes and understands (spec §7's
/// `format.major`).
///
/// **Why this number is now read and not merely written.** [_loadWorkspace]
/// skips any registry entry whose file is not there
/// (`if (File(file).existsSync())`), and [_saveWorkspace] then rewrites the
/// whole registry from whatever survived. So a student who upgrades the laptop
/// in October and the desktop at Christmas opens the old build on a migrated
/// workspace, sees an empty sidebar, creates one notebook — and *permanently
/// prunes all the others*. Nothing on disk was corrupt; the old build simply
/// wrote down what it could see.
///
/// This is the only mechanical guard against that, and it has to be shipped
/// and baked **before** any release moves a container (v0.17 plan, Step 8),
/// which is why it lands first with nothing yet depending on it.
///
/// Format 2 is still accepted so workspaces written by earlier releases remain
/// readable. New writes use the original local-only layout.
const int workspaceFormat = 2;

/// Workspace + notebook persistence. One SQLite Database handle per open
/// .onote (File Format Spec §2); workspace.json registry per spec §7.
class Repository {
  Repository._(this.workspaceDir);
  final Directory workspaceDir;
  final Map<String, Database> _open = {}; // notebookId -> db
  final List<NotebookRef> notebooks = [];
  // Soft-deleted notebooks (ORG-7). Their .onote file stays on disk so a
  // restore is lossless; purge removes the file for good.
  final List<NotebookRef> trashedNotebooks = [];

  static Future<Repository> open() async {
    final dir = await resolveWorkspaceDir();
    final repo = Repository._(dir);
    await repo._loadWorkspace();
    if (repo.notebooks.isEmpty) {
      await repo.createNotebook('My Notebook');
    }
    return repo;
  }

  /// Open a workspace at an explicit directory, bypassing platform folder
  /// resolution. For tests/tools that need an isolated, path_provider-free
  /// workspace. Does NOT seed a default notebook.
  static Future<Repository> openAt(Directory dir) async {
    await dir.create(recursive: true);
    final repo = Repository._(dir);
    await repo._loadWorkspace();
    return repo;
  }

  /// Prefer ~/Documents/Openote, but fall back to the app-support directory.
  /// On Windows the Documents "known folder" can be redirected (OneDrive) so
  /// the literal path may not exist — creating it then fails with errno 2.
  ///
  /// Public because `main()` needs the answer *before* it opens anything: the
  /// single-instance lock lives in this folder, and a second Openote has to
  /// find it and step aside before it paints a window (see
  /// `core/single_instance.dart`).
  static Future<Directory> resolveWorkspaceDir() async {
    Future<Directory?> tryCreate(Future<Directory> Function() base) async {
      try {
        final root = await base();
        final dir = Directory(p.join(root.path, 'Openote'));
        await dir.create(recursive: true);
        return dir;
      } catch (_) {
        return null;
      }
    }

    final dir = await tryCreate(getApplicationDocumentsDirectory) ??
        await tryCreate(getApplicationSupportDirectory);
    if (dir == null) {
      throw StateError(
          'Openote could not create a workspace folder in Documents or app data.');
    }
    return dir;
  }

  File get _workspaceFile => File(p.join(workspaceDir.path, 'workspace.json'));

  /// True when the registry was unreadable and a backup had to be used (or
  /// nothing could be recovered) — the UI warns rather than silently pretending
  /// the workspace is empty.
  String? workspaceRecoveryNote;

  /// Non-null when `workspace.json` was written by a newer Openote than this
  /// one, in which case this build reads the registry and **never rewrites
  /// it** — see [workspaceFormat] for the notebook-pruning disaster that
  /// prevents.
  ///
  /// Two fields for the same reason `OpenNotebookResult` has two: `message` is
  /// plain sentences safe to put in front of anybody, `details` is the version
  /// numbers, which belong behind an Advanced fold and nowhere else.
  ({String message, String details})? registryReadOnly;

  /// The registry's layout number, tolerant of every shape this file has had.
  ///
  /// Before the guard existed the field was written — and documented in spec
  /// §7 — as `{"major": 1, "minor": 0}`, and that is what every workspace on
  /// disk today still carries. A bare integer is accepted too so that a future
  /// build which flattens the field is still guarded by this one. **An
  /// unrecognised shape means "written by a build that predates the guard",
  /// which is by definition not newer than us**: guessing "newer" there would
  /// lock every existing user out of their own notebook list, which is the
  /// exact harm the guard exists to prevent.
  static int _formatOf(Map<String, dynamic> j) {
    final f = j['format'];
    if (f is num) return f.toInt();
    if (f is Map && f['major'] is num) return (f['major'] as num).toInt();
    return workspaceFormat;
  }

  Future<void> _loadWorkspace() async {
    // Try the live registry, then the `.bak` written before the last replace.
    // A registry we can't parse must never look like "you have no notebooks".
    Map<String, dynamic>? j;
    for (final candidate in [
      _workspaceFile,
      File('${_workspaceFile.path}.bak')
    ]) {
      if (!candidate.existsSync()) continue;
      try {
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is Map<String, dynamic>) {
          j = decoded;
          // `.path`, not the `File` objects. `_workspaceFile` is a getter that
          // returns a NEW `File` each call, and `dart:io`'s File does not
          // override `==` — so comparing the objects was always true, and the
          // "recovered from the backup" note was shown on every single launch,
          // including every successful one. A recovery notice that appears
          // when nothing was recovered is worse than none.
          if (candidate.path != _workspaceFile.path) {
            workspaceRecoveryNote =
                'workspace.json was unreadable; recovered from the backup.';
          }
          break;
        }
      } catch (_) {
        // Try the next candidate.
      }
    }
    if (j == null) {
      // Last resort: adopt any .onote files sitting in the workspace folder, so
      // a lost registry never hides real notebooks.
      final orphans = workspaceDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.onote'))
          .toList();
      if (orphans.isNotEmpty) {
        for (final f in orphans) {
          final ref = NotebookRef(
              id: newId(),
              file: f.path,
              title: p.basenameWithoutExtension(f.path));
          notebooks.add(ref);
          await _adoptLegacyAssetFolder(ref, null);
        }
        workspaceRecoveryNote =
            'workspace.json was missing or unreadable; recovered '
            '${orphans.length} notebook${orphans.length == 1 ? '' : 's'} from disk.';
        await _saveNow();
      }
      return;
    }
    final found = _formatOf(j);
    if (found > workspaceFormat) {
      // Load everything below as usual — the entries this build CAN see are
      // still real notebooks and the user should be able to open them. What it
      // must not do is write the list back.
      registryReadOnly = (
        message: 'This list of notebooks was last used by a newer version of '
            'Openote, so Openote is only reading it, not changing it. '
            'Notebooks you add, rename or delete now will be forgotten when '
            'you next start up.\n\n'
            'Updating Openote to the latest version fixes this. Nothing '
            'already in the list can be lost in the meantime.',
        details: 'workspace.json is format $found; this build writes and '
            'understands format $workspaceFormat.',
      );
    }
    _settings = (j['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final n in (j['notebooks'] as List? ?? const [])) {
      final m = (n as Map).cast<String, dynamic>();
      // `p.join` with a RELATIVE path, which is what `_registryPath` writes: for
      // a notebook sitting directly in the workspace that is still the bare
      // basename every registry on disk holds today, and for a migrated one it
      // is `.cache/<id>/cache.onote`. An absolute path wins outright, which is
      // how a notebook moved into a cloud folder resolves.
      final id = m['id'] as String;
      final file = p.join(workspaceDir.path, m['file'] as String);
      if (File(file).existsSync()) {
        final ref = NotebookRef(
            id: id, file: file, title: m['title'] as String? ?? 'Notebook');
        notebooks.add(ref);
        await _adoptLegacyAssetFolder(ref, m['logDir'] as String?);
      }
    }
    for (final n in (j['trashed'] as List? ?? const [])) {
      final m = (n as Map).cast<String, dynamic>();
      final id = m['id'] as String;
      final file = p.join(workspaceDir.path, m['file'] as String);
      if (File(file).existsSync()) {
        final ref = NotebookRef(
            id: id,
            file: file,
            title: m['title'] as String? ?? 'Notebook',
            deletedAt: (m['deletedAt'] as num?)?.toInt() ?? nowMs());
        trashedNotebooks.add(ref);
        await _adoptLegacyAssetFolder(ref, m['logDir'] as String?);
      }
    }
  }

  /// Bring assets written by the removed sync implementation back into the
  /// notebook's local storage. This is deliberately copy-only: after a
  /// successful upgrade the old folder remains a recoverable fallback and an
  /// external cloud client may still be using it as an ordinary backup.
  Future<void> _adoptLegacyAssetFolder(
      NotebookRef ref, String? registeredFolder) async {
    final legacyRoot = Directory(registeredFolder == null
        ? '${p.withoutExtension(ref.file)}.onotebook'
        : (p.isAbsolute(registeredFolder)
            ? registeredFolder
            : p.join(workspaceDir.path, registeredFolder)));
    if (!legacyRoot.existsSync()) return;

    final legacyBlobs = Directory(p.join(legacyRoot.path, 'blobs'));
    if (legacyBlobs.existsSync()) {
      final db = _db(ref.id);
      final validHash = RegExp(r'^[0-9a-fA-F]{64}$');
      for (final entry in legacyBlobs.listSync().whereType<File>()) {
        final hash = p.basename(entry.path).toLowerCase();
        if (!validHash.hasMatch(hash)) continue;
        try {
          final bytes = await entry.readAsBytes();
          if (sha256Hex(bytes) != hash) continue;
          db.execute(
              'INSERT OR IGNORE INTO blobs(hash,bytes,mime,size,created_at) '
              'VALUES(?,?,?,?,?)',
              [hash, bytes, _mimeOf(bytes), bytes.length, nowMs()]);
        } catch (_) {
          // One unreadable legacy asset must not prevent the notebook opening.
        }
      }
    }

    final oldMedia = Directory(p.join(legacyRoot.path, 'media'));
    if (!oldMedia.existsSync()) return;
    final localMedia = MediaStore.dirFor(ref);
    for (final entry in oldMedia.listSync().whereType<File>()) {
      final name = p.basename(entry.path);
      if (!MediaStore.isValidName(name)) continue;
      final target = File(p.join(localMedia.path, name));
      if (target.existsSync()) continue;
      try {
        await localMedia.create(recursive: true);
        await entry.copy(target.path);
      } catch (_) {
        // Keep loading; the source file remains untouched for manual recovery.
      }
    }
  }

  static String _mimeOf(Uint8List bytes) {
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(signature.length, (i) => bytes[i] == signature[i])
            .every((matches) => matches);
    if (starts(const [0x89, 0x50, 0x4e, 0x47])) return 'image/png';
    if (starts(const [0xff, 0xd8, 0xff])) return 'image/jpeg';
    if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (starts(const [0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
    if (bytes.length >= 12 &&
        starts(const [0x52, 0x49, 0x46, 0x46]) &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'application/octet-stream';
  }

  // Workspace-registry write serialisation. `workspace.json` lists every
  // notebook, and it used to be written with a bare (truncate-then-write)
  // `writeAsString`, fire-and-forget, up to three times per page switch. Any
  // crash inside that window truncated the file and the app then loaded ZERO
  // notebooks. Writes are now atomic (tmp + rename), chained so they can never
  // interleave, and coalesced so routine session state doesn't hammer the disk.
  Future<void> _writeChain = Future<void>.value();
  Timer? _writeDebounce;
  bool _writePending = false;

  /// The last workspace-write failure, if there has been one.
  ///
  /// Recorded rather than thrown, because the debounced path has nobody to
  /// throw to. `AppState` already surfaces `saveError` for page saves; this is
  /// the registry's equivalent and exists so a swallowed failure is still
  /// *discoverable*.
  Object? lastWorkspaceWriteError;

  /// Put one workspace write on the shared chain.
  ///
  /// **Returns a future that reports failure; leaves behind one that cannot.**
  /// That split is the whole point, and it fixes two distinct faults:
  ///
  /// *A failed write used to poison every later one.* `_writeChain.then(...)`
  /// on an already-errored future skips the callback entirely and
  /// re-propagates the old error for ever — so a single transient failure
  /// (antivirus holding the file, a redirected folder, a full disk) meant
  /// `workspace.json` was never written again for the lifetime of the process,
  /// and every subsequent `createNotebook` / `trashNotebook` threw someone
  /// else's stale exception. `_writeChain` is now the *recovered* future, so
  /// ordering is still guaranteed but failure does not accumulate.
  ///
  /// *A failed write used to escape into nowhere.* The debounced path awaits
  /// nothing, so an error there becomes an unhandled async error — which
  /// `flutter test` charges to whichever test happens to be running when it
  /// lands. That is precisely how a 400 ms registry write racing a temp
  /// directory's teardown produced an intermittent failure in an *unrelated*
  /// test, on the slowest CI runner and only there.
  Future<void> _enqueueWorkspaceWrite() {
    final result = _writeChain.then((_) => _saveWorkspace());
    _writeChain = result.catchError((Object e) {
      lastWorkspaceWriteError = e;
    });
    return result;
  }

  /// Queue an atomic workspace write. Coalesces bursts; returns immediately.
  void _scheduleSaveWorkspace() {
    _writePending = true;
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 400), () {
      // `.ignore()` rather than a bare call: it marks the future handled, so a
      // failure is recorded in `lastWorkspaceWriteError` and goes no further.
      // Dropping the future on the floor instead is what made this an
      // unhandled error.
      _enqueueWorkspaceWrite().ignore();
    });
  }

  /// Drop a pending debounced workspace write without performing it.
  ///
  /// For `AppState.cancelPendingSave` — a widget test that navigates arms the
  /// 400 ms debounce inside testWidgets' fake-async zone, where the write's
  /// file I/O could never complete and the armed timer fails the framework's
  /// own no-pending-timers invariant. `_writePending` is left true, so a later
  /// [flushWorkspace] still writes everything that was owed.
  void cancelPendingWorkspaceWrite() => _writeDebounce?.cancel();

  /// Write any pending workspace state now and wait for it (called on
  /// shutdown, and by any test that is about to delete the directory it lives
  /// in).
  ///
  /// **This one throws**, unlike the debounced path — a caller that asked to
  /// wait has somewhere to put the answer.
  Future<void> flushWorkspace() async {
    _writeDebounce?.cancel();
    if (_writePending) {
      await _enqueueWorkspaceWrite();
      return;
    }
    // Nothing pending: still wait for anything already in flight, but do not
    // resurrect an old failure that `_enqueueWorkspaceWrite` already recorded.
    await _writeChain;
  }

  /// Chain a write and wait for it — for structural changes (notebook created,
  /// renamed, trashed, purged) that must be durable before we report success.
  /// Goes through the same chain as the debounced writes so the two can never
  /// interleave on the file.
  Future<void> _saveNow() {
    _writeDebounce?.cancel();
    _writePending = true;
    return _enqueueWorkspaceWrite();
  }

  /// Write the registry NOW and bring the `.bak` copy in line with it.
  ///
  /// For a caller that has just REMOVED a secret from the settings (the
  /// interrupted setting migration). The ordinary atomic write
  /// keeps the PREVIOUS file as `workspace.json.bak` — which, right after a
  /// scrub, is precisely the copy still carrying the secret. Copying the
  /// freshly written file over the backup keeps the recovery path intact and
  /// leaves the secret in no file this class writes.
  Future<void> flushSettingsScrub() async {
    await _saveNow();
    // A read-only registry (written by a newer build) is never rewritten, so
    // nothing was scrubbed and the backup must not be touched either.
    if (registryReadOnly != null || _disposed) return;
    try {
      final target = _workspaceFile;
      if (target.existsSync()) await target.copy('${target.path}.bak');
    } catch (_) {
      // The live registry is already clean; a backup that could not be
      // refreshed is replaced by the next routine write anyway.
    }
  }

  Future<void> _saveWorkspace() async {
    if (_disposed) return; // the workspace may no longer exist
    _writePending = false;
    // A registry written by a newer build is read, never rewritten. Rewriting
    // it from what THIS build managed to load is the pruning disaster
    // [workspaceFormat] documents, and it is one `createNotebook` away. Silent
    // here on purpose: the message is already on screen, via
    // `AppState.saveError`.
    if (registryReadOnly != null) return;
    await _writeAtomic(const JsonEncoder.withIndent('  ').convert({
      'format': {'major': _formatToWrite, 'minor': 0},
      'workspace_id': _workspaceId ??= newId(),
      'notebooks': [
        for (final n in notebooks)
          {
            'id': n.id,
            'file': _registryPath(n.file),
            'title': n.title,
            // Always absolute: the shared folder is by definition outside the
            // workspace, so a basename would be meaningless.
          }
      ],
      'trashed': [
        for (final n in trashedNotebooks)
          {
            'id': n.id,
            // Same rules as the live list above. `trashNotebook` moves the
            // very same NotebookRef between the two, so a notebook deleted
            // after being moved to a cloud folder kept its absolute path and
            // was then written as a bare basename — dropped at the next load,
            // unrecoverable, and its file orphaned. The 30-day retention
            // promise quietly became "until you restart".
            'file': _registryPath(n.file),
            'title': n.title,
            'deletedAt': n.deletedAt,
          }
      ],
      'settings': _settings,
    }));
  }

  /// How a notebook's container path is recorded in `workspace.json`.
  ///
  /// Files inside the workspace are stored as relative paths so a complete
  /// workspace backup can be restored at a different location.
  String _registryPath(String file) => p.isWithin(workspaceDir.path, file)
      ? p.relative(file, from: workspaceDir.path)
      : file;

  /// New registries use the local-only format.
  int get _formatToWrite => 1;

  /// Atomic replace: write a temp file, flush it to disk, keep the previous
  /// version as `.bak`, then rename over the original. `rename` within a
  /// directory is atomic on NTFS, APFS and ext4, so a crash leaves either the
  /// old file or the new one — never a truncated one.
  Future<void> _writeAtomic(String contents) async {
    final target = _workspaceFile;
    final tmp = File('${target.path}.tmp');
    try {
      final handle = await tmp.open(mode: FileMode.writeOnly);
      try {
        await handle.writeString(contents);
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (target.existsSync()) {
        try {
          await target.copy('${target.path}.bak');
        } catch (_) {/* a missing backup must never block the real write */}
      }
      // Re-checked here, not only at the top of `_saveWorkspace`. Every line
      // above this one is an `await`, and the workspace can be disposed — or,
      // in a test, have its whole directory deleted — during any of them. The
      // top-of-function guard cannot see that; it already ran. Bailing quietly
      // is right because a disposed repository has, by definition, nobody left
      // who wants this file.
      if (_disposed) {
        try {
          if (tmp.existsSync()) await tmp.delete();
        } catch (_) {/* best effort */}
        return;
      }
      await tmp.rename(target.path);
    } catch (_) {
      // Leave the existing (valid) file alone rather than half-replacing it.
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {/* best effort */}
      rethrow;
    }
  }

  String? _workspaceId;

  /// Workspace settings (spec §7): session state, custom colours, templates.
  Map<String, dynamic> _settings = {};
  dynamic getSetting(String key) => _settings[key];

  /// Every settings key currently held. For callers that store a FAMILY of
  /// keys under a prefix (`protect:<notebook>:<node>`) and need to enumerate
  /// them without knowing the ids in advance.
  Iterable<String> settingKeys() => _settings.keys.toList(growable: false);

  void setSetting(String key, dynamic value) {
    // A null value REMOVES the key rather than storing a null. Without this a
    // "protected" flag could only ever be set, never taken off — the map would
    // keep the key and a prefix scan would still find it.
    if (value == null) {
      _settings.remove(key);
    } else {
      _settings[key] = value;
    }
    // Session state (view memory, last page) changes constantly — coalesce.
    _scheduleSaveWorkspace();
  }

  /// The open handle for [notebookId], opening it if this session has not yet.
  ///
  /// **[openExistingOnote], not [openOnote]** (v0.17 plan, Step 8 item 2). Every
  /// notebook reaching this line is one the registry already lists, so the file
  /// is *expected* to be there and a missing one is a fault to report, never a
  /// notebook to invent. Before this, a registered container whose path had gone
  /// — an unmounted drive, a cloud client that evicted the file, a user who
  /// moved it in Explorer — was silently re-seeded as an empty 73,728-byte
  /// notebook that `notebookFileProblem` then called *"looks like a notebook"*.
  /// The three callers that really do mean "make me one" ([createNotebook],
  /// [adoptLogDirectory], [adoptWorkspaceNotebook]) call [openOnote] directly
  /// and put the handle in `_open` themselves, so none of them comes through
  /// here.
  Database _db(String notebookId) {
    final nb = notebooks.firstWhere((n) => n.id == notebookId);
    return _open.putIfAbsent(notebookId,
        () => openExistingOnote(nb.file, notebookId: nb.id, title: nb.title));
  }

  /// The container-level writer for [notebookId]. Built per call rather than
  /// cached beside `_open`: [NotebookWriter] is a stateless wrapper over the
  /// handle, so a second cache to keep in step would be pure risk.
  NotebookWriter _writer(String notebookId) => NotebookWriter(_db(notebookId));

  /// Release this process's handle on a notebook's container.
  ///
  /// For handing the file to something else that will open it — today, the
  /// import writer isolate. Two connections to one WAL database is legal, but
  /// this one would sit on a stale page cache for the whole import and its
  /// decoded pages would describe a notebook that no longer exists. Closing is
  /// cheaper than reasoning about that, and the next read reopens.
  ///
  /// Safe to call for a notebook that was never opened.
  void closeNotebook(String notebookId) {
    _open.remove(notebookId)?.dispose();
    _decodedPages.remove(notebookId);
  }

  /// Write a **consistent** copy of a notebook's container to [destPath].
  ///
  /// Not `File.copy`. The container is open in WAL mode, so recent commits
  /// live in the `-wal` sidecar rather than the main file: copying the file
  /// alone can produce a database missing the last however-many saves, or —
  /// mid-checkpoint — a torn one. `VACUUM INTO` asks SQLite itself to
  /// serialise a complete, self-contained database at a consistent point,
  /// which is exactly what a backup has to be.
  ///
  /// Returns false if it couldn't (locked, out of disk); a backup that failed
  /// must never look like one that worked.
  bool snapshotContainer(String notebookId, String destPath) {
    try {
      final out = File(destPath);
      if (out.existsSync()) out.deleteSync();
      _db(notebookId).execute('VACUUM INTO ?', [destPath]);
      return out.existsSync() && out.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  // ── Notebooks ──────────────────────────────────────────────────────────

  Future<NotebookRef> createNotebook(String title) async {
    final id = newId();
    final file = _freeNotebookPath(title);
    final ref = NotebookRef(id: id, file: file, title: title);
    notebooks.add(ref);
    _open[id] = openOnote(file, notebookId: id, title: title);
    // Seed a first section + page so the notebook is immediately usable.
    final section =
        upsertNode(id, TreeNode(kind: NodeKind.section, title: 'Section 1'));
    upsertNode(
        id,
        TreeNode(
            kind: NodeKind.page, parentId: section.id, title: 'Untitled page'));
    await _saveNow();
    return ref;
  }

  /// Copy an existing notebook into this workspace.
  Future<NotebookRef> openExistingNotebook(String path, {String? title}) async {
    final file = File(path);
    if (!file.existsSync()) throw StateError('no notebook at $path');
    bool sameNotebook(NotebookRef n) => _isNotebookAt(n, path);

    final already = notebooks.where(sameNotebook).firstOrNull;
    if (already != null) return already;

    // The recycle bin counts. Joining a notebook you had deleted used to skip
    // this check entirely and copy the container again under a fresh id —
    // which is how a workspace ends up holding five ~95MB copies of one
    // notebook, each with its own review history and favourites. Restoring
    // the entry you already have is both cheaper and what the user meant.
    final trashed = trashedNotebooks.where(sameNotebook).firstOrNull;
    if (trashed != null) {
      await restoreNotebook(trashed.id);
      return trashed;
    }

    final name = title ?? p.basenameWithoutExtension(path);
    final local = _freeNotebookPath(name);
    await file.copy(local);
    if (!File(local).existsSync() ||
        File(local).lengthSync() != file.lengthSync()) {
      throw StateError('could not copy the notebook into this workspace');
    }

    final id = newId();
    final ref = NotebookRef(id: id, file: local, title: name);
    notebooks.add(ref);
    _open[id] = openOnote(local, notebookId: id, title: name);
    await _saveNow();
    return ref;
  }

  bool _isNotebookAt(NotebookRef n, String path) => p.equals(n.file, path);

  /// The registry entry for the notebook stored at [path] — live or in the
  /// recycle bin — or null when this workspace has never seen it.
  ///
  /// Exists for the *open this file* paths (the command line, a double-click
  /// in the file manager), which have to answer "do I already have this?"
  /// **before** deciding to copy anything. [openExistingNotebook] answers the
  /// same question internally, but only after it has committed to copying the
  /// file into the workspace, which a file already there does not need.
  NotebookRef? notebookAt(String path) =>
      notebooks.where((n) => _isNotebookAt(n, path)).firstOrNull ??
      trashedNotebooks.where((n) => _isNotebookAt(n, path)).firstOrNull;

  /// Register a `.onote` that is ALREADY sitting in the workspace folder,
  /// where it is, without copying it.
  ///
  /// The case is a file the user dropped into `Documents/Openote` by hand and
  /// then double-clicked. [openExistingNotebook] would answer it by copying —
  /// and since the obvious destination name is taken (by the source file
  /// itself) the copy lands as `Physics-1.onote`, leaving the workspace
  /// holding two containers for one notebook, the second of which is the one
  /// the user's edits go to. That is the same shape of mess as the five
  /// 95 MB copies described above, reached by an easier route.
  ///
  Future<NotebookRef> adoptWorkspaceNotebook(String path,
      {String? title}) async {
    if (!File(path).existsSync()) throw StateError('no notebook at $path');
    if (!p.isWithin(workspaceDir.path, path)) {
      throw StateError('$path is not inside the workspace');
    }
    final already = notebookAt(path);
    if (already != null) {
      if (trashedNotebooks.any((n) => n.id == already.id)) {
        await restoreNotebook(already.id);
      }
      return already;
    }
    final id = newId();
    final name = title ?? p.basenameWithoutExtension(path);
    final ref = NotebookRef(id: id, file: path, title: name);
    notebooks.add(ref);
    _open[id] = openOnote(path, notebookId: id, title: name);
    await _saveNow();
    return ref;
  }

  /// The page mirror's raw JSON, for tests that assert on what is actually
  /// stored rather than on what is read back.
  ///
  /// [readPage] deliberately inflates ink on the way out, so a test that only
  /// went through it could never tell whether the geometry was still in this
  /// column — which is the entire claim.
  @visibleForTesting
  String? rawPageJsonForTest(String notebookId, String pageId) =>
      _db(notebookId).select('SELECT json FROM page_mirror WHERE page_id=?',
          [pageId]).firstOrNull?['json'] as String?;

  /// How many bytes of JSON the page mirror holds for [pageId].
  ///
  /// Measured in SQLite rather than in Dart: `LENGTH(json)` on a 3 MB row is
  /// free, and pulling the string out to call `.length` on it is not.
  int pageJsonBytes(String notebookId, String pageId) =>
      (_db(notebookId).select(
              'SELECT LENGTH(json) AS n FROM page_mirror WHERE page_id=?',
              [pageId]).firstOrNull?['n'] as num?)
          ?.toInt() ??
      0;

  /// Write page JSON straight into the mirror, bypassing every projection.
  ///
  /// For tests that need to construct a page the way an OLDER build wrote it —
  /// inline ink strokes, for instance. Going through [writePage] would run it
  /// through today's code and produce today's shape, which is precisely what a
  /// migration test must not do.
  @visibleForTesting
  void writePageRawForTest(
          String notebookId, String pageId, Map<String, dynamic> json) =>
      _db(notebookId).execute(
          'INSERT INTO page_mirror(page_id,json,mirror_rev,updated_at) '
          'VALUES(?,?,1,?) ON CONFLICT(page_id) DO UPDATE SET '
          'json=excluded.json, mirror_rev=mirror_rev+1, '
          'updated_at=excluded.updated_at',
          [pageId, jsonEncode(json), nowMs()]);

  /// The blob hashes a page declares, for the garbage-collection reachability
  /// test.
  @visibleForTesting
  List<String> blobRefsForTest(String notebookId, String pageId) => [
        for (final r in _db(notebookId)
            .select('SELECT hash FROM blob_refs WHERE page_id=?', [pageId]))
          r['hash'] as String
      ];

  /// Hand back the space a notebook is holding but no longer using.
  ///
  /// Two distinct kinds of waste, and they need different instruments:
  ///
  /// * **Free pages inside the container.** Deleting a 60-slide deck frees
  ///   SQLite pages, but the FILE keeps its high-water mark and reuses them
  ///   internally. `VACUUM` rewrites the database without them. The real
  ///   workspace's 97 MB container was holding 742 free pages ≈ 3 MB.
  /// * **The write-ahead log.** See [checkpointAndClose] — measured at 4–8 MB
  ///   per notebook, and on one of them larger than the database itself.
  ///
  /// `VACUUM` and not `PRAGMA incremental_vacuum`: the incremental form only
  /// releases pages the auto-vacuum bookkeeping knows about, and every
  /// notebook that exists today was created before that pragma was set. A full
  /// VACUUM works on both, and this runs from an explicit user action rather
  /// than on a timer, so its cost is one the user asked for.
  ///
  String _freeNotebookPath(String title) {
    var base = title.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    if (base.isEmpty) base = 'Notebook';
    var file = p.join(workspaceDir.path, '$base.onote');
    var i = 2;
    while (File(file).existsSync()) {
      file = p.join(workspaceDir.path, '$base-$i.onote');
      i++;
    }
    return file;
  }

  Future<void> renameNotebook(String id, String title) async {
    final ref = notebooks.firstWhere((n) => n.id == id);
    ref.title = title;
    await _saveNow();
  }

  ({int sections, int pages}) notebookCounts(String id) {
    final rows = _db(id).select(
        "SELECT kind, COUNT(*) AS n FROM nodes WHERE deleted_at IS NULL GROUP BY kind");
    var sections = 0;
    var pages = 0;
    for (final row in rows) {
      if (row['kind'] == 'section') sections = (row['n'] as num).toInt();
      if (row['kind'] == 'page') pages = (row['n'] as num).toInt();
    }
    return (sections: sections, pages: pages);
  }

  /// Move a notebook to the recycle bin (ORG-7). Closes its db handle but keeps
  /// the .onote file, so [restoreNotebook] brings it back untouched.
  Future<void> trashNotebook(String id) async {
    final i = notebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final ref = notebooks.removeAt(i);
    ref.deletedAt = nowMs();
    trashedNotebooks.add(ref);
    _open.remove(id)?.dispose();
    _decodedPages.remove(id);
    await _saveNow();
  }

  Future<void> restoreNotebook(String id) async {
    final i = trashedNotebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final ref = trashedNotebooks.removeAt(i);
    ref.deletedAt = null;
    notebooks.add(ref);
    await _saveNow();
  }

  /// Permanently delete a trashed notebook and its local media.
  Future<void> purgeNotebook(String id) async {
    final i = trashedNotebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final ref = trashedNotebooks.removeAt(i);
    _open.remove(id)?.dispose();
    _decodedPages.remove(id);
    _deleteContainerFiles(ref.file);
    try {
      final media = MediaStore.dirFor(ref);
      if (media.existsSync()) media.deleteSync(recursive: true);
    } catch (_) {
      // A locked media file must not leave a stale workspace entry behind.
    }
    await _saveNow();
  }

  /// A container and the two files SQLite keeps beside it.
  ///
  /// Deleting the `.onote` alone strands its `-wal` and `-shm`, and they are
  /// not small: the real workspace held a 32 KB `-shm` and a 4.1 MB `-wal` for
  /// a notebook that no longer existed, and `findOrphanFiles` had to grow a
  /// case for them because nothing ever cleaned them up at the source. The
  /// `-wal` is the worse of the two — it holds committed pages that never made
  /// it into the main file, so a stranded one is real content in a file
  /// nothing will ever open again.
  static void _deleteContainerFiles(String container) {
    for (final path in [container, '$container-wal', '$container-shm']) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {/* best-effort; the workspace entry is already gone */}
    }
  }

  /// Remove a live notebook and its files outright, bypassing the recycle bin.
  ///
  /// For a notebook that was never the user's — the half-built target of a
  /// cancelled or crashed import. The recycle-bin route is wrong for it twice
  /// over: it would offer to restore half a notebook, and `deleteNotebook`
  /// refuses the *last* notebook (there is always somewhere to be), so on a
  /// workspace with nothing else in it a cancelled import was silently kept.
  Future<void> discardNotebook(String id) async {
    final i = notebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    trashedNotebooks.add(notebooks.removeAt(i));
    await purgeNotebook(id);
  }

  // ── Recycle-bin retention (ORG-7): auto-purge after N days ──────────────

  /// Deleted notebooks and nodes are permanently removed this long after they
  /// were trashed, so the recycle bin doesn't grow without bound.
  static const int recycleRetentionDays = 30;

  int _retentionCutoff() =>
      nowMs() - const Duration(days: recycleRetentionDays).inMilliseconds;

  /// Purge trashed notebooks past their retention window. Returns how many.
  Future<int> purgeExpiredNotebooks() async {
    final cutoff = _retentionCutoff();
    final expired = trashedNotebooks
        .where((n) => (n.deletedAt ?? 0) < cutoff)
        .map((n) => n.id)
        .toList();
    for (final id in expired) {
      await purgeNotebook(id);
    }
    return expired.length;
  }

  /// Purge soft-deleted nodes in [notebookId] past their retention window.
  void purgeExpiredNodes(String notebookId) {
    final db = _db(notebookId);
    db.execute(
        'DELETE FROM nodes WHERE deleted_at IS NOT NULL AND deleted_at < ?',
        [_retentionCutoff()]);
    // **There is no `page_versions` sweep here any more** (plan decision 1).
    // This used to be the other half of the hole [NotebookWriter.purgeNode]
    // closed — the table declared no foreign key onto `nodes`, so an expired
    // page's snapshots outlived it for good, measured at 1,002,020 leaked bytes
    // for one expired page of average size. `block_authors` declares the
    // `ON DELETE CASCADE` the old table never did and `recent_deletions`' cap of
    // ten is its own prune, so the leak is designed out rather than swept up.
    //
    // …and the same for the copy of the page that lives in memory. This method
    // evicted nothing at all, which is the same hole [purgeNode] had for its
    // subtree, only wider: it names no ids, so a page whose retention ran out
    // stayed in `_decodedPages` in full. Measured: read a page, trash it,
    // backdate it past the window, run this — `readPageShared` still returned
    // its blocks while `readPage` returned nothing. Nobody has to press
    // anything for that; this runs by itself at startup.
    //
    // The orphan predicate again rather than a list of ids, for the reason
    // above: the DELETE takes whole subtrees through the cascade and never
    // names what it took. Safe as an eviction rule because `page_mirror.page_id`
    // is `REFERENCES nodes(id)` with `foreign_keys=ON` — a cached page with no
    // `nodes` row has no stored JSON either, so the only thing it can be
    // holding is a dead page or the empty one [readPage] returns for a missing
    // row, and both are re-read for free.
    final cached = _decodedPages[notebookId];
    if (cached == null || cached.isEmpty) return;
    final live = {
      for (final r in db.select('SELECT id FROM nodes')) r['id'] as String
    };
    cached.removeWhere((id, _) => !live.contains(id));
  }

  // ── Tree nodes ─────────────────────────────────────────────────────────

  List<TreeNode> loadNodes(String notebookId) =>
      _writer(notebookId).loadNodes();

  TreeNode upsertNode(String notebookId, TreeNode n) =>
      _writer(notebookId).upsertNode(n);

  List<String> _descendants(Database db, String id) {
    final out = <String>[id];
    final queue = [id];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final r
          in db.select('SELECT id FROM nodes WHERE parent_id=?', [cur])) {
        final cid = r['id'] as String;
        out.add(cid);
        queue.add(cid);
      }
    }
    return out;
  }

  /// Soft-delete a node and everything under it (ORG-7 recycle bin).
  ///
  /// [at] makes bulk operations use one timestamp for every descendant.
  void softDeleteNode(String notebookId, String nodeId, {int? at}) {
    final db = _db(notebookId);
    final ts = at ?? nowMs();
    for (final id in _descendants(db, nodeId)) {
      db.execute(
          'UPDATE nodes SET deleted_at=? WHERE id=? AND deleted_at IS NULL',
          [ts, id]);
    }
  }

  /// Restore a node, its descendants, and its ancestors (so it reattaches).
  void restoreNode(String notebookId, String nodeId) {
    final db = _db(notebookId);
    for (final id in _descendants(db, nodeId)) {
      db.execute('UPDATE nodes SET deleted_at=NULL WHERE id=?', [id]);
    }
    var parent = db.select('SELECT parent_id FROM nodes WHERE id=?',
        [nodeId]).firstOrNull?['parent_id'] as String?;
    while (parent != null) {
      db.execute('UPDATE nodes SET deleted_at=NULL WHERE id=?', [parent]);
      parent = db.select('SELECT parent_id FROM nodes WHERE id=?',
          [parent]).firstOrNull?['parent_id'] as String?;
    }
  }

  /// Permanently delete a node and its subtree. The FK cascade clears
  /// `page_mirror`, `blob_refs` and `block_authors`; [NotebookWriter.purgeNode]
  /// is still the funnel rather than here because the import writer calls it
  /// directly, from its own isolate.
  void purgeNode(String notebookId, String nodeId) {
    // A purged page must not survive in the decoded cache: a page recreated
    // later under the same id would otherwise read as its dead predecessor.
    //
    // **Every id the purge took, not just the one we named.** `nodes.parent_id`
    // is `REFERENCES nodes(id) ON DELETE CASCADE`, so purging a SECTION deletes
    // its pages' rows without those page ids passing through here — and the
    // recycle bin purges sections, which is the common case rather than the
    // rare one. Evicting only [nodeId] left every page inside it cached:
    // measured, purging a section and then asking `readPageShared` for a page
    // that had been inside it returned that page's pre-purge blocks, while
    // `readPage` — the same page, straight from SQLite — correctly returned
    // nothing. Recreating the id later would then surface stale content. The
    // writer returns the complete subtree so there is only one traversal.
    final purged = _writer(notebookId).purgeNode(nodeId);
    final cached = _decodedPages[notebookId];
    if (cached == null) return;
    for (final id in purged) {
      cached.remove(id);
    }
  }

  List<({String id, String kind, String title, int deletedAt})>
      loadDeletedNodes(String notebookId) {
    final rows =
        _db(notebookId).select('SELECT id,kind,title,deleted_at FROM nodes '
            'WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC');
    return [
      for (final r in rows)
        (
          id: r['id'] as String,
          kind: r['kind'] as String,
          title: r['title'] as String,
          deletedAt: r['deleted_at'] as int,
        )
    ];
  }

  /// Distinct pages that link to [pageId] (backlinks, TEXT-8).
  List<String> backlinkPageIds(String notebookId, String pageId) {
    final rows = _db(notebookId).select(
        'SELECT DISTINCT src_page_id FROM refs '
        'WHERE dst_page_id=? AND src_page_id<>?',
        [pageId, pageId]);
    return [for (final r in rows) r['src_page_id'] as String];
  }

  // ── Page content (mirror-write mode, spec §4) ──────────────────────────

  /// How many times a page has been read and decoded out of SQLite — cache
  /// misses, in effect, since [readPageShared] only lands here when it has
  /// nothing cached. For tests that assert caching by COUNT: the wall-clock
  /// versions measured how busy the CI runner was, not whether the cache
  /// worked, and failed on loaded macOS/Linux runners while the cache was
  /// doing its job perfectly.
  static int debugPageDecodes = 0;

  PageData readPage(String notebookId, String pageId) {
    debugPageDecodes++;
    final rows = _db(notebookId)
        .select('SELECT json FROM page_mirror WHERE page_id=?', [pageId]);
    if (rows.isEmpty) return PageData([], PageProps());
    final data = _decodePage(rows.first['json'] as String);
    // **Ink comes back out of its blob here.** Every consumer above this line —
    // the painter, the eraser, lasso, drag, resize, the three exporters —
    // keeps seeing the stroke list it has always seen. Only what is written to
    // disk changed, which is where the 63 MB was.
    //
    // A page with no ink pays nothing: `workingAll` returns the same list
    // object when it changed nothing.
    return PageData(
      InkStorage.workingAll(data.blocks, (h) => getBlob(notebookId, h)),
      data.props,
    );
  }

  static PageData _decodePage(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return PageData(
      [
        for (final b in (j['blocks'] as List? ?? const []))
          Block.fromJson((b as Map).cast<String, dynamic>())
      ],
      PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>()),
    );
  }

  // ── Read-only page access for the summary surfaces ────────────────────
  //
  // The tags rollup, the planner's agenda and the flashcard deck all derive
  // from "every tagged line in the notebook". Deriving that by decoding every
  // page's JSON on the UI thread is what made opening the study tab on a big
  // imported notebook a multi-second freeze — reported directly: "opening the
  // tab is very slow… there has to be a more efficient way".
  //
  // Two layers fix it without introducing a maintained index that could
  // drift (the reasoning at `allTags` still holds — one source of truth):
  //
  //  1. **A SQL prefilter.** Tags live in block content as a `"tags"` key, so
  //     `json LIKE '%"tags":%'` finds every page that could possibly matter —
  //     inside SQLite, in C, without decoding anything. False positives (a
  //     page whose *text* contains the literal string) merely get decoded and
  //     contribute nothing; false negatives are impossible because
  //     `NoteTag.writeInto` writes exactly that key. Most pages carry no tags,
  //     so this alone cuts the work by an order of magnitude.
  //  2. **A decoded-page cache**, invalidated per page on write. `docRevision`
  //     bumps on ANY page save, so the callers' own memos rebuild from scratch
  //     after every keystroke-debounce — with this cache a rebuild re-decodes
  //     only the pages that actually changed.

  final Map<String, Map<String, PageData>> _decodedPages = {};
  static const _decodedPagesMax = 600;

  /// [readPage], through the cache. **The result is shared and must be
  /// treated as read-only** — mutating a block from it would corrupt what
  /// every later caller sees. Editors go through [readPage], which hands out
  /// fresh objects.
  /// How many times a caller has asked for a page through the shared cache.
  ///
  /// Distinct from [debugPageDecodes], and the distinction is the whole point.
  /// That one counts cache MISSES at this layer, so it answers "did we hit
  /// SQLite?" — which a small fixture never does twice however broken the
  /// callers are. This one counts the ASK, which is what the per-keystroke
  /// caches upstream (deck counts, the tag rollup, the planner agenda) exist to
  /// avoid making at all: each of them walks every page in the notebook, and a
  /// cache that stopped holding would show up here as hundreds of reads and in
  /// `debugPageDecodes` as zero.
  ///
  /// Found by writing the assertion the other way round first: a test that
  /// required the decode counter to MOVE when a deck was invalidated failed,
  /// which is what exposed the zero it was pairing with as vacuous.
  static int debugSharedPageReads = 0;

  PageData readPageShared(String notebookId, String pageId) {
    debugSharedPageReads++;
    final perNb = _decodedPages.putIfAbsent(notebookId, () => {});
    final hit = perNb[pageId];
    if (hit != null) return hit;
    if (perNb.length >= _decodedPagesMax) perNb.clear();
    return perNb[pageId] = readPage(notebookId, pageId);
  }

  /// Ids of pages whose stored JSON can contain tags, cheaply.
  List<String> pageIdsWithTags(String notebookId) => [
        for (final r in _db(notebookId).select(
            'SELECT page_id FROM page_mirror WHERE json LIKE ?',
            const ['%"tags":%']))
          r['page_id'] as String
      ];

  /// Pages that still hold their handwriting as inline JSON stroke arrays.
  ///
  /// A SQL prefilter, for the reason spelled out above [pageIdsWithTags]:
  /// decoding all 328 pages of a real notebook to discover that 215 have no ink
  /// is most of the work for none of the win. `"strokes":[{` is deliberately
  /// narrower than `"strokes"` — it excludes an empty array and excludes an
  /// already-converted page, so the conversion is re-runnable and a second run
  /// finds nothing.
  List<String> pageIdsWithInlineInk(String notebookId) => [
        for (final r in _db(notebookId).select(
            'SELECT page_id FROM page_mirror WHERE json LIKE ?',
            const [r'%"strokes":[{%']))
          r['page_id'] as String
      ];

  /// Every block id in [notebookId], from the raw JSON, without decoding it.
  ///
  /// `jsonEncode` writes a block's identity as exactly `"id":"<uuid>"`, so a
  /// string scan recovers all of them at a fraction of the cost of
  /// materialising every page. It can also pick up a lookalike from note
  /// *text* — accepted, because the one consumer (card-state pruning) treats
  /// membership as "do not prune", where an extra id is harmless and a missing
  /// one destroys review history.
  Set<String> allBlockIds(String notebookId) {
    final out = <String>{};
    for (final r in _db(notebookId).select('SELECT json FROM page_mirror')) {
      for (final m in _blockIdRe.allMatches(r['json'] as String)) {
        out.add(m.group(1)!);
      }
    }
    return out;
  }

  static final _blockIdRe = RegExp(r'"id":"([0-9a-f-]{36})"');

  /// Every scrap of page content this container holds, as raw JSON text.
  ///
  /// For the video sweep, which has to answer "does anything anywhere still
  /// name this file?" and where a missed reference deletes a lecture. Three
  /// deliberate choices, each of which is a way the obvious query would be
  /// wrong:
  ///
  ///  * **No `deleted_at` filter.** A page in the recycle bin keeps its
  ///    `page_mirror` row untouched — only `nodes.deleted_at` is stamped — and
  ///    it can be restored for thirty days. The usual
  ///    `WHERE deleted_at IS NULL` would hide precisely the pages whose videos
  ///    look unused, which is the deleted-page-comes-back-empty shape.
  ///  * **No `page_versions` any more, and that is a reduction in pinning
  ///    rather than a hole.** This used to yield up to thirty autosnapshots per
  ///    page as well, so a video removed from a page this morning was still
  ///    named by every snapshot taken before that — for ever, on a single-device
  ///    notebook, because a snapshot is only evicted when thirty newer ones of
  ///    the *same* page exist. Plan decision 1 dropped the table and put
  ///    `recent_deletions`' ten-deep list in its place as an explicit, bounded
  ///    garbage-collection root: [MediaGc] reads its `pins` column, so a video
  ///    in the last ten notable deletions is still safe and one that has fallen
  ///    off the end becomes reclaimable after `kVideoReclaimMinimumAge` — which
  ///    is what that constant was written to be.
  ///  * **Raw text, not decoded pages.** Decoding asks the schema's question;
  ///    the sweep needs the bytes' question. It is also what keeps this from
  ///    materialising a notebook's worth of `Block` objects to look for one
  ///    string.
  ///
  /// Lazy: the caller stops as soon as every candidate has been accounted for.
  Iterable<String> everyStoredPageText(String notebookId) sync* {
    final db = _db(notebookId);
    for (final r in db.select('SELECT json FROM page_mirror')) {
      yield r['json'] as String;
    }
  }

  /// Run [fn] in ONE transaction on [notebookId]'s database. [writePage] uses
  /// savepoints so it nests; imports batch hundreds of page writes into a
  /// single commit instead of paying per-page transaction overhead.
  T runInTransaction<T>(String notebookId, T Function() fn) =>
      _writer(notebookId).runInTransaction(fn);

  void writePage(
      String notebookId, String pageId, List<Block> blocks, PageProps props) {
    // The write is the single funnel every page change goes through — saves,
    // imports and restores — so evicting here is what makes the
    // shared decoded-page cache above trustworthy.
    _decodedPages[notebookId]?.remove(pageId);
    _writer(notebookId).writePage(pageId, blocks, props);
  }

  // ── Blobs (content-addressed) ──────────────────────────────────────────

  String putBlob(String notebookId, Uint8List bytes, String mime) {
    final hash = sha256Hex(bytes);
    _db(notebookId).execute(
        'INSERT OR IGNORE INTO blobs(hash,bytes,mime,size,created_at) '
        'VALUES(?,?,?,?,?)',
        [hash, bytes, mime, bytes.length, nowMs()]);
    return hash;
  }

  @visibleForTesting
  String putContainerBlobForTest(
          String notebookId, Uint8List bytes, String mime) =>
      putBlob(notebookId, bytes, mime);

  Uint8List? getBlob(String notebookId, String hash) =>
      containerBlob(notebookId, hash);

  Uint8List? containerBlob(String notebookId, String hash) {
    final rows = _db(notebookId).select('SELECT bytes FROM blobs WHERE hash=?',
        [hash.replaceFirst('sha256:', '')]);
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
  }

  /// Pages whose content contains [query], with a snippet around the first hit.
  ///
  /// Brute force over `page_mirror` by design (TEXT-7). An FTS5 index would be
  /// faster, but it is a second thing to keep correct — it must be rebuilt on
  /// every write, it can silently drift from the content, and the spec then has
  /// to describe it for third-party writers. Scanning JSON is ~10 ms for a
  /// 300-page notebook, which is well inside "instant" for a search box.
  /// Revisit when a real notebook makes it slow, not before.
  List<({String pageId, String snippet})> searchPageContent(
      String notebookId, String query,
      {int limit = 50}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <({String pageId, String snippet})>[];
    final rows =
        _db(notebookId).select('SELECT page_id, json FROM page_mirror');
    for (final r in rows) {
      final json = r['json'] as String;
      // Cheap reject on the raw JSON before parsing: most pages don't match,
      // and decoding every page's block tree to find that out is the expensive
      // part.
      if (!json.toLowerCase().contains(q)) continue;
      out.add((
        pageId: r['page_id'] as String,
        snippet: _snippetFrom(json, q),
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// A readable line of context around the first match, from the page's text
  /// blocks only — a raw-JSON substring would show field names and coordinates.
  static String _snippetFrom(String json, String lowerQuery) {
    try {
      final j = jsonDecode(json) as Map<String, dynamic>;
      for (final b in (j['blocks'] as List? ?? const [])) {
        final content = (b as Map)['content'] as Map?;
        // `sourceText` is an imported PDF slide's hidden text layer, so a
        // lecture deck is findable by its words even though the page shows a
        // picture (see export/pdf_import.dart).
        final text = content?['text'] ?? content?['sourceText'];
        if (text is! String) continue;
        final i = text.toLowerCase().indexOf(lowerQuery);
        if (i < 0) continue;
        final start = (i - 30).clamp(0, text.length);
        final end = (i + lowerQuery.length + 40).clamp(0, text.length);
        final s = text.substring(start, end).replaceAll('\n', ' ').trim();
        return '${start > 0 ? '…' : ''}$s${end < text.length ? '…' : ''}';
      }
    } catch (_) {/* fall through to no snippet */}
    return '';
  }

  /// Every blob hash with its mime and size, but **not** its bytes.
  ///
  /// Deliberately metadata-only: backup code reads blobs one at a time via
  /// [getBlob], avoiding loading a notebook's images into memory all at once.
  List<({String hash, String mime, int size})> blobIndex(String notebookId) => [
        for (final r in _db(notebookId)
            .select('SELECT hash,mime,size FROM blobs ORDER BY hash'))
          (
            hash: r['hash'] as String,
            mime: r['mime'] as String? ?? 'application/octet-stream',
            size: (r['size'] as num?)?.toInt() ?? 0,
          )
      ];

  void dispose() {
    // Stop the debounced registry writer first: a pending write firing after
    // the workspace has gone away throws an unhandled PathNotFoundException
    // (and in a test, after the temp directory is deleted).
    _writeDebounce?.cancel();
    _writePending = false;
    _disposed = true;
    for (final db in _open.values) {
      checkpointAndClose(db);
    }
    _open.clear();
  }

  bool _disposed = false;
}
