import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import 'onote_dialog.dart';

Future<({String notebookId, String? sectionId})?> showMoveNodeDialog(
    BuildContext context, AppState app, TreeNode node) {
  final isPage = node.kind == NodeKind.page;
  final notebooks =
      app.notebooks.where((n) => isPage || n.id != app.notebookId).toList();
  String? notebookId = notebooks.any((n) => n.id == app.notebookId)
      ? app.notebookId
      : notebooks.firstOrNull?.id;
  List<TreeNode> sections() => notebookId == null
      ? []
      : app
          .sectionsInNotebook(notebookId!)
          .where((s) => notebookId != app.notebookId || s.id != node.parentId)
          .toList();
  String? sectionId = isPage ? sections().firstOrNull?.id : null;
  return showOnoteDialog<({String notebookId, String? sectionId})>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final destinations = isPage ? sections() : <TreeNode>[];
      return AlertDialog(
        title: const AppText('Move to…'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(node.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 20),
                if (notebooks.isEmpty)
                  const AppText('Create another notebook to move this section.')
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: notebookId,
                    isExpanded: true,
                    menuMaxHeight: 300,
                    decoration:
                        InputDecoration(labelText: tr(context, 'Notebook')),
                    items: [
                      for (final notebook in notebooks)
                        DropdownMenuItem(
                            value: notebook.id,
                            child: Text(notebook.title,
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: (value) => setState(() {
                      notebookId = value;
                      sectionId = isPage ? sections().firstOrNull?.id : null;
                    }),
                  ),
                  if (isPage) ...[
                    const SizedBox(height: 16),
                    if (destinations.isEmpty)
                      const AppText('No other sections in this notebook.')
                    else
                      DropdownButtonFormField<String>(
                        key: ValueKey(notebookId),
                        initialValue: sectionId,
                        isExpanded: true,
                        menuMaxHeight: 300,
                        decoration:
                            InputDecoration(labelText: tr(context, 'Section')),
                        items: [
                          for (final section in destinations)
                            DropdownMenuItem(
                                value: section.id,
                                child: Text(section.title,
                                    overflow: TextOverflow.ellipsis))
                        ],
                        onChanged: (value) => setState(() => sectionId = value),
                      ),
                  ],
                ],
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const AppText('Cancel')),
          FilledButton(
            onPressed: notebookId == null || (isPage && sectionId == null)
                ? null
                : () => Navigator.pop(
                    context, (notebookId: notebookId!, sectionId: sectionId)),
            child: const AppText('Move'),
          ),
        ],
      );
    }),
  );
}
