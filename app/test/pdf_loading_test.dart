import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:openote/editor/image_block_view.dart';
import 'package:openote/export/pdf_vector_export.dart';
import 'package:openote/export/pdf_import.dart';
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

  test('queued slides do not open more sources while a render is active',
      () async {
    final firstRender = Completer<RenderedPdfPage?>();
    var opens = 0;
    var renders = 0;
    PdfPages.openForTest = (_, __) async {
      opens++;
      return _Document([_Page()]);
    };
    PdfPages.renderForTest = (_) {
      renders++;
      return renders == 1 ? firstRender.future : Future.value(null);
    };
    final otherHash = app.addBlob(Uint8List.fromList([4]), 'application/pdf');
    final first = PdfPages.pageImage(app, hash, 0);
    final second = PdfPages.pageImage(app, otherHash, 0);
    await Future<void>.delayed(Duration.zero);
    expect(opens, 1);
    expect(renders, 1);
    firstRender.complete(null);
    await Future.wait([first, second]);
    expect(opens, 2);
    expect(renders, 2);
  });

  test('reset discards queued work before it opens a source', () async {
    var opens = 0;
    PdfPages.openForTest = (_, __) async {
      opens++;
      return _Document();
    };
    final pending = PdfPages.pageImage(app, hash, 0);
    await PdfPages.reset();
    expect(await pending, null);
    expect(opens, 0);
    await PdfPages.pageImage(app, hash, 0);
    expect(opens, 1);
  });

  test('preparation stores every preview before completion, one page at a time',
      () async {
    final pages = List.generate(40, (_) => _Page());
    var active = 0;
    var peak = 0;
    var rendered = 0;
    final progress = <int>[];
    final refs = await preparePdfPreviews(
        app, app.notebookId!, _Document(pages), render: (page) async {
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(Duration.zero);
      final png = Uint8List.fromList([++rendered]);
      active--;
      return (png: png, width: 1, height: 1);
    }, onProgress: (done, total) {
      expect(total, 40);
      progress.add(done);
    });
    expect(peak, 1);
    expect(progress, List.generate(41, (i) => i));
    expect(refs, hasLength(40));
    for (var i = 0; i < refs.length; i++) {
      expect(app.blob(refs[i]), orderedEquals([i + 1]));
    }
  });

  test('a failed preview never reports the deck as complete', () async {
    var attempts = 0;
    final progress = <int>[];
    await expectLater(
        preparePdfPreviews(app, app.notebookId!, _Document([_Page(), _Page()]),
            render: (_) async {
              if (++attempts == 2) return null;
              return (png: Uint8List.fromList([1]), width: 1, height: 1);
            },
            onProgress: (done, _) => progress.add(done)),
        throwsStateError);
    expect(attempts, 2);
    expect(progress, [0, 1]);
    expect(app.blocks.where((b) => b.content['pdf'] != null), isEmpty);
  });

  test('opening more PDFs evicts and disposes the least recent document',
      () async {
    final docs = <_Document>[];
    PdfPages.openForTest = (_, __) async {
      final doc = _Document();
      docs.add(doc);
      return doc;
    };
    for (var i = 0; i < 3; i++) {
      final ref = app.addBlob(Uint8List.fromList([i]), 'application/pdf');
      await PdfPages.pageCount(app, ref);
    }
    await Future<void>.delayed(Duration.zero);
    expect(docs.map((d) => d.disposals), [1, 0, 0]);
    await PdfPages.reset();
    expect(docs.map((d) => d.disposals), [1, 1, 1]);
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
