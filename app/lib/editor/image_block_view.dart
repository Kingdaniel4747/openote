import 'dart:async';
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
  MemoryImage? _provider;
  String? _hash;

  /// True while an on-demand PDF page render is in flight — the placeholder
  /// then says "rendering" rather than "missing", which are different facts.
  bool _rendering = false;
  String? _pdfError;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ImageBlockView old) {
    super.didUpdateWidget(old);
    final key = widget.block.content['blob'] ?? widget.block.content['pdf'];
    if (key != _hash ||
        old.block.content['page'] != widget.block.content['page']) {
      _load();
    }
  }

  void _load() {
    final request = ++_loadRequest;
    _pdfError = null;
    // New PDF slides carry both the source `{pdf, page}` and a permanent
    // image `blob`. Legacy slides have only the source reference; render one
    // once, store it like an ordinary image and upgrade the block in place.
    final pdf = widget.block.content['pdf'] as String?;
    final preview = widget.block.content['blob'] as String?;
    if (pdf != null && preview == null) {
      final page = (widget.block.content['page'] as num?)?.toInt() ?? 0;
      _loadPdf(pdf, page, request);
      return;
    }
    final h = preview;
    _hash = h;
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
      if (!mounted || widget.block.content['blob'] != h) return;
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
      if (!mounted || widget.block.content['blob'] != h) return;
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
    _hash = pdf;
    final hit = PdfPages.cached(pdf, page);
    if (hit != null) {
      _persistPdfPreview(hit, request);
      return;
    }
    _rendering = true;
    PdfPages.pageImage(widget.app, pdf, page)
        .timeout(const Duration(seconds: 45))
        .then((png) {
      if (!mounted || request != _loadRequest) return;
      if (png != null) {
        _persistPdfPreview(png, request);
        return;
      }
      setState(() {
        _rendering = false;
        _pdfError = 'PDF page unavailable. Retry after syncing.';
        _provider = null;
      });
    }, onError: (Object error) {
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _rendering = false;
        _pdfError = 'PDF loading failed or timed out. Please retry.';
      });
    });
    if (mounted) setState(() {});
  }

  void _persistPdfPreview(Uint8List png, int request) {
    if (!mounted || request != _loadRequest) return;
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
    if (!mounted || request != _loadRequest) return;
    setState(() {
      _hash = ref ?? _hash;
      _rendering = false;
      _pdfError = null;
      _provider = MemoryImage(png);
    });
  }

  /// One event-loop turn between blob reads, shared by every image on the
  /// page — the stagger that keeps any single frame cheap.
  static Future<void> _readQueue = Future<void>.value();

  void _setBytes(Uint8List? b) {
    _provider = b == null ? null : MemoryImage(b);
    // Record intrinsic size once, so width-resize keeps aspect ratio.
    if (b != null && widget.block.content['naturalW'] == null) {
      ui.decodeImageFromList(b, (img) {
        if (!mounted) return;
        widget.block.content['naturalW'] = img.width.toDouble();
        widget.block.content['naturalH'] = img.height.toDouble();
        // Persist it (once) so proportional resize, export and hit-testing
        // all agree without re-decoding on every load.
        widget.app.markDirty();
        setState(() {});
      });
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
        return Center(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppText(_pdfError!, textAlign: TextAlign.center),
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh),
                label: const AppText('Retry')),
          ])));
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.broken_image_outlined,
              color: OnoteColors.graphite400),
          const SizedBox(width: 8),
          Flexible(child: Text(
              isPdf ? 'PDF not here yet — still syncing?' : 'Missing image',
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
      child: Align(
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
    );
  }
}
