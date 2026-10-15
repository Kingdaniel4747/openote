import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../canvas/media_drop.dart';
import '../core/platform_open.dart';
import '../state/app_state.dart';
import 'onote_dialog.dart';

Future<void> showDataPool(BuildContext context, AppState app) =>
    showOnoteDialog<void>(context: context,
        builder: (_) => _DataPoolDialog(app: app));

class _DataPoolDialog extends StatefulWidget {
  const _DataPoolDialog({required this.app});
  final AppState app;
  @override
  State<_DataPoolDialog> createState() => _DataPoolDialogState();
}

class _DataPoolDialogState extends State<_DataPoolDialog> {
  late Directory current = widget.app.poolDirectory;
  List<FileSystemEntity> entries = [];
  String? error;
  bool busy = false;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++revision;
    try {
      if (p.equals(current.path, widget.app.poolDirectory.path)) {
        await current.create(recursive: true);
      }
      final result = await current.list(followLinks: false).toList();
      result.removeWhere((e) => e is Link);
      result.sort((a, b) {
        if ((a is Directory) != (b is Directory)) return a is Directory ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      if (mounted && request == revision) setState(() { entries = result; error = null; });
    } catch (e) {
      if (mounted && request == revision) setState(() => error = '$e');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _newFolder() async {
    final name = await promptForText(context, title: 'Neuer Ordner', okLabel: 'Anlegen');
    if (name == null || name.isEmpty) return;
    if (name == '.' || name == '..' || p.basename(name) != name ||
        name.contains(RegExp(r'[<>:"/\\|?*]'))) {
      throw const FormatException('Bitte einen gültigen Ordnernamen eingeben.');
    }
    await Directory(p.join(current.path, name)).create();
  }

  Future<void> _import() async {
    final files = await openFiles();
    for (final file in files) {
      if (p.equals(p.dirname(file.path), current.path)) continue;
      var destination = p.join(current.path, file.name);
      var number = 1;
      while (await FileSystemEntity.type(destination) != FileSystemEntityType.notFound) {
        destination = p.join(current.path,
            '${p.basenameWithoutExtension(file.name)} ${number++}${p.extension(file.name)}');
      }
      await File(file.path).copy(destination);
    }
  }

  Future<void> _insert(File file, {required bool linked}) async {
    if (widget.app.pageId == null) return;
    if (linked) {
      widget.app.linkPoolFile(file.path);
    } else {
      final canvas = widget.app.canvas;
      final count = await dropFilesOntoCanvas(widget.app, [file.path],
          canvas.screenToPage(Offset(canvas.viewport.width / 2, canvas.viewport.height / 2)));
      if (count == 0) throw StateError('Die Datei konnte nicht eingefügt werden.');
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.app.poolDirectory.path;
    final atRoot = p.equals(root, current.path);
    return AlertDialog(
      title: const Text('Datenpool'),
      content: SizedBox(width: 720, height: 440, child: Column(children: [
        Wrap(spacing: 6, children: [
          IconButton(tooltip: 'Übergeordneter Ordner', icon: const Icon(Icons.arrow_upward),
              onPressed: atRoot || busy ? null : () { current = current.parent; _load(); }),
          TextButton.icon(icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Explorer'),
              onPressed: () async {
                if (!await PlatformOpen.directory(current.path) && mounted) {
                  setState(() => error = 'Der Ordner konnte nicht geöffnet werden.');
                }
              }),
          TextButton.icon(icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Neuer Ordner'),
              onPressed: busy ? null : () => _run(_newFolder)),
          TextButton.icon(icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Dateien hinzufügen'),
              onPressed: busy ? null : () => _run(_import)),
          IconButton(tooltip: 'Aktualisieren', icon: const Icon(Icons.refresh),
              onPressed: busy ? null : _load),
        ]),
        Align(alignment: Alignment.centerLeft, child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(atRoot ? 'Pool' : 'Pool / ${p.relative(current.path, from: root)}',
                overflow: TextOverflow.ellipsis))),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Expanded(child: entries.isEmpty
            ? const Center(child: Text('Hier kannst du Ordner und Dateien für deine Fächer ablegen.'))
            : ListView.builder(itemCount: entries.length, itemBuilder: (context, index) {
                final entry = entries[index];
                final directory = entry is Directory;
                return ListTile(
                  leading: Icon(directory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                  title: Text(p.basename(entry.path)),
                  onTap: busy ? null : () async {
                    if (entry is Directory) { current = entry; await _load(); }
                    else if (!await PlatformOpen.file(entry.path) && mounted) {
                      setState(() => error = 'Die Datei konnte nicht geöffnet werden.');
                    }
                  },
                  trailing: directory ? null : PopupMenuButton<bool>(
                    tooltip: 'Auf der aktuellen Seite einfügen',
                    enabled: !busy && widget.app.pageId != null,
                    onSelected: (linked) => _run(() => _insert(File(entry.path), linked: linked)),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('Auf Seite verlinken')),
                      PopupMenuItem(value: false, child: Text('Als Kopie einfügen')),
                    ],
                  ),
                );
              })),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}
