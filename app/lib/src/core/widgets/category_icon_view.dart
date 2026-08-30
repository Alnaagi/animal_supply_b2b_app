import 'package:flutter/material.dart';

import '../../data/models/category_icon.dart';
import '../../data/models/product_category.dart';

class CategoryIconView extends StatelessWidget {
  const CategoryIconView({
    super.key,
    this.iconKey,
    this.iconUrl,
    this.name = '',
    this.size = 24,
    this.color,
    this.imageFit = BoxFit.contain,
    this.circularImage = true,
    this.expand = false,
    this.expandedGlyphScale = .45,
  });

  factory CategoryIconView.fromCategory(
    ProductCategory category, {
    Key? key,
    double size = 24,
    Color? color,
    BoxFit imageFit = BoxFit.contain,
    bool circularImage = true,
    bool expand = false,
    double expandedGlyphScale = .45,
  }) {
    return CategoryIconView(
      key: key,
      iconKey: category.iconKey,
      iconUrl: category.iconUrl,
      name: category.name,
      size: size,
      color: color,
      imageFit: imageFit,
      circularImage: circularImage,
      expand: expand,
      expandedGlyphScale: expandedGlyphScale,
    );
  }

  final String? iconKey;
  final String? iconUrl;
  final String name;
  final double size;
  final Color? color;
  final BoxFit imageFit;
  final bool circularImage;

  /// Expands into the largest square allowed by the incoming constraints.
  ///
  /// Expanded category artwork is never oval-clipped. This keeps transparent
  /// custom artwork intact and gives fallback glyphs a consistent visual size.
  final bool expand;

  /// Fallback glyph size relative to the shortest side in expanded mode.
  final double expandedGlyphScale;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.primary;
    if (!expand) return _buildSquare(size, expanded: false, color: tone);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = _squareSide(constraints, size);
        return Center(
          child: _buildSquare(side, expanded: true, color: tone),
        );
      },
    );
  }

  Widget _buildSquare(
    double side, {
    required bool expanded,
    required Color color,
  }) {
    final url = iconUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      final image = Image.network(
        url,
        width: side,
        height: side,
        fit: imageFit,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        webHtmlElementStrategy: WebHtmlElementStrategy.never,
        errorBuilder: (context, error, stackTrace) => _glyph(
          side,
          expanded: expanded,
          color: color,
        ),
      );
      return SizedBox.square(
        key: expanded ? const Key('category-artwork-frame') : null,
        dimension: side,
        child: circularImage && !expanded ? ClipOval(child: image) : image,
      );
    }
    return SizedBox.square(
      key: expanded ? const Key('category-artwork-frame') : null,
      dimension: side,
      child: Center(child: _glyph(side, expanded: expanded, color: color)),
    );
  }

  Widget _glyph(
    double side, {
    required bool expanded,
    required Color color,
  }) {
    final scale = expandedGlyphScale.clamp(.1, 1.0).toDouble();
    return Icon(
      CategoryIconCatalog.iconData(iconKey: iconKey, fallbackName: name),
      size: expanded ? side * scale : side,
      color: color,
    );
  }
}

double _squareSide(BoxConstraints constraints, double fallback) {
  final width = constraints.maxWidth;
  final height = constraints.maxHeight;
  final hasWidth = width.isFinite && width > 0;
  final hasHeight = height.isFinite && height > 0;
  if (hasWidth && hasHeight) return width < height ? width : height;
  if (hasWidth) return width;
  if (hasHeight) return height;
  return fallback;
}
