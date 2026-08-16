import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ProductImagePlaceholder extends StatelessWidget {
  const ProductImagePlaceholder(
      {required this.category,
      this.productId,
      this.imageUrl,
      this.imageBytes,
      this.semanticLabel,
      this.size = 92,
      this.expand = false,
      this.borderRadius,
      super.key});
  final String category;
  final String? productId;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? semanticLabel;
  final double size;
  final bool expand;
  final BorderRadius? borderRadius;

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
    final image = expand
        ? LayoutBuilder(
            builder: (context, constraints) => _buildImage(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              iconSize: constraints.biggest.shortestSide * .32,
            ),
          )
        : _buildImage(width: size, height: size, iconSize: size * .42);
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
  }) {
    final radius =
        borderRadius ?? BorderRadius.circular(expand || size > 120 ? 28 : 20);
    final fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
            colors: [Color(0xffffffff), Color(0xffe9f4ee)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft),
      ),
      child: Icon(icon, color: AppTheme.green, size: iconSize),
    );
    final assetFallback = !_hasBundledProductImage(productId)
        ? fallback
        : ClipRRect(
            borderRadius: radius,
            child: Image.asset(
              'assets/images/products/$productId.png',
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
          );
    final bytes = imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          bytes,
          width: width,
          height: height,
          fit: BoxFit.cover,
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
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        imageUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        loadingBuilder: (context, child, loadingProgress) =>
            loadingProgress == null ? child : assetFallback,
        errorBuilder: (context, error, stackTrace) => assetFallback,
      ),
    );
  }
}

bool _hasBundledProductImage(String? productId) {
  if (productId == null) return false;
  return RegExp(
    r'^(cat|dog|bird|fish|farm|sup|clean|vit)-00[1-5]$',
  ).hasMatch(productId);
}
