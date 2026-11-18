import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Repository repo;
  setUpAll(() => expect(initSqliteForTests(), isTrue));
  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('openote_names_');
    repo =
        await Repository.openAt(Directory(p.join(temporary.path, 'workspace')));
  });
  tearDown(() {
    repo.dispose();
    temporary.deleteSync(recursive: true);
  });

  void expectMatchingNames(NotebookRef book, String name) {
    expect(book.title, name);
    expect(p.basename(p.dirname(book.file)), '$name.onotebook');
    expect(p.basename(book.file), '$name.onote');
    expect(File(book.file).existsSync(), isTrue);
  }

  Future<String> originalFile() async {
    final source =
        await Repository.openAt(Directory(p.join(temporary.path, 'source')));
    final book = await source.createNotebook('Informatik');
    final page =
        source.loadNodes(book.id).firstWhere((n) => n.kind == NodeKind.page);
    source.writePage(
        book.id,
        page.id,
        [
          Block(
              type: BlockType.text,
              x: 1,
              y: 2,
              content: {'text': 'Keep the original'})
        ],
        PageProps());
    source.dispose();
    return book.file;
  }

  test('direct notebook imports number display, folder and file together',
      () async {
    await repo.createNotebook('Informatik');
    final source = await originalFile();
    for (var number = 2; number <= 4; number++) {
      expectMatchingNames(
          await repo.openExistingNotebook(source), 'Informatik $number');
    }
    expect(repo.notebooks.map((n) => n.title).toSet(), hasLength(4));
  });

  test(
      'import numbering continues beyond existing suffixes instead of filling gaps',
      () async {
    await repo.createNotebook('Informatik');
    await repo.createNotebook('Informatik 3');
    expectMatchingNames(
        await repo.openExistingNotebook(await originalFile()), 'Informatik 4');
  });

  test('OneNote import creation also reserves numbered names including trash',
      () async {
    final original = await repo.createNotebook('Informatik');
    await repo.trashNotebook(original.id);
    final app = AppState(repo);
    try {
      expectMatchingNames(
          await app.importCreateNotebook('Informatik'), 'Informatik 2');
      expectMatchingNames(
          await app.importCreateNotebook('Informatik'), 'Informatik 3');
    } finally {
      app.dispose();
    }
  });

  test('adopting a loose notebook creates its own matching folder', () async {
    final source = await originalFile();
    final loose = p.join(repo.workspaceDir.path, 'Informatik.onote');
    File(source).copySync(loose);
    expectMatchingNames(await repo.adoptWorkspaceNotebook(loose), 'Informatik');
    expect(File(loose).existsSync(), isFalse);
  });

  test('application rename keeps Unicode names and container metadata portable',
      () async {
    final book = await repo.createNotebook('Französisch');
    expectMatchingNames(book, 'Französisch');
    await repo.renameNotebook(book.id, 'Mathe');
    expectMatchingNames(book, 'Mathe');
    repo.dispose();
    File(p.join(repo.workspaceDir.path, 'workspace.json')).deleteSync();
    File(p.join(repo.workspaceDir.path, 'workspace.json.bak')).deleteSync();
    repo = await Repository.openAt(repo.workspaceDir);
    expect(repo.notebooks.single.id, book.id);
    expectMatchingNames(repo.notebooks.single, 'Mathe');
  });

  test('case-only renames update the actual Windows folder and file names',
      () async {
    final book = await repo.createNotebook('Englisch');
    await repo.renameNotebook(book.id, 'englisch');
    expectMatchingNames(book, 'englisch');
    final folder = repo.workspaceDir.listSync().whereType<Directory>().single;
    expect(p.basename(folder.path), 'englisch.onotebook');
    expect(
        folder
            .listSync()
            .whereType<File>()
            .any((file) => p.basename(file.path) == 'englisch.onote'),
        isTrue);
  });

  test('registered loose notebooks are placed in their own folder on refresh',
      () async {
    final book = await repo.createNotebook('Informatik');
    repo.closeNotebook(book.id);
    final oldFolder = Directory(p.dirname(book.file));
    final loose = p.join(repo.workspaceDir.path, 'Informatik.onote');
    File(book.file).renameSync(loose);
    oldFolder.deleteSync();
    book.file = loose;
    await repo.refreshNotebooks();
    expectMatchingNames(book, 'Informatik');
    expect(File(loose).existsSync(), isFalse);
  });

  test('Explorer folder rename is reconciled after restart without a duplicate',
      () async {
    final book = await repo.createNotebook('Englisch');
    final root = repo.workspaceDir;
    repo.dispose();
    Directory(p.dirname(book.file))
        .renameSync(p.join(root.path, 'Mathe.onotebook'));
    repo = await Repository.openAt(root);
    expect(repo.notebooks, hasLength(1));
    expect(repo.notebooks.single.id, book.id);
    expectMatchingNames(repo.notebooks.single, 'Mathe');
  });

  test('Explorer container rename updates its folder and display on refresh',
      () async {
    final book = await repo.createNotebook('Englisch');
    repo.closeNotebook(book.id);
    File(book.file).renameSync(p.join(p.dirname(book.file), 'Mathe.onote'));
    await repo.refreshNotebooks();
    expect(repo.notebooks, hasLength(1));
    expect(repo.notebooks.single.id, book.id);
    expectMatchingNames(book, 'Mathe');
  });

  test('Explorer folder rename is also detected without restarting', () async {
    final book = await repo.createNotebook('Englisch');
    repo.closeNotebook(book.id);
    Directory(p.dirname(book.file))
        .renameSync(p.join(repo.workspaceDir.path, 'Mathe.onotebook'));
    final app = AppState(repo)..notebookId = book.id;
    final previousNavigation = app.navRevision;
    try {
      await app.refreshNotebooks();
      expect(repo.notebooks, hasLength(1));
      expectMatchingNames(book, 'Mathe');
      expect(app.navRevision, greaterThan(previousNavigation),
          reason: 'cached navigation must repaint the changed book name');
    } finally {
      app.dispose();
    }
  });

  test(
      'legacy duplicate labels and dash suffixes become matching numbered names',
      () async {
    await repo.createNotebook('Informatik');
    final copy = await repo.createNotebook('Informatik 2');
    repo.closeNotebook(copy.id);
    final folder = p.join(repo.workspaceDir.path, 'Informatik-2.onotebook');
    Directory(p.dirname(copy.file)).renameSync(folder);
    File(p.join(folder, 'Informatik 2.onote'))
        .renameSync(p.join(folder, 'Informatik-2.onote'));
    repo.dispose();
    final registryFile = File(p.join(repo.workspaceDir.path, 'workspace.json'));
    final registry =
        jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>;
    final entry = (registry['notebooks'] as List)
        .cast<Map>()
        .singleWhere((n) => n['id'] == copy.id);
    entry['title'] = 'Informatik';
    entry['file'] = p.join('Informatik-2.onotebook', 'Informatik-2.onote');
    registryFile.writeAsStringSync(jsonEncode(registry));
    repo = await Repository.openAt(repo.workspaceDir);
    expect(repo.notebooks.map((n) => n.title).toSet(),
        {'Informatik', 'Informatik 2'});
    expectMatchingNames(
        repo.notebooks.singleWhere((n) => n.id == copy.id), 'Informatik 2');
  });
}
