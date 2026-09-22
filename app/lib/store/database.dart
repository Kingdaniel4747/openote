/// The .onote container — File Format Spec (docs/specs/10-file-format-spec.md).
///
/// `page_mirror` is the authoritative page store. There is one durable copy of
/// a page in its local `.onote` container.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqlite3/sqlite3.dart';

const onoteApplicationId = 0x4F4E4F54; // "ONOT"

/// What a container that is somebody's **notebook file** is stamped with.
///
/// Still 1, deliberately, and it stays 1: a notebook a student can hand to
/// another computer is a v1 `.onote` and every build ever released reads one.
const onoteFormatMajor = 1;

/// Version 2 existed in prerelease builds. It remains readable so removing the
/// abandoned storage design does not strand notebooks created by those builds.
const onoteWorkingCopyVersion = 2;

/// Why a file handed to Openote from OUTSIDE the app — the command line, a
/// double-click in the file manager — cannot be opened as a notebook.
enum NotebookFileProblem {
  /// Nothing at that path.
  missing,

  /// A folder, or a device — not a file we can read.
  notAFile,

  /// It is there, but this process cannot read it.
  unreadable,

  /// Readable, and not one of ours.
  notANotebook,
}

/// Sniff [path] and say why it could not be a notebook, or null when it looks
/// like one.
///
/// **This runs BEFORE anything opens or copies the file, and that ordering is
/// the whole point.** [openOnote] treats an `application_id` of zero as "a
/// fresh file" and seeds a brand-new notebook into it, and
/// `Repository.openExistingNotebook` copies its argument into the workspace
/// *first* and opens it *second*. Point the two of them at a stray empty file
/// — trivially reachable, because Explorer will happily hand us anything the
/// user renamed to `.onote` — and the result is a mystery blank notebook
/// permanently in the sidebar. Point them at a `.txt` and the copy has already
/// landed in the workspace by the time SQLite objects.
///
/// The test is the container's own identity, and deliberately the SAME rule
/// `packaging/linux/openote.xml` gives the desktop: "SQLite format 3" at
/// offset 0 *and* `application_id` = "ONOT" at offset 68, which is where
/// SQLite keeps that field. Matching only the SQLite magic would claim every
/// database on the machine.
///
/// The one concession is an `application_id` of zero **with a `-wal` file
/// beside it**. Notebooks are opened `journal_mode=WAL`, so a container whose
/// header change has not been checkpointed back yet still reads as zeros here;
/// `checkpointAndClose` means that only survives a crash, but calling a real
/// notebook "not a notebook" because the app died once is the wrong way to be
/// wrong. The real open decides that case.
NotebookFileProblem? notebookFileProblem(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: true);
  if (type == FileSystemEntityType.notFound) return NotebookFileProblem.missing;
  if (type != FileSystemEntityType.file) return NotebookFileProblem.notAFile;

  Uint8List head;
  try {
    final handle = File(path).openSync();
    try {
      head = handle.readSync(_headerBytes);
    } finally {
      handle.closeSync();
    }
  } catch (_) {
    return NotebookFileProblem.unreadable;
  }
  if (head.length < _headerBytes) return NotebookFileProblem.notANotebook;
  for (var i = 0; i < _sqliteMagic.length; i++) {
    if (head[i] != _sqliteMagic[i]) return NotebookFileProblem.notANotebook;
  }
  // Big-endian, like every multi-byte field in a SQLite header.
  final appId =
      (head[68] << 24) | (head[69] << 16) | (head[70] << 8) | head[71];
  if (appId == onoteApplicationId) return null;
  if (appId == 0 && File('$path-wal').existsSync()) return null;
  return NotebookFileProblem.notANotebook;
}

/// Offset 68 holds `application_id`; 72 is the first byte past it.
const int _headerBytes = 72;

/// The 16 bytes every SQLite file starts with: `SQLite format 3` and a NUL.
/// Spelled as bytes rather than as a string literal because the sixteenth byte
/// is a zero — a literal is the one way to write this that either hides a real
/// NUL in the source or, worse, quietly puts a space there instead.
const List<int> _sqliteMagic = [
  0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
  0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3" + NUL
];

/// Thrown by [openExistingOnote] when the container it was told to open is not
/// there. Carries the path for the Advanced fold and nothing else.
class NotebookFileMissing implements Exception {
  const NotebookFileMissing(this.path);
  final String path;

  @override
  String toString() => 'no notebook file at $path';
}

/// [openOnote], for a container that is **expected to already exist**.
///
/// **The difference is that this one refuses to invent a notebook** (v0.17
/// plan, Step 8 item 2). [openOnote] treats an `application_id` of zero as "a
/// fresh file" and seeds a brand-new notebook into it — which is right for
/// `createNotebook` and `adoptLogDirectory`, the two callers that genuinely
/// mean "make me one", and catastrophic for every other caller, which means
/// "open the one that is there".
///
/// Reachable today, without any migration: `Repository._db` opened whatever
/// path the registry named with no existence check at all, so an unmounted
/// drive, a cloud client that had evicted the file, or a container the user
/// moved in Explorer produced a valid `Database` with 0 nodes and 0 pages and
/// left a 73,728-byte file behind — after which `notebookFileProblem` reports
/// it as *"looks like a notebook"* and the real one is no longer registered.
///
/// It is also the single hazard that turned a crash into a disaster in the
/// spike this whole plan is written around: killed immediately after a rename,
/// the obvious *"just run it again"* called `openOnote` on the now-missing old
/// path, fabricated an empty database, and renamed it over the real
/// container — which `File.renameSync` on Windows does silently. 329 pages
/// became 73,728 bytes with `integrity_check` reporting `ok`.
Database openExistingOnote(String path,
    {required String notebookId, required String title}) {
  // `typeSync`, not `existsSync`: a directory at this path should produce the
  // same clear missing-file error on every platform.
  if (FileSystemEntity.typeSync(path, followLinks: true) !=
      FileSystemEntityType.file) {
    throw NotebookFileMissing(path);
  }
  return openOnote(path, notebookId: notebookId, title: title);
}

Database openOnote(String path,
    {required String notebookId, required String title}) {
  final db = sqlite3.open(path);
  // **Before `journal_mode`, and before any table exists.** `auto_vacuum` can
  // only be set on a database with no pages — after that it takes a full
  // `VACUUM` to change, which is why this line's position is load-bearing
  // rather than stylistic.
  //
  // INCREMENTAL rather than FULL: FULL repacks on every commit. INCREMENTAL
  // records reusable pages without adding that cost to ordinary saves.
  db.execute('PRAGMA auto_vacuum=INCREMENTAL;');
  db.execute('PRAGMA journal_mode=WAL;');
  // WAL's recommended durability level: commits don't each fsync (a power cut
  // can lose the last few commits but never corrupts). Import measured ~700
  // small transactions; FULL fsync'd every one.
  db.execute('PRAGMA synchronous=NORMAL;');
  db.execute('PRAGMA foreign_keys=ON;');

  final appId = db.select('PRAGMA application_id;').first.columnAt(0) as int;
  final freshFile = appId == 0;
  if (!freshFile && appId != onoteApplicationId) {
    db.dispose();
    throw StateError('Not an Openote notebook: $path');
  }
  if (!freshFile) {
    final ver = db.select('PRAGMA user_version;').first.columnAt(0) as int;
    // **Two accepted values, not one** (v0.17 Step 8). 1 is a notebook file; 2
    // is this app's own working copy, which this build both writes and reads.
    // Anything higher is a format nobody here has heard of and is refused, which
    // is the same sentence a pre-v0.17 build gives a `cache.onote`.
    if (ver > onoteWorkingCopyVersion) {
      db.dispose();
      throw StateError(
          'Notebook format v$ver is newer than this app supports.');
    }
  }
  // Every table/index is created idempotently on EVERY open, so a notebook made
  // by an earlier build that predates a table (e.g. refs) gains it here rather
  // than throwing on first write.
  _ensureSchema(db);
  _dropBlobRefsBlobsFk(db);
  if (freshFile) {
    _seedNotebook(db, notebookId: notebookId, title: title);
  }
  return db;
}

/// Rewrite `blob_refs` without its foreign key onto `blobs(hash)`.
///
/// **The one schema change v0.17 Step 6 could not avoid**, and the plan says
/// this step needs no migration at all — it does. Step 6 stops the container
/// storing blob bytes, so from that release on there is no `blobs` row for any
/// new picture. `writePage` records the page's blob references unconditionally
/// now (it has to: `blob_refs` is ADR-0007's GC root set, and a root set that
/// can only name bytes the container holds names nothing once the container
/// holds nothing). With the key still present that INSERT raises a constraint
/// violation *inside `writePage`'s savepoint*, which fails the whole page save.
///
/// `CREATE TABLE IF NOT EXISTS` does not alter a table that already exists, so
/// changing the DDL above fixes new notebooks only; every notebook already on
/// disk has to be rewritten here. SQLite cannot drop a constraint in place, so
/// this is the documented twelve-step procedure
/// (<https://sqlite.org/lang_altertable.html>) reduced to what applies: build
/// the replacement, copy, drop, rename.
///
/// **Not a format bump.** `user_version` stays 1 deliberately — v2 is Step 8's,
/// and a build that predates this one opens a rewritten container perfectly
/// well: its `writePage` uses the old `SELECT … FROM blobs` form, which simply
/// records fewer rows, exactly as it does today.
///
/// Best-effort by design. A read-only volume or a full disk must still open the
/// notebook and show it (matrix row D5), and [NotebookWriter.writePage] falls
/// back to the old conditional INSERT when it meets the key still in place, so
/// a container this could not rewrite keeps saving.
void _dropBlobRefsBlobsFk(Database db) {
  try {
    final rows = db.select(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='blob_refs'");
    final ddl = rows.isEmpty ? null : rows.first['sql'] as String?;
    if (ddl == null || !ddl.contains('REFERENCES blobs')) return;
    // Outside any transaction, and off while the table is swapped: with
    // enforcement ON, `DROP TABLE blob_refs` would be checked against the very
    // rows being carried across.
    db.execute('PRAGMA foreign_keys=OFF;');
    try {
      db.execute('BEGIN;');
      db.execute('''
        CREATE TABLE blob_refs_new (
          page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
          hash TEXT NOT NULL,
          PRIMARY KEY (page_id, hash));
      ''');
      db.execute('INSERT OR IGNORE INTO blob_refs_new(page_id,hash) '
          'SELECT page_id,hash FROM blob_refs;');
      db.execute('DROP TABLE blob_refs;');
      db.execute('ALTER TABLE blob_refs_new RENAME TO blob_refs;');
      db.execute('COMMIT;');
    } catch (_) {
      try {
        db.execute('ROLLBACK;');
      } catch (_) {/* nothing was open */}
      rethrow;
    } finally {
      db.execute('PRAGMA foreign_keys=ON;');
    }
  } catch (e) {
    // Said out loud rather than swallowed: the fallback in `writePage` keeps
    // saves working, but a container stuck here has an under-recorded GC root
    // set, and Step 7 must not run against one.
    debugPrint('[openote/store] blob_refs could not be rewritten: $e');
  }
}

/// Fold the write-ahead log back into the database, then close.
///
/// **Measured, on a real workspace:** `My Notebook.onote` was 2.8 MB with a
/// **4.1 MB** `-wal` beside it, and a 94 MB container carried 7.4 MB. SQLite
/// only checkpoints automatically at a page threshold and never truncates the
/// file, so a session that ends between thresholds leaves the whole WAL on
/// disk — permanently, because the next open starts appending again rather
/// than reclaiming it.
///
/// `TRUNCATE` (not `PASSIVE` or `FULL`) is the mode that actually returns the
/// space: the other two fold the pages in and leave the file at its
/// high-water mark, which is exactly the state being fixed.
///
/// Best-effort. A checkpoint can legitimately fail — another connection is
/// mid-read, the volume is gone — and a failure here must never stop the app
/// closing. The data is already durable either way; this is about the file's
/// size, not its contents.
void checkpointAndClose(Database db) {
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
  } catch (_) {
    // Nothing to do about it, and nothing at risk.
  }
  db.dispose();
}

/// Idempotent DDL — safe to run on every open (all `IF NOT EXISTS`).
void _ensureSchema(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS notebook_meta (
      key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS nodes (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK (kind IN ('section_group','section','page')),
      parent_id TEXT REFERENCES nodes(id) ON DELETE CASCADE,
      title TEXT NOT NULL DEFAULT '',
      position TEXT NOT NULL,
      color TEXT, level INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      deleted_at INTEGER);
    CREATE INDEX IF NOT EXISTS idx_nodes_parent ON nodes(parent_id, position);
    -- page_mirror is the authoritative page store.
    CREATE TABLE IF NOT EXISTS page_mirror (
      page_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      json TEXT NOT NULL, mirror_rev INTEGER NOT NULL, updated_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS blobs (
      hash TEXT PRIMARY KEY, bytes BLOB NOT NULL, mime TEXT NOT NULL,
      size INTEGER NOT NULL, created_at INTEGER NOT NULL);
    -- No hash foreign key is retained for compatibility with older notebooks.
    CREATE TABLE IF NOT EXISTS blob_refs (
      page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      hash TEXT NOT NULL,
      PRIMARY KEY (page_id, hash));
    CREATE TABLE IF NOT EXISTS refs (
      src_page_id TEXT NOT NULL, src_block_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('link','embed')),
      dst_page_id TEXT NOT NULL, dst_notebook TEXT, dst_target TEXT,
      PRIMARY KEY (src_page_id, src_block_id, kind));
    CREATE INDEX IF NOT EXISTS idx_refs_dst ON refs(dst_page_id);
  ''');
  db.execute('''
    DROP TABLE IF EXISTS page_docs;
    DROP TABLE IF EXISTS page_updates;
    DROP TABLE IF EXISTS page_versions;
    DROP TABLE IF EXISTS block_authors;
    DROP TABLE IF EXISTS recent_deletions;
    DROP TABLE IF EXISTS fts_pages;
  ''');
}

/// First-create-only: stamp the format identity and seed notebook metadata.
void _seedNotebook(Database db,
    {required String notebookId, required String title}) {
  db.execute('PRAGMA application_id = $onoteApplicationId;');
  db.execute('PRAGMA user_version = $onoteFormatMajor;');
  final now = DateTime.now().millisecondsSinceEpoch;
  final meta = <String, Object?>{
    'format': {'major': onoteFormatMajor, 'minor': 0},
    'notebook_id': notebookId,
    'title': title,
    'created_at': now,
    'app': 'openote/0.1.0',
    'features': <String>[],
    // `page_mirror` is the authoritative store in this container, not a
    // projection of something else — so there is no CRDT state for a
    // `dirty_mirror` flag to mark as stale, and setting one would tell a
    // third-party reader the opposite of the truth. Declared as a capability
    // instead: a reader that understands SQLite + JSON has everything.
    'content': 'page_mirror',
  };
  final stmt = db
      .prepare('INSERT OR REPLACE INTO notebook_meta(key,value) VALUES (?,?)');
  meta.forEach((k, v) => stmt.execute([k, jsonEncode(v)]));
  stmt.dispose();
}
