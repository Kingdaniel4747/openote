import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Fixed command order, measured during layout in the actual theme/language.
/// The trailing menu contains precisely the controls that did not fit.
class FixedToolbar extends StatefulWidget {
  const FixedToolbar({super.key, required this.children});
  final List<Widget> children;

  @override
  State<FixedToolbar> createState() => _FixedToolbarState();
}

class _FixedToolbarState extends State<FixedToolbar> {
  int? _shown;
  int? _pending;
  bool _measurementScheduled = false;

  void _measured(int count) {
    if (_shown == count || _pending == count) return;
    _pending = count;
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (mounted && _shown != _pending) setState(() => _shown = _pending);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown =
        (_shown ?? widget.children.length).clamp(0, widget.children.length);
    return _ToolbarLayout(
      onMeasured: _measured,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          ExcludeFocus(excluding: i >= shown, child: widget.children[i]),
        SizedBox(
          width: 40,
          child: MenuAnchor(
            builder: (context, controller, _) => IconButton(
              tooltip: 'More commands',
              icon: const Icon(Icons.more_horiz, size: 18),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: MediaQuery.sizeOf(context)
                          .width
                          .clamp(80, 520)
                          .toDouble() -
                      32,
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 8,
                    children: widget.children.skip(shown).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolbarLayout extends MultiChildRenderObjectWidget {
  const _ToolbarLayout({required super.children, required this.onMeasured});
  final ValueChanged<int> onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderToolbar(onMeasured);

  @override
  void updateRenderObject(BuildContext context, _RenderToolbar renderObject) {
    renderObject.onMeasured = onMeasured;
  }
}

class _ToolbarData extends ContainerBoxParentData<RenderBox> {
  bool visible = false;
}

class _RenderToolbar extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ToolbarData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ToolbarData> {
  _RenderToolbar(this.onMeasured);
  ValueChanged<int> onMeasured;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ToolbarData) child.parentData = _ToolbarData();
  }

  @override
  void performLayout() {
    final items = getChildrenAsList();
    var total = 0.0;
    var height = 0.0;
    for (final child in items) {
      child.layout(BoxConstraints(maxHeight: constraints.maxHeight),
          parentUsesSize: true);
      if (child != items.last) total += child.size.width;
      if (child.size.height > height) height = child.size.height;
    }
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : total;
    size = constraints.constrain(Size(width, height));
    final overflow = total > size.width;
    final available = size.width - (overflow ? items.last.size.width : 0);
    var x = 0.0;
    var shown = 0;
    var folding = false;
    for (final child in items.take(items.length - 1)) {
      final data = child.parentData! as _ToolbarData;
      folding = folding || x + child.size.width > available;
      data.visible = !folding;
      data.offset = Offset(x, (size.height - child.size.height) / 2);
      if (!folding) {
        x += child.size.width;
        shown++;
      }
    }
    final more = items.last;
    final data = more.parentData! as _ToolbarData;
    data.visible = overflow;
    data.offset = Offset(
        (size.width - more.size.width).clamp(0, double.infinity),
        (size.height - more.size.height) / 2);
    onMeasured(shown);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in getChildrenAsList()) {
      final data = child.parentData! as _ToolbarData;
      if (data.visible) context.paintChild(child, offset + data.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in getChildrenAsList().reversed) {
      final data = child.parentData! as _ToolbarData;
      if (data.visible &&
          result.addWithPaintOffset(
              offset: data.offset,
              position: position,
              hitTest: (result, position) =>
                  child.hitTest(result, position: position))) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final child in getChildrenAsList()) {
      if ((child.parentData! as _ToolbarData).visible) visitor(child);
    }
  }
}
