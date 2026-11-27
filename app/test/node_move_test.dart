import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/page_protection.dart';
import 'package:openote/store/media_store.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => expect(initSqliteForTests(), isTrue));
  late Directory directory;
  late Repository repo;
  late AppState app;
  late NotebookRef source, destination;
  late TreeNode section, target, page, child;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('openote_move_');
    repo = await Repository.openAt(directory);
    source = await repo.createNotebook('Source book');
    destination = await repo.createNotebook('Destination book');
    app = AppState(repo)
      ..notebookId = source.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    page = app.pagesOf(section.id).first;
    app.renameNode(page.id, 'Moving page');
    child = app.importNode(
        source.id,
        TreeNode(
            kind: NodeKind.page,
            parentId: section.id,
            title: 'Child',
            position: '${page.position}b',
            level: 1));
    target = repo
        .loadNodes(destination.id)
        .firstWhere((n) => n.kind == NodeKind.section);
    app.reloadNodes();
  });
  tearDown(() async {
    await app.flushSave();
    await repo.flushWorkspace();
    app.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
      'page moves with children, raw unknown content, blobs and external media',
      () async {
    final reminder = app.planner.reminders.add(
        text: 'Linked task',
        at: DateTime(2026, 12, 1),
        notebookId: source.id,
        pageId: page.id);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final hash = repo.putBlob(source.id, bytes, 'application/pdf');
    final video = File('${directory.path}/sample.mp4')..writeAsBytesSync(bytes);
    final media = await MediaStore.add(source, video);
    repo.writePageRawForTest(source.id, page.id, {
      'schema': 'onote-page/1',
      'pageId': page.id,
      'page': {
        'background': 'grid',
        'futureProperty': [42]
      },
      'blocks': [
        {
          'id': 'unknown-block',
          'type': 'future-widget',
          'x': 0,
          'y': 150,
          'w': 100,
          'content': {
            'pdf': hash,
            'media': media,
            'future': {
              'value': [1, 'kept']
            }
          }
        },
      ],
    });
    final before = repo.readPage(source.id, page.id);
    await app.moveNodeTo(page.id, destination.id, sectionId: target.id);
    expect(app.node(page.id), isNull);
    expect(app.node(child.id), isNull);
    expect(reminder.notebookId, destination.id);
    final nodes = repo.loadNodes(destination.id);
    expect(nodes.firstWhere((n) => n.id == page.id).parentId, target.id);
    expect(nodes.firstWhere((n) => n.id == child.id).level, 1);
    final moved = repo.readPage(destination.id, page.id);
    expect(moved.props.toJson(), before.props.toJson());
    expect(moved.blocks.single.toJson()['type'], 'future-widget');
    expect(moved.blocks.single.content['future'], {
      'value': [1, 'kept']
    });
    expect(repo.getBlob(destination.id, hash), bytes);
    final newMedia = moved.blocks.single.content['media'] as String;
    expect(MediaStore.resolve(destination, newMedia)!.readAsBytesSync(), bytes);
    expect(MediaStore.resolve(source, media), isNotNull);
    // Moving back is supported without changing the stable page identities.
    await app.selectNotebook(destination.id);
    await app.moveNodeTo(page.id, source.id, sectionId: section.id);
    expect(repo.loadNodes(source.id).any((n) => n.id == child.id), isTrue);
  });

  test('section keeps live and deleted pages and passcodes', () async {
    final deleted = app.importNode(
        source.id,
        TreeNode(
            kind: NodeKind.page,
            parentId: section.id,
            title: 'Deleted page',
            position: 'z9'));
    repo.writePage(
        source.id,
        deleted.id,
        [
          Block(
              type: BlockType.text,
              x: 0,
              y: 150,
              w: 300,
              content: {'text': 'Restorable content'})
        ],
        PageProps());
    repo.softDeleteNode(source.id, deleted.id);
    app.protectNode(section.id, 'secret', UnlockPolicy.session);
    expect(app.unlockNode(section.id, 'secret'), isTrue);
    await app.moveNodeTo(section.id, destination.id);
    expect(repo.loadNodes(source.id).where((n) => n.id == section.id), isEmpty);
    expect(
        repo
            .loadNodes(destination.id)
            .where((n) => n.parentId == section.id)
            .length,
        2);
    expect(repo.loadDeletedNodes(destination.id).any((n) => n.id == deleted.id),
        isTrue);
    repo.restoreNode(destination.id, deleted.id);
    expect(
        repo.readPage(destination.id, deleted.id).blocks.single.content['text'],
        'Restorable content');
    await app.selectNotebook(destination.id);
    expect(app.isLocked(page.id), isTrue);
    expect(app.unlockNode(section.id, 'secret'), isTrue);
  });

  test('invalid target and ID collision leave the source intact', () async {
    await expectLater(
        app.moveNodeTo(page.id, destination.id, sectionId: 'missing'),
        throwsArgumentError);
    repo.upsertNode(
        destination.id,
        TreeNode(
            id: page.id,
            kind: NodeKind.page,
            parentId: target.id,
            title: 'Existing copy'));
    await expectLater(
        app.moveNodeTo(page.id, destination.id, sectionId: target.id),
        throwsStateError);
    expect(app.node(page.id), isNotNull);
    expect(app.node(child.id), isNotNull);
    expect(
        repo.loadNodes(destination.id).firstWhere((n) => n.id == page.id).title,
        'Existing copy');
  });

  test('same-book move carries children and updates the active section',
      () async {
    final other = app.importNode(
        source.id, TreeNode(kind: NodeKind.section, title: 'Other section'));
    app.reloadNodes();
    await app.selectPage(page.id);
    app.protectNode(section.id, 'secret', UnlockPolicy.session);
    app.unlockNode(section.id, 'secret');
    await app.moveNodeTo(page.id, source.id, sectionId: other.id);
    expect(app.node(child.id)!.parentId, other.id);
    expect(app.pageId, page.id);
    expect(app.activeSectionId, other.id);
    app.reloadProtection();
    expect(app.isLocked(page.id), isTrue);
    expect(app.unlockNode(page.id, 'secret'), isTrue);
  });

  test('missing attachments abort before removing any source nodes', () async {
    repo.writePage(
        source.id,
        page.id,
        [
          Block(
              type: BlockType.image,
              x: 0,
              y: 150,
              content: {'blob': List.filled(64, 'a').join()})
        ],
        PageProps());
    await expectLater(
        app.moveNodeTo(page.id, destination.id, sectionId: target.id),
        throwsStateError);
    expect(repo.loadNodes(source.id).any((n) => n.id == page.id), isTrue);
    expect(repo.loadNodes(destination.id).any((n) => n.id == page.id), isFalse);
  });

  test('unsaved changes in both split editors are saved before a move',
      () async {
    await app.selectPage(page.id);
    final split = await app.createSplitEditor();
    await split.selectPage(child.id);
    app.addBlock(Block(
        type: BlockType.text,
        x: 0,
        y: 150,
        content: {'text': 'Unsaved parent'}));
    split.addBlock(Block(
        type: BlockType.text,
        x: 0,
        y: 150,
        content: {'text': 'Unsaved child'}));
    await app.moveNodeTo(page.id, destination.id, sectionId: target.id);
    expect(repo.readPage(destination.id, page.id).blocks.single.content['text'],
        'Unsaved parent');
    expect(
        repo.readPage(destination.id, child.id).blocks.single.content['text'],
        'Unsaved child');
    expect(app.pageId, isNull);
    expect(split.pageId, isNull);
    expect(app.hasUnsavedChanges, isFalse);
  });

  testWidgets('context menu lets a page choose a notebook and its section',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showNodeMenu(context, app, page,
                        canIndent: true, position: const Offset(100, 100)),
                    child: const Text('Open menu'))))));
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    expect(find.text('Source book'), findsOneWidget);
    expect(find.text('No other sections in this notebook.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Move'))
            .onPressed,
        isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination book').last);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.node(page.id), isNotNull);
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination book').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    for (var i = 0; app.node(page.id) != null && i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(app.node(page.id), isNull);
    expect(repo.loadNodes(destination.id).any((n) => n.id == page.id), isTrue);
    expect(tester.takeException(), isNull);
  });
}
