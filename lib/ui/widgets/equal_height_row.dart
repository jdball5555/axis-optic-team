import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays [children] out side by side in equal-width columns ([spacing] apart)
/// and makes them all as tall as the tallest one, so cards line up across
/// the row. Unlike IntrinsicHeight this works with scrolling lists inside
/// the children (each child is laid out once to measure, then again at the
/// row's height).
class EqualHeightRow extends MultiChildRenderObjectWidget {
  final double spacing;

  const EqualHeightRow({super.key, super.children, this.spacing = 16});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightRow(spacing);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderEqualHeightRow).spacing = spacing;
  }
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  _RenderEqualHeightRow(this._spacing);

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData)
      child.parentData = _RowParentData();
  }

  @override
  void performLayout() {
    final n = childCount;
    if (n == 0) {
      size = constraints.constrain(Size.zero);
      return;
    }
    final width = constraints.maxWidth;
    final columnWidth = math.max(0.0, (width - _spacing * (n - 1)) / n);

    // Measure: each child at its own height, within the height the row
    // may use (so a child that fills its space fills it, e.g. in a header
    // of a fixed height).
    var tallest = constraints.minHeight;
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints(
          minWidth: columnWidth,
          maxWidth: columnWidth,
          maxHeight: constraints.maxHeight,
        ),
        parentUsesSize: true,
      );
      tallest = math.max(tallest, child.size.height);
      child = childAfter(child);
    }
    if (tallest.isInfinite) tallest = 0;

    // Then all at least at the tallest height.
    var x = 0.0;
    child = firstChild;
    var finalTallest = tallest;
    while (child != null) {
      child.layout(
        BoxConstraints(
          minWidth: columnWidth,
          maxWidth: columnWidth,
          minHeight: tallest,
          maxHeight: constraints.maxHeight,
        ),
        parentUsesSize: true,
      );
      finalTallest = math.max(finalTallest, child.size.height);
      (child.parentData! as _RowParentData).offset = Offset(x, 0);
      x += columnWidth + _spacing;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, finalTallest));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
