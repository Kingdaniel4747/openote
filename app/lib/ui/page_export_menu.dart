import 'package:flutter/material.dart';

import '../export/markdown_export.dart';
import '../export/open_export.dart';
import '../export/pdf_export.dart';
import '../export/pdf_vector_export.dart';
import '../l10n/app_strings.dart';
import '../state/app_state.dart';
import 'transfer_progress.dart';

enum PageExportFormat { markdown, pdf, picturePdf, canvas, inkml, notebook }

const _formats = [
  (PageExportFormat.markdown, Icons.description_outlined, 'Markdown (.md)'),
  (PageExportFormat.pdf, Icons.picture_as_pdf_outlined, 'PDF (.pdf)'),
  (
    PageExportFormat.picturePdf,
    Icons.image_outlined,
    'PDF — picture of the page'
  ),
  (
    PageExportFormat.canvas,
    Icons.hub_outlined,
    'For Obsidian Canvas (.canvas)'
  ),
  (PageExportFormat.inkml, Icons.gesture, 'Just the drawing (.inkml)'),
  (
    PageExportFormat.notebook,
    Icons.folder_zip_outlined,
    'Save the whole notebook as folders and files…'
  ),
];

List<Widget> pageExportMenuItems(ValueChanged<PageExportFormat> select) => [
      for (final (format, icon, label) in _formats) ...[
        if (format == PageExportFormat.notebook) const Divider(height: 6),
        MenuItemButton(
          closeOnActivate: false,
          leadingIcon: Icon(icon, size: 18),
          onPressed: () => select(format),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AppText(label, softWrap: true),
          ),
        ),
      ],
    ];

/// Export the page whose context menu was opened, including when a different
/// page was active. Raster capture needs that page's canvas to be visible.
Future<void> exportPageFromMenu(BuildContext context, AppState app,
    String pageId, PageExportFormat format) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (app.node(pageId) == null) return;
    if (format == PageExportFormat.notebook) {
      await _exportNotebook(context, app);
      return;
    }
    if (app.pageId != pageId) await app.selectPage(pageId);
    if (!context.mounted || app.pageId != pageId) return;
    final path = await runTransfer(context, 'Export page', (progress) async {
      progress.update(detail: app.node(pageId)?.title ?? 'Page');
      final path = await switch (format) {
        PageExportFormat.markdown => exportPageMarkdown(app,
            onProgress: (done, total) =>
                progress.update(done: done, total: total)),
        PageExportFormat.pdf => exportPagePdfVector(app,
            onProgress: (done, total) =>
                progress.update(current: .99 * done / total)),
        PageExportFormat.picturePdf => exportPagePdf(app),
        PageExportFormat.canvas => exportPageJsonCanvas(app),
        PageExportFormat.inkml => exportPageInkML(app),
        PageExportFormat.notebook => Future<String?>.value(null),
      };
      if (path != null) progress.update(done: progress.total);
      return path;
    });
    if (path != null) {
      messenger?.showSnackBar(SnackBar(content: AppText('Exported to $path')));
    }
  } catch (error) {
    messenger?.showSnackBar(SnackBar(
      content: Text("That couldn't be saved: $error"),
      duration: const Duration(seconds: 6),
    ));
  }
}

Future<void> _exportNotebook(BuildContext context, AppState app) async {
  final path = await runTransfer(context, 'Export notebook', (progress) async {
    progress.update(unit: 'steps');
    return materializeNotebook(app,
        onProgress: (done, total) => progress.update(done: done, total: total));
  });
  if (path != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: AppText('Exported to $path')));
  }
}
