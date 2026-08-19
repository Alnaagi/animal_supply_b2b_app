import 'package:flutter/material.dart';

import '../../data/models/product.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Shared Arabic labels and compact facts for customer product cards.
abstract final class CustomerProductCardCopy {
  static const addToCart = 'للسلة';
  static const wholesale = 'سعر الجملة';

  static String brand(Product product) => product.brand.trim();

  static String packSize(Product product) =>
      product.effectivePackageSize.trim();

  static String compactAvailability(Product product) {
    if (!product.isOrderable) return 'غير متوفر';
    if (product.stockTrackingEnabled && product.showStockQuantityToCustomers) {
      return 'متوفر ${product.orderableStockQuantity}';
    }
    return 'متوفر';
  }

  static String suggestedUnitPrice(double price) => 'بيع الوحدة ${lyd(price)}';

  static String suggestedUnitPriceCatalog(double price) =>
      'بيع الوحدة المقترح: ${lyd(price)}';
}

class CompactAvailabilityChip extends StatelessWidget {
  const CompactAvailabilityChip({
    required this.product,
    this.compact = false,
    super.key,
  });

  final Product product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final available = product.isOrderable;
    final color = available ? AppTheme.green : AppTheme.red;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            CustomerProductCardCopy.compactAvailability(product),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: compact ? 10 : 11,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ProductMetaLine extends StatelessWidget {
  const ProductMetaLine({
    required this.product,
    this.brandKey,
    this.packKey,
    super.key,
  });

  final Product product;
  final Key? brandKey;
  final Key? packKey;

  @override
  Widget build(BuildContext context) {
    final brand = CustomerProductCardCopy.brand(product);
    final pack = CustomerProductCardCopy.packSize(product);
    if (brand.isEmpty && pack.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        if (brand.isNotEmpty)
          Flexible(
            child: Text(
              brand,
              key: brandKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.darkGreen.withValues(alpha: .62),
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.15,
              ),
            ),
          ),
        if (brand.isNotEmpty && pack.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            '·',
            style: TextStyle(
              color: AppTheme.darkGreen.withValues(alpha: .35),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (pack.isNotEmpty)
          Flexible(
            child: Container(
              key: packKey,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                pack,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.green,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  height: 1.15,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class WholesalePriceBlock extends StatelessWidget {
  const WholesalePriceBlock({
    required this.product,
    this.priceKey,
    this.compact = false,
    this.showWholesaleLabel = true,
    this.showSuggestedPrice = true,
    super.key,
  });

  final Product product;
  final Key? priceKey;
  final bool compact;
  final bool showWholesaleLabel;
  final bool showSuggestedPrice;

  @override
  Widget build(BuildContext context) {
    final suggested = product.retailUnitPrice;
    final basePrice = product.effectivePrice ?? product.basePrice;
    final hasDiscount = product.hasProductDiscount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showWholesaleLabel)
          Text(
            CustomerProductCardCopy.wholesale,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.darkGreen,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        Text(
          lyd(product.price),
          key: priceKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: hasDiscount ? const Color(0xff00897b) : AppTheme.darkGreen,
            fontWeight: FontWeight.w900,
            fontSize: compact ? 15.5 : 16,
            height: 1.15,
          ),
        ),
        if (hasDiscount) ...[
          const SizedBox(height: 1),
          Text(
            lyd(basePrice),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              decoration: TextDecoration.lineThrough,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 10.5 : 11,
              height: 1.15,
            ),
          ),
        ],
        if (showSuggestedPrice && suggested != null && !hasDiscount) ...[
          const SizedBox(height: 2),
          Text(
            compact
                ? CustomerProductCardCopy.suggestedUnitPrice(suggested)
                : CustomerProductCardCopy.suggestedUnitPriceCatalog(suggested),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.darkGreen.withValues(alpha: .55),
              fontSize: compact ? 10.5 : 11,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ],
      ],
    );
  }
}

class DiscountBadge extends StatelessWidget {
  const DiscountBadge({
    required this.discountPercent,
    this.compact = false,
    super.key,
  });

  final double discountPercent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xff00897b),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'خصم ${discountPercent.truncate() == discountPercent ? discountPercent.toInt() : discountPercent.toStringAsFixed(1)}٪',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: compact ? 10 : 11,
          height: 1.1,
        ),
      ),
    );
  }
}

class AddToCartPill extends StatelessWidget {
  const AddToCartPill({
    required this.enabled,
    required this.tooltip,
    required this.onPressed,
    this.expand = false,
    this.height = 38,
    super.key,
  });

  final bool enabled;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    final child = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xff1fa275), Color(0xff12805a)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
          color: enabled ? null : Colors.grey.shade400,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppTheme.green.withValues(alpha: .30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: SizedBox(
            height: height,
            width: expand ? double.infinity : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: expand ? 10 : 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.add_shopping_cart_outlined,
                    color: Colors.white,
                    size: 17,
                  ),
                  SizedBox(width: 5),
                  Text(
                    CustomerProductCardCopy.addToCart,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: tooltip, child: child);
  }
}
