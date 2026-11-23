import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'node_context_menu.dart';

/// Reorders sections in their clipped strip or list, preserving the grab point.
class InlineSectionStrip extends StatefulWidget {
  const InlineSectionStrip(
      {super.key,
      required this.ids,
      required this.widths,
      required this.children,
      required this.trailing,
      required this.onReorder,
      this.disabledId,
      this.axis = Axis.horizontal,
      this.fixedIds = const {},
      this.dragGroups = const {},
      this.canInsertBefore,
      this.allowExternalDrops = false,
      this.preferNextTarget = false,
      this.canNest,
      this.onNest,
      this.onHold,
      this.onNestPreview});

  final List<String> ids;

  /// Extent of each entry along [axis]: tab width or list row height.
  final List<double> widths;
  final List<Widget> children;
  final Widget trailing;
  final String? disabledId;
  final Axis axis;
  final Set<String> fixedIds;
  final Map<String, List<String>> dragGroups;
  final bool Function(String moving, String? next)? canInsertBefore;
  final bool allowExternalDrops;
  final bool preferNextTarget;
  final bool Function(String moving, String target)? canNest;
  final void Function(String moving, String target)? onNest;
  final void Function(String? moving, String? target)? onNestPreview;
  final void Function(String id, Offset position)? onHold;
  final void Function(String moving, String target, bool after) onReorder;

  @override
  State<InlineSectionStrip> createState() => _InlineSectionStripState();
}

class _InlineSectionStripState extends State<InlineSectionStrip> {
  final _viewport = GlobalKey();
  final _scroll = ScrollController();
  Timer? _autoScroll;
  Timer? _nestTimer;
  String? _hoverTarget, _nestTarget;
  Rect? _hoverBounds;
  String? _moving;
  List<String>? _order;
  double _grab = 0, _left = 0;
  Offset _pointer = Offset.zero;
  Offset _down = Offset.zero;
  Offset _latest = Offset.zero;

  List<String> get _movingIds =>
      widget.dragGroups[_moving] ?? [if (_moving != null) _moving!];

  bool get _horizontal => widget.axis == Axis.horizontal;
  double get _padding => _horizontal ? 7 : 0;
  double get _gap => _horizontal ? 2 : 0;
  double _coordinate(Offset point) => _horizontal ? point.dx : point.dy;
  double get _viewportExtent =>
      _horizontal ? _box.size.width : _box.size.height;
  bool _disabled(String id) =>
      id == widget.disabledId || widget.fixedIds.contains(id);

  double _width(String id) => widget.widths[widget.ids.indexOf(id)];
  double get _tabsWidth => widget.widths.fold(0, (a, b) => a + b + _gap);
  double _slot(String id) {
    if (_moving != null && id != _moving && _movingIds.contains(id)) {
      var offset = _left;
      for (final entry in _movingIds) {
        if (entry == id) break;
        offset += _width(entry) + _gap;
      }
      return offset;
    }
    var x = _padding;
    for (final entry in _order ?? widget.ids) {
      if (entry == id) break;
      x += _width(entry) + _gap;
    }
    return x;
  }

  RenderBox get _box =>
      _viewport.currentContext!.findRenderObject()! as RenderBox;

  void _clearNest({bool notify = true}) {
    _nestTimer?.cancel();
    _nestTimer = null;
    final hadPreview = _nestTarget != null;
    _hoverTarget = _nestTarget = null;
    _hoverBounds = null;
    if (notify && hadPreview) widget.onNestPreview?.call(null, null);
  }

  void _trackNest(Offset pointer) {
    if (widget.canNest == null || _horizontal) return;
    final local = _box.globalToLocal(pointer);
    if (local.dx < 0 ||
        local.dx > _box.size.width ||
        local.dy < 0 ||
        local.dy > _box.size.height) {
      _clearNest();
      return;
    }
    // Keep the hovered row's footprint stable while its neighbours slide.
    // Otherwise the automatic displacement would cancel a stationary hold.
    if (_hoverBounds?.contains(pointer) ?? false) return;
    _clearNest();
    final contentY = local.dy + _scroll.offset;
    for (final id in _order!) {
      if (_movingIds.contains(id) || !widget.canNest!(_moving!, id)) continue;
      final top = _slot(id);
      if (contentY < top || contentY >= top + _width(id)) continue;
      _hoverTarget = id;
      _hoverBounds = Rect.fromLTWH(
          _box.localToGlobal(Offset.zero).dx,
          _box.localToGlobal(Offset(0, top - _scroll.offset)).dy,
          _box.size.width,
          _width(id));
      final moving = _moving!;
      _nestTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted ||
            _moving != moving ||
            _hoverTarget != id ||
            !widget.canNest!(moving, id)) {
          return;
        }
        _nestTarget = id;
        widget.onNestPreview?.call(moving, id);
      });
      break;
    }
  }

  void _start(String id, DragStartDetails details) {
    if (!mounted) return;
    _pointer = details.globalPosition;
    _grab =
        _coordinate(_box.globalToLocal(_pointer)) + _scroll.offset - _slot(id);
    setState(() {
      _order = List.of(widget.ids);
      _moving = id;
      _left = _slot(id);
    });
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final x = _coordinate(_box.globalToLocal(_pointer));
      final delta = x < 32
          ? -((32 - x) / 4).clamp(0, 12)
          : x > _viewportExtent - 32
              ? ((x - _viewportExtent + 32) / 4).clamp(0, 12)
              : 0.0;
      final next =
          (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent);
      if (next != _scroll.offset) {
        _clearNest();
        _scroll.jumpTo(next);
        _update(_pointer);
      }
    });
  }

  void _update(Offset pointer) {
    if (!mounted || _moving == null) return;
    _pointer = pointer;
    _trackNest(pointer);
    final width = _width(_moving!);
    // Clamp the entire tab to the visible strip, including on vertical escapes.
    final minLeft = math.max(_padding, _scroll.offset);
    final maxLeft = math.max(
        minLeft,
        math.min(_padding + _tabsWidth - width - _gap,
            _scroll.offset + _viewportExtent - width));
    setState(() {
      _left =
          (_coordinate(_box.globalToLocal(pointer)) + _scroll.offset - _grab)
              .clamp(minLeft, maxLeft);
      final movingIds = _movingIds;
      final others = _order!.where((id) => !movingIds.contains(id)).toList();
      var x = _padding;
      var at = 0;
      // Compare with settled slots, never the neighbours' animated positions.
      for (final id in others) {
        if (_left + width / 2 <= x + _width(id) / 2) break;
        x += _width(id) + _gap;
        at++;
      }
      // Clamping prevents the dragged entry from crossing the first centre.
      // Reaching the leading edge must still allow insertion at index zero,
      // including when the grabbed entry is wider/taller than the first one.
      if (_left <= _padding) at = 0;
      // A group header stays above its children; the first section can be
      // inserted directly below it, never above the grouped list.
      if (!_horizontal &&
          others.isNotEmpty &&
          widget.fixedIds.contains(others.first)) {
        at = math.max(1, at);
      }
      while (at < others.length &&
          !(widget.canInsertBefore?.call(_moving!, others[at]) ?? true)) {
        at++;
      }
      others.insertAll(at, movingIds);
      _order = others;
    });
  }

  void _finish({bool cancel = false}) {
    if (!mounted) return;
    _autoScroll?.cancel();
    final moving = _moving;
    final order = _order;
    final groupLength = _movingIds.length;
    final nestTarget = _nestTarget;
    _clearNest();
    setState(() {
      _moving = null;
      _order = null;
    });
    if (cancel ||
        moving == null ||
        order == null ||
        !widget.ids.contains(moving)) {
      return;
    }
    if (nestTarget != null &&
        (widget.canNest?.call(moving, nestTarget) ?? false)) {
      widget.onNest?.call(moving, nestTarget);
      return;
    }
    final at = order.indexOf(moving);
    if (at == widget.ids.indexOf(moving)) return;
    if (widget.preferNextTarget && at + groupLength < order.length) {
      widget.onReorder(moving, order[at + groupLength], false);
      return;
    }
    widget.onReorder(moving, order[at == 0 ? 1 : at - 1], at != 0);
  }

  @override
  void didUpdateWidget(covariant InlineSectionStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_moving != null &&
        (oldWidget.ids.length != widget.ids.length ||
            !oldWidget.ids.every(widget.ids.contains))) {
      _autoScroll?.cancel();
      final hadPreview = _nestTarget != null;
      _clearNest(notify: false);
      _moving = null;
      _order = null;
      if (hadPreview) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _moving == null) {
            widget.onNestPreview?.call(null, null);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _clearNest(notify: false);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
        key: _viewport,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: widget.axis,
          physics:
              _moving == null ? null : const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: _horizontal ? _padding + _tabsWidth + 40 : null,
            height: _horizontal ? 36 : _tabsWidth + 8,
            child: Stack(children: [
              for (final id in [
                ...widget.ids.where((id) => !_movingIds.contains(id)),
                ..._movingIds,
              ])
                AnimatedPositioned(
                  key: ValueKey(id),
                  duration:
                      Duration(milliseconds: _movingIds.contains(id) ? 0 : 180),
                  curve: Curves.easeOutCubic,
                  left: _horizontal ? (id == _moving ? _left : _slot(id)) : 0,
                  right: _horizontal ? null : 0,
                  top: _horizontal ? 0 : (id == _moving ? _left : _slot(id)),
                  bottom: _horizontal ? 0 : null,
                  width: _horizontal ? _width(id) : null,
                  height: _horizontal ? null : _width(id),
                  child: Listener(
                    onPointerDown: (event) => _latest = _down = event.position,
                    onPointerMove: (event) => _latest = event.position,
                    onPointerCancel: (_) {
                      if (_moving == id) _finish(cancel: true);
                    },
                    child: NavigatorHoldMenu(
                      onHold: id == widget.disabledId || widget.onHold == null
                          ? null
                          : (position) => widget.onHold!(id, position),
                      child: widget.allowExternalDrops
                          ? Draggable<String>(
                              data: id,
                              maxSimultaneousDrags: _disabled(id) ? 0 : 1,
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              feedback: const SizedBox.shrink(),
                              onDragStarted: () {
                                final current = _latest;
                                _start(id,
                                    DragStartDetails(globalPosition: _down));
                                _update(current);
                              },
                              onDragUpdate: (_) => _update(_latest),
                              onDragEnd: (details) =>
                                  _finish(cancel: details.wasAccepted),
                              child: widget.children[widget.ids.indexOf(id)],
                            )
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              dragStartBehavior: DragStartBehavior.down,
                              onHorizontalDragStart:
                                  !_horizontal || _disabled(id)
                                      ? null
                                      : (d) => _start(id, d),
                              onHorizontalDragUpdate:
                                  !_horizontal || _disabled(id)
                                      ? null
                                      : (d) => _update(d.globalPosition),
                              onHorizontalDragEnd: !_horizontal || _disabled(id)
                                  ? null
                                  : (_) => _finish(),
                              onHorizontalDragCancel:
                                  !_horizontal || _disabled(id)
                                      ? null
                                      : () => _finish(cancel: true),
                              onVerticalDragStart: _horizontal || _disabled(id)
                                  ? null
                                  : (d) => _start(id, d),
                              onVerticalDragUpdate: _horizontal || _disabled(id)
                                  ? null
                                  : (d) => _update(d.globalPosition),
                              onVerticalDragEnd: _horizontal || _disabled(id)
                                  ? null
                                  : (_) => _finish(),
                              onVerticalDragCancel: _horizontal || _disabled(id)
                                  ? null
                                  : () => _finish(cancel: true),
                              child: widget.children[widget.ids.indexOf(id)],
                            ),
                    ),
                  ),
                ),
              if (_horizontal)
                Positioned(
                    left: 7 + _tabsWidth,
                    top: 0,
                    bottom: 0,
                    width: 36,
                    child: widget.trailing),
            ]),
          ),
        ),
      );
}
