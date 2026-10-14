import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/product_info_chip.dart';
import '../../data/models/product.dart';
import 'admin_product_discount_helpers.dart';

typedef AdminProductCardAction = Future<void> Function(String action);

class AdminProductOperationalCard extends StatelessWidget {
  const AdminProductOperationalCard({
    required this.product,
    required this.busy,
    required this.multiSelectMode,
    required this.selected,
    required this.onToggleSelected,
    required this.onQuickAction,
    required this.onMenuAction,
    required this.onFeaturedToggle,
    required this.onVisibilityToggle,
    required this.onOpenFullEdit,
    this.compact = false,
    super.key,
  });

  final Product product;
  final bool busy;
  final bool multiSelectMode;
  final bool selected;
  final VoidCallback onToggleSelected;
  final ValueChanged<String> onQuickAction;
  final AdminProductCardAction onMenuAction;
  final VoidCallback onFeaturedToggle;
  final VoidCallback onVisibilityToggle;
  final VoidCallback onOpenFullEdit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final imageSize = compact ? 88.0 : 112.0;
    final stockColor = !product.stockTrackingEnabled
        ? Colors.blueGrey
        : !product.isOrderable
            ? AppTheme.red
            : product.lowStock
                ? AppTheme.orange
                : AppTheme.success;
    final visibilityLabel = product.isArchived
        ? 'مؤرشف'
        : product.active
            ? 'ظاهر للعملاء'
            : 'مخفي';
    final visibilityColor = product.isArchived || !product.active
        ? Colors.blueGrey
        : scheme.primary;

    return Card(
      key: ValueKey('admin-product-card-${product.id}'),
      clipBehavior: Clip.antiAlias,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: .55)
              : scheme.primary.withValues(alpha: .12),
          width: selected ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (multiSelectMode)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Checkbox(
                          key: ValueKey('admin-product-select-${product.id}'),
                          value: selected,
                          onChanged: (_) => onToggleSelected(),
                        ),
                      ),
                    SizedBox(
                      width: imageSize,
                      height: imageSize,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ProductImagePlaceholder(
                            key: ValueKey('admin-product-image-${product.id}'),
                            productId: product.id,
                            category: product.category,
                            imageUrl: product.imageUrl,
                            semanticLabel: 'صورة ${product.name}',
                            expand: true,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          if (product.hasProductDiscount)
                            PositionedDirectional(
                              top: 6,
                              start: 6,
                              child: _DiscountBadge(
                                key: ValueKey(
                                  'admin-product-discount-badge-${product.id}',
                                ),
                                percent: product.discountPercent!,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      maxLines: compact ? 2 : 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (product.brand.trim().isNotEmpty)
                                          product.brand,
                                        if (product.category.trim().isNotEmpty)
                                          product.category,
                                      ].join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: ValueKey(
                                  'admin-product-featured-${product.id}',
                                ),
                                tooltip: product.isFeatured
                                    ? 'إلغاء التمييز'
                                    : 'تمييز',
                                onPressed: onFeaturedToggle,
                                icon: Icon(
                                  product.isFeatured
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: product.isFeatured
                                      ? AppTheme.orange
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                lyd(product.price),
                                style: textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (product.hasProductDiscount)
                                Text(
                                  lyd(product.effectivePrice ??
                                      product.basePrice),
                                  style: TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ProductChipWrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              InkWell(
                                key: ValueKey(
                                  'admin-product-stock-pill-${product.id}',
                                ),
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => onQuickAction('stock'),
                                child: ProductInfoChip(
                                  adminStockStatusLabel(product),
                                  icon: Icons.inventory_2_outlined,
                                  color: stockColor,
                                ),
                              ),
                              ProductInfoChip(
                                visibilityLabel,
                                icon: product.active
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: visibilityColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 10),
                  _QuickActionRow(
                    productId: product.id,
                    onPrice: () => onQuickAction('price'),
                    onDiscount: () => onQuickAction('discount'),
                    onStock: () => onQuickAction('stock'),
                    onMenu: (value) async => onMenuAction(value),
                    onVisibilityToggle: onVisibilityToggle,
                    product: product,
                  ),
                ],
              ],
            ),
          ),
          if (busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: .45),
                child: const Center(
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.productId,
    required this.onPrice,
    required this.onDiscount,
    required this.onStock,
    required this.onMenu,
    required this.onVisibilityToggle,
    required this.product,
  });

  final String productId;
  final VoidCallback onPrice;
  final VoidCallback onDiscount;
  final VoidCallback onStock;
  final Future<void> Function(String value) onMenu;
  final VoidCallback onVisibilityToggle;
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          key: ValueKey('admin-product-quick-price-$productId'),
          onPressed: onPrice,
          child: const Text('السعر'),
        ),
        FilledButton.tonal(
          key: ValueKey('admin-product-quick-discount-$productId'),
          onPressed: onDiscount,
          child: const Text('الخصم'),
        ),
        FilledButton.tonal(
          key: ValueKey('admin-product-quick-stock-$productId'),
          onPressed: onStock,
          child: const Text('المخزون'),
        ),
        PopupMenuButton<String>(
          key: ValueKey('admin-product-menu-$productId'),
          tooltip: 'خيارات المنتج',
          icon: const Icon(Icons.more_horiz),
          onSelected: (value) async => onMenu(value),
          itemBuilder: (context) => adminProductOverflowItems(product),
        ),
      ],
    );
  }
}

List<PopupMenuEntry<String>> adminProductOverflowItems(Product product) {
  return [
    PopupMenuItem(
      key: ValueKey('admin-product-edit-${product.id}'),
      value: 'edit',
      child: const Text('تعديل كامل'),
    ),
    PopupMenuItem(
      key: ValueKey('admin-product-change-image-${product.id}'),
      value: 'change-image',
      child: const Text('تغيير الصورة'),
    ),
    PopupMenuItem(
      key: ValueKey('admin-product-duplicate-${product.id}'),
      value: 'duplicate',
      child: const Text('نسخ المنتج'),
    ),
    PopupMenuItem(
      key: ValueKey('admin-product-stock-settings-${product.id}'),
      value: 'stock-settings',
      child: const Text('إعدادات المخزون'),
    ),
    PopupMenuItem(
      key: ValueKey('admin-product-toggle-featured-${product.id}'),
      value: 'toggle-featured',
      child: Text(product.isFeatured ? 'إلغاء التمييز' : 'تمييز'),
    ),
    PopupMenuItem(
      key: ValueKey('admin-product-toggle-visibility-${product.id}'),
      value: 'toggle-visibility',
      child: Text(product.active ? 'إخفاء' : 'إظهار'),
    ),
    if (product.isArchived)
      PopupMenuItem(
        key: ValueKey('admin-product-restore-${product.id}'),
        value: 'restore',
        child: const Text('استعادة ونشر المنتج'),
      )
    else
      PopupMenuItem(
        key: ValueKey('admin-product-archive-${product.id}'),
        value: 'archive',
        child: const Text('أرشفة'),
      ),
  ];
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.percent, super.key});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final label = percent.truncateToDouble() == percent
        ? percent.toInt()
        : percent.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xffe65100),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '🔥 -$label%',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ignore: unused_element
void unawaited(Future<void> future) {}
