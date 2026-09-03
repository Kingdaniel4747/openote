import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../l10n/app_strings.dart';

/// Non-modal: the next lasso can start immediately on the canvas.
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (e) => app.claimedPointers.add(e.pointer),
        child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).colorScheme.surface,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _button(
                  context, 'Delete', Icons.delete_outline, app.removeSelected),
              _button(context, 'Duplicate', Icons.copy_all_outlined,
                  app.duplicateSelectedBlocks),
              _button(
                  context, 'Copy', Icons.copy_outlined, app.copySelectedBlocks),
              _button(
                  context, 'Cut', Icons.cut_outlined, app.cutSelectedBlocks),
              _button(context, 'Deselect', Icons.close, () => app.select(null)),
            ])),
      );
  Widget _button(BuildContext context, String label, IconData icon,
          VoidCallback action) =>
      IconButton(
          tooltip: tr(context, label),
          onPressed: action,
          icon: Icon(icon, size: 20));
}
