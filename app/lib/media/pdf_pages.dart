/// Render pages of a stored PDF on demand — storage wave 1c.
///
/// A newly imported PDF keeps the source once and stores durable 2× PNG page
/// previews beside it. This renderer remains the fallback for legacy blocks,
/// a preview blob that has not arrived from sync yet, PDF cards and exports.
/// The source PDF always survives, so text selection/search and lossless source
/// access do not depend on the raster previews.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../state/app_state.dart';
import 'pdf_runtime.dart';

/// Render scale for page images: the importer's historical choice, kept so an
/// on-demand slide is pixel-for-pixel the slide the raster path produced.
const double kPdfPageScale = 2.0;

abstract final class PdfPages {
  static final LinkedHashMap<String, _Doc> _docs = LinkedHashMap();
  static final LinkedHashMap<String, Uint8List> _pages = LinkedHashMap();
  static final Map<String, Future<Uint8List?>> _renders = {};
  static final Map<String, void Function()> _cancelRenders = {};
  static const _maxDocs = 4;
  static const _maxPageBytes = 96 << 20;
  static var _pageBytes = 0;
  static var _generation = 0;

  @visibleForTesting
  static Future<PdfDocument> Function(Uint8List, String)? openForTest;
  @visibleForTesting
  static Future<RenderedPdfPage?> Function(PdfPage)? renderForTest;

  static Future<Uint8List?> pageImage(AppState app, String hash, int page) {
    final key = '$hash#$page';
    final hit = _pages.remove(key);
    if (hit != null) {
      _pages[key] = hit;
      return Future.value(hit);
    }
    // One open per document, one render per page, even for overlapping viewers.
    return _renders.putIfAbsent(
        key, () => Future.microtask(() => _render(app, hash, page, key)));
  }

  static Future<Uint8List?> _render(
      AppState app, String hash, int page, String key) async {
    final generation = _generation;
    _Doc? entry;
    try {
      entry = _acquire(app, hash);
      if (entry == null) return null;
      final doc = await entry.ready;
      if (page < 0 || page >= doc.pages.length) return null;
      final image =
          await (renderForTest ?? renderPdfPageToPng)(doc.pages[page]);
      if (image == null) return null;
      if (generation == _generation) {
        _pageBytes -= _pages.remove(key)?.length ?? 0;
        _pages[key] = image.png;
        _pageBytes += image.png.length;
        while (_pageBytes > _maxPageBytes && _pages.length > 1) {
          _pageBytes -= _pages.remove(_pages.keys.first)!.length;
        }
      }
      return image.png;
    } catch (e) {
      debugPrint('[openote/pdf] page $page failed: $e');
      return null;
    } finally {
      if (entry != null) entry.busy--;
      // A reset/new attempt must never be removed by an older render.
      if (generation == _generation) _renders.remove(key);
      _evict();
    }
  }

  static Uint8List? cached(String hash, int page) => _pages['$hash#$page'];

  static Future<int?> pageCount(AppState app, String hash) async {
    final entry = _acquire(app, hash);
    if (entry == null) return null;
    try {
      return (await entry.ready).pages.length;
    } catch (_) {
      return null;
    } finally {
      entry.busy--;
      _evict();
    }
  }

  static _Doc? _acquire(AppState app, String hash) {
    var entry = _docs.remove(hash);
    if (entry == null) {
      final bytes = app.blob(hash);
      if (bytes == null) return null;
      // Cache the FUTURE, not a late, uninitialized PdfDocument.
      entry = _Doc((openForTest ?? PdfRuntime.open)(bytes, hash));
    }
    _docs[hash] = entry;
    entry.busy++;
    return entry;
  }

  static void _evict() {
    final keys = _docs.keys.toList();
    for (final key in keys) {
      final entry = _docs[key]!;
      if (entry.busy != 0) continue;
      if (!entry.failed && _docs.length <= _maxDocs) continue;
      _docs.remove(key);
      unawaited(entry.dispose());
    }
  }

  static Future<void> reset() async {
    _generation++;
    for (final cancel in _cancelRenders.values.toList(growable: false)) {
      cancel();
    }
    _cancelRenders.clear();
    final docs = _docs.values.toList();
    final renders = _renders.values.toList();
    _docs.clear();
    _renders.clear();
    _pages.clear();
    _pageBytes = 0;
    await Future.wait(renders);
    for (final doc in docs) {
      await doc.dispose();
    }
  }
}

class _Doc {
  _Doc(Future<PdfDocument> opening) {
    ready = opening.then((doc) => doc, onError: (Object e, StackTrace st) {
      failed = true;
      Error.throwWithStackTrace(e, st);
    });
  }
  late final Future<PdfDocument> ready;
  var busy = 0;
  var failed = false;
  Future<void> dispose() async {
    try {
      await (await ready).dispose();
    } catch (_) {}
  }
}

/// A rendered page's PNG bytes and pixel size.
typedef RenderedPdfPage = ({Uint8List png, int width, int height});

/// Render one page at the standard scale. Shared by the importer (which uses
/// it for nothing but sizing now), the on-demand path above, and the vector
/// PDF exporter's pre-render pass.
Future<RenderedPdfPage?> renderPdfPageToPng(PdfPage page) async {
  if (!page.width.isFinite ||
      !page.height.isFinite ||
      page.width <= 0 ||
      page.height <= 0) return null;
  final scale =
      math.min(kPdfPageScale, 4096 / math.max(page.width, page.height));
  final w = (page.width * scale).round();
  final h = (page.height * scale).round();
  if (w <= 0 || h <= 0) return null;

  PdfImage? img;
  final cancellation = page.createCancellationToken();
  final cancelId = '${identityHashCode(page)}#${DateTime.now().microsecondsSinceEpoch}';
  PdfPages._cancelRenders[cancelId] = cancellation.cancel;
  var expired = false;
  try {
    final rendering = page.render(
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      width: w,
      height: h,
      // White, not transparent: a slide with a transparent background renders
      // as invisible text on the page's own colour, and in dark mode that is
      // black-on-black.
      backgroundColor: 0xFFFFFFFF,
      cancellationToken: cancellation,
    );
    unawaited(rendering.then((image) {
      if (expired) image?.dispose();
    }, onError: (Object _) {}));
    img = await rendering.timeout(const Duration(seconds: 30), onTimeout: () {
      expired = true;
      cancellation.cancel();
      return null;
    });
    if (img == null) return null;
    final png = await _bgraToPng(img.pixels, img.width, img.height);
    if (png == null) return null;
    return (png: png, width: img.width, height: img.height);
  } catch (e) {
    debugPrint('[openote/pdf] page render failed: $e');
    return null;
  } finally {
    PdfPages._cancelRenders.remove(cancelId);
    img?.dispose();
  }
}

/// pdfium hands back raw BGRA; consumers get a real PNG so that anything
/// downstream — an export, a clipboard — holds an image file, not a pixel dump.
Future<Uint8List?> _bgraToPng(Uint8List bgra, int width, int height) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bgra,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
