import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/learning_access.dart';
import '../l10n/app_strings.dart';
import '../state/app_state.dart';
import 'onote_dialog.dart';

Future<void> showLearningAccessDialog(BuildContext context, AppState app) =>
    showOnoteDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
              title: const AppText('AI learning access'),
              content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                      child: LearningAccessPanel(app: app))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const AppText('Close'))
              ],
            ));

class LearningAccessButton extends StatelessWidget {
  const LearningAccessButton({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app.learning,
        builder: (context, _) {
          final scope = app.learning.scope;
          final label = switch (scope) {
            LearningScope.off => 'AI: off',
            LearningScope.page => 'AI: current page',
            LearningScope.notebook => 'AI: shared notebook',
          };
          return IconButton(
            tooltip: tr(context, label),
            visualDensity: VisualDensity.compact,
            isSelected: scope != LearningScope.off,
            icon: Icon(
                scope == LearningScope.off
                    ? Icons.shield_outlined
                    : Icons.visibility_outlined,
                size: 18),
            onPressed: () => showLearningAccessDialog(context, app),
          );
        },
      );
}

class LearningAccessPanel extends StatelessWidget {
  const LearningAccessPanel({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final access = app.learning;
    Future<void> copy(String text) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(tr(context, 'Copied'))));
      }
    }

    Future<void> openCodexConfig() async {
      try {
        final environment = Platform.environment;
        final home = environment['CODEX_HOME'];
        final directory = Directory(home != null && home.trim().isNotEmpty
            ? home
            : '${environment['USERPROFILE']}\\.codex');
        if (!await directory.exists()) {
          throw const FileSystemException('Codex directory not found');
        }
        await Process.start(
          'notepad.exe',
          ['${directory.path}\\config.toml'],
          mode: ProcessStartMode.detached,
        );
      } on FileSystemException {
        if (context.mounted) showCodexConfigError(context);
      } on ProcessException {
        if (context.mounted) showCodexConfigError(context);
      }
    }

    return ListenableBuilder(
      listenable: Listenable.merge([app, access]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppText('Let a connected AI read your learning materials. '
              'It cannot edit, delete or open other notebooks.'),
          const SizedBox(height: 10),
          DropdownButtonFormField<LearningScope>(
            key: ValueKey(access.scope),
            initialValue: access.scope,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(context, 'AI access')),
            items: const [
              DropdownMenuItem(value: LearningScope.off, child: AppText('Off')),
              DropdownMenuItem(
                  value: LearningScope.page,
                  child: AppText('Current page (follows navigation)')),
              DropdownMenuItem(
                  value: LearningScope.notebook,
                  child: AppText('This notebook')),
            ],
            onChanged: access.busy
                ? null
                : (scope) {
                    if (scope != null) access.setScope(scope);
                  },
          ),
          if (access.busy) const LinearProgressIndicator(),
          if (access.scope == LearningScope.off && !access.busy)
            const AppText('Choose Current page or This notebook to start '
                'the local MCP server.'),
          if (access.error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr(context, access.error!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (access.scope == LearningScope.notebook) ...[
            const SizedBox(height: 8),
            Text(
                '${tr(context, 'Shared notebook')}: ${access.sharedNotebookTitle}'),
            if (app.notebookId != access.sharedNotebookId)
              const AppText('The open notebook is not shared. Access is paused '
                  'until you return to the shared notebook.'),
            TextButton(
                onPressed: access.busy
                    ? null
                    : () => access.setScope(LearningScope.notebook),
                child: const AppText('Share the open notebook instead')),
          ],
          const SizedBox(height: 8),
          const AppText('Reads happen only when the AI requests them. '
              'Long pages and books are read in small parts. '
              'Handwriting and scans are provided as page images.'),
          const SizedBox(height: 8),
          const AppText(
              'Openote must stay open. Access is off after restarting. '
              'Locked pages are excluded. Content already sent stays in the '
              'chat; a cloud AI processes it with its provider.'),
          if (access.scope != LearningScope.off && access.url != null) ...[
            const Divider(height: 24),
            const AppText('Connect your AI client'),
            const SizedBox(height: 6),
            SelectableText(access.url!),
            const SizedBox(height: 6),
            const AppText('Add an MCP server in your desktop AI client: '
                'choose Streamable HTTP, use this URL and set the '
                'Authorization header to Bearer followed by the copied token. '
                'A web-only client cannot reach this local address.'),
            Wrap(spacing: 6, children: [
              TextButton(
                  onPressed: () => copy(access.url!),
                  child: const AppText('Copy URL')),
              TextButton(
                  onPressed: () => copy(access.authorizationHeader),
                  child: const AppText('Copy Authorization value')),
            ]),
            const AppText('For Codex, paste the copied configuration into '
                '~/.codex/config.toml (or the config.toml in CODEX_HOME). '
                'Replace any existing Openote entry, save the file, and '
                'restart Codex while sharing is on.'),
            Wrap(spacing: 6, children: [
              if (Platform.isWindows)
                TextButton(
                    onPressed: openCodexConfig,
                    child: const AppText('Open Codex configuration')),
              TextButton(
                  onPressed: () => copy(access.clientConfig),
                  child: const AppText('Copy Codex configuration')),
            ]),
          ],
          if (access.lastRead != null) ...[
            const SizedBox(height: 6),
            Text('${tr(context, 'Last read')}: ${access.lastRead}'),
          ],
        ],
      ),
    );
  }
}

void showCodexConfigError(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
    content: AppText(
        'Could not open the Codex configuration. Open config.toml manually.'),
  ));
}
