import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProductImagePlaceholder extends StatelessWidget {
  const ProductImagePlaceholder({
    required this.category,
    this.productId,
    this.imageUrl,
    this.imageBytes,
    this.semanticLabel,
    this.size = 92,
    this.expand = false,
    this.borderRadius,
    this.fit = BoxFit.contain,
    this.backgroundColor,
    super.key,
  });

  final String category;
  final String? productId;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? semanticLabel;
  final double size;
  final bool expand;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  /// Overrides the neutral surface behind a real product photo.
  ///
  /// Missing, loading, and failed images intentionally keep the themed brand
  /// placeholder so they remain distinguishable from product photography.
  final Color? backgroundColor;

  IconData get icon => switch (category) {
        'قطط' => Icons.pets,
        'كلاب' => Icons.cruelty_free,
        'طيور' => Icons.flutter_dash,
        'أسماك' => Icons.water,
        'مواشي' => Icons.agriculture,
        'تنظيف' => Icons.cleaning_services,
        'مكملات' => Icons.medication_liquid,
        _ => Icons.inventory_2,
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final photoSurfaceColor = backgroundColor ?? Colors.white;
    final placeholderStart = Color.alphaBlend(
      colors.primary.withValues(alpha: .08),
      colors.surface,
    );
    final placeholderEnd = Color.alphaBlend(
      colors.primary.withValues(alpha: .20),
      colors.surface,
    );
    final image = expand
        ? LayoutBuilder(
            builder: (context, constraints) {
              final width = _finiteSize(constraints.maxWidth, size);
              final height = _finiteSize(constraints.maxHeight, size);
              return _buildImage(
                width: width,
                height: height,
                iconSize: (width < height ? width : height) * .62,
                photoSurfaceColor: photoSurfaceColor,
                placeholderStart: placeholderStart,
                placeholderEnd: placeholderEnd,
                placeholderIconColor: colors.primary,
              );
            },
          )
        : _buildImage(
            width: size,
            height: size,
            iconSize: size * .42,
            photoSurfaceColor: photoSurfaceColor,
            placeholderStart: placeholderStart,
            placeholderEnd: placeholderEnd,
            placeholderIconColor: colors.primary,
          );
    return Semantics(
      image: true,
      label: semanticLabel ?? 'صورة منتج من تصنيف $category',
      child: ExcludeSemantics(child: image),
    );
  }

  Widget _buildImage({
    required double width,
    required double height,
    required double iconSize,
    required Color photoSurfaceColor,
    required Color placeholderStart,
    required Color placeholderEnd,
    required Color placeholderIconColor,
  }) {
    final radius =
        borderRadius ?? BorderRadius.circular(expand || size > 120 ? 28 : 20);
    final fallback = _placeholderPanel(
      width: width,
      height: height,
      radius: radius,
      startColor: placeholderStart,
      endColor: placeholderEnd,
      child: Center(
        child: _placeholderGlyph(
          iconSize: iconSize,
          color: placeholderIconColor,
        ),
      ),
    );
    final assetFallback = !_hasBundledProductImage(productId)
        ? fallback
        : _photoPanel(
            width: width,
            height: height,
            radius: radius,
            surfaceColor: photoSurfaceColor,
            image: Image.asset(
              'assets/images/products/$productId.png',
              width: width,
              height: height,
              fit: fit,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
          );
    final bytes = imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return _photoPanel(
        width: width,
        height: height,
        radius: radius,
        surfaceColor: photoSurfaceColor,
        image: Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          alignment: Alignment.center,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => assetFallback,
        ),
      );
    }
    if (imageUrl == null ||
        imageUrl!.isEmpty ||
        imageUrl!.contains('placehold.co')) {
      return assetFallback;
    }
    return _photoPanel(
      width: width,
      height: height,
      radius: radius,
      surfaceColor: photoSurfaceColor,
      image: Image.network(
        imageUrl!,
        width: width,
        height: height,
        fit: fit,
        alignment: Alignment.center,
        excludeFromSemantics: true,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        loadingBuilder: (context, child, loadingProgress) =>
            loadingProgress == null ? child : assetFallback,
        errorBuilder: (context, error, stackTrace) => assetFallback,
      ),
    );
  }

  Widget _placeholderGlyph({
    required double iconSize,
    required Color color,
  }) {
    final glyph = Icon(icon, color: color, size: iconSize);
    if (!expand) return glyph;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: FittedBox(fit: BoxFit.contain, child: glyph),
    );
  }

  Widget _photoPanel({
    required double width,
    required double height,
    required BorderRadius radius,
    required Color surfaceColor,
    required Widget image,
  }) {
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          key: const Key('product-image-photo-surface'),
          color: surfaceColor,
          child: image,
        ),
      ),
    );
  }

  Widget _placeholderPanel({
    required double width,
    required double height,
    required BorderRadius radius,
    required Color startColor,
    required Color endColor,
    required Widget child,
  }) {
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          key: const Key('product-image-placeholder-surface'),
          fit: StackFit.expand,
          children: [
            ColoredBox(color: startColor),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [startColor, endColor],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

double _finiteSize(double value, double fallback) {
  return value.isFinite && value > 0 ? value : fallback;
}

bool _hasBundledProductImage(String? productId) {
  if (productId == null) return false;
  return RegExp(
    r'^(cat|dog|bird|fish|farm|sup|clean|vit)-00[1-5]$',
  ).hasMatch(productId);
}
