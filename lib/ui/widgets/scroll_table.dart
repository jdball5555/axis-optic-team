import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A wide table that scrolls both ways at once: a header row that stays on
/// top (and scrolls sideways with the rows), a vertical list of rows, the
/// side-to-side scrollbar always along the bottom of the visible area and
/// the up-and-down one along its right edge.
///
/// Optional pinned column on the left (e.g. for team member names) that stays
/// anchored horizontally while scrolling vertically in sync with the table.
///
/// Diagonal trackpad / wheel scrolling moves both ways together. (Nested
/// scroll views normally hand a diagonal scroll to the inner list only, so
/// the sideways part is lost and it feels stuck to one axis.)
class ScrollTable extends StatefulWidget {
  /// Width of the table's content (header and rows).
  final double width;
  final Widget header;

  /// The rows: a scrollable list that must use [vertical] as its controller.
  final Widget Function(ScrollController vertical) body;

  /// Optional pinned column on the left.
  final double? pinnedWidth;
  final Widget? pinnedHeader;
  final Widget Function(ScrollController vertical)? pinnedBody;

  const ScrollTable({
    super.key,
    required this.width,
    required this.header,
    required this.body,
    this.pinnedWidth,
    this.pinnedHeader,
    this.pinnedBody,
  });

  @override
  State<ScrollTable> createState() => _ScrollTableState();
}

class _ScrollTableState extends State<ScrollTable> {
  final _h = ScrollController();
  final _hHeader = ScrollController();
  final _v = ScrollController();
  final _vPinned = ScrollController();
  bool _syncingV = false;

  @override
  void initState() {
    super.initState();
    _h.addListener(() {
      if (_hHeader.hasClients && _hHeader.offset != _h.offset) {
        _hHeader.jumpTo(
          _h.offset.clamp(0.0, _hHeader.position.maxScrollExtent),
        );
      }
    });
    _v.addListener(() => _syncV(_v, _vPinned));
    _vPinned.addListener(() => _syncV(_vPinned, _v));
  }

  void _syncV(ScrollController from, ScrollController to) {
    if (_syncingV || !to.hasClients || !from.hasClients) return;
    if ((to.offset - from.offset).abs() < 0.5) return;
    _syncingV = true;
    to.jumpTo(from.offset.clamp(0.0, to.position.maxScrollExtent));
    _syncingV = false;
  }

  @override
  void dispose() {
    _h.dispose();
    _hHeader.dispose();
    _v.dispose();
    _vPinned.dispose();
    super.dispose();
  }

  void _moveBy(ScrollController c, double delta) {
    if (!c.hasClients || delta == 0) return;
    final p = c.position;
    final to = (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to != p.pixels) c.jumpTo(to);
  }

  /// Would the rows scroll vertically by [dy]?
  bool _verticalTakes(double dy) {
    if (dy == 0 || !_v.hasClients) return false;
    final p = _v.position;
    final to = (p.pixels + dy).clamp(p.minScrollExtent, p.maxScrollExtent);
    return to != p.pixels;
  }

  /// Over the rows: the list takes the vertical part of a diagonal scroll,
  /// so move sideways here (a purely sideways scroll is handled by the
  /// sideways scroll view itself).
  void _onBodySignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final dx = e.scrollDelta.dx;
    if (dx != 0 && _verticalTakes(e.scrollDelta.dy)) _moveBy(_h, dx);
  }

  /// Over the header (which doesn't scroll by itself): move both ways.
  void _onHeaderSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final s = event as PointerScrollEvent;
      _moveBy(_h, s.scrollDelta.dx);
      _moveBy(_v, s.scrollDelta.dy);
    });
  }

  /// Over the pinned column (which doesn't scroll horizontally): move vertically,
  /// and if scrolled horizontally, also move table sideways.
  void _onPinnedSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final s = event as PointerScrollEvent;
      _moveBy(_v, s.scrollDelta.dy);
      if (s.scrollDelta.dx != 0) {
        _moveBy(_h, s.scrollDelta.dx);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Our own scrollbars only (no automatic ones in odd places).
    final behavior = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);
    final hasPinned =
        widget.pinnedBody != null &&
        widget.pinnedWidth != null &&
        widget.pinnedWidth! > 0;

    return ScrollConfiguration(
      behavior: behavior,
      child: LayoutBuilder(
        builder: (context, c) {
          final pinnedW = hasPinned ? widget.pinnedWidth! : 0.0;
          final availableWidth = math.max(0.0, c.maxWidth - pinnedW);
          final tableWidth = math.max(widget.width, availableWidth);

          final mainTable = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Listener(
                onPointerSignal: _onHeaderSignal,
                child: SingleChildScrollView(
                  controller: _hHeader,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: tableWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: widget.header,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Listener(
                  onPointerSignal: _onBodySignal,
                  child: Scrollbar(
                    controller: _v,
                    thumbVisibility: true,
                    // The list sits inside the sideways scroll view.
                    notificationPredicate: (n) =>
                        n.metrics.axis == Axis.vertical,
                    child: Scrollbar(
                      controller: _h,
                      thumbVisibility: true,
                      notificationPredicate: (n) =>
                          n.depth == 0 && n.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _h,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Padding(
                            // Room for the sideways scrollbar under the rows.
                            padding: const EdgeInsets.only(
                              bottom: 14,
                              right: 14,
                            ),
                            child: widget.body(_v),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );

          if (!hasPinned) {
            return mainTable;
          }

          final pinnedColumn = SizedBox(
            width: pinnedW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.pinnedHeader != null)
                  widget.pinnedHeader!
                else
                  const SizedBox.shrink(),
                const SizedBox(height: 8),
                Expanded(
                  child: Listener(
                    onPointerSignal: _onPinnedSignal,
                    child: Padding(
                      // Match the bottom padding so pinned rows align with main table rows.
                      padding: const EdgeInsets.only(bottom: 14),
                      child: widget.pinnedBody!(_vPinned),
                    ),
                  ),
                ),
              ],
            ),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pinnedColumn,
              Expanded(child: mainTable),
            ],
          );
        },
      ),
    );
  }
}
