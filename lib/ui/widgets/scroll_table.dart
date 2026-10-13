import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A wide table that scrolls both ways at once: a header row that stays on
/// top (and scrolls sideways with the rows), a vertical list of rows, the
/// side-to-side scrollbar always along the bottom of the visible area and
/// the up-and-down one along its right edge.
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

  const ScrollTable({
    super.key,
    required this.width,
    required this.header,
    required this.body,
  });

  @override
  State<ScrollTable> createState() => _ScrollTableState();
}

class _ScrollTableState extends State<ScrollTable> {
  final _h = ScrollController();
  final _hHeader = ScrollController();
  final _v = ScrollController();

  @override
  void initState() {
    super.initState();
    _h.addListener(() {
      if (_hHeader.hasClients && _hHeader.offset != _h.offset) {
        _hHeader.jumpTo(_h.offset.clamp(0.0, _hHeader.position.maxScrollExtent));
      }
    });
  }

  @override
  void dispose() {
    _h.dispose();
    _hHeader.dispose();
    _v.dispose();
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

  @override
  Widget build(BuildContext context) {
    // Our own scrollbars only (no automatic ones in odd places).
    final behavior = ScrollConfiguration.of(context).copyWith(scrollbars: false);
    return ScrollConfiguration(
      behavior: behavior,
      child: LayoutBuilder(
        builder: (context, c) {
          final width = math.max(widget.width, c.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Listener(
                onPointerSignal: _onHeaderSignal,
                child: SingleChildScrollView(
                  controller: _hHeader,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(width: width, child: widget.header),
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
                    notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                    child: Scrollbar(
                      controller: _h,
                      thumbVisibility: true,
                      notificationPredicate: (n) =>
                          n.depth == 0 && n.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _h,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: width,
                          child: Padding(
                            // Room for the sideways scrollbar under the rows.
                            padding: const EdgeInsets.only(bottom: 14, right: 14),
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
        },
      ),
    );
  }
}
