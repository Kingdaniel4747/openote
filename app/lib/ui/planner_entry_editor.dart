import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/tokens.dart';

const plannerEntryColors = <String, Color>{
  'purple': Color(0xFF7868DB),
  'blue': Color(0xFF4285D4),
  'green': Color(0xFF39956B),
  'orange': Color(0xFFC98226),
  'red': Color(0xFFCC5968),
};

/// Kept by the panel while another day or entry is being viewed.
class PlannerEntryDraft {
  PlannerEntryDraft(
      {this.title = '',
      this.notes = '',
      this.category = 'homework',
      this.color = 'purple',
      this.linkPage = false,
      this.notebookId,
      this.pageId});
  String title, notes, category, color;
  bool linkPage;
  String? notebookId, pageId;
}

class PlannerEntryEditor extends StatefulWidget {
  const PlannerEntryEditor(
      {super.key,
      required this.draft,
      required this.onSave,
      required this.onChanged,
      this.pageTitle,
      this.onOpenPage,
      this.editing = false,
      this.autofocus = false});
  final PlannerEntryDraft draft;
  final VoidCallback onSave;
  final VoidCallback onChanged;
  final String? pageTitle;
  final VoidCallback? onOpenPage;
  final bool editing;
  final bool autofocus;

  @override
  State<PlannerEntryEditor> createState() => _PlannerEntryEditorState();
}

class _PlannerEntryEditorState extends State<PlannerEntryEditor> {
  late final _title = TextEditingController(text: widget.draft.title);
  late final _notes = TextEditingController(text: widget.draft.notes);
  PlannerEntryDraft get draft => widget.draft;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: OnoteRadius.lgAll,
        child: Padding(
          padding: const EdgeInsets.all(OnoteSpace.x5),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppText(widget.editing ? 'Edit entry' : 'New homework',
                style: OnoteType.uiStrong),
            const SizedBox(height: OnoteSpace.x5),
            TextField(
                key: const ValueKey('planner-entry-title'),
                controller: _title,
                minLines: 1,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                autofocus: widget.autofocus,
                style: OnoteType.ui,
                decoration: InputDecoration(
                    labelText: tr(context, 'Task'),
                    hintText: tr(
                        context, 'For example: Maths, page 42, exercises 3–5')),
                textInputAction: TextInputAction.done,
                onChanged: (text) {
                  setState(() => draft.title = text);
                  widget.onChanged();
                },
                onSubmitted: (_) {
                  if (draft.title.trim().isNotEmpty) widget.onSave();
                }),
            const SizedBox(height: OnoteSpace.x5),
            TextField(
                key: const ValueKey('planner-entry-notes'),
                controller: _notes,
                minLines: 3,
                maxLines: null,
                style: OnoteType.ui,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                    labelText: tr(context, 'Notes (optional)'),
                    alignLabelWithHint: true),
                onChanged: (text) => draft.notes = text),
            const SizedBox(height: OnoteSpace.x5),
            DropdownButtonFormField<String>(
                initialValue: draft.category,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: tr(context, 'Entry type')),
                items: [
                  for (final (value, label) in [
                    ('homework', 'Homework'),
                    ('todo', 'To-do'),
                    ('exam', 'Exam')
                  ])
                    DropdownMenuItem(
                        value: value,
                        child: AppText(label, style: OnoteType.ui))
                ],
                onChanged: (value) {
                  if (value != null) setState(() => draft.category = value);
                }),
            const SizedBox(height: OnoteSpace.x5),
            const AppText('Color', style: OnoteType.small),
            Wrap(spacing: OnoteSpace.x2, children: [
              for (final color in plannerEntryColors.entries)
                Semantics(
                  button: true,
                  selected: draft.color == color.key,
                  label: tr(context, color.key),
                  child: InkWell(
                      key: ValueKey('planner-color-${color.key}'),
                      borderRadius: OnoteRadius.mdAll,
                      onTap: () => setState(() => draft.color = color.key),
                      child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                              child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color.value,
                                border: Border.all(
                                    width: draft.color == color.key ? 3 : 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface)),
                          )))),
                ),
            ]),
            if (draft.pageId != null) ...[
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const AppText('Link page', style: OnoteType.ui),
                  subtitle: Text(widget.pageTitle ?? tr(context, 'Linked page'),
                      style: OnoteType.small,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  value: draft.linkPage,
                  onChanged: (value) =>
                      setState(() => draft.linkPage = value ?? false)),
              if (draft.linkPage && widget.onOpenPage != null)
                TextButton.icon(
                    onPressed: widget.onOpenPage,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const AppText('Open linked page')),
            ],
          ]),
        ),
      );
}
