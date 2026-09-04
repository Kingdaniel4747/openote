import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../l10n/app_strings.dart';
import '../spell/writing_services.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../update/app_update.dart';
import 'mcp_dialog.dart';
import 'onote_dialog.dart';
import 'shortcut_overlay.dart';
import 'sync_dialog.dart';
import 'update_dialog.dart';
import 'windows_window_frame.dart';

/// The centralised settings page (PLANNING "Consistency/UX"): one place
/// holding every app-wide preference and door — previously each lived only
/// wherever its feature happened to put a control. The per-feature controls
/// stay where they are (a toggle you use while drawing belongs in Draw);
/// this page is where you LOOK for one you can't find.
Future<void> showSettingsDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(app: app),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.app});
  final AppState app;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  AppState get app => widget.app;

  bool _checking = false;
  bool _checkingLanguage = false;
  String? _updateNote;

  Future<void> _checkLanguage() async {
    setState(() => _checkingLanguage = true);
    String note;
    try {
      final result = await WritingServices.run({
        'kind': 'status',
        'language': app.writingLanguage,
      }) as Map;
      note = result['handwriting'] == true
          ? 'Language support is ready.'
          : 'Install the selected handwriting language in Windows Settings.';
    } catch (_) {
      note =
          'Local writing services are unavailable. Check Windows language packs.';
    }
    if (!mounted) return;
    setState(() {
      _checkingLanguage = false;
      app.writingServiceProblem = note;
    });
  }

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _updateNote = null;
    });
    await app.checkForAppUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateNote = app.updateAvailable == null
          ? "You're up to date ($kAppVersion is the newest version)."
          : null;
    });
    if (app.updateAvailable != null && mounted) {
      await showUpdateDialog(context, app);
    }
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: AppText(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _row(String label, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: AppText(label, style: const TextStyle(fontSize: 13))),
          control,
        ]),
      );

  /// An on/off preference, shown the same way as the Theme row above it — a
  /// highlighted segment, not a switch. One visual language for "this is
  /// currently set to X" throughout the dialog, not two.
  Widget _toggle(bool value, ValueChanged<bool> onChanged) =>
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
        segments: const [
          ButtonSegment(value: false, label: AppText('Off')),
          ButtonSegment(value: true, label: AppText('On')),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );

  Widget _door(IconData icon, String label, String hint, VoidCallback open) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppText(label, style: const TextStyle(fontSize: 13)),
              AppText(hint,
                  style: const TextStyle(
                      fontSize: 11, color: OnoteColors.graphite400)),
            ]),
          ),
          TextButton.icon(
            icon: Icon(icon, size: 15),
            label: const AppText('Open…', style: TextStyle(fontSize: 12)),
            onPressed: open,
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => AlertDialog(
        title: const AppText('Settings'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              _section('Appearance'),
              _row(
                  'Interface language',
                  DropdownButton<String>(
                    value: app.interfaceLanguage,
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                    ],
                    onChanged: (value) {
                      if (value != null) app.setInterfaceLanguage(value);
                    },
                  )),
              _row(
                'Theme',
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 11))),
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system, label: AppText('System')),
                    ButtonSegment(
                        value: ThemeMode.light, label: AppText('Light')),
                    ButtonSegment(
                        value: ThemeMode.dark, label: AppText('Dark')),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
              ),
              if (WindowsWindowFrame.of(context) case final window?) ...[
                _row('Start maximized',
                    _toggle(app.startMaximized, app.setStartMaximized)),
                TextButton.icon(
                  icon: const Icon(Icons.crop_square),
                  label: const AppText('Maximize / restore (F11)'),
                  onPressed: window.maximize,
                ),
                const AppText(
                    'Maximized mode keeps the Windows taskbar available.',
                    style: TextStyle(fontSize: 11)),
              ],
              _section('Writing and drawing'),
              _row('Spell check',
                  _toggle(app.spellCheckEnabled, app.setSpellCheck)),
              _row(
                  'Writing language',
                  DropdownButton<String>(
                    value: app.writingLanguage,
                    items: const [
                      DropdownMenuItem(value: 'en-US', child: Text('English')),
                      DropdownMenuItem(value: 'de-DE', child: Text('Deutsch')),
                    ],
                    onChanged: (value) {
                      if (value != null) app.setWritingLanguage(value);
                    },
                  )),
              _row(
                  'Check handwriting',
                  _toggle(
                      app.handwritingSpellCheck, app.setHandwritingSpellCheck)),
              const AppText(
                  'Local Windows language packs are required. No notes are uploaded.',
                  style: TextStyle(fontSize: 11)),
              const AppText(
                  'Recognition may misread handwriting; marks are suggestions, not corrections.',
                  style: TextStyle(fontSize: 11)),
              TextButton.icon(
                onPressed: _checkingLanguage ? null : _checkLanguage,
                icon: const Icon(Icons.spellcheck, size: 16),
                label: const AppText('Check language support'),
              ),
              if (app.writingServiceProblem != null)
                AppText(app.writingServiceProblem!,
                    style: const TextStyle(fontSize: 11)),
              _section('Connections'),
              _door(
                  Icons.sync,
                  'Sync',
                  'Back up and share this notebook — GitHub or a folder.',
                  () => showSyncDialog(context, app)),
              _door(
                  Icons.smart_toy_outlined,
                  'AI access',
                  app.mcpEnabled
                      ? 'On — AI helpers on this computer can use your notes.'
                      : 'Off — connect Claude or other AI helpers.',
                  () => showMcpDialog(context, app)),
              _section('Keyboard'),
              _door(
                  Icons.keyboard_outlined,
                  'Keyboard shortcuts',
                  'Everything has a key — the full list.  (Ctrl+/)',
                  () => showShortcutOverlay(context)),
              _section('About'),
              _row(
                'Openote $kAppVersion',
                _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: _checkNow,
                        child: const AppText('Check for updates',
                            style: TextStyle(fontSize: 12)),
                      ),
              ),
              if (_updateNote != null)
                AppText(_updateNote!,
                    style: const TextStyle(
                        fontSize: 11.5, color: OnoteColors.graphite400)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => PlatformOpen.url(
                      'https://github.com/$kUpdateRepository/releases'),
                  child: const AppText("What's new",
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const AppText('Close')),
        ],
      ),
    );
  }
}
