import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_strings.dart';
import '../model/models.dart';
import '../state/app_state.dart';

/// Non-modal: the next lasso can start immediately on the canvas.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final selected =
        app.blocks.where((b) => app.selectedIds.contains(b.id)).toList();
    final downloadable =
        selected.length == 1 && selected.single.type == BlockType.image
            ? selected.single
            : null;
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
                () => _saveOriginal(context, downloadable)),
          _button(context, 'Deselect', Icons.close, () => app.select(null)),
        ]),
      ),
    );
  }

  Future<void> _saveOriginal(BuildContext context, Block block) async {
    final pdf = block.content['pdf'] as String?;
    final blob = pdf ?? block.content['blob'] as String?;
    if (blob == null) return;
    final extension = pdf != null
        ? 'pdf'
        : switch (block.content['mime'] as String?) {
            'image/jpeg' => 'jpg',
            'image/gif' => 'gif',
            'image/webp' => 'webp',
            _ => 'png',
          };
    final location = await getSaveLocation(
      suggestedName: 'Openote file.$extension',
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension])
      ],
    );
    if (location == null) return;
    final bytes = app.blob(blob);
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The original file is unavailable.')));
      }
      return;
    }
    var destination = location.path;
    if (p.extension(destination).isEmpty) destination += '.$extension';
    await File(destination).writeAsBytes(bytes, flush: true);
  }

  Widget _button(BuildContext context, String label, IconData icon,
          VoidCallback action) =>
      IconButton(
          tooltip: tr(context, label),
          onPressed: action,
          icon: Icon(icon, size: 20));
}
