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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('السلة',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        for (final item in items)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                ProductImagePlaceholder(
                    category: item.product.category,
                    productId: item.product.id,
                    imageUrl: item.product.imageUrl,
                    size: 76),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(item.product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      if (item.product.brand.trim().isNotEmpty)
                        Text(
                          item.product.brand,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      Text(
                        'سعر الجملة • أقل طلب ${item.product.minOrderQuantity}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      PriceText(price: item.product.price),
                      QuantitySelector(
                        quantity: item.quantity,
                        min: item.product.minOrderQuantity,
                        max: item.product.orderQuantityLimit,
                        onChanged: (qty) => ref
                            .read(cartControllerProvider.notifier)
                            .updateQty(item.product.id, qty),
                      ),
                    ])),
                IconButton(
                    tooltip: 'حذف ${item.product.name} من السلة',
                    onPressed: () => ref
                        .read(cartControllerProvider.notifier)
                        .remove(item.product.id),
                    icon:
                        const Icon(Icons.delete_outline, color: AppTheme.red)),
              ]),
            ),
          ),
        if (settings != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _TotalRow(
                    label: 'الإجمالي الفرعي التقديري',
                    value: lyd(pricing.subtotal)),
                if (pricing.deliveryFee > 0)
                  _TotalRow(
                      label: 'توصيل تقديري', value: lyd(pricing.deliveryFee)),
                if (pricing.handlingFee > 0)
                  _TotalRow(
                      label: 'مناولة تقديرية', value: lyd(pricing.handlingFee)),
                const Divider(),
                _TotalRow(
                    label: 'الإجمالي التقديري',
                    value: lyd(pricing.total),
                    bold: true),
                const SizedBox(height: 8),
                const Text(
                  'يعتمد الخادم السعر النهائي حسب حسابك والمخزون ورسوم التوصيل، وسيظهر قبل تأكيد نجاح الطلب.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                if (!meetsMinimum) ...[
                  const SizedBox(height: 10),
                  Text(
                    'الحد الأدنى للطلب ${lyd(minimumOrderAmount)}. '
                    'أضف منتجات بقيمة تقديرية ${lyd(pricing.amountNeededForMinimum(minimumOrderAmount))} للمتابعة.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ]),
            ),
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
                      onPressed: () => ref.invalidate(appSettingsProvider),
                      icon: const Icon(Icons.refresh),
                    )
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
            key: const Key('cart-checkout-button'),
            onPressed: settings != null && !maintenanceMode && meetsMinimum
                ? () => context.go('/checkout')
                : null,
            child: const Text('متابعة تأكيد الطلب')),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w900 : FontWeight.normal)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w900 : FontWeight.normal)),
        ]),
      );
}
