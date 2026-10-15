import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_strings.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../core/original_download.dart';

/// Non-modal: the next lasso can start immediately on the canvas.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final selected =
        app.blocks.where((b) => app.selectedIds.contains(b.id)).toList();
    final downloadable = selected.where((b) => b.type == BlockType.image ||
        b.content['kind'] == 'drawio').firstOrNull;
    return Listener(
      onPointerDown: (e) => app.claimedPointers.add(e.pointer),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surface,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _button(context, 'Delete', Icons.delete_outline, app.removeSelected),
          _button(context, 'Duplicate', Icons.copy_all_outlined,
              app.duplicateSelectedBlocks),
          _button(context, 'Copy', Icons.copy_outlined, app.copySelectedBlocks),
          _button(context, 'Cut', Icons.cut_outlined, app.cutSelectedBlocks),
          _button(
              context,
              app.selectedAreLocked ? 'Unlock' : 'Lock in place',
              app.selectedAreLocked
                  ? Icons.lock_open_outlined
                  : Icons.lock_outline,
              app.toggleSelectedLock),
          if (downloadable != null)
            _button(context, 'Save original', Icons.download_outlined,
                () => saveOriginal(context, app, downloadable)),
          _button(context, 'Deselect', Icons.close, () => app.select(null)),
        ]),
      ),
    );
  }

  static Future<void> _saveQueue = Future<void>.value();

  static Future<void> saveOriginal(
      BuildContext context, AppState app, Block block) async {
    final selected = app.blocks.where((b) => app.selectedIds.contains(b.id) &&
        (b.type == BlockType.image || b.content['kind'] == 'drawio')).toList();
    final targets = app.selectedIds.contains(block.id) ? selected : [block];
    _saveQueue = _saveQueue.then((_) => _saveOriginals(context, app, targets));
    await _saveQueue;
  }

  static Future<void> _saveOriginals(
      BuildContext context, AppState app, List<Block> targets) async {
    try {
      final downloads = await getDownloadsDirectory();
      final directory = downloads?.path ?? await getDirectoryPath(
          confirmButtonText: 'Save originals here');
      if (directory == null) return;
      await Directory(directory).create(recursive: true);
      var saved = 0;
      for (final target in targets) {
        try {
          await _saveOriginalTo(app, target, directory);
          saved++;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not save original: $e')));
          }
        }
      }
      if (context.mounted && saved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$saved original(s) saved to $directory')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save originals: $e')));
      }
    }
  }

  static Future<void> _saveOriginalTo(
      AppState app, Block block, String directory) async {
    if (block.content['kind'] == 'drawio') {
      final source = File(block.content['path'] as String? ?? '');
      if (!await source.exists()) throw StateError('The original file is unavailable.');
      final destination = await reserveOriginalDownload(directory, 'drawio');
      await source.copy(destination.path);
      return;
    }
    final pdf = block.content['pdf'] as String?;
    final blob = pdf ?? block.content['blob'] as String?;
    if (blob == null) throw StateError('The original file is unavailable.');
    final extension = pdf != null
        ? 'pdf'
        : switch (block.content['mime'] as String?) {
            'image/jpeg' => 'jpg',
            'image/gif' => 'gif',
            'image/webp' => 'webp',
            _ => 'png',
          };
    final bytes = app.blob(blob);
    if (bytes == null) {
      throw StateError('The original file is unavailable.');
    }
    final destination = await reserveOriginalDownload(directory, extension);
    await destination.writeAsBytes(bytes, flush: true);
  }

  Widget _button(BuildContext context, String label, IconData icon,
          VoidCallback action) =>
      IconButton(
          tooltip: tr(context, label),
          onPressed: action,
          icon: Icon(icon, size: 20));
}
