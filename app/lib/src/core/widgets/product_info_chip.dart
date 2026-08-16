import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One-line product pill that must not mid-wrap Arabic.
class ProductInfoChip extends StatelessWidget {
  const ProductInfoChip(
    this.label, {
    this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              color: c,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// [Wrap] lays children out with the run's leftover width, which squeezes
/// Arabic into a tiny clipped pill. This wrap measures each child unbounded
/// so a chip moves to the next line as a whole unit.
class ProductChipWrap extends MultiChildRenderObjectWidget {
  const ProductChipWrap({
    super.key,
    this.spacing = 6,
    this.runSpacing = 4,
    required super.children,
  });

  final double spacing;
  final double runSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderProductChipWrap(
      spacing: spacing,
      runSpacing: runSpacing,
      textDirection: Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderProductChipWrap renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..textDirection = Directionality.of(context);
  }
}

class ProductChipWrapParentData extends ContainerBoxParentData<RenderBox> {}

class RenderProductChipWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ProductChipWrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, ProductChipWrapParentData> {
  RenderProductChipWrap({
    required double spacing,
    required double runSpacing,
    required TextDirection textDirection,
  })  : _spacing = spacing,
        _runSpacing = runSpacing,
        _textDirection = textDirection;

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  double get runSpacing => _runSpacing;
  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ProductChipWrapParentData) {
      child.parentData = ProductChipWrapParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return _foldChildren(0, (sum, child) {
      return math.max(sum, child.getMinIntrinsicWidth(height));
    });
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var width = 0.0;
    var index = 0;
    var child = firstChild;
    while (child != null) {
      if (index > 0) width += spacing;
      width += child.getMaxIntrinsicWidth(height);
      child = childAfter(child);
      index += 1;
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _computeDryLayout(BoxConstraints(maxWidth: width)).height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _computeDryLayout(BoxConstraints(maxWidth: width)).height;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _computeDryLayout(constraints);
  }

  Size _computeDryLayout(BoxConstraints constraints) {
    return _layoutChildren(constraints, dry: true);
  }

  @override
  void performLayout() {
    size = _layoutChildren(constraints, dry: false);
  }

  Size _layoutChildren(BoxConstraints constraints, {required bool dry}) {
    final maxWidth = constraints.maxWidth;
    var x = 0.0;
    var y = 0.0;
    var runHeight = 0.0;
    var runWidth = 0.0;
    var maxRunWidth = 0.0;

    var child = firstChild;
    while (child != null) {
      final Size childSize;
      if (dry) {
        childSize = child.getDryLayout(const BoxConstraints());
      } else {
        child.layout(const BoxConstraints(), parentUsesSize: true);
        childSize = child.size;
      }

      if (x > 0 && x + childSize.width > maxWidth) {
        maxRunWidth = math.max(maxRunWidth, runWidth);
        y += runHeight + runSpacing;
        x = 0;
        runHeight = 0;
        runWidth = 0;
      }

      if (!dry) {
        final parentData = child.parentData! as ProductChipWrapParentData;
        final dx = textDirection == TextDirection.rtl && maxWidth.isFinite
            ? maxWidth - x - childSize.width
            : x;
        parentData.offset = Offset(dx, y);
      }

      x += childSize.width + spacing;
      runWidth += childSize.width + spacing;
      runHeight = math.max(runHeight, childSize.height);
      child = childAfter(child);
    }

    maxRunWidth = math.max(maxRunWidth, runWidth > 0 ? runWidth - spacing : 0);
    final height = y + runHeight;
    return constraints.constrain(Size(maxWidth.isFinite ? maxWidth : maxRunWidth, height));
  }

  double _foldChildren(double initial, double Function(double, RenderBox) combine) {
    var value = initial;
    var child = firstChild;
    while (child != null) {
      value = combine(value, child);
      child = childAfter(child);
    }
    return value;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}
