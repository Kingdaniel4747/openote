import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/engine.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

class _DelayedSnapshotEngine implements DocumentEngine {
  _DelayedSnapshotEngine(this.repo);

  final Repository repo;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  String get label => 'Delayed test engine';

  @override
  String? get lastSavedHash => null;

  @override
  Future<PageData> loadPage(String notebookId, String pageId) async =>
      repo.readPage(notebookId, pageId);

  @override
  Future<void> savePage(String notebookId, String pageId, List<Block> blocks,
      PageProps props) async {
    final snapshot = [
      for (final block in blocks)
        Block.fromJson((jsonDecode(jsonEncode(block.toJson())) as Map)
            .cast<String, dynamic>()),
    ];
    if (!started.isCompleted) started.complete();
    await release.future;
    repo.writePage(notebookId, pageId, snapshot, props);
  }
}

void main() {
  test('an older save cannot mark a newer text edit as saved', () async {
    if (!initSqliteForTests()) return markTestSkipped('sqlite unavailable');
    AppState.syncLogEnabled = false;
    final tmp = Directory.systemTemp.createTempSync('onote_save_generation_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      AppState.syncLogEnabled = true;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final notebook = await repo.createNotebook('Generation');
    final engine = _DelayedSnapshotEngine(repo);
    final app = AppState(repo, documentEngine: engine)
      ..notebookId = notebook.id
      ..nodes = repo.loadNodes(notebook.id);
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    final text =
        Block(type: BlockType.text, x: 10, y: 100, content: {'text': 'older'});
    app
      ..pageId = pageId
      ..blocks = [text]
      ..markDirty();

    final firstSave = app.flushSave();
    await engine.started.future;
    text.content['text'] = 'newer';
    app.markDirty();
    engine.release.complete();
    await firstSave;

    expect(app.hasUnsavedChanges, isTrue);
    await app.flushSave();
    expect(repo.readPage(notebook.id, pageId).blocks.single.content['text'],
        'newer');
    app.cancelPendingSave();
  });
}
