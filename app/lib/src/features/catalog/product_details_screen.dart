import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/quantity_selector.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../cart/cart_controller.dart';

class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({required this.productId, super.key});
  final String productId;

  @override
  ConsumerState<ProductDetailsScreen> createState() =>
      _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  int? quantity;
  String? selectedPackage;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Product?>(
      future: ref.read(catalogRepositoryProvider).productById(widget.productId),
      builder: (context, snapshot) {
        final product = snapshot.data;
        if (product == null &&
            snapshot.connectionState != ConnectionState.waiting) {
          return const EmptyState(
              title: 'المنتج غير موجود',
              message: 'قد يكون المنتج غير متاح حالياً.');
        }
        if (product == null) {
          return const Center(child: CircularProgressIndicator());
        }
        quantity ??= product.minOrderQuantity;
        selectedPackage ??= product.packageOptions.isNotEmpty
            ? product.packageOptions.first
            : product.unitSize;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'رجوع',
              onPressed: () => context.go('/catalog'),
            ),
            title: const Text('تفاصيل المنتج'),
            actions: [
              IconButton(
                  onPressed: () {}, icon: const Icon(Icons.favorite_border)),
              IconButton(
                  onPressed: () {}, icon: const Icon(Icons.share_outlined))
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final image = Center(
                child: ProductImagePlaceholder(
                  category: product.category,
                  productId: product.id,
                  imageUrl: product.imageUrl,
                  size: constraints.maxWidth > 760 ? 320 : 210,
                ),
              );
              final details = _ProductInfo(
                product: product,
                quantity: quantity!,
                selectedPackage: selectedPackage!,
                onPackageSelected: (value) =>
                    setState(() => selectedPackage = value),
                onQuantityChanged: (value) => setState(() => quantity = value),
                onAddToCart: product.inStock
                    ? () {
                        ref
                            .read(cartControllerProvider.notifier)
                            .addQuantity(product, quantity!);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('تمت إضافة المنتج للسلة')));
                      }
                    : null,
              );
              if (constraints.maxWidth > 760) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: image))),
                              const SizedBox(width: 24),
                              Expanded(flex: 2, child: details),
                            ]),
                      ],
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [image, const SizedBox(height: 18), details],
              );
            },
          ),
        );
      },
    );
  }
}

class _ProductInfo extends StatelessWidget {
  const _ProductInfo({
    required this.product,
    required this.quantity,
    required this.selectedPackage,
    required this.onPackageSelected,
    required this.onQuantityChanged,
    required this.onAddToCart,
  });

  final Product product;
  final int quantity;
  final String selectedPackage;
  final ValueChanged<String> onPackageSelected;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(product.name,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text('المورّد: ${product.brand} • تقييم تجريبي 4.8',
          style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 12),
      PriceText(price: product.price, oldPrice: product.oldPrice),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Chip(label: Text('SKU: ${product.sku}')),
        Chip(label: Text('المتوفر: ${product.stockQuantity}')),
        Chip(label: Text('أقل طلب: ${product.minOrderQuantity}')),
        Chip(label: Text(product.effectivePackageSize)),
      ]),
      if (product.lowStock) ...[
        const SizedBox(height: 10),
        const Text('تنبيه: الكمية المتوفرة منخفضة',
            style:
                TextStyle(color: AppTheme.orange, fontWeight: FontWeight.bold)),
      ],
      const SizedBox(height: 18),
      Text('خيارات العبوة',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          children: (product.packageOptions.isEmpty
                  ? [product.unitSize]
                  : product.packageOptions)
              .map((option) {
            return ChoiceChip(
                label: Text(option),
                selected: selectedPackage == option,
                onSelected: (_) => onPackageSelected(option));
          }).toList()),
      const SizedBox(height: 18),
      Text('الوصف',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text(product.description),
      if (product.imageAttribution != null) ...[
        const SizedBox(height: 8),
        Text(product.imageAttribution!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey)),
      ],
      const SizedBox(height: 18),
      Row(children: [
        const Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        QuantitySelector(
            quantity: quantity,
            min: product.minOrderQuantity,
            max: product.stockQuantity,
            onChanged: onQuantityChanged),
      ]),
      const SizedBox(height: 18),
      FilledButton.icon(
          onPressed: onAddToCart,
          icon: const Icon(Icons.add_shopping_cart),
          label: Text(product.inStock ? 'إضافة للسلة' : 'غير متوفر')),
      OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.chat),
          label: const Text('اطلب عبر واتساب')),
    ]);
  }
}
