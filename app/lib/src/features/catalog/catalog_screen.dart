import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../cart/cart_controller.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({this.initialCategory, super.key});
  final String? initialCategory;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String query = '';
  String? category;

  @override
  void initState() {
    super.initState();
    category = widget.initialCategory;
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      category = widget.initialCategory;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Object>>(
      future: Future.wait([
        ref
            .read(catalogRepositoryProvider)
            .products(query: query, category: category),
        ref.read(catalogRepositoryProvider).categories(),
      ]),
      builder: (context, snapshot) {
        final products = (snapshot.data?[0] ?? <Product>[]) as List<Product>;
        final categories = (snapshot.data?[1] ?? <String>[]) as List<String>;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('المنتجات',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'ابحث بالاسم أو SKU أو التصنيف'),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: FilterChip(
                      label: const Text('الكل'),
                      selected: category == null,
                      onSelected: (_) => setState(() => category = null)),
                ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                        label: Text(c),
                        selected: category == c,
                        onSelected: (_) => setState(() => category = c)),
                  ),
                ActionChip(
                    avatar: const Icon(Icons.tune, size: 18),
                    label: const Text('فلترة'),
                    onPressed: () {}),
              ]),
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator()),
            if (products.isEmpty &&
                snapshot.connectionState != ConnectionState.waiting)
              const EmptyState(
                  title: 'لا توجد منتجات',
                  message: 'جرّب بحثاً آخر أو اختر تصنيفاً مختلفاً.',
                  icon: Icons.search_off),
            for (final product in products) ProductListCard(product: product),
          ],
        );
      },
    );
  }
}

class ProductListCard extends ConsumerWidget {
  const ProductListCard({required this.product, super.key});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.go('/product/${product.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProductImagePlaceholder(
                category: product.category,
                productId: product.id,
                imageUrl: product.imageUrl,
                size: 86),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  Text(
                      '${product.sku} • ${product.category} • ${product.brand}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _MiniChip(
                        product.inStock
                            ? 'متوفر ${product.stockQuantity}'
                            : 'غير متوفر',
                        color: product.inStock ? AppTheme.green : AppTheme.red),
                    _MiniChip('أقل طلب ${product.minOrderQuantity}'),
                    _MiniChip(product.effectivePackageSize),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    PriceText(price: product.price, oldPrice: product.oldPrice),
                    const Spacer(),
                    IconButton.filled(
                        onPressed: product.inStock
                            ? () => ref
                                .read(cartControllerProvider.notifier)
                                .add(product)
                            : null,
                        icon: const Icon(Icons.add)),
                  ]),
                ])),
          ]),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, {this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: (color ?? Colors.grey).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color ?? Colors.grey.shade700,
                fontWeight: FontWeight.w700)),
      );
}
