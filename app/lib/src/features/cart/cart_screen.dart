import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/quantity_selector.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/order.dart';
import '../../data/repositories/admin_repository.dart';
import 'cart_controller.dart';

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
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                  color: Colors.amber.shade50,
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
                      : Colors.amber.shade50,
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
                            onPressed: () =>
                                ref.invalidate(appSettingsProvider),
                            icon: const Icon(Icons.refresh),
                          )
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (settings != null)
          _CartSummaryCard(
            pricing: pricing,
            minimumOrderAmount: minimumOrderAmount,
            meetsMinimum: meetsMinimum,
            onCheckout: () => context.go('/checkout'),
            checkoutEnabled: !maintenanceMode && meetsMinimum,
          ),
        if (settings == null)
          _CartCheckoutBar(
            enabled: false,
            onCheckout: () => context.go('/checkout'),
          ),
      ],
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سلة المشتريات',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                'راجع الكميات والأسعار التقديرية قبل تأكيد الطلب.',
                style: TextStyle(
                  color: AppTheme.darkGreen.withValues(alpha: 0.65),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'عدد الأصناف: $itemCount',
            style: const TextStyle(
              color: AppTheme.green,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductImagePlaceholder(
                  category: item.product.category,
                  productId: item.product.id,
                  imageUrl: item.product.imageUrl,
                  size: 84,
                  fit: BoxFit.contain,
                  borderRadius: BorderRadius.circular(16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      if (item.product.brand.trim().isNotEmpty)
                        Text(
                          item.product.brand,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        'سعر الجملة • أقل طلب ${item.product.minOrderQuantity}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      PriceText(price: item.product.price),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'حذف ${item.product.name} من السلة',
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.grey.shade500,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  QuantitySelector(
                    quantity: item.quantity,
                    min: item.product.minOrderQuantity,
                    max: item.product.orderQuantityLimit,
                    onChanged: onQuantityChanged,
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'إجمالي الصنف',
                        style: TextStyle(
                          color: AppTheme.darkGreen.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        lyd(item.lineTotal),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: AppTheme.darkGreen,
                        ),
                      ),
                    ],
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
  });

  final CartPricingSummary pricing;
  final double minimumOrderAmount;
  final bool meetsMinimum;
  final VoidCallback onCheckout;
  final bool checkoutEnabled;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Material(
      color: AppTheme.darkGreen,
      elevation: 6,
      shadowColor: AppTheme.darkGreen.withValues(alpha: 0.4),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 14 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SummaryRow(
              label: 'الإجمالي التقديري',
              value: lyd(pricing.total),
              emphasize: true,
            ),
            if (!meetsMinimum) ...[
              const SizedBox(height: 10),
              Text(
                'الحد الأدنى للطلب ${lyd(minimumOrderAmount)}. '
                'أضف منتجات بقيمة تقديرية ${lyd(pricing.amountNeededForMinimum(minimumOrderAmount))} للمتابعة.',
                style: const TextStyle(
                  color: Color(0xffffd4a8),
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
                backgroundColor: AppTheme.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.2),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
                elevation: 2,
                shadowColor: AppTheme.green.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: checkoutEnabled ? onCheckout : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('متابعة تأكيد الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.muted = false,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool muted;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: muted ? Colors.white.withValues(alpha: 0.82) : Colors.white,
      fontWeight: emphasize ? FontWeight.w900 : FontWeight.w600,
      fontSize: emphasize ? 18 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _CartCheckoutBar extends StatelessWidget {
  const _CartCheckoutBar({required this.enabled, required this.onCheckout});

  final bool enabled;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
      child: FilledButton.icon(
        key: const Key('cart-checkout-button'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: AppTheme.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
          elevation: 2,
          shadowColor: AppTheme.green.withValues(alpha: 0.35),
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
