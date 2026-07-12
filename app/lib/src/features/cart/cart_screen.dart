import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/quantity_selector.dart';
import 'cart_controller.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartControllerProvider);
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.total);
    final handling = items.isEmpty ? 0.0 : 10.0;
    final total = subtotal + handling;
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
                      Text(item.product.sku,
                          style: const TextStyle(color: Colors.grey)),
                      PriceText(price: item.product.price),
                      QuantitySelector(
                        quantity: item.quantity,
                        min: item.product.minOrderQuantity,
                        max: item.product.stockQuantity,
                        onChanged: (qty) => ref
                            .read(cartControllerProvider.notifier)
                            .updateQty(item.product.id, qty),
                      ),
                    ])),
                IconButton(
                    onPressed: () => ref
                        .read(cartControllerProvider.notifier)
                        .remove(item.product.id),
                    icon:
                        const Icon(Icons.delete_outline, color: AppTheme.red)),
              ]),
            ),
          ),
        TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.local_offer_outlined),
                labelText: 'كود خصم اختياري'),
            onChanged: (_) {}),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _TotalRow(label: 'الإجمالي الفرعي', value: lyd(subtotal)),
              _TotalRow(label: 'توصيل/مناولة تقديرية', value: lyd(handling)),
              const Divider(),
              _TotalRow(label: 'الإجمالي', value: lyd(total), bold: true),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: () => context.go('/checkout'),
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
