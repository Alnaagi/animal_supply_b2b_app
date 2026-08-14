import 'package:flutter/material.dart';

/// Keeps related form fields side-by-side on wide dialogs and stacks them on
/// phones so Arabic labels and validation messages remain readable.
class ResponsiveFieldGroup extends StatelessWidget {
  const ResponsiveFieldGroup({
    required this.children,
    this.columns = 2,
    this.breakpoint = 600,
    this.spacing = 10,
    this.runSpacing = 10,
    super.key,
  }) : assert(columns > 0);

  final List<Widget> children;
  final int columns;
  final double breakpoint;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final useSingleColumn =
            availableWidth < breakpoint || children.length == 1;
        final effectiveColumns =
            useSingleColumn ? 1 : columns.clamp(1, children.length);
        final itemWidth = effectiveColumns == 1
            ? availableWidth
            : (availableWidth - spacing * (effectiveColumns - 1)) /
                effectiveColumns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
