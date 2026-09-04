/// Import a PDF as annotatable pages (D1 — the lecture-slide flagship).
///
/// **The pitch:** drop the lecture PDF in, write on the slides with your pen,
/// and search the slide text later.
///
/// This is the workflow GoodNotes and Notability built businesses on, and it
/// is Apple-locked and paid there. OneNote's equivalent ("Insert → PDF
/// printout") rasterises pages into images.
///
/// **The PDF is stored ONCE, and every page gets a durable preview.** The
/// source PDF remains one content-addressed blob, preserving searchable text
/// and lossless export. Each slide also carries a content-addressed 2× PNG in
/// `blob`, so drawing and scrolling use the same simple, immutable image path
/// as ordinary pictures and do not keep pdfium involved after import.
///
/// This intentionally spends disk space for reliability. The blobs are
/// content-addressed, so identical bytes are deduplicated, sync safely and can
/// never become stale. A legacy `{pdf, page}` block without `blob` still works:
/// the image view renders it once and upgrades it lazily.
///
/// Two deliberate choices survive from the raster era:
///
/// - **Slides keep their layout.** A slide's layout is the information;
///   re-flowing it into our block model would destroy the thing the student
///   is annotating. The text layer rides alongside for search.
/// - **The background is locked.** An annotation layer is only usable if the
///   thing underneath cannot be nudged.
library;

import 'dart:io';
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../media/pdf_pages.dart';
import '../media/pdf_runtime.dart';

/// Page width we lay imported slides out at, matching the default page width
/// so a slide fills the page the way it does in a PDF reader.
const double kPdfPageWidth = 1100.0;

/// Gap between stacked slides on a single page, and above the first one.
const double kPdfStackGap = 36.0;

/// Where the imported slides go.
enum PdfPlacement {
  /// Every slide stacked down the CURRENT page, below whatever is already
  /// there. The default, because a printout is what a student reaches for:
  /// one continuous page you scroll through and write on, exactly like
  /// OneNote's "Insert ▸ PDF printout", and it keeps the slides next to the
  /// notes already on that page.
  currentPage,

  /// One Openote page per PDF page, in a new section named after the file.
  /// Better for a 200-slide unit you want in the navigator as separate pages.
  pagePerSlide,

  /// One small card with a thumbnail — the whole deck behind a click, not
  /// spread over the page. "Have a little thumbnail appear in my page, but
  /// not have the whole thing always open." Clicking the card opens the
  /// viewer, where the text is selectable.
  card,

  /// Fixed-size pages: the PDF is the paper, without extra drawing margins.
  pdfOnly,
}

/// Result of an import, for the caller's summary.
typedef PdfImportResult = ({int pages, String? sectionId, String? firstPageId});

/// Pick a PDF and import it into the current notebook.
Future<PdfImportResult?> importPdfAsPages(
  AppState app, {
  BuildContext? progressContext,
  PdfPlacement placement = PdfPlacement.currentPage,
  void Function(int done, int total)? onProgress,
}) async {
  const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
  if (placement == PdfPlacement.pdfOnly || app.pageProps.pdfOnly) {
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return null;
    PdfImportResult? first;
    var pages = 0;
    for (final file in files) {
      final result = await importPdfFile(app, file.path, file.name,
          placement: PdfPlacement.pdfOnly, onProgress: onProgress);
      first ??= result;
      pages += result.pages;
    }
    return (
      pages: pages,
      sectionId: first?.sectionId,
      firstPageId: first?.firstPageId
    );
  }
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  return importPdfFile(app, file.path, file.name,
      placement: placement, onProgress: onProgress);
}

/// Import [path] — onto the current page, as one page per slide, or as a card.
///
/// Exposed separately from the picker so it can be driven by a drop, by a
/// test, or by a future "attach the reading list" flow.
Future<PdfImportResult> importPdfFile(
  AppState app,
  String path,
  String displayName, {
  PdfPlacement placement = PdfPlacement.currentPage,
  void Function(int done, int total)? onProgress,
}) async {
  final nb = app.notebookId;
  if (nb == null) return (pages: 0, sectionId: null, firstPageId: null);
  final separatePages = placement == PdfPlacement.pagePerSlide;
  if (placement != PdfPlacement.pdfOnly &&
      !separatePages &&
      app.pageId == null) {
    // No page open — make one and put it there.
    //
    // This used to silently switch to one-page-per-slide, which is a different
    // feature, not a fallback: the deck arrived scattered across dozens of
    // navigator entries and nothing said why. Honour the mode that was asked
    // for; only the arrow menu switches modes.
    await app.addPage();
    if (app.pageId == null) {
      return (pages: 0, sectionId: null, firstPageId: null);
    }
  }

  // The source file, once, into the content-addressed store. Everything else
  // in this import is a reference to this hash.
  final bytes = await File(path).readAsBytes();
  final doc = await PdfRuntime.open(bytes, displayName);
  try {
    final title =
        displayName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

    // PDF editor mode is one Openote page in the current section. Further
    // PDFs selected in the same picker append to that page instead of creating
    // one section or one navigator page per PDF sheet.
    if (placement == PdfPlacement.pdfOnly && !app.pageProps.pdfOnly) {
      final sectionId = app.sectionOf(app.pageId) ?? app.activeSectionId;
      await app.addPage(sectionId: sectionId);
      if (app.pageId != null) {
        app.renameNode(app.pageId!, title.isEmpty ? 'PDF' : title);
        app.pendingTitleEdit = null;
      }
    }
    if (app.pageId == null) {
      return (pages: 0, sectionId: null, firstPageId: null);
    }

    final pdfHash = separatePages
        ? app.importBlob(nb, bytes, 'application/pdf')
        : app.addBlob(bytes, 'application/pdf');

    if (placement == PdfPlacement.card) {
      return _importAsCard(
          app, doc, pdfHash, title.isEmpty ? displayName : title);
    }
    if (placement == PdfPlacement.currentPage) {
      return await _importOntoCurrentPage(app, doc, pdfHash, onProgress);
    }
    if (placement == PdfPlacement.pdfOnly) {
      return await _importIntoPdfPage(app, doc, pdfHash, onProgress);
    }

    // A section per PDF: a 60-slide deck dumped into an existing section
    // would bury everything already there.
    final section = app.importNode(
        nb,
        TreeNode(
          kind: NodeKind.section,
          title: title.isEmpty ? 'PDF' : title,
          position: 'a${nowMs().toString().padLeft(15, '0')}',
        ));

    String? firstPageId;
    var made = 0;
    final total = doc.pages.length;
    var pos = nowMs();

    // Chunked transactions keep large imports responsive. Page previews are
    // deliberately rendered before the batch write: once imported, a slide
    // is an ordinary immutable image and never depends on an open PDF worker.
    const chunkSize = 16;
    for (var start = 0; start < total; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, total);
      final batch =
          <({PdfPage page, String? text, String? preview, int index})>[];
      for (var i = start; i < end; i++) {
        final page = doc.pages[i];
        batch.add((
          page: page,
          text: await _textOf(page),
          preview: await _storePagePreview(app, nb, page),
          index: i,
        ));
      }

      app.importBatch(nb, () {
        for (final item in batch) {
          final node = app.importNode(
              nb,
              TreeNode(
                kind: NodeKind.page,
                parentId: section.id,
                title: '${item.index + 1}',
                position: 'a${(pos++).toString().padLeft(15, '0')}',
              ));
          firstPageId ??= node.id;

          const w = kPdfPageWidth;
          final h = item.page.height / item.page.width * w;
          app.importPage(
            nb,
            node.id,
            [
              _slideBlock(pdfHash, item.page, item.index, item.text,
                  x: 0, y: 0, w: w, background: true, preview: item.preview)
                ..h = h
            ],
            PageProps(
                pageWidth: w,
                layout: placement == PdfPlacement.pdfOnly ? 'pdf' : 'canvas',
                pdfPageHeight: h),
          );
          made++;
        }
      });
      onProgress?.call(made, total);
      // A real delay, not Duration.zero: this loop runs on the UI isolate, and
      // on Windows posted work outranks hardware input, so a queue that never
      // goes idle starves the mouse and keyboard for the whole import.
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    app.reloadNodes();
    return (pages: made, sectionId: section.id, firstPageId: firstPageId);
  } finally {
    await doc.dispose().timeout(const Duration(seconds: 5), onTimeout: () {});
  }
}

/// One reference block for one slide.
Block _slideBlock(
  String pdfHash,
  PdfPage page,
  int index,
  String? text, {
  required double x,
  required double y,
  required double w,
  bool background = false,
  String? preview,
}) =>
    Block(
      type: BlockType.image,
      x: x,
      y: y,
      w: w,
      content: {
        'pdf': 'sha256:$pdfHash',
        if (preview != null) 'blob': preview,
        'page': index,
        'mime': 'application/pdf',
        // The PDF's own geometry, so aspect and proportional resize never
        // need the pixels.
        'naturalW': page.width,
        'naturalH': page.height,
        // The two properties that make this an annotation surface rather
        // than a picture someone dropped on the page.
        // A normal printout is an ordinary canvas object and can be selected,
        // moved and arranged. In PDF-only/page-per-slide mode it is the page
        // itself, so it stays fixed as the background.
        'locked': background,
        if (background) 'background': true,
        if (text != null && text.isNotEmpty) 'sourceText': text,
      },
    );

Future<String?> _textOf(PdfPage page) async {
  try {
    // Hidden, but present in the page JSON, so the existing brute-force
    // notebook search finds slides by their words.
    return (await page.loadText().timeout(const Duration(seconds: 8)))
        ?.fullText
        .trim();
  } on TimeoutException {
    // Fail visibly instead of waiting once per remaining page of a stalled worker.
    rethrow;
  } catch (_) {
    return null; // a scanned deck has no text layer; that's fine
  }
}

/// Persist the visual page beside the original PDF. A failed render does not
/// abort the import: the `{pdf, page}` reference remains a complete fallback
/// and the image view can retry and upgrade that one page later.
Future<String?> _storePagePreview(
    AppState app, String notebookId, PdfPage page) async {
  final image = await renderPdfPageToPng(page);
  if (image == null) return null;
  final hash = app.importBlob(notebookId, image.png, 'image/png');
  return 'sha256:$hash';
}

/// The card: one block, the deck behind a click.
PdfImportResult _importAsCard(
    AppState app, PdfDocument doc, String pdfHash, String name) {
  final anchor = _insertionAnchor(app);
  app.pushUndo();
  final b = app.addBlock(
    Block(
      type: BlockType.file,
      x: AppState.pageLeftMargin,
      y: anchor.top,
      w: 300,
      content: {
        'kind': 'pdf',
        'blob': 'sha256:$pdfHash',
        'name': name,
        'mime': 'application/pdf',
        'pages': doc.pages.length,
      },
    ),
    recordUndo: false,
  );
  app.select(b.id);
  return (pages: doc.pages.length, sectionId: null, firstPageId: app.pageId);
}

/// Stack every slide down the page that is currently open, below whatever is
/// already on it.
///
/// One `pushUndo` for the whole import, so Ctrl+Z takes the deck back out in
/// one go rather than sixty times. With rendering gone from the import path,
/// the whole deck lands in one visible step.
Future<PdfImportResult> _importOntoCurrentPage(
  AppState app,
  PdfDocument doc,
  String pdfHash,
  void Function(int done, int total)? onProgress,
) async {
  final total = doc.pages.length;
  // Slide width: the page's own writing column, so a slide lines up with the
  // text already on the page instead of hanging off the side.
  final width = (app.pageProps.pageWidth - AppState.pageLeftMargin * 2)
      .clamp(320.0, kPdfPageWidth);
  final anchor = _insertionAnchor(app);
  var y = anchor.top;

  app.pushUndo();
  final top = y;
  // Everything that sat below the insertion point moves down as slides land,
  // so inserting at the caret opens a gap instead of burying what follows.
  final displaced = anchor.displaced;
  Block? first;
  var made = 0;
  for (var i = 0; i < total; i++) {
    final page = doc.pages[i];
    final text = await _textOf(page);
    final preview = await _storePagePreview(app, app.notebookId!, page);
    final h = page.height / page.width * width;
    final block = app.addBlock(
      _slideBlock(pdfHash, page, i, text,
          x: AppState.pageLeftMargin, y: y, w: width, preview: preview)
        ..h = h,
      recordUndo: false,
    );
    first ??= block;
    // Read the position back: addBlock may snap it to the grid, and computing
    // the next slide's y from the requested position would drift.
    final advance = block.y + h + kPdfStackGap - y;
    y = block.y + h + kPdfStackGap;
    for (final d in displaced) {
      d.y += advance;
    }
    made++;
    onProgress?.call(made, total);
    // Text extraction is quick, but the loop still yields so a 200-slide
    // deck never freezes input — and a REAL delay, for the same Windows
    // message-loop reason as always.
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  // Bring the result into view — the slides land below everything already on
  // the page, which on a page with content means off screen.
  if (first != null) {
    app.select(first.id);
    app.canvas.centerOn(Offset(width / 2 + AppState.pageLeftMargin, top + 200));
  }
  await app.flushSave();
  return (pages: made, sectionId: null, firstPageId: app.pageId);
}

/// Put every sheet of a PDF into one continuous, marginless Openote page.
/// The PDF blocks are fixed backgrounds; ink remains the only editable layer.
Future<PdfImportResult> _importIntoPdfPage(
  AppState app,
  PdfDocument doc,
  String pdfHash,
  void Function(int done, int total)? onProgress,
) async {
  const width = kPdfPageWidth;
  var y = 0.0;
  for (final b in app.blocks) {
    final bottom = b.y + (b.h ?? 0);
    if (bottom > y) y = bottom;
  }

  app.pushUndo();
  app.pageProps
    ..layout = 'pdf'
    ..background = 'blank'
    ..pageWidth = width;

  final firstY = y;
  Block? first;
  for (var i = 0; i < doc.pages.length; i++) {
    final page = doc.pages[i];
    final text = await _textOf(page);
    final preview = await _storePagePreview(app, app.notebookId!, page);
    final height = page.height / page.width * width;
    final block = app.addBlock(
      _slideBlock(pdfHash, page, i, text,
          x: 0, y: y, w: width, background: true, preview: preview)
        ..h = height,
      recordUndo: false,
    );
    first ??= block;
    y += height;
    onProgress?.call(i + 1, doc.pages.length);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  app.pageProps.pdfPageHeight = y <= 0 ? 1.0 : y;
  app.markDirty();
  app.select(null);
  if (first != null) {
    app.canvas.centerOn(Offset(width / 2, firstY + 200));
  }
  await app.flushSave();
  return (
    pages: doc.pages.length,
    sectionId: app.sectionOf(app.pageId),
    firstPageId: app.pageId,
  );
}

/// Where a printout should start, and which blocks have to move to make room.
///
/// **At the cursor if there is one, below everything otherwise.** A student
/// importing a deck mid-lecture wants it where they are working, not appended
/// a screen and a half below their last note; a student importing into an empty
/// page wants it at the top.
///
/// [displaced] is every block strictly below the anchor, which the caller
/// shifts down as slides land. Landing on top of somebody's notes is not a
/// recoverable mistake.
({double top, List<Block> displaced}) _insertionAnchor(AppState app) {
  final caretId = app.editingBlockId ?? app.selectedBlockId;
  final caret = caretId == null
      ? null
      : app.blocks.where((b) => b.id == caretId).firstOrNull;

  double bottomOf(Block b) =>
      b.y + (b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b));

  if (caret != null) {
    final top = bottomOf(caret) + kPdfStackGap;
    return (
      top: top,
      // Strictly below the anchor block, by its own top edge — a block that
      // merely overlaps the gap stays put.
      displaced: [
        for (final b in app.blocks)
          if (b.id != caret.id && b.y >= caret.y + 1) b
      ],
    );
  }

  // Nothing focused: append below everything. Belt and braces, because
  // `contentExtent` can under-report for culled, never-measured blocks — and
  // an import is exactly when most of the page is off screen.
  var y = app.contentExtent().bottom;
  for (final b in app.blocks) {
    final bottom = bottomOf(b);
    if (bottom > y) y = bottom;
  }
  return (top: y + kPdfStackGap, displaced: const []);
}

/// The placement decision, exposed for tests.
///
/// The rendering half needs pdfium and a real file; the *placement* half is
/// where the reported bug lived, and it is pure.
@visibleForTesting
({double top, List<Block> displaced}) debugInsertionAnchor(AppState app) =>
    _insertionAnchor(app);
