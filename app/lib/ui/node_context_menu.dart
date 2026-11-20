import 'package:flutter/material.dart';

/// A modal context menu whose Material submenus automatically choose the
/// available side of the window and support both mouse hover and touch.
Future<String?> showNodeContextMenu(BuildContext context, Offset position,
        List<Widget> Function(ValueChanged<String> select) items) =>
    showGeneralDialog<String>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) =>
          _NodeContextMenu(position: position, items: items),
    );

class _NodeContextMenu extends StatefulWidget {
  const _NodeContextMenu({required this.position, required this.items});
  final Offset position;
  final List<Widget> Function(ValueChanged<String> select) items;
  @override
  State<_NodeContextMenu> createState() => _NodeContextMenuState();
}

class _NodeContextMenuState extends State<_NodeContextMenu> {
  final _controller = MenuController();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.open(position: widget.position);
    });
  }

  void _finish(String? action) {
    if (!mounted || _closing) return;
    _closing = true;
    Navigator.of(context).pop(action);
  }

  @override
  void dispose() {
    _closing = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: MenuAnchor(
          controller: _controller,
          style: const MenuStyle(
              maximumSize: WidgetStatePropertyAll(Size(280, double.infinity))),
          onClose: () => _finish(null),
          menuChildren: widget.items((action) => _finish(action)),
          child: const SizedBox.expand(),
        ),
      );
}
