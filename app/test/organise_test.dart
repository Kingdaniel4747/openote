// Recents, page hierarchy and the page outline
// (TEXT-10) — the state logic behind the navigator and the outline panel.
//
// The property that matters most here is that sorting keeps subpages attached
// to their parent: pages carry a level, the navigator renders hierarchy from
// contiguous runs, so a sort that reorders pages individually silently
// reparents every subpage in the section.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory, AppState, String)> fixture(
      String prefix) async {
    final tmp = Directory.systemTemp.createTempSync(prefix);
    final repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Organise');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    return (repo, tmp, app, section);
  }

  /// Add a page under [section]; `level > 0` makes it a subpage of whatever
  /// precedes it.
  TreeNode addPage(AppState app, String section, String title, String pos,
      {int level = 0, int? updatedAt}) {
    final n = TreeNode(
        kind: NodeKind.page, parentId: section, title: title, position: pos)
      ..level = level;
    if (updatedAt != null) n.updatedAt = updatedAt;
    final saved = app.importNode(app.notebookId!, n);
    app.reloadNodes();
    return saved;
  }

  test('nesting keeps descendants and rejects cycles or excessive depth',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app, section) = await fixture('onote_nest_tree_');
    addTearDown(() {
      app.cancelPendingSave();
      app.dispose();
      repo.dispose();
      tmp.deleteSync(recursive: true);
    });
    final parent = addPage(app, section, 'Parent', 'a000');
    final child = addPage(app, section, 'Child', 'a010', level: 1);
    final grandchild = addPage(app, section, 'Grandchild', 'a020', level: 2);
    final sibling = addPage(app, section, 'Sibling', 'a030', level: 1);
    final target = addPage(app, section, 'Target', 'z1');
    final before =
        app.pagesOf(section).map((p) => (p.id, p.level, p.position)).toList();
    app.reorderPageTree(parent.id, child.id, after: true, nest: true);
    expect(
        app.pagesOf(section).map((p) => (p.id, p.level, p.position)), before);
    app.reorderPageTree(parent.id, target.id, after: true, nest: true);
    expect(app.pagesOf(section).map((p) => (p.id, p.level, p.position)), before,
        reason: 'a full branch must never be flattened at the maximum depth');
    app.collapsedPages.add(child.id);
    app.reorderPageTree(child.id, target.id, after: true, nest: true);
    final pages = app.pagesOf(section);
    final at = pages.indexWhere((p) => p.id == target.id);
    expect(
        pages.skip(at).map((p) => p.id), [target.id, child.id, grandchild.id]);
    expect(
        pages[pages.indexWhere((p) => p.id == parent.id) + 1].id, sibling.id);
    final saved = {for (final p in repo.loadNodes(app.notebookId!)) p.id: p};
    expect(saved[child.id]!.level, 1);
    expect(saved[grandchild.id]!.level, 2);
    expect(saved[grandchild.id]!.parentId, section);
  });

  test('manual page order survives renaming and reload with its subpages',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app, section) = await fixture('onote_manual_order_');
    addTearDown(() {
      app.cancelPendingSave();
      app.dispose();
      repo.dispose();
      tmp.deleteSync(recursive: true);
    });
    final parent = addPage(app, section, 'Zebra', 'z1');
    final child = addPage(app, section, 'Child', 'z2', level: 1);
    final other = addPage(app, section, 'Apple', 'z3');
    app.reorderPageTree(other.id, parent.id, after: false);
    final order = app.pagesOf(section).map((p) => p.id).toList();
    app.renameNode(other.id, 'Zulu');
    app.renameNode(parent.id, 'AAA');
    app.reloadNodes();
    final pages = app.pagesOf(section);
    expect(pages.map((p) => p.id), order);
    expect(pages[pages.indexWhere((p) => p.id == parent.id) + 1].id, child.id);
    final positions = pages.map((p) => p.position).toList();
    expect(positions.toSet().length, positions.length);
    expect(positions, [...positions]..sort());
  });

  group('recents (ORG-10)', () {
    test('recents record most-recent-first and de-duplicate', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_recent_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final a = addPage(app, section, 'A', 'a100');
      final b = addPage(app, section, 'B', 'a200');
      await app.selectPage(a.id);
      await app.selectPage(b.id);
      await app.selectPage(a.id); // revisit

      final recent = app.recentPages().map((n) => n.id).toList();
      expect(recent.first, a.id, reason: 'most recent first');
      expect(recent.where((id) => id == a.id).length, 1,
          reason: 'a revisit moves the entry, it does not duplicate it');
      expect(recent, contains(b.id));
    });
  });

  group('page outline (TEXT-10)', () {
    test('lists headings in reading order with their levels', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_toc_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final page = addPage(app, section, 'Outlined', 'a100');
      await app.selectPage(page.id);
      // Deliberately added out of vertical order: reading order is y, not
      // insertion order.
      app.blocks = [
        Block(
            type: BlockType.text,
            x: 0,
            y: 200,
            content: {'text': '## Second\nbody'}),
        Block(
            type: BlockType.text,
            x: 0,
            y: 10,
            content: {'text': '# First\nnot a heading\n### Third'}),
      ];
      app.docRevision++;

      final items = app.pageOutline();
      expect(items.map((i) => i.text).toList(), ['First', 'Third', 'Second']);
      expect(items.map((i) => i.level).toList(), [1, 3, 2]);
    });

    test('a page with no headings yields an empty outline', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_toc_empty_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final page = addPage(app, section, 'Plain', 'a100');
      await app.selectPage(page.id);
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'just prose'})
      ];
      app.docRevision++;
      expect(app.pageOutline(), isEmpty);
    });
  });
}
