import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../l10n/app_strings.dart';
import '../spell/writing_services.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../update/app_update.dart';
import 'onote_dialog.dart';
import 'update_dialog.dart';

/// App-wide preferences, grouped by what the user wants to change.
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
  String _category = 'Appearance';
  final _contentScroll = ScrollController();

  @override
  void dispose() {
    _contentScroll.dispose();
    super.dispose();
  }

  void _chooseCategory(String category) {
    if (_category == category) return;
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
    setState(() => _category = category);
  }

  static const _categories = <String, IconData>{
    'Appearance': Icons.palette_outlined,
    'Writing and drawing': Icons.edit_outlined,
    'Navigation': Icons.open_with,
    'Storage': Icons.folder_outlined,
    'About': Icons.info_outline,
  };

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
      _updateNote =
          app.updateAvailable == null ? 'You have the latest version.' : null;
    });
    if (app.updateAvailable != null && mounted) {
      await showUpdateDialog(context, app);
    }
  }

  static const _descriptions = <String, String>{
    'Appearance': 'Choose the language and look of your workspace.',
    'Writing and drawing': 'Set up your pen, touch and writing assistance.',
    'Navigation': 'Choose where sections appear and how the page moves.',
    'Storage': 'Choose how long deleted notes can be restored.',
    'About': 'Keep Openote up to date or get help.',
  };

  Widget _group(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: OnoteSpace.x8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: OnoteSpace.x4),
            child: AppText(title, style: OnoteType.uiStrong),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: OnoteRadius.lgAll,
              side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: OnoteAlpha.borderOnTint)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    children[i],
                  ],
                ]),
          ),
        ]),
      );

  Widget _label(String title, String? subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(title, style: OnoteType.uiStrong),
          if (subtitle != null) ...[
            const SizedBox(height: OnoteSpace.x2),
            AppText(subtitle,
                style: OnoteType.small.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      );

  Widget _row(String title, Widget control, {String? subtitle}) => Padding(
        padding: const EdgeInsets.all(OnoteSpace.x6),
        child: LayoutBuilder(builder: (context, constraints) {
          final label = _label(title, subtitle);
          final field = Semantics(label: tr(context, title), child: control);
          if (constraints.maxWidth < 440) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label,
                  const SizedBox(height: OnoteSpace.x5),
                  field
                ]);
          }
          return Row(children: [
            Expanded(child: label),
            const SizedBox(width: OnoteSpace.x8),
            SizedBox(width: 180, child: field),
          ]);
        }),
      );

  Widget _switch(String title, bool value, ValueChanged<bool>? onChanged,
          {String? subtitle}) =>
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: OnoteSpace.x6, vertical: OnoteSpace.x4),
        title: AppText(title, style: OnoteType.uiStrong),
        subtitle: subtitle == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: OnoteSpace.x2),
                child: AppText(subtitle, style: OnoteType.small),
              ),
        value: value,
        onChanged: onChanged,
      );

  Widget _select<T>(T value, List<(T, String)> values, ValueChanged<T> change,
          {Key? key}) =>
      DropdownButtonHideUnderline(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: OnoteRadius.mdAll,
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: OnoteAlpha.borderOnTint)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x5),
            child: DropdownButton<T>(
              key: key,
              value: value,
              isExpanded: true,
              borderRadius: OnoteRadius.lgAll,
              style: OnoteType.ui
                  .copyWith(color: Theme.of(context).colorScheme.onSurface),
              items: [
                for (final (value, label) in values)
                  DropdownMenuItem(value: value, child: AppText(label))
              ],
              onChanged: (value) {
                if (value != null) change(value);
              },
            ),
          ),
        ),
      );

  Widget _themePicker() => Padding(
        padding: const EdgeInsets.all(OnoteSpace.x6),
        child: Row(children: [
          for (final (mode, label, icon) in [
            (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
            (ThemeMode.light, 'Light', Icons.light_mode_outlined),
            (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
          ]) ...[
            if (mode != ThemeMode.system) const SizedBox(width: OnoteSpace.x4),
            Expanded(
                child: Semantics(
              selected: app.themeMode == mode,
              button: true,
              child: Material(
                color: app.themeMode == mode
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: OnoteAlpha.selected)
                    : Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: OnoteRadius.mdAll,
                  side: BorderSide(
                      width: 2,
                      color: app.themeMode == mode
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: OnoteAlpha.borderOnTint)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('settings-theme-${mode.name}'),
                  onTap: () => app.setThemeMode(mode),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: OnoteSpace.x4, vertical: OnoteSpace.x6),
                    child: Column(children: [
                      Icon(icon,
                          size: 24,
                          color: app.themeMode == mode
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(height: OnoteSpace.x4),
                      AppText(label,
                          style: OnoteType.uiStrong.copyWith(
                              color: app.themeMode == mode
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface),
                          textAlign: TextAlign.center),
                    ]),
                  ),
                ),
              ),
            )),
          ],
        ]),
      );

  List<Widget> _content() => switch (_category) {
        'Appearance' => [
            _group('Language', [
              _row(
                  'Interface language',
                  _select(
                      app.interfaceLanguage,
                      [('en', 'English'), ('de', 'Deutsch')],
                      app.setInterfaceLanguage)),
            ]),
            _group('Theme', [
              _themePicker(),
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: AppText(
                      'System follows the light or dark appearance in Windows.',
                      style: OnoteType.small.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant))),
            ]),
          ],
        'Writing and drawing' => [
            _group('Pen and touch', [
              _row(
                  'Draw with finger',
                  _select(
                      app.touchDrawing,
                      [
                        (TouchDrawing.auto, 'Automatic'),
                        (TouchDrawing.always, 'Always'),
                        (TouchDrawing.never, 'Never')
                      ],
                      app.setTouchDrawing),
                  subtitle: switch (app.touchDrawing) {
                    TouchDrawing.auto =>
                      'Use a finger to draw when no pen is in use.',
                    TouchDrawing.always =>
                      'Draw with one finger, even when a pen is nearby.',
                    TouchDrawing.never =>
                      'Use a finger to move the page; draw only with your pen.',
                  }),
            ]),
            _group('Writing assistance', [
              _row(
                  'Writing language',
                  _select(
                      app.writingLanguage,
                      [('en-US', 'English'), ('de-DE', 'Deutsch')],
                      app.setWritingLanguage)),
              _switch('Spell check', app.spellCheckEnabled, app.setSpellCheck,
                  subtitle:
                      'Underline possible spelling mistakes. Your text stays unchanged.'),
              _switch('Check handwriting', app.handwritingSpellCheck,
                  app.spellCheckEnabled ? app.setHandwritingSpellCheck : null,
                  subtitle: app.spellCheckEnabled
                      ? 'Suggest spelling checks for handwriting. Recognition can make mistakes.'
                      : 'Turn on spell check to check handwriting too.'),
            ]),
            _group('Windows language support', [
              Padding(
                padding: const EdgeInsets.all(OnoteSpace.x6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                          'Local Windows language packs are required. No notes are uploaded.',
                          style: OnoteType.small),
                      const SizedBox(height: OnoteSpace.x4),
                      TextButton.icon(
                          style: TextButton.styleFrom(
                              minimumSize: const Size(0, 44)),
                          onPressed: _checkingLanguage ? null : _checkLanguage,
                          icon: const Icon(Icons.spellcheck, size: 20),
                          label: const AppText('Check language support')),
                      if (app.writingServiceProblem != null)
                        AppText(app.writingServiceProblem!,
                            style: OnoteType.small),
                    ]),
              ),
            ]),
          ],
        'Navigation' => [
            _group('Sections', [
              _row(
                  'Section position',
                  _select(
                      app.sectionTabsAbovePage,
                      [(true, 'Above the page'), (false, 'Beside the page')],
                      app.setSectionTabsAbovePage),
                  subtitle:
                      'Keep sections above the page or beside the page list.'),
            ]),
            _group('Page movement', [
              Padding(
                padding: const EdgeInsets.all(OnoteSpace.x6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('Pan sensitivity',
                          'Controls page movement with touch, touchpad and mouse wheel. Zoom speed stays the same.'),
                      const SizedBox(height: OnoteSpace.x5),
                      Slider(
                          value: app.panSensitivity,
                          min: 0.5,
                          max: 3.5,
                          divisions: 12,
                          label: '${app.panSensitivity.toStringAsFixed(1)}×',
                          semanticFormatterCallback: (value) =>
                              '${value.toStringAsFixed(1)}×',
                          onChanged: app.setPanSensitivity),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const AppText('Slower', style: OnoteType.small),
                            Text('${app.panSensitivity.toStringAsFixed(1)}×',
                                style: OnoteType.uiStrong),
                            const AppText('Faster', style: OnoteType.small),
                          ]),
                    ]),
              ),
            ]),
            _hint(
                'Hold a section or page for a moment to open its menu. Drag to change the order.'),
          ],
        'Storage' => [
            _group('Recycle bin', [
              _row(
                  'Keep deleted notes for',
                  _select(
                      app.recycleRetentionDays,
                      [
                        (7, '7 days'),
                        (14, '14 days'),
                        (30, '30 days'),
                        (60, '60 days'),
                        (90, '90 days'),
                        (365, '1 year')
                      ],
                      app.setRecycleRetentionDays),
                  subtitle:
                      'Deleted notebooks, sections and pages can be restored until this time expires.'),
            ]),
          ],
        _ => [
            _group('Updates', [
              Padding(
                padding: const EdgeInsets.all(OnoteSpace.x6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Openote $kAppVersion',
                          style: OnoteType.title),
                      const SizedBox(height: OnoteSpace.x5),
                      OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44)),
                          onPressed: _checking ? null : _checkNow,
                          icon: const Icon(Icons.refresh, size: 20),
                          label: AppText(_checking
                              ? 'Checking for updates…'
                              : 'Check for updates')),
                      if (_updateNote != null)
                        Padding(
                            padding: const EdgeInsets.only(top: OnoteSpace.x4),
                            child:
                                AppText(_updateNote!, style: OnoteType.small)),
                    ]),
              ),
            ]),
            _group('Help and feedback', [
              ListTile(
                  leading: const Icon(Icons.new_releases_outlined),
                  title: const AppText("What's new", style: OnoteType.ui),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () => PlatformOpen.url(
                      'https://github.com/$kUpdateRepository/releases')),
              ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const AppText('Report a bug', style: OnoteType.ui),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () => PlatformOpen.url(
                      'https://github.com/$kUpdateRepository/issues/new')),
            ]),
          ],
      };

  Widget _hint(String text) => AppText(text,
      style: OnoteType.small
          .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));

  Widget _navigation() => ListView(
        padding: const EdgeInsets.all(OnoteSpace.x5),
        children: [
          for (final entry in _categories.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: OnoteSpace.x2),
              child: Semantics(
                selected: _category == entry.key,
                button: true,
                child: Material(
                  color: _category == entry.key
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: OnoteAlpha.selected)
                      : Colors.transparent,
                  borderRadius: OnoteRadius.mdAll,
                  child: InkWell(
                    key: ValueKey('settings-category-${entry.key}'),
                    borderRadius: OnoteRadius.mdAll,
                    onTap: () => _chooseCategory(entry.key),
                    child: Padding(
                      padding: const EdgeInsets.all(OnoteSpace.x5),
                      child: Row(children: [
                        Icon(entry.value,
                            size: 20,
                            color: _category == entry.key
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                        const SizedBox(width: OnoteSpace.x5),
                        Expanded(
                            child: AppText(entry.key,
                                style: _category == entry.key
                                    ? OnoteType.uiStrong.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary)
                                    : OnoteType.ui)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Dialog(
          insetPadding: const EdgeInsets.all(OnoteSpace.x8),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 880,
            height: 640,
            child: LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
                  child: Row(children: [
                    const Expanded(
                        child: AppText('Settings', style: OnoteType.headline)),
                    IconButton(
                        tooltip: tr(context, 'Close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 20)),
                  ]),
                ),
                const Divider(height: 1),
                if (compact)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Semantics(
                      label: tr(context, 'Settings category'),
                      child: _select(
                          _category,
                          [
                            for (final category in _categories.keys)
                              (category, category)
                          ],
                          _chooseCategory,
                          key: const ValueKey('settings-category-picker')),
                    ),
                  ),
                if (compact) const Divider(height: 1),
                Expanded(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      if (!compact) ...[
                        SizedBox(width: 208, child: _navigation()),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                          child: Scrollbar(
                              controller: _contentScroll,
                              thumbVisibility: true,
                              child: ListView(
                                controller: _contentScroll,
                                key: ValueKey('settings-content-$_category'),
                                padding: const EdgeInsets.all(OnoteSpace.x8),
                                children: [
                                  AppText(_category, style: OnoteType.headline),
                                  const SizedBox(height: OnoteSpace.x4),
                                  _hint(_descriptions[_category]!),
                                  const SizedBox(height: OnoteSpace.x8),
                                  ..._content(),
                                ],
                              ))),
                    ])),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: OnoteSpace.x8, vertical: OnoteSpace.x5),
                  child: Row(children: [
                    Icon(Icons.save_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: OnoteSpace.x4),
                    Expanded(
                        child: _hint(
                            'Changes are saved automatically on this device.')),
                  ]),
                ),
              ]);
            }),
          ),
        ),
      );
}
