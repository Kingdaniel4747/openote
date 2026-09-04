import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:openote/editor/image_block_view.dart';
import 'package:openote/export/pdf_vector_export.dart';
import 'package:openote/media/pdf_pages.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'support/sqlite.dart';

class _Document implements PdfDocument {
  _Document([this.pages = const []]);

  int disposals = 0;
  @override
  final List<PdfPage> pages;
  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Page implements PdfPage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => expect(initSqliteForTests(), true));
  late Directory dir;
  late Repository repo;
  late AppState app;
  late String hash;
  setUp(() async {
    AppState.syncLogEnabled = false;
    dir = Directory.systemTemp.createTempSync('openote-pdf-loading-');
    repo = await Repository.openAt(dir);
    final nb = await repo.createNotebook('PDF tests');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    hash = app.addBlob(Uint8List.fromList([1, 2, 3]), 'application/pdf');
  });
  tearDown(() async {
    await PdfPages.reset();
    PdfPages.openForTest = null;
    PdfPages.renderForTest = null;
    app.cancelPendingSave();
    app.dispose();
    repo.dispose();
    dir.deleteSync(recursive: true);
    AppState.syncLogEnabled = true;
  });

  test(
      'concurrent page requests share opening future, not an uninitialized document',
      () async {
    final opening = Completer<PdfDocument>();
    var opens = 0;
    PdfPages.openForTest = (_, __) {
      opens++;
      return opening.future;
    };
    final first = PdfPages.pageImage(app, hash, 0);
    final same = PdfPages.pageImage(app, hash, 0);
    final other = PdfPages.pageImage(app, hash, 1);
    await Future<void>.delayed(Duration.zero);
    expect(identical(first, same), true);
    expect(opens, 1);
    final doc = _Document();
    opening.complete(doc);
    expect(await Future.wait([first, same, other]), [null, null, null]);
    await PdfPages.reset();
    expect(doc.disposals, 1);
  });

  test('failed openings are evicted and can be retried', () async {
    var opens = 0;
    PdfPages.openForTest = (_, __) async {
      opens++;
      throw StateError('unreadable');
    };
    expect(await PdfPages.pageImage(app, hash, 0), null);
    expect(await PdfPages.pageImage(app, hash, 0), null);
    expect(opens, 2);
  });

  testWidgets('PDF failure stops the spinner and offers a retry',
      (tester) async {
    var opens = 0;
    PdfPages.openForTest = (_, __) async {
      opens++;
      throw StateError('unreadable');
    };
    final block = Block(
        type: BlockType.image,
        x: 0,
        y: 0,
        w: 400,
        h: 500,
        content: {'pdf': hash, 'page': 0});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 400,
                height: 500,
                child: ImageBlockView(block: block, app: app)))));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(opens, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a legacy PDF page becomes a durable image after first display',
      (tester) async {
    var opens = 0;
    PdfPages.openForTest = (_, __) async {
      opens++;
      return _Document([_Page()]);
    };
    final png = File('assets/icon/openote_icon.png').readAsBytesSync();
    PdfPages.renderForTest = (_) async => (png: png, width: 1, height: 1);
    final block = Block(
        type: BlockType.image,
        x: 0,
        y: 0,
        w: 400,
        h: 500,
        content: {'pdf': hash, 'page': 0, 'locked': true});

    Widget page() => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 400,
                height: 500,
                child: ImageBlockView(block: block, app: app))));

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final preview = block.content['blob'];
    expect(preview, isA<String>());
    expect(app.blob(preview as String), orderedEquals(png));
    expect(opens, 1);

    // A fresh view reads the stored image and never opens the PDF again.
    app.cancelPendingSave();
    await tester.pumpWidget(const SizedBox());
    await PdfPages.reset();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('PDF-only paper geometry round-trips and stays exact when exporting',
      () {
    final props = PageProps(pageWidth: 1100, layout: 'pdf', pdfPageHeight: 600);
    app.pageProps = PageProps.fromJson(props.toJson());
    expect(app.pageProps.pdfOnly, true);
    expect(app.pageSize(), const Size(1100, 600));
    app.blocks = [
      Block(
          type: BlockType.text,
          x: 10,
          y: 900,
          w: 100,
          h: 100,
          content: {'text': 'Outside the paper'})
    ];
    final format = debugPageFormat(app, app.pageId!);
    expect(format.width / format.height, closeTo(1100 / 600, .0001));
    expect(PageProps.fromJson({}).pdfOnly, false);
  });
}
