import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/api/learning_access.dart';
import 'package:openote/export/pdf_vector_export.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/page_protection.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/learning_access_dialog.dart';

import 'support/sqlite.dart';

// Only this loopback integration test bypasses the widget binding's fake HTTP.
class _LoopbackHttp extends HttpOverrides {}

Map<String, dynamic> body(Map<String, dynamic> result) =>
    jsonDecode((result['content'] as List).first['text'])
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Repository repo;
  late AppState app;
  late LearningAccess access;
  late String first;
  late String second;
  Object? settings;
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  setUp(() async {
    if (!haveSqlite) return;
    directory = Directory.systemTemp.createTempSync('openote-learning-');
    repo = await Repository.openAt(directory);
    final notebook = await repo.createNotebook('Learning');
    app = AppState(repo);
    await app.selectNotebook(notebook.id);
    first = app.pageId!;
    second = TreeNode(
            kind: NodeKind.page,
            parentId: app.node(first)!.parentId,
            title: 'Second page',
            position: 'a1')
        .id;
    repo.upsertNode(
        notebook.id,
        TreeNode(
            id: second,
            kind: NodeKind.page,
            parentId: app.node(first)!.parentId,
            title: 'Second page',
            position: 'a1'));
    repo.writePage(
        notebook.id,
        second,
        [
          Block(
              type: BlockType.text,
              x: 64,
              y: 100,
              content: {'text': 'Second page stored material'})
        ],
        PageProps());
    app.reloadNodes();
    app.blocks = [
      Block(
          type: BlockType.text,
          x: 64,
          y: 100,
          content: {'text': 'Unsaved first page algebra'})
    ];
    settings = {'port': 0}; // Use OS-assigned ports in parallel tests.
    access = LearningAccess(app,
        readSettings: () => settings,
        writeSettings: (value) => settings = value,
        renderSheet: (_, __, ___) async => Uint8List.fromList([1, 2, 3]));
    // A saved port of zero is deliberately not accepted in production. Start
    // the test listener on zero explicitly before enabling a sharing mode.
    access.port = 0;
  });
  tearDown(() async {
    if (!haveSqlite) return;
    await access.stop();
    access.dispose();
    app.cancelPendingSave();
    await repo.flushWorkspace();
    app.dispose();
    await Future<void>.delayed(Duration.zero);
    directory.deleteSync(recursive: true);
  });

  Future<void> enable(LearningScope scope) async {
    await access.setScope(scope);
    expect(access.error, isNull);
    expect(access.scope, scope);
  }

  test('off is the default and no write tools exist', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await expectLater(access.call('read_page', {}), throwsFormatException);
    expect(
        LearningAccess.tools
            .every((t) => t['annotations']['readOnlyHint'] == true),
        isTrue);
    await enable(LearningScope.page);
    await expectLater(access.call('write_page', {}), throwsFormatException);
    await expectLater(access.call('read_page', {'notebookId': 'other'}),
        throwsFormatException);
  });

  test(
      'page scope uses unsaved state and follows navigation, rejects other IDs',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await enable(LearningScope.page);
    expect(body(await access.call('read_page', {}))['text'],
        contains('Unsaved first'));
    expect(body(await access.call('list_pages', {}))['total'], 1);
    await expectLater(
        access.call('read_page', {'pageId': second}), throwsFormatException);
    await app.selectPage(second);
    expect(body(await access.call('get_context', {}))['currentPageId'], second);
    expect(body(await access.call('read_page', {}))['text'],
        contains('Second page stored'));
    await expectLater(
        access.call('read_page', {'pageId': first}), throwsFormatException);
  });

  test('book scope reads all its pages, stays pinned across notebook switches',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await enable(LearningScope.notebook);
    expect(
        body(await access.call('list_pages', {'limit': 1}))['nextOffset'], 1);
    expect(body(await access.call('list_pages', {'offset': 1}))['pages'],
        hasLength(1));
    expect(body(await access.call('read_page', {'pageId': second}))['text'],
        contains('stored material'));
    final original = app.notebookId!;
    final other = await repo.createNotebook('Private');
    await app.selectNotebook(other.id);
    await expectLater(access.call('list_pages', {}), throwsFormatException);
    await app.selectNotebook(original);
    expect(body(await access.call('list_pages', {}))['total'], 2);
  });

  test('real HTTP endpoint returns scoped live text to an MCP client',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await enable(LearningScope.page);
    final uri = Uri.parse(access.url!);
    final client = _LoopbackHttp().createHttpClient(null);
    try {
      expect(
          access.clientConfig,
          '[mcp_servers.openote]\nurl = "$uri"\n'
          'http_headers = { Authorization = "${access.authorizationHeader}" }\n');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', access.authorizationHeader);
      request.headers.set('Accept', 'application/json, text/event-stream');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 42,
        'method': 'tools/call',
        'params': {'name': 'read_page'}
      }));
      final response = await request.close();
      expect(response.statusCode, 200);
      final result = jsonDecode(await utf8.decoder.bind(response).join());
      expect(result['id'], 42);
      expect(body((result['result'] as Map).cast<String, dynamic>())['text'],
          contains('Unsaved first page algebra'));
    } finally {
      client.close(force: true);
    }

    await enable(LearningScope.off);
    await expectLater(
        Socket.connect(uri.host, uri.port, timeout: const Duration(seconds: 2)),
        throwsA(isA<SocketException>()));
    await enable(LearningScope.page);
    expect(access.url, uri.toString());
    final connection = await Socket.connect(uri.host, uri.port);
    connection.destroy();
  });

  test(
      'split focus determines current page and book reads both unsaved editors',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final split = await app.createSplitEditor();
    await split.selectPage(second);
    split.blocks.single.content['text'] = 'Unsaved split material';
    app.focusLearningEditor(split);
    await enable(LearningScope.page);
    expect(body(await access.call('get_context', {}))['currentPageId'], second);
    expect(body(await access.call('read_page', {}))['text'],
        contains('Unsaved split'));
    await expectLater(
        access.call('read_page', {'pageId': first}), throwsFormatException);
    await enable(LearningScope.notebook);
    expect(body(await access.call('read_page', {'pageId': first}))['text'],
        contains('Unsaved first'));
    app.focusLearningEditor(app);
  });

  test('pending editor text is readable without modifying its stored block',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final controller = TextEditingController(text: 'Still typing this');
    final block = app.blocks.single;
    app.setActiveEditor(controller, block, 'text');
    await enable(LearningScope.page);
    expect(body(await access.call('read_page', {}))['text'],
        contains('Still typing this'));
    expect(block.content['text'], contains('Unsaved first'));
    app.clearActiveEditor(block.id);
    controller.dispose();
  });

  test('locked pages are excluded from listing, search, text and images',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await enable(LearningScope.notebook);
    app.protectNode(second, 'test-passcode', UnlockPolicy.session);
    expect(body(await access.call('list_pages', {}))['total'], 1);
    expect(
        body(await access.call('search_pages', {'query': 'stored material'}))[
            'matches'],
        isEmpty);
    await expectLater(
        access.call('read_page', {'pageId': second}), throwsFormatException);
    await expectLater(access.call('read_page_image', {'pageId': second}),
        throwsFormatException);
  });

  test('protection changes in another pane revoke stale learning unlocks',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final split = await app.createSplitEditor();
    await split.selectPage(second);
    app.protectNode(first, 'first-passcode', UnlockPolicy.session);
    app.focusLearningEditor(split);
    await enable(LearningScope.notebook);
    await expectLater(
        access.call('read_page', {'pageId': first}), throwsFormatException);
    split.reloadProtection();
    expect(split.unlockNode(first, 'first-passcode'), true);
    expect(body(await access.call('read_page', {'pageId': first}))['text'],
        contains('Unsaved first'));
    app.protectNode(first, 'new-passcode', UnlockPolicy.session);
    await expectLater(
        access.call('read_page', {'pageId': first}), throwsFormatException);
    app.focusLearningEditor(app);
  });

  test(
      'long text has bounded continuations, unchanged revision and change detection',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks.single.content['text'] = 'word ' * 5000;
    await enable(LearningScope.page);
    final firstPart = body(await access.call('read_page', {'maxChars': 256}));
    expect((firstPart['text'] as String).length, 256);
    expect(firstPart['nextOffset'], 256);
    final next =
        body(await access.call('read_page', {'offset': 256, 'maxChars': 256}));
    expect(next['revision'], firstPart['revision']);
    expect(
        body(await access.call(
            'read_page', {'ifRevision': firstPart['revision']}))['unchanged'],
        true);
    app.blocks.single.content['text'] = 'Changed';
    final changed = body(
        await access.call('read_page', {'ifRevision': firstPart['revision']}));
    expect(changed['revision'], isNot(firstPart['revision']));
    expect(changed['text'], contains('Changed'));
    await expectLater(
        access.call('read_page', {'maxChars': 1000000}), throwsFormatException);
    await expectLater(
        access.call('read_page', {'offset': -1}), throwsFormatException);
  });

  test(
      'search includes live text and PDF source text without dumping ink arrays',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks.add(Block(
        type: BlockType.image,
        x: 0,
        y: 200,
        content: {'sourceText': 'Photosynthesis from PDF'}));
    app.blocks.add(
        Block(type: BlockType.ink, x: 0, y: 300, content: {'strokes': []}));
    await enable(LearningScope.notebook);
    expect(
        body(
            await access.call('search_pages', {'query': 'algebra'}))['matches'],
        hasLength(1));
    expect(
        body(await access.call('search_pages', {'query': 'photosynthesis'}))[
            'matches'],
        hasLength(1));
    final text = body(await access.call('read_page', {}));
    expect(text['hasVisuals'], true);
    expect(text['text'], contains('read_page_image'));
    expect(text['text'], isNot(contains('"strokes"')));
  });

  test('image sheets are cached by content, invalidated by edits', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    var renders = 0;
    await access.stop();
    access.dispose();
    access = LearningAccess(app,
        readSettings: () => null,
        writeSettings: (_) {},
        renderSheet: (snapshot, sheet, size) async {
          renders++;
          expect(
              snapshot.blocks.single.content['text'], contains('first page'));
          return Uint8List.fromList([1, 2, 3]);
        })
      ..port = 0;
    await enable(LearningScope.page);
    final result = await access.call('read_page_image', {});
    expect((result['content'] as List)[1]['type'], 'image');
    expect(body(result)['totalSheets'], 1);
    await access.call('read_page_image', {});
    expect(renders, 1);
    app.blocks.single.content['text'] = 'Modified first page';
    await access.call('read_page_image', {});
    expect(renders, 2);
    await expectLater(
        access.call('read_page_image', {'sheet': 100}), throwsFormatException);
  });

  for (final change in ['page', 'lock', 'off']) {
    test('async image response is revoked after $change changes', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final rendering = Completer<Uint8List>();
      final started = Completer<void>();
      await access.stop();
      access.dispose();
      access = LearningAccess(app,
          readSettings: () => null,
          writeSettings: (_) {},
          renderSheet: (_, __, ___) {
            started.complete();
            return rendering.future;
          })
        ..port = 0;
      await enable(LearningScope.page);
      final image = access.call('read_page_image', {});
      final rejected = expectLater(image, throwsFormatException);
      await started.future;
      if (change == 'page') await app.selectPage(second);
      if (change == 'lock') {
        app.protectNode(first, 'test-passcode', UnlockPolicy.session);
      }
      if (change == 'off') await enable(LearningScope.off);
      rendering.complete(Uint8List.fromList([1, 2, 3]));
      await rejected;
    });
  }

  test('long and wide page images provide bounded sheets and detailed crops',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks.add(Block(
        type: BlockType.text,
        x: 1500,
        y: 5000,
        w: 500,
        content: {'text': 'Far right and bottom'}));
    final full = PdfPageSnapshot.capture(app, first, expandCanvas: true);
    expect(full.pageProps.pageWidth, greaterThanOrEqualTo(2024));
    expect(snapshotSheetCount(full), greaterThan(1));
    final oneSheet =
        await buildSnapshotPdf(full, title: 'Long page', sheetIndex: 0);
    expect(latin1.decode(oneSheet), contains('/Count 1'));
    final crop = PdfPageSnapshot.capture(app, first,
        region: const Rect.fromLTWH(1500, 4900, 500, 500));
    expect(snapshotSheetCount(crop), 1);
    final cropped =
        await buildSnapshotPdf(crop, title: 'Detail', sheetIndex: 0);
    expect(latin1.decode(cropped), contains('/Count 1'));
    await enable(LearningScope.page);
    final result = body(await access.call('read_page_image',
        {'x': 1500, 'y': 4900, 'width': 500, 'height': 500}));
    expect(result['totalSheets'], 1);
    await expectLater(
        access.call('read_page_image', {'x': 10}), throwsFormatException);
    await expectLater(
        access.call('read_page_image',
            {'x': 0, 'y': 0, 'width': 100, 'height': 100, 'sheet': 0}),
        throwsFormatException);
  });

  test('snapshot freezes text, images and page title before asynchronous work',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final hash = app.addBlob(Uint8List.fromList([1, 2, 3]), 'image/png');
    app.blocks.add(
        Block(type: BlockType.image, x: 0, y: 200, content: {'blob': hash}));
    final snapshot = PdfPageSnapshot.capture(app, first, linkedTitles: false);
    app.blocks.first.content['text'] = 'Changed';
    app.node(first)!.title = 'Changed title';
    final other = await repo.createNotebook('Other');
    await app.selectNotebook(other.id);
    expect(snapshot.blocks.first.content['text'], contains('Unsaved first'));
    expect(snapshot.blob(hash), [1, 2, 3]);
    expect(snapshot.node(first)!.title, isNot('Changed title'));
    expect(snapshot.node(second), isNull);
  });

  test('new sharing session starts off but reuses connection credentials',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await enable(LearningScope.page);
    final header = access.authorizationHeader;
    await enable(LearningScope.off);
    await expectLater(access.call('read_page', {}), throwsFormatException);
    await enable(LearningScope.notebook);
    expect(access.authorizationHeader, header);
    expect(access.clientConfig, contains('http_headers'));
    expect((settings as Map).keys, unorderedEquals(['token', 'port']));
  });

  testWidgets('access controls fit narrow windows and show German labels',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.interfaceLanguage = 'de';
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('de')],
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 280,
                    child: SingleChildScrollView(
                        child: LearningAccessPanel(app: app)))))));
    expect(find.text('KI-Zugriff'), findsOneWidget);
    expect(
        find.text('Wähle „Aktuelle Seite“ oder „Dieses Notizbuch“, '
            'um den lokalen MCP-Server zu starten.'),
        findsOneWidget);
    expect(find.text('Codex-Konfiguration kopieren'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.cancelPendingSave();
  });
}
