import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../core/platform_open.dart';
import '../export/md_common.dart' show safeFilename;
import '../media/pdf_pages.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import '../ui/pdf_viewer_dialog.dart';
import 'video_block_view.dart';
import '../ui/onote_dialog.dart';

/// File attachment block (MEDIA-2): the file lives in the notebook's
/// content-addressed blob store; "Save a copy…" extracts it back out.
/// content: { blob: "sha256:…", name, mime, size }
///
/// **Also the media LINK block (MEDIA-7).** A block with a `url` and no `blob`
/// is a link card — a lecture recording embedded in the page so it can be
/// reached from the notes rather than hunted for in a browser. It rides this
/// block type on purpose rather than taking a new one:
///
///   * `BlockType.embed` looks free but is not — the data-model spec and the
///     PRD reserve it for live page transclusion, which is the "read-only
///     version of one page visible inside another" ask sitting a few lines
///     further down PLANNING.md. Taking it for video would collide head-on.
///   * A brand-new enum value would be the honest choice, and it is now safe
///     to add one (see `Block.rawType`) — but it is still not free: every
///     build older than that fix renders it as "Unsupported block". A `file`
///     block degrades far better, because every shipped build already knows
///     the type.
///
/// What an OLD build does with a link card, exactly: it mounts this widget,
/// shows the icon and the correct name, and both buttons return early because
/// `content['blob']` is null. An inert, correctly-labelled card — and `url`
/// rides along untouched in `content`, so opening the same page in a current
/// build restores the feature completely.
class FileBlockView extends StatelessWidget {
  const FileBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    // A recording kept in the notebook, played in the page. Checked before the
    // url and blob branches because it is neither: the bytes are a file beside
    // the container (store/media_store.dart), and an older build that knows
    // about neither still shows the right name on an inert card.
    final media = (block.content['media'] as String?)?.trim();
    if (media != null && media.isNotEmpty) {
      return VideoBlockView(block: block, app: app);
    }
    if (block.content['kind'] == 'drawio') return _drawioCard(context);
    final url = (block.content['url'] as String?)?.trim();
    if (url != null && url.isNotEmpty) return _linkCard(context, url);
    // A PDF card: the deck behind a click, with a thumbnail so the page
    // reads as holding the document rather than a paperclip. Keyed on the
    // mime, so a plain .pdf attachment dropped before this existed upgrades
    // itself the next time it renders. An older build shows it as its
    // ordinary attachment card — same blob, both buttons still work.
    final blob = block.content['blob'] as String?;
    if (blob != null && block.content['mime'] == 'application/pdf') {
      return _pdfCard(context, blob);
    }
    final name = block.content['name'] as String? ?? 'file';
    final size = (block.content['size'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file,
              size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text(_fmtSize(size),
                    style: const TextStyle(
                        fontSize: 11, color: OnoteColors.graphite400)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Open with the default app',
            onPressed: () => _openWithDefaultApp(context),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Save a copy…',
            onPressed: () => _saveCopy(context),
          ),
        ],
      ),
    );
  }

  /// The whole document behind a click: first page as the thumbnail, opened
  /// in the popup viewer where the text is selectable. "Embed my lectures
  /// into the page to be able to quickly reference in the future."
  Widget _pdfCard(BuildContext context, String blob) {
    final name = (block.content['name'] as String?)?.trim();
    final pages = (block.content['pages'] as num?)?.toInt();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      // growFrom: the card's own centre — the viewer reads as the
      // thumbnail opening rather than a dialog appearing over it.
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        showPdfViewerDialog(context, app,
            hash: blob,
            title: name,
            growFrom: box != null && box.hasSize
                ? box.localToGlobal(box.size.center(Offset.zero))
                : null);
      },
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: FutureBuilder<Uint8List?>(
              future: PdfPages.pageImage(app, blob, 0),
              builder: (context, snap) => snap.data == null
                  ? Container(
                      height: 120,
                      color: OnoteColors.paper100,
                      child: const Center(
                        child: Icon(Icons.picture_as_pdf_outlined,
                            size: 32, color: OnoteColors.graphite400),
                      ),
                    )
                  : Image.memory(snap.data!,
                      height: 160,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      gaplessPlayback: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              Icon(Icons.picture_as_pdf_outlined,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name == null || name.isEmpty ? 'PDF' : name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                        pages == null
                            ? 'Open — text is selectable'
                            : '$pages page${pages == 1 ? '' : 's'} — open to '
                                'read and copy',
                        style: const TextStyle(
                            fontSize: 11, color: OnoteColors.graphite400)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.download_outlined, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: 'Save a copy…',
                onPressed: () => _saveCopy(context),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// A link to something that lives outside the notebook — a lecture
  /// recording on a university site, a video, a page worth coming back to.
  ///
  /// Still a link and not a player, but for a narrower reason than it used to
  /// be. The old reason was that inline playback meant a media engine on three
  /// desktop platforms and the AppImage could not declare a system libmpv;
  /// Openote now ships a .deb and an .rpm, which can, so a video the user
  /// copies IN does play in the page (see video_block_view.dart). What stays
  /// true is that a URL is not a file: a YouTube or Panopto page is a web
  /// application, not a stream we can hand to a decoder, and pretending
  /// otherwise would mean embedding a browser. Those go to the browser.
  Widget _linkCard(BuildContext context, String url) {
    final scheme = Theme.of(context).colorScheme;
    final name = (block.content['name'] as String?)?.trim();
    final kind = block.content['kind'] as String?;
    final openable = PlatformOpen.isOpenableUrl(url);
    final host = Uri.tryParse(url)?.host ?? '';

    return InkWell(
      // Only wire the tap when the scheme is one we will actually hand to the
      // OS. A card that looks clickable and silently does nothing is worse
      // than one that plainly is not.
      onTap: openable ? () => _openLink(context, url) : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                kind == 'video'
                    ? Icons.play_circle_outline
                    : Icons.link_outlined,
                size: 22,
                color: openable ? scheme.primary : OnoteColors.graphite400),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name == null || name.isEmpty ? url : name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(
                      openable
                          ? (host.isEmpty ? url : host)
                          : 'Not a link this can open',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: OnoteColors.graphite400)),
                ],
              ),
            ),
            if (openable) ...[
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new,
                  size: 14, color: OnoteColors.graphite400),
            ],
          ],
        ),
      ),
    );
  }

  /// A local reference rather than an attachment: diagrams commonly live in a
  /// separately synchronised folder and must remain editable there.
  Widget _drawioCard(BuildContext context) {
    final path = (block.content['path'] as String?)?.trim() ?? '';
    final name = (block.content['name'] as String?)?.trim();
    final file = File(path);
    final exists = path.isNotEmpty && file.existsSync();
    final previewable = exists;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: exists ? () => _selectOrOpenDiagram(context, file, name) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(9)),
                child: exists
                    ? _diagramPreview(file, compact: true)
                    : _diagramPlaceholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 5, 7),
              child: Row(children: [
                Icon(Icons.account_tree_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 7),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text(
                          name == null || name.isEmpty
                              ? 'draw.io diagram'
                              : name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 13)),
                      Text(
                          exists
                              ? (previewable
                                  ? 'Tap to preview · open to edit'
                                  : 'Open in draw.io to view or edit')
                              : 'Original file is unavailable',
                          style: const TextStyle(
                              fontSize: 11, color: OnoteColors.graphite400)),
                    ])),
                IconButton(
                    icon: const Icon(Icons.open_in_new, size: 17),
                    tooltip: 'Open in draw.io',
                    onPressed:
                        exists ? () => _openDiagram(context, path) : null),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diagramPlaceholder() => const Center(
        child: Icon(Icons.account_tree_outlined,
            size: 46, color: OnoteColors.graphite400),
      );

  /// A PNG can use Flutter's normal image decoder. Native draw.io files are
  /// XML, so their diagram model is drawn locally for a useful read-only
  /// preview; editing stays in draw.io.
  Widget _diagramPreview(File file, {bool compact = false}) {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.png') {
      return Image.file(file,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _diagramPlaceholder());
    }
    if (ext == '.drawio' || ext == '.xml') {
      return FutureBuilder<_DrawioPreview?>(
        future: _DrawioPreview.read(file),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final preview = snapshot.data;
          if (preview == null) return _diagramPlaceholder();
          if (preview.image != null) {
            return Image.memory(preview.image!, fit: BoxFit.contain);
          }
          return CustomPaint(
              painter: _DrawioPreviewPainter(preview),
              child: const SizedBox.expand());
        },
      );
    }
    return _diagramPlaceholder();
  }

  Future<void> _openDiagram(BuildContext context, String path) async {
    if (!await PlatformOpen.file(path) && context.mounted) {
      _toast(context, 'No app is registered to open this diagram.');
    }
  }

  /// Object cards follow the rest of the canvas: one click selects and shows
  /// its common action bar; clicking an already-selected card opens its viewer.
  void _selectOrOpenDiagram(BuildContext context, File file, String? name) {
    if (!app.selectedIds.contains(block.id)) {
      app.select(block.id);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    _showDiagramPreview(context, file, name,
        growFrom: box != null && box.hasSize
            ? box.localToGlobal(box.size.center(Offset.zero))
            : null);
  }

  void _showDiagramPreview(BuildContext context, File file, String? name,
      {Offset? growFrom}) {
    showOnoteDialog<void>(
      context: context,
      growFrom: growFrom,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 980,
          height: 760,
          child: Column(children: [
            AppBar(
                title: Text(
                    name == null || name.isEmpty ? 'Diagram preview' : name),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx))
                ]),
            Expanded(
                child: InteractiveViewer(
                    minScale: .3,
                    maxScale: 5,
                    child: SizedBox(
                        width: 900,
                        height: 650,
                        child: _diagramPreview(file)))),
          ]),
        ),
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final ok = await PlatformOpen.url(url);
    if (!ok && context.mounted)
      _toast(context, "That link couldn't be opened.");
  }

  /// MEDIA-2: open the attachment in whatever application owns its type.
  ///
  /// The bytes live in the notebook's blob store, so there's no path to hand the
  /// OS — materialise a copy in the temp directory under the original filename
  /// (so the extension drives the file association) and open that.
  Future<void> _openWithDefaultApp(BuildContext context) async {
    final hash = block.content['blob'] as String?;
    if (hash == null) return;
    final bytes = app.blob(hash);
    if (bytes == null) {
      if (context.mounted) _toast(context, 'That attachment is missing.');
      return;
    }
    final name = (block.content['name'] as String?)?.trim();
    final safe =
        safeFilename(name == null || name.isEmpty ? 'attachment' : name);
    // A notebook can arrive from an import or a shared folder, so an
    // attachment is not necessarily something this user chose to put here.
    // Opening a document is safe; opening a program is a decision, and it
    // should be one the person makes on purpose.
    if (PlatformOpen.isExecutableName(safe)) {
      if (!context.mounted) return;
      final go = await _confirmRun(context, safe);
      if (go != true || !context.mounted) return;
    }
    try {
      final dir = await Directory.systemTemp.createTemp('onote_open_');
      final f = File(p.join(dir.path, safe));
      await f.writeAsBytes(bytes);
      final ok = await PlatformOpen.file(f.path);
      if (!ok && context.mounted) {
        _toast(context,
            'No app is registered for that file type — use “Save a copy…”.');
      }
    } catch (e) {
      if (context.mounted) _toast(context, "Couldn't open that attachment: $e");
    }
  }

  /// Ask before running a program that came out of a notebook.
  ///
  /// States what will happen rather than warning vaguely, and offers the safe
  /// alternative as the other button — the same shape §7h asks of every
  /// destructive-or-risky confirmation.
  Future<bool?> _confirmRun(BuildContext context, String filename) =>
      showOnoteDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Run this file?'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filename, style: OnoteType.uiStrong),
                const SizedBox(height: OnoteSpace.x4),
                const Text(
                  'This attachment is a program, not a document — opening it '
                  'runs it. If the notebook came from someone else or was '
                  'imported, only continue if you know what this is.',
                  style: OnoteType.ui,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
                _saveCopy(context);
              },
              child: const Text('Save a copy instead'),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Run it')),
          ],
        ),
      );

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _saveCopy(BuildContext context) async {
    final hash = block.content['blob'] as String?;
    if (hash == null) return;
    final bytes = app.blob(hash);
    if (bytes == null) {
      // The SAME words the Open button gives for the same missing file. One
      // of the two used to explain it and the other silently did nothing.
      _toast(context, 'That attachment is missing.');
      return;
    }
    final loc = await getSaveLocation(
        suggestedName: block.content['name'] as String? ?? 'file');
    if (loc == null) return;
    try {
      await File(loc.path).writeAsBytes(bytes);
    } catch (e) {
      // A full stick, a protected folder: the write threw into an unhandled
      // Future and the student was told nothing at all.
      if (context.mounted) _toast(context, "That copy didn't save: $e");
      return;
    }
    if (context.mounted) _toast(context, 'Saved to ${loc.path}');
  }

  String _fmtSize(int b) => b < 1024
      ? '$b B'
      : b < 1024 * 1024
          ? '${(b / 1024).toStringAsFixed(1)} KB'
          : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// A small, dependency-free renderer for the useful core of draw.io's mxGraph
/// XML: vertices, labels and connectors. It deliberately does not edit or
/// reinterpret the diagram; draw.io remains the editor of record.
class _DrawioPreview {
  const _DrawioPreview(this.cells, this.edges, this.bounds) : image = null;
  const _DrawioPreview.image(this.image)
      : cells = const [],
        edges = const [],
        bounds = Rect.zero;

  final List<_DrawioCell> cells;
  final List<_DrawioEdge> edges;
  final Rect bounds;
  final Uint8List? image;

  /// Rebuilding selection chrome must not restart XML parsing and briefly
  /// replace a diagram with its loading spinner. The source's timestamp and
  /// size make this cache refresh automatically after it is edited in draw.io.
  static final _reads = <String, Future<_DrawioPreview?>>{};

  static Future<_DrawioPreview?> read(File file) {
    final stat = file.statSync();
    final key =
        '${file.path}:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    return _reads.putIfAbsent(key, () => _read(file));
  }

  static Future<_DrawioPreview?> _read(File file) async {
    try {
      // draw.io itself is the only renderer that knows every library shape,
      // icon and custom style. When its desktop app is installed, ask it for
      // a temporary PNG first so the preview is pixel-faithful, not an
      // approximation made from the graph's rectangles.
      final rendered = await _exportWithDrawio(file);
      if (rendered != null) return _DrawioPreview.image(rendered);
      final raw = await file.readAsString();
      final source = _diagramXml(raw);
      if (source == null) return null;
      final document = XmlDocument.parse(source);
      final cells = <_DrawioCell>[];
      final byId = <String, _DrawioCell>{};
      for (final element in document.findAllElements('mxCell')) {
        if (element.getAttribute('vertex') != '1') continue;
        final geometry = element.getElement('mxGeometry');
        if (geometry == null) continue;
        final width = double.tryParse(geometry.getAttribute('width') ?? '');
        final height = double.tryParse(geometry.getAttribute('height') ?? '');
        if (width == null || height == null || width <= 0 || height <= 0) {
          continue;
        }
        final cell = _DrawioCell(
          id: element.getAttribute('id') ?? '',
          rect: Rect.fromLTWH(
            double.tryParse(geometry.getAttribute('x') ?? '') ?? 0,
            double.tryParse(geometry.getAttribute('y') ?? '') ?? 0,
            width,
            height,
          ),
          label: _plainText(element.getAttribute('value') ?? ''),
          color: _styleColor(element.getAttribute('style') ?? ''),
        );
        cells.add(cell);
        if (cell.id.isNotEmpty) byId[cell.id] = cell;
      }
      if (cells.isEmpty) return null;
      final edges = <_DrawioEdge>[];
      for (final element in document.findAllElements('mxCell')) {
        if (element.getAttribute('edge') != '1') continue;
        final from = byId[element.getAttribute('source')];
        final to = byId[element.getAttribute('target')];
        if (from != null && to != null) edges.add(_DrawioEdge(from, to));
      }
      var bounds = cells.first.rect;
      for (final cell in cells.skip(1)) {
        bounds = bounds.expandToInclude(cell.rect);
      }
      return _DrawioPreview(cells, edges, bounds.inflate(20));
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _exportWithDrawio(File source) async {
    if (!Platform.isWindows) return null;
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final candidates = [
      p.join(programFiles, 'draw.io', 'draw.io.exe'),
      p.join(programFiles, 'diagrams.net', 'diagrams.net.exe'),
      if (localAppData != null)
        p.join(localAppData, 'Programs', 'draw.io', 'draw.io.exe'),
    ];
    final executable = candidates.firstWhere(
        (candidate) => File(candidate).existsSync(),
        orElse: () => '');
    if (executable.isEmpty) return null;
    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('openote_drawio_preview_');
      final output = File(p.join(temp.path, 'preview.png'));
      final result = await Process.run(executable, [
        '--export',
        '--format',
        'png',
        '--output',
        output.path,
        source.path,
      ]).timeout(const Duration(seconds: 12));
      if (result.exitCode != 0 || !output.existsSync()) return null;
      return await output.readAsBytes();
    } catch (_) {
      return null;
    } finally {
      if (temp != null) {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  static String? _diagramXml(String raw) {
    try {
      final doc = XmlDocument.parse(raw);
      if (doc.findAllElements('mxGraphModel').isNotEmpty) return raw;
      final diagrams = doc.findAllElements('diagram');
      if (diagrams.isEmpty) return null;
      final encoded = diagrams.first.innerText.trim();
      if (encoded.isEmpty) return null;
      final inflated = ZLibDecoder(raw: true)
          .convert(base64.decode(base64.normalize(encoded)));
      return Uri.decodeComponent(utf8.decode(inflated));
    } catch (_) {
      return null;
    }
  }

  static String _plainText(String value) => value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Color _styleColor(String style) {
    final m = RegExp(r'fillColor=(#[0-9A-Fa-f]{6})').firstMatch(style);
    if (m == null) return const Color(0xffeef3ff);
    return Color(int.parse(m.group(1)!.substring(1), radix: 16) | 0xff000000);
  }
}

class _DrawioCell {
  const _DrawioCell(
      {required this.id,
      required this.rect,
      required this.label,
      required this.color});
  final String id;
  final Rect rect;
  final String label;
  final Color color;
}

class _DrawioEdge {
  const _DrawioEdge(this.from, this.to);
  final _DrawioCell from;
  final _DrawioCell to;
}

class _DrawioPreviewPainter extends CustomPainter {
  const _DrawioPreviewPainter(this.preview);
  final _DrawioPreview preview;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = [
          size.width / preview.bounds.width,
          size.height / preview.bounds.height
        ].reduce((a, b) => a < b ? a : b) *
        .92;
    final dx = (size.width - preview.bounds.width * scale) / 2 -
        preview.bounds.left * scale;
    final dy = (size.height - preview.bounds.height * scale) / 2 -
        preview.bounds.top * scale;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    final line = Paint()
      ..color = OnoteColors.graphite400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final edge in preview.edges) {
      canvas.drawLine(edge.from.rect.center, edge.to.rect.center, line);
    }
    for (final cell in preview.cells) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(cell.rect, const Radius.circular(5)),
          Paint()..color = cell.color);
      canvas.drawRRect(
          RRect.fromRectAndRadius(cell.rect, const Radius.circular(5)), line);
      if (cell.label.isEmpty) continue;
      final text = TextPainter(
          text: TextSpan(
              text: cell.label,
              style: const TextStyle(
                  fontSize: 12, color: OnoteColors.graphite900)),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: 3,
          ellipsis: '…')
        ..layout(
            maxWidth:
                (cell.rect.width - 12).clamp(1, double.infinity).toDouble());
      text.paint(
          canvas,
          Offset(cell.rect.center.dx - text.width / 2,
              cell.rect.center.dy - text.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrawioPreviewPainter oldDelegate) =>
      oldDelegate.preview != preview;
}
