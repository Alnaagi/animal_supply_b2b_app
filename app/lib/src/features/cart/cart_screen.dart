import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/order.dart';
import '../../data/repositories/admin_repository.dart';
import 'cart_controller.dart';

const _cartDesktopBreakpoint = 1024.0;
const _cartDesktopMaxWidth = 1280.0;
const _cartDesktopSummaryWidth = 360.0;

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartControllerProvider);
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.asData?.value;
    final pricing = CartPricingSummary.estimate(
      items,
      handlingFee: settings?.handlingFee ?? 0,
      deliveryFee: settings?.deliveryFee ?? 0,
    );
    final minimumOrderAmount = settings?.minimumOrderAmount ?? 0;
    final meetsMinimum = pricing.meetsMinimum(minimumOrderAmount);
    final maintenanceMode = settings?.maintenanceMode ?? false;
    final isDesktop =
        MediaQuery.sizeOf(context).width >= _cartDesktopBreakpoint;
    if (items.isEmpty) {
      return EmptyState(
        title: 'السلة فارغة',
        message: 'أضف منتجات من الكتالوج لإرسال طلب جملة.',
        icon: Icons.shopping_cart_outlined,
        action: FilledButton(
            onPressed: () => context.go('/catalog'),
            child: const Text('تصفح المنتجات')),
      );
    }
    final itemsList = ListView(
      key: Key(
        isDesktop ? 'cart-desktop-items-scroll' : 'cart-mobile-items-scroll',
      ),
      padding: isDesktop
          ? const EdgeInsets.only(bottom: 24)
          : const EdgeInsets.fromLTRB(16, 14, 16, 22),
      children: [
        _CartHeader(itemCount: items.length),
        const SizedBox(height: 14),
        for (final item in items)
          _CartItemCard(
            item: item,
            onQuantityChanged: (qty) => ref
                .read(cartControllerProvider.notifier)
                .updateQty(item.product.id, qty),
            onRemove: () => ref
                .read(cartControllerProvider.notifier)
                .remove(item.product.id),
          ),
        if (maintenanceMode) ...[
          const SizedBox(height: 10),
          Card(
            key: const Key('cart-maintenance-notice'),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: const ListTile(
              leading: Icon(Icons.build_circle_outlined),
              title: Text('الطلبات متوقفة مؤقتاً للصيانة'),
              subtitle: Text(
                'يمكنك مراجعة السلة، لكن لن يتم إرسال طلب جديد حتى تعيد الإدارة فتح الطلبات.',
              ),
            ),
          ),
        ],
        if (settings == null) ...[
          const SizedBox(height: 10),
          Card(
            color: settingsAsync.hasError
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: settingsAsync.hasError
                  ? const Icon(Icons.cloud_off_outlined)
                  : const ShopLoading.compact(size: 22),
              title: Text(
                settingsAsync.hasError
                    ? 'تعذر تحميل رسوم وحد الطلب'
                    : 'جارٍ تحميل رسوم وحد الطلب...',
              ),
              subtitle: Text(
                settingsAsync.hasError
                    ? 'لن نعرض إجمالياً ناقصاً أو نسمح بالمتابعة قبل استرجاع الإعدادات.'
                    : 'انتظر لحظات حتى نحسب الإجمالي التقديري الصحيح.',
              ),
              trailing: settingsAsync.hasError
                  ? IconButton(
                      tooltip: 'إعادة تحميل إعدادات الطلب',
                      onPressed: () => ref.invalidate(appSettingsProvider),
                      icon: const Icon(Icons.refresh),
                    )
                  : null,
            ),
          ),
        ],
      ],
    );

    final summary = settings != null
        ? _CartSummaryCard(
            pricing: pricing,
            minimumOrderAmount: minimumOrderAmount,
            meetsMinimum: meetsMinimum,
            onCheckout: () => context.go('/checkout'),
            checkoutEnabled: !maintenanceMode && meetsMinimum,
            desktop: isDesktop,
          )
        : _CartCheckoutBar(
            enabled: false,
            onCheckout: () => context.go('/checkout'),
            desktop: isDesktop,
          );

    if (!isDesktop) {
      return Column(
        key: const Key('cart-mobile-layout'),
        children: [
          Expanded(child: itemsList),
          summary,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          key: const Key('cart-desktop-layout'),
          constraints: const BoxConstraints(maxWidth: _cartDesktopMaxWidth),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: const Key('cart-desktop-items'),
                      child: itemsList,
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: _cartDesktopSummaryWidth,
                    child: SingleChildScrollView(
                      key: const Key('cart-desktop-summary-scroll'),
                      child: KeyedSubtree(
                        key: const Key('cart-desktop-summary'),
                        child: summary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              color: scheme.onPrimaryContainer,
              size: 25,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سلة المشتريات',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 1),
                Text(
                  'راجع الكميات قبل تأكيد طلب الجملة.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$itemCount ${itemCount == 1 ? 'صنف' : 'أصناف'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('cart-item-card'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ProductImagePlaceholder(
                    key: ValueKey('cart-product-image-${item.product.id}'),
                    category: item.product.category,
                    productId: item.product.id,
                    imageUrl: item.product.imageUrl,
                    expand: true,
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (item.product.brand.trim().isNotEmpty ||
                          item.product.unitSize.trim().isNotEmpty)
                        Text(
                          [
                            if (item.product.brand.trim().isNotEmpty)
                              item.product.brand.trim(),
                            if (item.product.unitSize.trim().isNotEmpty)
                              item.product.unitSize.trim(),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 7),
                      Text(
                        'سعر الجملة',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        lyd(item.product.price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  key: const Key('cart-remove-button'),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    tooltip: 'حذف ${item.product.name} من السلة',
                    onPressed: onRemove,
                    padding: const EdgeInsets.all(10),
                    constraints:
                        const BoxConstraints.tightFor(width: 44, height: 44),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الكمية',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _CartQuantitySelector(
                          key: const Key('cart-item-quantity'),
                          quantity: item.quantity,
                          minimum: item.product.minOrderQuantity,
                          max: item.product.orderQuantityLimit,
                          onChanged: onQuantityChanged,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 42,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: scheme.outlineVariant,
                  ),
                  SizedBox(
                    width: 88,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'إجمالي الصنف',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Semantics(
                          label: 'إجمالي الصنف ${lyd(item.lineTotal)}',
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              lyd(item.lineTotal),
                              key: const Key('cart-item-total'),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartSummaryCard extends StatelessWidget {
  const _CartSummaryCard({
    required this.pricing,
    required this.minimumOrderAmount,
    required this.meetsMinimum,
    required this.onCheckout,
    required this.checkoutEnabled,
    this.desktop = false,
  });

  final CartPricingSummary pricing;
  final double minimumOrderAmount;
  final bool meetsMinimum;
  final VoidCallback onCheckout;
  final bool checkoutEnabled;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset =
        desktop ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;
    return Material(
      key: const Key('cart-summary-card'),
      color: scheme.primary,
      elevation: desktop ? 0 : 6,
      shadowColor: scheme.shadow.withValues(alpha: 0.25),
      borderRadius: desktop
          ? BorderRadius.circular(24)
          : const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          desktop ? 20 : 15,
          20,
          (desktop ? 20 : 14) + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: scheme.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الإجمالي التقديري',
                        style: TextStyle(
                          color: scheme.onPrimary.withValues(alpha: 0.74),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        lyd(pricing.total),
                        key: const Key('cart-summary-total'),
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'جاهز للمراجعة',
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (desktop) ...[
              const SizedBox(height: 16),
              Divider(color: scheme.onPrimary.withValues(alpha: 0.2)),
              const SizedBox(height: 4),
              _CartSummaryRow(
                label: 'الإجمالي الفرعي',
                value: lyd(pricing.subtotal),
                color: scheme.onPrimary,
              ),
              if (pricing.deliveryFee > 0)
                _CartSummaryRow(
                  label: 'التوصيل التقديري',
                  value: lyd(pricing.deliveryFee),
                  color: scheme.onPrimary,
                ),
              if (pricing.handlingFee > 0)
                _CartSummaryRow(
                  label: 'المناولة التقديرية',
                  value: lyd(pricing.handlingFee),
                  color: scheme.onPrimary,
                ),
            ],
            if (!meetsMinimum) ...[
              const SizedBox(height: 10),
              Text(
                'الحد الأدنى للطلب ${lyd(minimumOrderAmount)}. '
                'أضف منتجات بقيمة تقديرية ${lyd(pricing.amountNeededForMinimum(minimumOrderAmount))} للمتابعة.',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('cart-checkout-button'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: scheme.surface,
                foregroundColor: scheme.primary,
                disabledBackgroundColor:
                    scheme.onPrimary.withValues(alpha: 0.18),
                disabledForegroundColor:
                    scheme.onPrimary.withValues(alpha: 0.48),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
                elevation: desktop ? 0 : 2,
                shadowColor: scheme.shadow.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: checkoutEnabled ? onCheckout : null,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('متابعة تأكيد الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartCheckoutBar extends StatelessWidget {
  const _CartCheckoutBar({
    required this.enabled,
    required this.onCheckout,
    this.desktop = false,
  });

  final bool enabled;
  final VoidCallback onCheckout;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset =
        desktop ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: desktop
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(24)),
        border: desktop ? Border.all(color: scheme.outlineVariant) : null,
        boxShadow: [
          if (!desktop)
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        desktop ? 20 : 16,
        desktop ? 20 : 12,
        desktop ? 20 : 16,
        (desktop ? 20 : 12) + bottomInset,
      ),
      child: FilledButton.icon(
        key: const Key('cart-checkout-button'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
          elevation: desktop ? 0 : 2,
          shadowColor: scheme.shadow.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: enabled ? onCheckout : null,
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('متابعة تأكيد الطلب'),
      ),
    );
  }
}

class _CartSummaryRow extends StatelessWidget {
  const _CartSummaryRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.76),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _CartQuantitySelector extends StatelessWidget {
  const _CartQuantitySelector({
    super.key,
    required this.quantity,
    required this.minimum,
    required this.onChanged,
    this.max,
  });

  final int quantity;
  final int minimum;
  final int? max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDecrease = quantity > minimum;
    final canIncrease = max == null || quantity < max!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CartQuantityButton(
            tooltip: 'تقليل الكمية',
            icon: Icons.remove,
            enabled: canDecrease,
            onPressed: () => onChanged(quantity - 1),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Semantics(
                label: 'الكمية الحالية: $quantity',
                child: ExcludeSemantics(
                  child: Text(
                    '$quantity',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _CartQuantityButton(
            tooltip: 'زيادة الكمية',
            icon: Icons.add,
            enabled: canIncrease,
            onPressed: () => onChanged(quantity + 1),
          ),
        ],
      ),
    );
  }
}

class _CartQuantityButton extends StatelessWidget {
  const _CartQuantityButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      iconSize: 20,
      icon: Icon(
        icon,
        color: enabled ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}
