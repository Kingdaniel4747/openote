import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/learning_access.dart';
import '../l10n/app_strings.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'onote_switch.dart';

Future<void> showLearningAccessDialog(BuildContext context, AppState app) {
  final box = context.findRenderObject();
  final anchor = box is RenderBox
      ? box.localToGlobal(Offset(0, box.size.height))
      : const Offset(0, 40);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: child,
    ),
    pageBuilder: (context, _, __) => SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        final top = (anchor.dy + 8).clamp(
            8.0, (constraints.maxHeight - 160).clamp(8.0, double.infinity));
        return Padding(
          padding: EdgeInsets.fromLTRB(12, top, 12, 12),
          child: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 360,
              child: Material(
                key: const ValueKey('learning-access-popover'),
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                elevation: 12,
                shadowColor: Colors.black26,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(6),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        const Expanded(
                            child: AppText('AI learning access',
                                style: OnoteType.uiStrong)),
                        IconButton(
                          tooltip: tr(context, 'Close'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      LearningAccessPanel(app: app),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    ),
  );
}

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

class LearningAccessPanel extends StatefulWidget {
  const LearningAccessPanel({super.key, required this.app});
  final AppState app;

  @override
  State<LearningAccessPanel> createState() => _LearningAccessPanelState();
}

class _LearningAccessPanelState extends State<LearningAccessPanel> {
  late LearningScope _selection;
  LearningScope? _pendingScope;

  @override
  void initState() {
    super.initState();
    final scope = widget.app.learning.scope;
    _selection = scope == LearningScope.off ? LearningScope.page : scope;
  }

  Future<void> _changeScope(LearningScope scope) async {
    setState(() => _pendingScope = scope);
    await widget.app.learning.setScope(scope);
    if (!mounted) return;
    setState(() => _pendingScope = null);
    final error = widget.app.learning.error;
    if (error != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(tr(context, error))));
    }
  }

  void _select(LearningScope scope) {
    setState(() => _selection = scope);
    if (widget.app.learning.scope != LearningScope.off) _changeScope(scope);
  }

  Future<void> _copy() async {
    await Clipboard.setData(
        ClipboardData(text: learningChatText(context, widget.app.learning)));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(tr(context, 'Copied'))));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final access = app.learning;
    return ListenableBuilder(
      listenable: Listenable.merge([app, access]),
      builder: (context, _) {
        final scope = _pendingScope ?? access.scope;
        final enabled = scope != LearningScope.off;
        final selection = enabled ? scope : _selection;
        final busy = access.busy || _pendingScope != null;
        final paused = access.scope == LearningScope.notebook &&
            app.notebookId != access.sharedNotebookId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  style: OnoteType.uiStrong.copyWith(
                    fontSize: enabled ? 14 : 13,
                    color: enabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  child: const AppText('AI access'),
                ),
              ),
              OnoteSwitch(
                value: enabled,
                onChanged: busy
                    ? null
                    : (value) =>
                        _changeScope(value ? _selection : LearningScope.off),
              ),
            ]),
            const SizedBox(height: OnoteSpace.x4),
            _ScopeOption(
              title: 'Only this page',
              subtitle: 'Follows page changes',
              icon: Icons.description_outlined,
              selected: selection == LearningScope.page,
              onPressed:
                  !enabled || busy ? null : () => _select(LearningScope.page),
            ),
            const SizedBox(height: OnoteSpace.x4),
            _ScopeOption(
              title: 'Whole notebook',
              subtitle: 'All unlocked pages',
              icon: Icons.menu_book_outlined,
              selected: selection == LearningScope.notebook,
              onPressed: !enabled || busy
                  ? null
                  : () => _select(LearningScope.notebook),
            ),
            const SizedBox(height: OnoteSpace.x6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: OnoteSpace.x6, vertical: OnoteSpace.x5)),
              onPressed: !enabled || busy || paused || access.url == null
                  ? null
                  : _copy,
              icon: const Icon(Icons.copy_outlined),
              label: const AppText('Copy for chat'),
            ),
          ],
        );
      },
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.selected,
      required this.onPressed});

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final disabled = onPressed == null;
    final disabledForeground =
        colors.onSurface.withValues(alpha: OnoteAlpha.disabled);
    return Semantics(
      selected: selected,
      enabled: !disabled,
      child: Material(
        color: disabled
            ? colors.onSurface.withValues(alpha: OnoteAlpha.selected)
            : selected
                ? colors.primary.withValues(alpha: .10)
                : colors.surfaceContainerHighest.withValues(alpha: .5),
        shape: RoundedRectangleBorder(
            borderRadius: OnoteRadius.lgAll,
            side: BorderSide(
                color: !disabled && selected
                    ? colors.primary
                    : Colors.transparent)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(OnoteSpace.x6),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: !disabled && selected
                      ? colors.primary.withValues(alpha: .12)
                      : colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    size: OnoteIcon.lg,
                    color: disabled
                        ? disabledForeground
                        : selected
                            ? colors.primary
                            : colors.onSurfaceVariant),
              ),
              const SizedBox(width: OnoteSpace.x5),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(title,
                      style: OnoteType.uiStrong.copyWith(
                          fontSize: 14,
                          color: disabled
                              ? disabledForeground
                              : selected
                                  ? colors.onSurface
                                  : colors.onSurface)),
                  const SizedBox(height: OnoteSpace.x2),
                  AppText(subtitle,
                      style: OnoteType.small.copyWith(
                          color: disabled
                              ? disabledForeground
                              : selected
                                  ? colors.onSurfaceVariant
                                  : colors.onSurfaceVariant)),
                ],
              )),
              const SizedBox(width: OnoteSpace.x4),
              Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: OnoteIcon.lg,
                  color: disabled
                      ? disabledForeground
                      : selected
                          ? colors.primary
                          : colors.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

String learningChatText(BuildContext context, LearningAccess access) =>
    '${tr(context, 'Connect to my local Openote MCP server using this Streamable HTTP configuration. In Codex, update only the Openote entry in the personal config.toml (~/.codex or CODEX_HOME), preserving other settings. Keep the token secret and out of repositories. If setup or a restart is needed, tell me the next step. Verify with get_context before claiming success. If this client cannot reach localhost or configure MCP, explain the limitation. Read only the scope shared in Openote; page access follows navigation. Openote must stay open; sharing is off after restarting. Locked pages are excluded. Content sent stays in this chat and may be processed by the AI provider.')}\n\n'
    '```toml\n${access.clientConfig}```\n';
