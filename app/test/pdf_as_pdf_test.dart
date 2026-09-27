// A PDF is stored once as the lossless source and each page gets a durable PNG
// preview. The source preserves text/search/export; the preview makes display
// independent of the PDF worker after import.
//
// The fixture PDF is GENERATED with the `pdf` package the exporter already
// uses, so the bytes are a real document with a real text layer. Everything
// that needs pdfium to open it is guarded — `flutter test` environments
// without the native library skip those and still run the rest.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'package:openote/export/pdf_import.dart';
import 'package:openote/media/pdf_pages.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/pdfium.dart';
import 'support/sqlite.dart';

Future<List<int>> _twoPagePdf() async {
  final doc = pw.Document();
  doc.addPage(pw.Page(build: (_) => pw.Text('alpha slide')));
  doc.addPage(pw.Page(build: (_) => pw.Text('beta slide')));
  return doc.save();
}

void main() {
  var haveSqlite = false;
  var havePdfium = false;
  late List<int> pdfBytes;

  setUpAll(() async {
    haveSqlite = initSqliteForTests();
    await initPdfiumForTests();
    pdfBytes = await _twoPagePdf();
    try {
      final d = await PdfDocument.openData(Uint8List.fromList(pdfBytes),
          sourceName: 'probe');
      havePdfium = d.pages.length == 2;
      await d.dispose();
    } catch (_) {
      havePdfium = false;
    }
  });

  late Repository repo;
  late Directory tmp;
  late AppState app;
  late String pageId;
  late File pdfFile;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_pdf1c_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Slides');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    await app.selectPage(pageId);
    pdfFile = File('${tmp.path}/deck.pdf')..writeAsBytesSync(pdfBytes);
  });

  tearDown(() async {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    await PdfPages.reset();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a printout keeps one PDF and stores durable page previews', () async {
    if (!haveSqlite || !havePdfium) {
      return markTestSkipped('sqlite or pdfium unavailable');
    }
    final blobsBefore = repo.blobIndex(app.notebookId!).length;
    final r = await importPdfFile(app, pdfFile.path, 'deck.pdf');
    expect(r.pages, 2);

    final slides = app.blocks.where((b) => b.content['pdf'] is String).toList();
    expect(slides, hasLength(2));
    for (final s in slides) {
      expect(s.type, BlockType.image);
      expect(s.content['blob'], startsWith('sha256:'),
          reason: 'each page carries an immutable visual preview');
      expect(app.blob(s.content['blob'] as String), isNotNull);
      expect(s.content['locked'], false,
          reason: 'a normal printout can be selected and moved page by page');
    }
    expect(slides.map((s) => s.content['page']).toSet(), {0, 1});
    expect(slides.first.content['sourceText'], contains('alpha'),
        reason: 'the text layer still feeds notebook search');

    expect(repo.blobIndex(app.notebookId!).length, blobsBefore + 3,
        reason: 'one original PDF plus one PNG for each of two pages');
  });

  test('blob_refs reaches the source PDF, or a future GC eats the deck',
      () async {
    if (!haveSqlite || !havePdfium) {
      return markTestSkipped('sqlite or pdfium unavailable');
    }
    await importPdfFile(app, pdfFile.path, 'deck.pdf');
    await app.flushSave();
    final slide = app.blocks.firstWhere((b) => b.content['pdf'] is String);
    final hash = (slide.content['pdf'] as String).replaceFirst('sha256:', '');
    final preview =
        (slide.content['blob'] as String).replaceFirst('sha256:', '');
    final refs = repo.blobRefsForTest(app.notebookId!, pageId);
    expect(refs, contains(hash),
        reason: 'the page must declare it reaches the PDF blob');
    expect(refs, contains(preview),
        reason: 'the durable preview must survive blob garbage collection');
  });

  test('the original PDF remains available for fallback rendering', () async {
    if (!haveSqlite || !havePdfium) {
      return markTestSkipped('sqlite or pdfium unavailable');
    }
    await importPdfFile(app, pdfFile.path, 'deck.pdf');
    final ref = app.blocks
        .firstWhere((b) => b.content['pdf'] is String)
        .content['pdf'] as String;

    expect(PdfPages.cached(ref, 0), isNull,
        reason: 'the durable preview is a blob, not the temporary PDF cache');
    final png = await PdfPages.pageImage(app, ref, 0);
    expect(png, isNotNull);
    expect(png!.length, greaterThan(1000), reason: 'a real PNG, not a stub');
    expect(PdfPages.cached(ref, 0), same(png),
        reason: 'the pixels exist once while something is looking at them');
    expect(await PdfPages.pageImage(app, ref, 99), isNull,
        reason: 'a page the document does not have is null, not a throw');
  });

  test('PDF slides can switch to the PDF editor view and back', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.addBlock(Block(
      type: BlockType.image,
      x: AppState.pageLeftMargin,
      y: AppState.contentTop,
      w: 960,
      h: 540,
      content: {'pdf': 'sha256:fixture', 'page': 0},
    ));
    app.addBlock(Block(
      type: BlockType.image,
      x: AppState.pageLeftMargin,
      y: AppState.contentTop + 576,
      w: 960,
      h: 540,
      content: {'pdf': 'sha256:fixture', 'page': 1},
    ));
    final note = app.addBlock(Block(
      type: BlockType.text,
      x: AppState.pageLeftMargin + 20,
      y: AppState.contentTop + 20,
      w: 200,
      content: {'text': 'annotation'},
    ));
    final slides = app.blocks.where((b) => b.content['pdf'] is String).toList();
    final positions = [for (final b in slides) (b.x, b.y, b.w)];
    final notePosition = (note.x, note.y);
    app.setPdfEditorView(true);
    expect(app.pageProps.pdfOnly, isTrue);
    expect(app.pageProps.pageWidth, 960);
    expect(slides.every((b) => b.content['locked'] == true), isTrue);
    app.setPdfEditorView(false);
    expect(app.pageProps.pdfOnly, isFalse);
    expect([for (final b in slides) (b.x, b.y, b.w)], positions);
    expect((note.x, note.y), notePosition);
  });

  test('the refs index needs no pdfium: any pdf-ref block is declared', () {
    // The blob_refs write path itself, with dummy bytes — this half must
    // hold even on machines where pdfium is missing entirely.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final hash = repo.putBlob(app.notebookId!,
        Uint8List.fromList(List.filled(64, 7)), 'application/pdf');
    repo.writePage(
      app.notebookId!,
      pageId,
      [
        Block(
            type: BlockType.image,
            x: 0,
            y: 0,
            w: 500,
            content: {'pdf': 'sha256:$hash', 'page': 0, 'locked': true})
          ..h = 300
      ],
      PageProps(),
    );
    expect(repo.blobRefsForTest(app.notebookId!, pageId), contains(hash));
  });
}
