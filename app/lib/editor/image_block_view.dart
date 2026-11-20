import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';

import '../media/pdf_pages.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// Image block: content-addressed blob reference (File Format Spec §3 blobs).
/// content: { blob: "sha256:…", mime, naturalW?, naturalH? }
///
/// Stateful so the decoded image + its provider are cached — this stops the
/// hover flicker (a fresh Image.memory each rebuild would blank for a frame)
/// and lets us record the intrinsic size for proportional resizing.
/// Content-addressed LRU for block-image bytes, shared across every
/// image view and every page. Keys are sha256 hashes, so an entry can
/// never be stale; the cap bounds memory, evicting least-recently-used.
class _BlobCache {
  static final _map = <String, Uint8List>{};
  static var _size = 0;
  static const _cap = 48 << 20; // 48 MB — a few pages of slides

  Uint8List? get(String h) {
    final v = _map.remove(h);
    if (v != null) _map[h] = v; // re-insert = most recent
    return v;
  }

  void put(String h, Uint8List b) {
    if (b.length > _cap) return;
    final old = _map.remove(h);
    if (old != null) _size -= old.length;
    _map[h] = b;
    _size += b.length;
    while (_size > _cap && _map.isNotEmpty) {
      final k = _map.keys.first;
      _size -= _map[k]!.length;
      _map.remove(k);
    }
  }
}

final _blobCache = _BlobCache();

class ImageBlockView extends StatefulWidget {
  const ImageBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<ImageBlockView> createState() => _ImageBlockViewState();
}

class _ImageBlockViewState extends State<ImageBlockView> {
  ImageProvider<Object>? _provider;
  String? _hash;
  Uint8List? _sourceBytes;
  Timer? _zoomRenderTimer;
  int _qualityRequest = 0;
  bool _zoomRendering = false;
  int _pdfRenderFailures = 0;
  String? _pdf;
  int _pdfPage = 0;
  String? _notebook;
  String? _ownerPage;
  double _pixelRatio = 1;
  int _decodedWidth = 0, _decodedHeight = 0;
  int? _sourceWidth;
  RenderedPdfRegion? _detail;
  String? _detailKey;
  String? _requestedDetail;
  bool _detailFailed = false;

  /// True while an on-demand PDF page render is in flight — the placeholder
  /// then says "rendering" rather than "missing", which are different facts.
  bool _rendering = false;
  String? _pdfError;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
    widget.app.canvas.addListener(_scheduleZoomRender);
    _scheduleZoomRender();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    _scheduleZoomRender();
  }

  @override
  void dispose() {
    _zoomRenderTimer?.cancel();
    widget.app.canvas.removeListener(_scheduleZoomRender);
    _qualityRequest++;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ImageBlockView old) {
    super.didUpdateWidget(old);
    if (old.app != widget.app) {
      old.app.canvas.removeListener(_scheduleZoomRender);
      widget.app.canvas.addListener(_scheduleZoomRender);
    }
    final key = widget.block.content['blob'] ?? widget.block.content['pdf'];
    if (key != _hash ||
        _pdf != widget.block.content['pdf'] ||
        _pdfPage != ((widget.block.content['page'] as num?)?.toInt() ?? 0) ||
        _notebook != widget.app.notebookId ||
        _ownerPage != widget.app.pageId) {
      _qualityRequest++;
      _zoomRenderTimer?.cancel();
      _zoomRendering = false;
      _detail = null;
      _detailKey = _requestedDetail = null;
      _sourceBytes = null;
      _sourceWidth = null;
      _provider = null;
      _load();
    }
    _scheduleZoomRender();
  }

  void _scheduleZoomRender() {
    // Invalidate old queued detail work immediately, not after the debounce.
    // The last sharp patch remains visible until its replacement arrives.
    _qualityRequest++;
    _requestedDetail = null;
    _zoomRenderTimer?.cancel();
    _zoomRenderTimer =
        Timer(const Duration(milliseconds: 180), _refreshResolution);
  }

  Rect _imageRect(Size size) {
    final nw = (widget.block.content['naturalW'] as num?)?.toDouble();
    final nh = (widget.block.content['naturalH'] as num?)?.toDouble();
    final natural =
        nw != null && nh != null && nw > 0 && nh > 0 ? Size(nw, nh) : size;
    return Offset.zero & applyBoxFit(BoxFit.contain, natural, size).destination;
  }

  Future<void> _refreshResolution() async {
    if (!mounted) return;
    final request = _qualityRequest;
    if (_sourceBytes != null) {
      final changed = _updateProvider();
      if (changed) setState(() {});
    }
    final pdf = _pdf;
    final box = context.findRenderObject();
    if (pdf == null ||
        _provider == null ||
        _sourceWidth == null ||
        box is! RenderBox ||
        !box.hasSize) {
      if (_zoomRendering) setState(() => _zoomRendering = false);
      return;
    }
    final imageRect = _imageRect(box.size);
    if (imageRect.isEmpty) return;
    final window = Offset.zero & MediaQuery.sizeOf(context);
    final points = [
      window.topLeft,
      window.topRight,
      window.bottomLeft,
      window.bottomRight
    ].map(box.globalToLocal).toList();
    var visible = Rect.fromLTRB(
            points.map((p) => p.dx).reduce(math.min),
            points.map((p) => p.dy).reduce(math.min),
            points.map((p) => p.dx).reduce(math.max),
            points.map((p) => p.dy).reduce(math.max))
        .intersect(imageRect);
    if (visible.isEmpty) return;
    final physicalWidth =
        imageRect.width * widget.app.canvas.scale * _pixelRatio;
    final fullWidth =
        ((physicalWidth * 1.25 / 128).ceil() * 128).clamp(128, 1048576);
    if (_sourceWidth != null && fullWidth <= _sourceWidth!) {
      if (_zoomRendering) setState(() => _zoomRendering = false);
      return; // The durable preview already covers this screen resolution.
    }
    // Pad and quantize the patch so small pans reuse it. Convert all four
    // window corners through the real widget transform, including rotation.
    visible = visible.inflate(96 / math.max(widget.app.canvas.scale, .01));
    final left =
        ((visible.left - imageRect.left) / imageRect.width * 32).floor() / 32;
    final top =
        ((visible.top - imageRect.top) / imageRect.height * 32).floor() / 32;
    final right =
        ((visible.right - imageRect.left) / imageRect.width * 32).ceil() / 32;
    final bottom =
        ((visible.bottom - imageRect.top) / imageRect.height * 32).ceil() / 32;
    final region = Rect.fromLTRB(left, top, right, bottom)
        .intersect(const Rect.fromLTWH(0, 0, 1, 1));
    final key = '$pdf#$_pdfPage#$fullWidth#$region';
    if (key == _detailKey) {
      if (_zoomRendering) setState(() => _zoomRendering = false);
      return;
    }
    _requestedDetail = key;
    setState(() {
      _zoomRendering = true;
      _detailFailed = false;
    });
    bool current() =>
        mounted &&
        request == _qualityRequest &&
        _requestedDetail == key &&
        _notebook == widget.app.notebookId &&
        _ownerPage == widget.app.pageId;
    final image = await PdfPages.pageRegion(
        widget.app, pdf, _pdfPage, region, fullWidth.toInt(),
        isCurrent: current);
    if (!current()) return;
    setState(() {
      _zoomRendering = false;
      _detailFailed = image == null;
      if (image != null) {
        _detail = image;
        _detailKey = key;
        _pdfRenderFailures = 0;
      } else {
        _pdfRenderFailures++;
      }
    });
    if (image == null && _pdfRenderFailures <= 3) {
      _zoomRenderTimer =
          Timer(const Duration(milliseconds: 600), _refreshResolution);
    }
  }

  void _load() {
    final request = ++_loadRequest;
    _pdfError = null;
    _pdfRenderFailures = 0;
    _detailFailed = false;
    // New PDF slides carry both the source `{pdf, page}` and a permanent
    // image `blob`. Legacy slides have only the source reference; render one
    // once, store it like an ordinary image and upgrade the block in place.
    final pdf = widget.block.content['pdf'] as String?;
    final preview = widget.block.content['blob'] as String?;
    _pdf = pdf;
    _pdfPage = (widget.block.content['page'] as num?)?.toInt() ?? 0;
    _notebook = widget.app.notebookId;
    _ownerPage = widget.app.pageId;
    _hash = preview ?? pdf;
    if (pdf != null && preview == null) {
      final page = (widget.block.content['page'] as num?)?.toInt() ?? 0;
      _loadPdf(pdf, page, request);
      return;
    }
    final h = preview;
    if (h == null) {
      _provider = null;
      if (mounted) setState(() {});
      return;
    }
    // Content-addressed LRU first: a hash can never go stale, so a hit IS
    // the bytes — revisiting a page costs no reads at all.
    final cached = _blobCache.get(h);
    if (cached != null) {
      _setBytes(cached);
      if (mounted) setState(() {});
      return;
    }
    // Cold read, DEFERRED. The fetch is a synchronous SQLite read —
    // megabytes for an imported slide — and doing it during build was THE
    // page-switch stall: every image on the incoming page was read
    // back-to-back before the first frame could paint ("about half a
    // second or so very consistently"). Reads now run after the frame,
    // one per event-loop turn through a shared queue, so the page appears
    // immediately and its pictures pop in over the next few frames.
    _rendering = true;
    _readQueue = _readQueue.then((_) async {
      await Future<void>.delayed(Duration.zero);
      if (!_loadCurrent(request) || widget.block.content['blob'] != h) return;
      // The queue is SHARED and CHAINED: every later image read `.then`s
      // onto this future, and a future carrying an error never runs those
      // callbacks. So one throwing read — a file a cloud client had locked —
      // used to blank every image loaded after it, all session. A failed
      // read must cost exactly this image its placeholder and nothing else.
      Uint8List? b;
      try {
        b = widget.app.blob(h);
      } catch (e) {
        debugPrint('[openote] could not read image $h: $e');
      }
      if (b != null) _blobCache.put(h, b);
      if (!_loadCurrent(request) || widget.block.content['blob'] != h) return;
      if (b == null && pdf != null) {
        // A cloud client can deliver the small page record before the preview
        // blob. The original PDF is sufficient to rebuild it, so a temporarily
        // missing preview must not leave the slide blank.
        _loadPdf(
            pdf, (widget.block.content['page'] as num?)?.toInt() ?? 0, request);
        return;
      }
      setState(() {
        _rendering = false;
        _setBytes(b);
      });
    });
    if (mounted) setState(() {});
  }

  void _loadPdf(String pdf, int page, int request) {
    final hit = PdfPages.cached(pdf, page);
    if (hit != null) {
      _persistPdfPreview(hit, request);
      return;
    }
    _rendering = true;
    PdfPages.pageImage(widget.app, pdf, page,
        isCurrent: () => _loadCurrent(request)).then((png) {
      if (!_loadCurrent(request)) return;
      if (png != null) {
        _persistPdfPreview(png, request);
        return;
      }
      setState(() {
        _rendering = false;
        _pdfError = 'PDF page unavailable. Re-import the PDF.';
        _provider = null;
      });
    }, onError: (Object error) {
      if (!_loadCurrent(request)) return;
      setState(() {
        _rendering = false;
        _pdfError = 'PDF loading failed or timed out. Please retry.';
      });
    });
    if (mounted) setState(() {});
  }

  bool _loadCurrent(int request) =>
      mounted &&
      request == _loadRequest &&
      _notebook == widget.app.notebookId &&
      _ownerPage == widget.app.pageId;

  void _persistPdfPreview(Uint8List png, int request) {
    if (!_loadCurrent(request)) return;
    String? ref;
    try {
      // Content-addressed writes are idempotent. Once this block is saved,
      // opening the page again never needs pdfium for display.
      final notebookId = widget.app.notebookId;
      if (notebookId != null && !widget.app.notebookIsReadOnly(notebookId)) {
        final hash = widget.app.addBlob(png, 'image/png');
        ref = 'sha256:$hash';
        widget.block.content['blob'] = ref;
        _hash = ref;
        _blobCache.put(ref, png);
        widget.app.markDirty();
      }
    } catch (e) {
      debugPrint('[openote/pdf] could not persist page preview: $e');
    }
    if (!_loadCurrent(request)) return;
    setState(() {
      _hash = ref ?? _hash;
      _rendering = false;
      _pdfError = null;
      _setBytes(png);
    });
  }

  /// One event-loop turn between blob reads, shared by every image on the
  /// page — the stagger that keeps any single frame cheap.
  static Future<void> _readQueue = Future<void>.value();

  bool _updateProvider() {
    final bytes = _sourceBytes;
    if (bytes == null) return false;
    final nw = (widget.block.content['naturalW'] as num?)?.toDouble();
    final nh = (widget.block.content['naturalH'] as num?)?.toDouble();
    final height = widget.block.h ??
        (nw != null && nh != null && nw > 0
            ? widget.block.w * nh / nw
            : widget.block.w);
    final size = _imageRect(Size(widget.block.w, height)).size;
    final scale = widget.app.canvas.scale * _pixelRatio * 1.25;
    var width = ((size.width * scale / 64).ceil() * 64).clamp(1, 8192).toInt();
    var decodeHeight =
        ((size.height * scale / 64).ceil() * 64).clamp(1, 8192).toInt();
    if (width * decodeHeight > 8 * 1024 * 1024) {
      final reduce = math.sqrt(8 * 1024 * 1024 / (width * decodeHeight));
      width = math.max(1, (width * reduce).floor());
      decodeHeight = math.max(1, (decodeHeight * reduce).floor());
    }
    if (_provider != null &&
        _decodedWidth >= width &&
        _decodedHeight >= decodeHeight) {
      return false;
    }
    _decodedWidth = width;
    _decodedHeight = decodeHeight;
    _provider = ResizeImage(MemoryImage(bytes),
        width: width, height: decodeHeight, policy: ResizeImagePolicy.fit);
    return true;
  }

  void _setBytes(Uint8List? b) {
    if (!identical(_sourceBytes, b)) {
      _decodedWidth = _decodedHeight = 0;
      _provider = null;
    }
    _sourceBytes = b;
    if (b == null) {
      _provider = null;
    } else {
      _updateProvider();
      _inspectImage(b, _loadRequest);
    }
    _scheduleZoomRender();
  }

  Future<void> _inspectImage(Uint8List bytes, int request) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!_loadCurrent(request) || !identical(bytes, _sourceBytes)) return;
      _sourceWidth = descriptor.width;
      if (widget.block.content['naturalW'] == null) {
        widget.block.content['naturalW'] = descriptor.width.toDouble();
        widget.block.content['naturalH'] = descriptor.height.toDouble();
        widget.app.markDirty();
      }
      setState(() {});
      _scheduleZoomRender();
    } catch (e) {
      debugPrint('[openote] could not inspect image: $e');
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_provider == null && _rendering) {
      // The slide's own footprint, so the page does not reflow when the
      // pixels arrive a frame or two later.
      return SizedBox(
        width: widget.block.w,
        height: widget.block.h,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_provider == null) {
      final isPdf = widget.block.content['pdf'] != null;
      if (isPdf && _pdfError != null) {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AppText(_pdfError!, textAlign: TextAlign.center),
                  TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const AppText('Retry')),
                ])));
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              isPdf
                  ? Icons.picture_as_pdf_outlined
                  : Icons.broken_image_outlined,
              color: OnoteColors.graphite400),
          const SizedBox(width: 8),
          Flexible(
              child: Text(isPdf ? 'PDF page unavailable' : 'Missing image',
                  style: const TextStyle(color: OnoteColors.graphite400))),
        ]),
      );
    }
    final nw = (widget.block.content['naturalW'] as num?)?.toDouble();
    final nh = (widget.block.content['naturalH'] as num?)?.toDouble();
    final aspect = (nw != null && nh != null && nh > 0) ? nw / nh : null;
    final boxH = widget.block.h;
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      // Anchor top-left, always.
      //
      // This is why imported images sat **too high**. `BlockView` gives the block
      // a container of exactly `w × h` — OneNote's own display rectangle — and an
      // `AspectRatio` child derives its height from the width instead. When the
      // stored rectangle's aspect doesn't quite match the PNG's, the child ends
      // up a different height from the container, and a `Container` with one
      // child **centres** it: the image shifted up by half the difference, which
      // is exactly the "layout is right, just offset vertically" symptom. It was
      // also `BoxFit.cover`, so the mismatch was cropped rather than visible.
      child: Stack(children: [
        Align(
          alignment: Alignment.topLeft,
          child: boxH != null
              // Imported (or explicitly sized): honour OneNote's rectangle exactly
              // and fit inside it — never crop, never shift.
              ? Image(
                  image: _provider!,
                  width: widget.block.w,
                  height: boxH,
                  fit: BoxFit.contain,
                  alignment: Alignment.topLeft,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                )
              : aspect != null
                  // Auto-height: derive the height from the width so a width
                  // resize scales the image proportionally.
                  ? AspectRatio(
                      aspectRatio: aspect,
                      child: Image(
                        image: _provider!,
                        fit: BoxFit.contain,
                        alignment: Alignment.topLeft,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    )
                  : Image(
                      image: _provider!,
                      width: widget.block.w,
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topLeft,
                      gaplessPlayback: true, // no blank frame on rebuild
                      filterQuality: FilterQuality.medium,
                    ),
        ),
        if (_detail != null)
          Positioned.fill(
            child: IgnorePointer(
                child: LayoutBuilder(builder: (context, constraints) {
              final rect = _imageRect(constraints.biggest);
              final detail = _detail!;
              return Stack(children: [
                Positioned(
                  left: rect.left + detail.region.left * rect.width,
                  top: rect.top + detail.region.top * rect.height,
                  width: detail.region.width * rect.width,
                  height: detail.region.height * rect.height,
                  child: Image.memory(detail.png,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium),
                )
              ]);
            })),
          ),
        if (_detailFailed && !_zoomRendering)
          Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                tooltip: 'Retry',
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  _pdfRenderFailures = 0;
                  _scheduleZoomRender();
                },
              )),
        if (_zoomRendering)
          const Positioned(
            right: 8,
            top: 8,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ]),
    );
  }
}
