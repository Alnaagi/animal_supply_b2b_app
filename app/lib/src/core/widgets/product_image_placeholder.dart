import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ProductImagePlaceholder extends StatelessWidget {
  const ProductImagePlaceholder(
      {required this.category,
      this.productId,
      this.imageUrl,
      this.size = 92,
      super.key});
  final String category;
  final String? productId;
  final String? imageUrl;
  final double size;

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
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size > 120 ? 28 : 20),
        gradient: const LinearGradient(
            colors: [Color(0xffffffff), Color(0xffe9f4ee)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft),
      ),
      child: Icon(icon, color: AppTheme.green, size: size * .42),
    );
    final assetFallback = productId == null || productId!.isEmpty
        ? fallback
        : ClipRRect(
            borderRadius: BorderRadius.circular(size > 120 ? 28 : 20),
            child: Image.asset(
              'assets/images/products/$productId.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
          );
    if (imageUrl == null || imageUrl!.isEmpty) return assetFallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 120 ? 28 : 20),
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        loadingBuilder: (context, child, loadingProgress) =>
            loadingProgress == null ? child : assetFallback,
        errorBuilder: (context, error, stackTrace) => assetFallback,
      ),
    );
  }
}
