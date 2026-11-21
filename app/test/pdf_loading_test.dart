import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
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

class _Cancellation implements PdfPageRenderCancellationToken {
  @override
  bool isCanceled = false;
  @override
  void cancel() => isCanceled = true;
}

class _RasterPage extends _Page {
  @override
  double get width => 200;
  @override
  double get height => 400;
  final calls = <Rect>[];
  Size? fullSize;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Cancellation();
  @override
  Future<PdfImage?> render(
      {int x = 0,
      int y = 0,
      int? width,
      int? height,
      double? fullWidth,
      double? fullHeight,
      int? backgroundColor,
      PdfPageRotation? rotationOverride,
      PdfAnnotationRenderingMode annotationRenderingMode =
          PdfAnnotationRenderingMode.annotationAndForms,
      int flags = 0,
      PdfPageRenderCancellationToken? cancellationToken}) async {
    calls.add(Rect.fromLTWH(
        x.toDouble(), y.toDouble(), width!.toDouble(), height!.toDouble()));
    fullSize = Size(fullWidth!, fullHeight!);
    return PdfImage.createFromBgraData(Uint8List(width * height * 4),
        width: width, height: height);
  }
}

class _BlockedRasterPage extends _RasterPage {
  _BlockedRasterPage(this.result, this.started);
  final Completer<PdfImage?> result;
  final Completer<void> started;
  final cancellation = _Cancellation();
  @override
  PdfPageRenderCancellationToken createCancellationToken() => cancellation;
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = 0,
    PdfPageRenderCancellationToken? cancellationToken,
  }) {
    started.complete();
    return result.future;
  }
}

Future<void> waitForDetail(WidgetTester tester,
    {void Function()? checkFrame}) async {
  // Native codec callbacks need real time; pumpAndSettle advances only the
  // artificial clock and can outrun decoding a newly rendered PNG.
  for (var i = 0; i < 200; i++) {
    checkFrame?.call();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  fail('PDF detail did not finish decoding');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => expect(initSqliteForTests(), true));
  late Directory dir;
  late Repository repo;
  late AppState app;
  late String hash;
  setUp(() async {
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
    PdfPages.resumeAfterFailedExit();
    await PdfPages.reset();
    PdfPages.openForTest = null;
    PdfPages.renderForTest = null;
    PdfPages.renderAtScaleForTest = null;
    PdfPages.renderRegionForTest = null;
    app.cancelPendingSave();
    app.dispose();
    repo.dispose();
    // Windows scanners can briefly retain a handle after SQLite closes.
    for (var attempt = 0;; attempt++) {
      try {
        dir.deleteSync(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
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

  test('a source larger than the document budget is reused', () async {
    final large = app.addBlob(Uint8List(33 << 20), 'application/pdf');
    var opens = 0;
    PdfPages.openForTest = (_, __) async {
      opens++;
      return _Document([_Page()]);
    };
    expect(await PdfPages.pageCount(app, large), 1);
    expect(await PdfPages.pageCount(app, large), 1);
    expect(opens, 1);
  });

  test('region rendering crops at the requested full-page resolution',
      () async {
    final page = _RasterPage();
    const region = Rect.fromLTWH(.25, .5, .25, .25);
    final image = await renderPdfRegionToPng(page, region, 800);
    expect(page.fullSize, const Size(800, 1600));
    expect(page.calls, [const Rect.fromLTWH(200, 800, 200, 400)]);
    expect(image?.width, 200);
    expect(image?.height, 400);
    expect(image?.region, region);
    expect(image?.png, isNotEmpty);
  });

  test('region rendering bounds the allocated pixel buffer', () async {
    final page = _RasterPage();
    final image = await renderPdfRegionToPng(
        page, const Rect.fromLTWH(0, 0, 1, 1), 10000);
    expect(image, isNotNull);
    expect(image!.width * image.height, lessThanOrEqualTo(8 * 1024 * 1024));
  });

  test('obsolete queued requests never open their source', () async {
    var opens = 0;
    var current = true;
    PdfPages.openForTest = (_, __) async {
      opens++;
      return _Document();
    };
    final pending = PdfPages.pageImage(app, hash, 0, isCurrent: () => current);
    current = false;
    expect(await pending, null);
    expect(opens, 0);
  });

  test('a live viewer keeps a shared request when another leaves', () async {
    var current = true;
    var renders = 0;
    PdfPages.openForTest = (_, __) async => _Document([_Page()]);
    PdfPages.renderForTest = (_) async {
      renders++;
      return (png: Uint8List.fromList([9]), width: 1, height: 1);
    };
    final first = PdfPages.pageImage(app, hash, 0, isCurrent: () => current);
    final second = PdfPages.pageImage(app, hash, 0);
    current = false;
    expect(await first, orderedEquals([9]));
    expect(await second, orderedEquals([9]));
    expect(renders, 1);
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

  test('closing cancels an active native render and rejects new work',
      () async {
    final native = Completer<PdfImage?>();
    final started = Completer<void>();
    final page = _BlockedRasterPage(native, started);
    final doc = _Document([page]);
    PdfPages.openForTest = (_, __) async => doc;
    final rendering =
        PdfPages.pageRegion(app, hash, 0, const Rect.fromLTWH(0, 0, 1, 1), 800);
    await started.future;
    var cleaned = false;
    final cleanup = PdfPages.stopForExit().then((_) => cleaned = true);
    expect(page.cancellation.isCanceled, true);
    expect(cleaned, false);
    expect(await PdfPages.pageImage(app, hash, 0), null);
    expect(await PdfPages.pageImageAtScale(app, hash, 0, 4), null);
    expect(await PdfPages.pageCount(app, hash), null);
    expect(
        await PdfPages.pageRegion(
            app, hash, 0, const Rect.fromLTWH(0, 0, 1, 1), 1600),
        null);
    // Persisting notes is independent of the unresponsive PDF worker.
    app.markDirty();
    await app.shutdown();
    expect(app.hasUnsavedChanges, false);
    expect(cleaned, false);
    native.complete(null);
    expect(await rendering, null);
    await cleanup;
    expect(doc.disposals, 1);
    PdfPages.resumeAfterFailedExit();
    expect(await PdfPages.pageCount(app, hash), 1);
  });

  test('a source opened after closing never starts or publishes a render',
      () async {
    final opening = Completer<PdfDocument>();
    var renders = 0;
    PdfPages.openForTest = (_, __) => opening.future;
    PdfPages.renderForTest = (_) async {
      renders++;
      return (png: Uint8List.fromList([9]), width: 1, height: 1);
    };
    final pending = PdfPages.pageImage(app, hash, 0);
    await Future<void>.delayed(Duration.zero);
    final cleanup = PdfPages.stopForExit();
    final doc = _Document([_Page()]);
    opening.complete(doc);
    expect(await pending, null);
    await cleanup;
    expect(renders, 0);
    expect(doc.disposals, 1);
    expect(PdfPages.cached(hash, 0), null);
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
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
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

  testWidgets('a stalled legacy PDF stops spinning without storing late pixels',
      (tester) async {
    final native = Completer<RenderedPdfPage?>();
    PdfPages.openForTest = (_, __) async => _Document([_Page()]);
    PdfPages.renderForTest = (_) => native.future;
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
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    final png = File('assets/icon/openote_icon.png').readAsBytesSync();
    native.complete((png: png, width: 1024, height: 1024));
    await tester.pump();
    expect(block.content['blob'], null);
    expect(PdfPages.cached(hash, 0), null);
    app.cancelPendingSave();
    await tester.pumpWidget(const SizedBox());
    await PdfPages.reset();
  });

  testWidgets('an existing PDF preview re-renders from its source on zoom',
      (tester) async {
    final png = File('assets/icon/openote_icon.png').readAsBytesSync();
    final preview = app.addBlob(png, 'image/png');
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    final widths = <int>[];
    final regions = <Rect>[];
    PdfPages.openForTest = (_, __) async => _Document([_Page()]);
    PdfPages.renderRegionForTest = (_, region, width) async {
      widths.add(width);
      regions.add(region);
      return (png: png, width: 1, height: 1, region: region);
    };
    final block = Block(
        type: BlockType.image,
        x: 0,
        y: 0,
        w: 400,
        h: 500,
        content: {'pdf': hash, 'blob': 'sha256:$preview', 'page': 0});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AnimatedBuilder(
                animation: app.canvas,
                builder: (context, _) => Transform.scale(
                    scale: app.canvas.scale,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: 400,
                        height: 500,
                        child: ImageBlockView(block: block, app: app)))))));
    await tester.pumpAndSettle();
    app.canvas.jumpTo(4, Offset.zero);
    await tester
        .pump(); // Apply the canvas transform before the debounce fires.
    await tester.pump(const Duration(milliseconds: 200));
    await waitForDetail(tester);
    await tester.pumpAndSettle();
    expect(widths, [2048]);
    expect(regions.single.width, lessThan(1));
    expect(regions.single.height, lessThan(1));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(RawImage), findsNWidgets(2));
    expect(block.content['blob'], 'sha256:$preview');
    expect(app.blob(hash), orderedEquals([1, 2, 3]));
    expect(app.blob('sha256:$preview'), orderedEquals(png));
    app.cancelPendingSave();
    await tester.pumpWidget(const SizedBox());
    await PdfPages.reset();
  });

  testWidgets('PDF crop pixels and geometry change together after panning',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final png = File('assets/icon/openote_icon.png').readAsBytesSync();
    Future<Uint8List> smallerPng(int width) async {
      final codec = await ui.instantiateImageCodec(png, targetWidth: width);
      final frame = await codec.getNextFrame();
      try {
        return (await frame.image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    }

    final firstPng = (await tester.runAsync(() => smallerPng(32)))!;
    final secondPng = (await tester.runAsync(() => smallerPng(64)))!;
    final preview = app.addBlob(png, 'image/png');
    final replacement = Completer<RenderedPdfRegion?>();
    final regions = <Rect>[];
    PdfPages.openForTest = (_, __) async => _Document([_Page()]);
    PdfPages.renderRegionForTest = (_, region, width) async {
      regions.add(region);
      if (regions.length > 1) return replacement.future;
      return (png: firstPng, width: 32, height: 32, region: region);
    };
    final block =
        Block(type: BlockType.image, x: 0, y: 0, w: 400, h: 500, content: {
      'pdf': hash,
      'blob': 'sha256:$preview',
      'page': 0,
      'naturalW': 1024,
      'naturalH': 1024
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AnimatedBuilder(
      animation: app.canvas,
      builder: (_, __) => Transform.translate(
          offset: app.canvas.offset,
          child: Transform.scale(
              scale: app.canvas.scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 400,
                  height: 500,
                  child: ImageBlockView(block: block, app: app)))),
    ))));
    await tester.pumpAndSettle();
    app.canvas.jumpTo(4, Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await waitForDetail(tester);
    final detail = find.byWidgetPredicate(
        (w) => w is RawImage && (w.image?.width == 32 || w.image?.width == 64));
    final position =
        find.ancestor(of: detail, matching: find.byType(Positioned)).first;
    Rect rect() {
      final p = tester.widget<Positioned>(position);
      return Rect.fromLTWH(p.left!, p.top!, p.width!, p.height!);
    }

    final initialRect = rect();
    expect(tester.widget<RawImage>(detail).image!.width, 32);
    app.canvas.jumpTo(4, const Offset(-400, -240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(regions, hasLength(2));
    expect(regions.last, isNot(regions.first));
    expect(rect(), initialRect,
        reason: 'keep the old crop fixed while rendering');
    replacement.complete(
        (png: secondPng, width: 64, height: 64, region: regions.last));
    var sawReplacement = false;
    void checkFrame() {
      final image = tester.widget<RawImage>(detail).image!;
      if (image.width == 32) {
        expect(rect(), initialRect,
            reason: 'old pixels must never move into the new crop');
      } else {
        sawReplacement = true;
        final r = regions.last;
        // The square preview is top-left aligned inside the 400 x 500 block.
        expect(
            rect(),
            Rect.fromLTWH(
                r.left * 400, r.top * 400, r.width * 400, r.height * 400));
      }
    }

    await tester.pump();
    await waitForDetail(tester, checkFrame: checkFrame);
    expect(sawReplacement, true);
    expect(block.content['blob'], 'sha256:$preview');
    app.cancelPendingSave();
    await tester.pumpWidget(const SizedBox());
    await PdfPages.reset();
  });

  testWidgets('a stalled detail stops spinning and ignores its late result',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = File('assets/icon/openote_icon.png').readAsBytesSync();
    final preview = app.addBlob(png, 'image/png');
    final native = Completer<RenderedPdfRegion?>();
    Rect? requested;
    var renders = 0;
    PdfPages.openForTest = (_, __) async => _Document([_Page()]);
    PdfPages.renderRegionForTest = (_, region, width) {
      requested = region;
      renders++;
      return native.future;
    };
    final block =
        Block(type: BlockType.image, x: 0, y: 0, w: 400, h: 500, content: {
      'pdf': hash,
      'blob': 'sha256:$preview',
      'page': 0,
      'naturalW': 1024,
      'naturalH': 1024
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 400,
                height: 500,
                child: ImageBlockView(block: block, app: app)))));
    await tester.pumpAndSettle();
    app.canvas.jumpTo(4, Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Retry'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(renders, 1,
        reason: 'do not automatically repeat a stalled native operation');
    native.complete((png: png, width: 1024, height: 1024, region: requested!));
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget,
        reason: 'only the durable preview remains');
    expect(block.content['blob'], 'sha256:$preview');
    app.cancelPendingSave();
    await tester.pumpWidget(const SizedBox());
    await PdfPages.reset();
  });

  testWidgets('preview decoding sharpens between low zoom levels and on resize',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final png = File('assets/icon/openote_icon.png').readAsBytesSync();
    final preview = app.addBlob(png, 'image/png');
    final block = Block(
        type: BlockType.image,
        x: 0,
        y: 0,
        w: 400,
        h: 400,
        content: {
          'blob': 'sha256:$preview',
          'naturalW': 1024,
          'naturalH': 1024
        });
    Widget page() => MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: block.w,
                    height: block.h,
                    child: ImageBlockView(block: block, app: app)))));
    int width() =>
        (tester.widget<Image>(find.byType(Image)).image as ResizeImage).width!;
    app.canvas.jumpTo(.25, Offset.zero);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final small = width();
    app.canvas.jumpTo(1, Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(width(), greaterThan(small));
    final normal = width();
    block.w = 600;
    block.h = 600;
    await tester.pumpWidget(page());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(width(), greaterThan(normal));
    final resized = width();
    tester.view.devicePixelRatio = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(width(), greaterThan(resized));
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
