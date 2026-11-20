import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_strings.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../core/original_download.dart';
import '../store/media_store.dart';
import 'transfer_progress.dart';

/// Non-modal: the next lasso can start immediately on the canvas.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final selected =
        app.blocks.where((b) => app.selectedIds.contains(b.id)).toList();
    final downloadable =
        selected.where((b) => originalSourceKey(b) != null).firstOrNull;
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

  static Future<void>? _saveQueue;

  static Future<void> saveOriginal(
      BuildContext context, AppState app, Block block) async {
    final selected = app.blocks
        .where((b) =>
            app.selectedIds.contains(b.id) && originalSourceKey(b) != null)
        .toList();
    final targets = uniqueOriginals(
        app.selectedIds.contains(block.id) ? selected : [block]);
    final previous = _saveQueue;
    final work = () async {
      if (previous != null) await previous;
      if (!context.mounted) return;
      await _saveOriginals(context, app, targets);
    }();
    _saveQueue = work;
    try {
      await work;
    } finally {
      if (identical(_saveQueue, work)) _saveQueue = null;
    }
  }

  static Future<void> _saveOriginals(
      BuildContext context, AppState app, List<Block> targets) async {
    try {
      if (targets.isEmpty) return;
      String? singlePath;
      String? directory;
      if (targets.length == 1) {
        final block = targets.single;
        singlePath = (await getSaveLocation(
                suggestedName: block.content['name'] as String? ??
                    'OpenNote.${_extension(block)}'))
            ?.path;
        if (singlePath == null) return;
      } else {
        directory =
            await getDirectoryPath(confirmButtonText: 'Save originals here');
        if (directory == null) return;
      }
      if (!context.mounted) return;
      var saved = 0;
      var failed = 0;
      await runTransfer(context, 'Export originals', (progress) async {
        progress.update(total: targets.length);
        for (var i = 0; i < targets.length; i++) {
          final target = targets[i];
          progress.update(
              done: i,
              detail: target.content['name'] as String? ?? 'Original ${i + 1}');
          File? reserved;
          try {
            final destination = singlePath == null
                ? await reserveOriginalDownload(directory!, _extension(target))
                : File(singlePath);
            if (singlePath == null) reserved = destination;
            await _saveOriginalTo(app, target, destination,
                (fraction) => progress.update(done: i, current: fraction));
            saved++;
          } catch (_) {
            failed++;
            if (reserved != null && await reserved.exists()) {
              await reserved.delete();
            }
          }
          progress.update(done: i + 1, failed: failed);
        }
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(failed == 0 && singlePath != null
                ? 'Saved to $singlePath'
                : '$saved original(s) saved${failed > 0 ? ' · $failed failed' : ''}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save originals: $e')));
      }
    }
  }

  static String _extension(Block block) {
    final pdf = block.content['pdf'] as String?;
    final name = block.content['name'] as String?;
    return pdf != null
        ? 'pdf'
        : name != null && p.extension(name).isNotEmpty
            ? p.extension(name).substring(1)
            : switch (block.content['mime'] as String?) {
                'image/jpeg' => 'jpg',
                'image/gif' => 'gif',
                'image/webp' => 'webp',
                'image/bmp' => 'bmp',
                'application/pdf' => 'pdf',
                'application/octet-stream' => 'bin',
                _ => 'png',
              };
  }

  static Future<void> _saveOriginalTo(AppState app, Block block,
      File destination, ValueChanged<double> progress) async {
    final temporary = await destination.parent.createTemp('.openote-export-');
    final output = File(p.join(temporary.path, 'original'));
    try {
      final blob = block.content['pdf'] ?? block.content['blob'];
      if (blob is String) {
        final bytes = app.blob(blob);
        if (bytes == null) {
          throw StateError('The original file is unavailable.');
        }
        final handle = await output.open(mode: FileMode.write);
        try {
          const chunkSize = 1024 * 1024;
          for (var offset = 0; offset < bytes.length; offset += chunkSize) {
            final end = (offset + chunkSize).clamp(0, bytes.length);
            await handle.writeFrom(bytes, offset, end);
            progress(.99 * end / bytes.length);
          }
          await handle.flush();
        } finally {
          await handle.close();
        }
      } else {
        final media = block.content['media'] as String?;
        final source = media != null
            ? MediaStore.resolve(app.currentNotebook, media)
            : File(block.content['path'] as String);
        if (source == null ||
            p.equals(p.absolute(source.path), p.absolute(destination.path))) {
          throw StateError('Choose a different destination.');
        }
        final length = await source.length();
        final sink = output.openWrite();
        var copied = 0;
        try {
          await for (final chunk in source.openRead()) {
            sink.add(chunk);
            copied += chunk.length;
            if (length > 0) progress(.99 * copied / length);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      await output.rename(destination.path);
    } finally {
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        /* A later cleanup can remove a locked temporary folder. */
      }
    }
  }

  Widget _button(BuildContext context, String label, IconData icon,
          VoidCallback action) =>
      IconButton(
          tooltip: tr(context, label),
          onPressed: action,
          icon: Icon(icon, size: 20));
}
