/// Render pages of a stored PDF on demand — storage wave 1c.
///
/// A newly imported PDF keeps the source once and stores durable 2× PNG page
/// previews beside it. This renderer remains the fallback for legacy blocks,
/// a missing preview blob, PDF cards and exports.
/// The source PDF always survives, so text selection/search and lossless source
/// access do not depend on the raster previews.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

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
  static final LinkedHashMap<String, RenderedPdfRegion> _regions =
      LinkedHashMap();
  static final Map<String, Future<RenderedPdfRegion?>> _regionRenders = {};
  static final Map<String, List<bool Function()>> _interests = {};
  static final Map<String, void Function()> _cancelRenders = {};
  static const _maxDocs = 2;
  static const _maxDocBytes = 32 << 20;
  static const _maxPageBytes = 32 << 20;
  static Timer? _idleRelease;
  static var _pageBytes = 0;
  static var _regionBytes = 0;
  static var _generation = 0;
  static Future<void>? _pageQueue;

  @visibleForTesting
  static Future<PdfDocument> Function(Uint8List, String)? openForTest;
  @visibleForTesting
  static Future<RenderedPdfPage?> Function(PdfPage)? renderForTest;
  @visibleForTesting
  static Future<RenderedPdfPage?> Function(PdfPage, double)?
      renderAtScaleForTest;
  @visibleForTesting
  static Future<RenderedPdfRegion?> Function(PdfPage, Rect, int)?
      renderRegionForTest;

  static void _registerInterest(String key, bool Function()? isCurrent) =>
      _interests.putIfAbsent(key, () => []).add(isCurrent ?? () => true);

  static bool _needed(String key) =>
      _interests[key]?.any((current) => current()) ?? false;

  static Future<Uint8List?> pageImage(AppState app, String hash, int page,
      {bool Function()? isCurrent}) {
    final key = '$hash#$page';
    final hit = _pages.remove(key);
    if (hit != null) {
      _pages[key] = hit;
      return Future.value(hit);
    }
    // One open per document, one render per page, even for overlapping viewers.
    final pendingKey = '$_generation#${app.notebookId}#$key';
    _registerInterest(pendingKey, isCurrent);
    return _renders.putIfAbsent(pendingKey, () {
      final generation = _generation;
      final notebook = app.notebookId;
      // Queue before acquiring source bytes: rapid scrolling must not open
      // dozens of documents that all wait with their bytes pinned in memory.
      final result = (_pageQueue ?? Future<void>.value()).then<Uint8List?>((_) {
        if (generation != _generation ||
            notebook != app.notebookId ||
            !_needed(pendingKey)) {
          return null;
        }
        return _render(app, hash, page, key,
            isCurrent: () => _needed(pendingKey));
      }).whenComplete(() {
        _renders.remove(pendingKey);
        _interests.remove(pendingKey);
      });
      _pageQueue = result.then<void>((_) {}, onError: (Object _) {});
      return result;
    });
  }

  /// A transient, zoom-specific raster. The stored 2x preview stays untouched.
  static Future<Uint8List?> pageImageAtScale(
      AppState app, String hash, int page, double scale,
      {bool Function()? isCurrent}) {
    final key = '$hash#$page#${scale.toStringAsFixed(0)}';
    final hit = _pages.remove(key);
    if (hit != null) {
      _pages[key] = hit;
      return Future.value(hit);
    }
    final pendingKey = '$_generation#${app.notebookId}#$key';
    _registerInterest(pendingKey, isCurrent);
    return _renders.putIfAbsent(pendingKey, () {
      final generation = _generation;
      final notebook = app.notebookId;
      final result = (_pageQueue ?? Future<void>.value()).then<Uint8List?>((_) {
        if (generation != _generation ||
            notebook != app.notebookId ||
            !_needed(pendingKey)) {
          return null;
        }
        return _render(app, hash, page, key,
            scale: scale, isCurrent: () => _needed(pendingKey));
      }).whenComplete(() {
        _renders.remove(pendingKey);
        _interests.remove(pendingKey);
      });
      _pageQueue = result.then<void>((_) {}, onError: (Object _) {});
      return result;
    });
  }

  static Future<Uint8List?> _render(
      AppState app, String hash, int page, String key,
      {double scale = kPdfPageScale, bool Function()? isCurrent}) async {
    final generation = _generation;
    _Doc? entry;
    try {
      entry = _acquire(app, hash);
      if (entry == null) return null;
      final doc = await entry.ready;
      if (isCurrent != null && !isCurrent()) return null;
      if (page < 0 || page >= doc.pages.length) return null;
      final image = scale != kPdfPageScale && renderAtScaleForTest != null
          ? await renderAtScaleForTest!(doc.pages[page], scale)
          : scale == kPdfPageScale && renderForTest != null
              ? await renderForTest!(doc.pages[page])
              : await renderPdfPageToPng(doc.pages[page],
                  scale: scale, isCurrent: isCurrent);
      if (image == null) return null;
      if (generation == _generation) {
        _pageBytes -= _pages.remove(key)?.length ?? 0;
        _pages[key] = image.png;
        _pageBytes += image.png.length;
        while (_pageBytes > _maxPageBytes && _pages.isNotEmpty) {
          _pageBytes -= _pages.remove(_pages.keys.first)!.length;
        }
      }
      return image.png;
    } catch (e) {
      debugPrint('[openote/pdf] page $page failed: $e');
      return null;
    } finally {
      if (entry != null) entry.busy--;
      _evict();
    }
  }

  /// Only the visible part of a page, at screen resolution. These bytes are
  /// transient and never replace the original PDF or its durable preview.
  static Future<RenderedPdfRegion?> pageRegion(
      AppState app, String hash, int page, Rect region, int fullWidth,
      {bool Function()? isCurrent}) {
    final key =
        '$hash#$page#$fullWidth#${region.left},${region.top},${region.right},${region.bottom}';
    final hit = _regions.remove(key);
    if (hit != null) {
      _regions[key] = hit;
      return Future.value(hit);
    }
    final generation = _generation;
    final notebook = app.notebookId;
    final pendingKey = '$generation#$notebook#region#$key';
    _registerInterest(pendingKey, isCurrent);
    return _regionRenders.putIfAbsent(pendingKey, () {
      final result = (_pageQueue ?? Future<void>.value())
          .then<RenderedPdfRegion?>((_) async {
        if (generation != _generation ||
            notebook != app.notebookId ||
            !_needed(pendingKey)) {
          return null;
        }
        _Doc? entry;
        try {
          entry = _acquire(app, hash);
          if (entry == null) return null;
          final doc = await entry.ready;
          if (!_needed(pendingKey) || page < 0 || page >= doc.pages.length) {
            return null;
          }
          final image = renderRegionForTest != null
              ? await renderRegionForTest!(doc.pages[page], region, fullWidth)
              : await renderPdfRegionToPng(doc.pages[page], region, fullWidth,
                  isCurrent: () => _needed(pendingKey));
          if (image != null && generation == _generation) {
            _regionBytes -= _regions.remove(key)?.png.length ?? 0;
            _regions[key] = image;
            _regionBytes += image.png.length;
            while (_regionBytes > _maxPageBytes && _regions.isNotEmpty) {
              _regionBytes -= _regions.remove(_regions.keys.first)!.png.length;
            }
          }
          return image;
        } catch (e) {
          debugPrint('[openote/pdf] detail $page failed: $e');
          return null;
        } finally {
          if (entry != null) entry.busy--;
          _evict();
        }
      }).whenComplete(() {
        _regionRenders.remove(pendingKey);
        _interests.remove(pendingKey);
      });
      _pageQueue = result.then<void>((_) {}, onError: (Object _) {});
      return result;
    });
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
      entry = _Doc((openForTest ?? PdfRuntime.open)(bytes, hash), bytes.length);
    }
    _docs[hash] = entry;
    entry.busy++;
    return entry;
  }

  static void _evict() {
    var bytes = _docs.values.fold<int>(0, (sum, doc) => sum + doc.sourceBytes);
    final keys = _docs.keys.toList();
    final newest = _docs.entries.where((e) => !e.value.failed).lastOrNull?.key;
    for (final key in keys) {
      final entry = _docs[key]!;
      if (entry.busy != 0) continue;
      // Keep one recent document even if its source exceeds the normal budget.
      // Otherwise every sequential page would reopen the same large PDF.
      if (key == newest) continue;
      if (!entry.failed && _docs.length <= _maxDocs && bytes <= _maxDocBytes) {
        continue;
      }
      _docs.remove(key);
      bytes -= entry.sourceBytes;
      unawaited(entry.dispose());
    }
    _idleRelease?.cancel();
    if (_docs.isEmpty) return;
    _idleRelease = Timer(const Duration(seconds: 10), () {
      for (final key in _docs.keys.toList()) {
        final entry = _docs[key]!;
        if (entry.busy != 0) continue;
        _docs.remove(key);
        unawaited(entry.dispose());
      }
    });
  }

  static Future<void> reset() async {
    _idleRelease?.cancel();
    final queue = _pageQueue;
    _generation++;
    for (final cancel in _cancelRenders.values.toList(growable: false)) {
      cancel();
    }
    _cancelRenders.clear();
    final docs = _docs.values.toList();
    final renders = <Future<dynamic>>[
      ..._renders.values,
      ..._regionRenders.values
    ];
    _docs.clear();
    _renders.clear();
    _regionRenders.clear();
    _interests.clear();
    _pages.clear();
    _regions.clear();
    _pageBytes = 0;
    _regionBytes = 0;
    await Future.wait(renders);
    if (identical(queue, _pageQueue)) _pageQueue = null;
    _idleRelease?.cancel();
    for (final doc in docs) {
      await doc.dispose();
    }
  }
}

class _Doc {
  _Doc(Future<PdfDocument> opening, this.sourceBytes) {
    ready = opening.then((doc) => doc, onError: (Object e, StackTrace st) {
      failed = true;
      Error.throwWithStackTrace(e, st);
    });
  }
  late final Future<PdfDocument> ready;
  final int sourceBytes;
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
typedef RenderedPdfRegion = ({
  Uint8List png,
  int width,
  int height,
  Rect region
});

Future<void> _renderQueue = Future<void>.value();

/// Render one page at the standard scale for import, display or export.
Future<RenderedPdfPage?> renderPdfPageToPng(PdfPage page,
    {double scale = kPdfPageScale, bool Function()? isCurrent}) {
  // Bound raw pixel buffers and PNG encodes across imports and legacy views.
  // The timeout starts when work begins, not while waiting for another page.
  final result =
      _renderQueue.then((_) => _renderPdfPageToPng(page, scale, isCurrent));
  _renderQueue = result.then<void>((_) {}, onError: (Object _) {});
  return result;
}

Future<RenderedPdfPage?> _renderPdfPageToPng(
    PdfPage page, double requestedScale, bool Function()? isCurrent) async {
  if (isCurrent != null && !isCurrent()) return null;
  if (!page.width.isFinite ||
      !page.height.isFinite ||
      page.width <= 0 ||
      page.height <= 0) {
    return null;
  }
  final maxSide = requestedScale > kPdfPageScale ? 6144 : 4096;
  final scale =
      math.min(requestedScale, maxSide / math.max(page.width, page.height));
  final w = (page.width * scale).round();
  final h = (page.height * scale).round();
  if (w <= 0 || h <= 0) return null;

  final image = await _renderRaster(
      page, w, h, const Rect.fromLTWH(0, 0, 1, 1), isCurrent,
      maxPixels: maxSide * maxSide);
  return image == null
      ? null
      : (png: image.png, width: image.width, height: image.height);
}

Future<RenderedPdfRegion?> renderPdfRegionToPng(
    PdfPage page, Rect region, int fullWidth,
    {bool Function()? isCurrent}) {
  final result = _renderQueue.then((_) async {
    if ((isCurrent != null && !isCurrent()) ||
        !page.width.isFinite ||
        !page.height.isFinite ||
        page.width <= 0 ||
        page.height <= 0 ||
        fullWidth <= 0) {
      return null;
    }
    return _renderRaster(page, fullWidth,
        (fullWidth * page.height / page.width).ceil(), region, isCurrent);
  });
  _renderQueue = result.then<void>((_) {}, onError: (Object _) {});
  return result;
}

Future<RenderedPdfRegion?> _renderRaster(PdfPage page, int fullWidth,
    int fullHeight, Rect requestedRegion, bool Function()? isCurrent,
    {int maxPixels = 8 * 1024 * 1024}) async {
  final region = requestedRegion.intersect(const Rect.fromLTWH(0, 0, 1, 1));
  if (region.isEmpty ||
      !region.left.isFinite ||
      !region.top.isFinite ||
      !region.width.isFinite ||
      !region.height.isFinite) {
    return null;
  }
  // Bound actual patch buffers rather than limiting the resolution of the
  // complete page, which made deeply zoomed text permanently blurry.
  final pixels = fullWidth * fullHeight * region.width * region.height;
  if (pixels > maxPixels) {
    final reduce = math.sqrt(maxPixels / pixels);
    fullWidth = math.max(1, (fullWidth * reduce).floor());
    fullHeight = math.max(1, (fullHeight * reduce).floor());
  }
  final left = (region.left * fullWidth).floor();
  final top = (region.top * fullHeight).floor();
  final right = (region.right * fullWidth).ceil().clamp(left + 1, fullWidth);
  final bottom = (region.bottom * fullHeight).ceil().clamp(top + 1, fullHeight);
  final w = right - left;
  final h = bottom - top;
  final actualRegion = Rect.fromLTRB(left / fullWidth, top / fullHeight,
      right / fullWidth, bottom / fullHeight);

  PdfImage? img;
  final cancellation = page.createCancellationToken();
  final cancelId =
      '${identityHashCode(page)}#${DateTime.now().microsecondsSinceEpoch}';
  PdfPages._cancelRenders[cancelId] = cancellation.cancel;
  var expired = false;
  try {
    final rendering = page.render(
      x: left,
      y: top,
      fullWidth: fullWidth.toDouble(),
      fullHeight: fullHeight.toDouble(),
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
    if (isCurrent != null && !isCurrent()) return null;
    final png = await _bgraToPng(img.pixels, img.width, img.height);
    if (png == null) return null;
    return (
      png: png,
      width: img.width,
      height: img.height,
      region: actualRegion
    );
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
