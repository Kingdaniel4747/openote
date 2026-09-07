library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/models.dart';
import '../state/app_state.dart';

/// Store one phone scan in [notebookId] and append it below the page content.
/// The target is captured when the QR code is created, so navigating elsewhere
/// while the phone scanner is open cannot put a worksheet on the wrong page.
Future<Block> importPhoneScan(
  AppState app, {
  required String notebookId,
  required String pageId,
  required Uint8List bytes,
  required String mime,
}) async {
  if (mime != 'image/jpeg' && mime != 'image/png') {
    throw const FormatException('The scanner sent an unsupported image type.');
  }
  if (!app.notebooks.any((notebook) => notebook.id == notebookId)) {
    throw StateError('The target notebook no longer exists.');
  }
  if (!app.readNodesOf(notebookId).any(
        (node) => node.id == pageId && node.kind == NodeKind.page,
      )) {
    throw StateError('The target page no longer exists.');
  }
  if (app.notebookIsReadOnly(notebookId)) {
    throw StateError('The target notebook is read-only.');
  }

  // Finish any edit already in progress before deciding whether the captured
  // target is still the live page or now needs the off-screen import path.
  await app.flushSave();
  final onScreen = app.notebookId == notebookId && app.pageId == pageId;
  final data = onScreen
      ? PageData(app.blocks, app.pageProps)
      : app.readPageOf(notebookId, pageId);
  final hash = app.importBlob(notebookId, bytes, mime);
  final dimensions = await _imageDimensions(bytes);

  var y = AppState.contentTop;
  for (final block in data.blocks) {
    final bottom = block.y + (block.h ?? app.estimatedHeight(block));
    if (bottom > y) y = bottom;
  }
  final width =
      (data.props.pageWidth - AppState.pageLeftMargin * 2).clamp(280.0, 760.0);
  final height =
      dimensions == null ? null : width * dimensions.$2 / dimensions.$1;
  final scan = Block(
    type: BlockType.image,
    x: AppState.pageLeftMargin,
    y: y + 36,
    w: width,
    h: height,
    content: {
      'blob': 'sha256:$hash',
      'mime': mime,
      'source': 'phone-scan',
      if (dimensions != null) 'naturalW': dimensions.$1,
      if (dimensions != null) 'naturalH': dimensions.$2,
    },
  );

  if (onScreen) {
    app.addBlock(scan);
    await app.flushSave();
  } else {
    app.importPage(
      notebookId,
      pageId,
      [...data.blocks, scan],
      data.props,
    );
  }
  return scan;
}

Future<(double, double)?> _imageDimensions(Uint8List bytes) async {
  ui.Codec? codec;
  ui.FrameInfo? frame;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    frame = await codec.getNextFrame();
    return (frame.image.width.toDouble(), frame.image.height.toDouble());
  } catch (_) {
    // A valid MIME type with unusual metadata is still worth importing. Its
    // widget will determine a display height when it decodes normally.
    return null;
  } finally {
    frame?.image.dispose();
    codec?.dispose();
  }
}
