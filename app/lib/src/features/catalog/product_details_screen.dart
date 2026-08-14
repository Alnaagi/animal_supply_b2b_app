import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/support/whatsapp_support.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/quantity_selector.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
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
  late Future<Product?> _productFuture;

  @override
  void initState() {
    super.initState();
    _productFuture = _loadProduct();
  }

  @override
  void didUpdateWidget(covariant ProductDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      quantity = null;
      _productFuture = _loadProduct();
    }
  }

  Future<Product?> _loadProduct() =>
      ref.read(catalogRepositoryProvider).productById(widget.productId);

  void _retryProduct() {
    setState(() {
      _productFuture = _loadProduct();
    });
  }

  AppBar _appBar({Product? product}) => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/catalog'),
        ),
        title: const Text('تفاصيل المنتج'),
        actions: [
          if (product != null)
            IconButton(
              tooltip: 'نسخ بيانات المنتج',
              onPressed: () => _copyProductSummary(product),
              icon: const Icon(Icons.share_outlined),
            ),
        ],
      );

  Future<void> _copyProductSummary(Product product) async {
    final summary = [
      product.name,
      if (product.brand.trim().isNotEmpty) 'الشركة: ${product.brand}',
      '${AppConfig.isDemoMode ? 'سعر الجملة التجريبي' : 'سعر الجملة'}: '
          '${product.price.toStringAsFixed(2)} LYD',
      if (product.retailUnitPrice != null)
        'سعر بيع الوحدة المقترح: '
            '${product.retailUnitPrice!.toStringAsFixed(2)} LYD',
      'الحد الأدنى لطلب الجملة: ${product.minOrderQuantity}',
      if (product.unitsPerBoxLabel != null) product.unitsPerBoxLabel!,
      product.isOrderable ? 'متوفر للطلب' : 'غير متوفر حالياً',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: summary));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ بيانات المنتج')),
    );
  }

  Future<void> _openProductSupport(
    Product product, {
    required String shopName,
    required String supportPhone,
  }) async {
    final opened = await WhatsAppSupport.openMessage(
      'مرحباً، أريد الاستفسار عن ${product.name} '
      'من ${product.brand} في $shopName.',
      phone: supportPhone,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب حالياً')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).asData?.value;
    final shopName = settings?.shopName.trim().isNotEmpty == true
        ? settings!.shopName.trim()
        : AppConfig.shopName;
    final supportPhone = settings?.supportWhatsapp.trim().isNotEmpty == true
        ? settings!.supportWhatsapp
        : AppConfig.supportWhatsapp;
    return FutureBuilder<Product?>(
      future: _productFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: _appBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: _appBar(),
            body: EmptyState(
              key: const Key('product-details-load-error'),
              title: 'تعذر تحميل تفاصيل المنتج',
              message:
                  'تعذر الوصول إلى بيانات هذا المنتج. تحقق من الاتصال بالخادم ثم أعد المحاولة.',
              icon: Icons.cloud_off_outlined,
              action: FilledButton.icon(
                key: const Key('product-details-retry-button'),
                onPressed: _retryProduct,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ),
          );
        }
        final product = snapshot.data;
        if (product == null) {
          return Scaffold(
            appBar: _appBar(),
            body: const EmptyState(
              title: 'المنتج غير موجود',
              message: 'قد يكون المنتج محذوفاً أو غير متاح حالياً.',
              icon: Icons.inventory_2_outlined,
            ),
          );
        }
        quantity ??= product.minOrderQuantity;
        return Scaffold(
          appBar: _appBar(product: product),
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
                onQuantityChanged: (value) => setState(() => quantity = value),
                onAddToCart: product.isOrderable
                    ? () {
                        ref
                            .read(cartControllerProvider.notifier)
                            .addQuantity(product, quantity!);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('تمت إضافة المنتج للسلة')));
                      }
                    : null,
                onSupport: WhatsAppSupport.isConfiguredFor(supportPhone)
                    ? () => _openProductSupport(
                          product,
                          shopName: shopName,
                          supportPhone: supportPhone,
                        )
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
    required this.onQuantityChanged,
    required this.onAddToCart,
    required this.onSupport,
  });

  final Product product;
  final int quantity;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback? onAddToCart;
  final VoidCallback? onSupport;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(product.name,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      if (product.brand.trim().isNotEmpty)
        Text(
          'الشركة: ${product.brand}',
          style: const TextStyle(color: Colors.grey),
        ),
      const SizedBox(height: 12),
      Text(
        'سعر الجملة',
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      PriceText(price: product.price),
      if (product.retailUnitPrice != null) ...[
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'سعر بيع الوحدة المقترح للتاجر',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${product.retailUnitPrice!.toStringAsFixed(2)} د.ل',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Chip(
          label: Text(product.customerAvailabilityLabel),
        ),
        Chip(
          label: Text(
            'الحد الأدنى للجملة: ${product.minOrderQuantity}',
          ),
        ),
        if (product.unitsPerBoxLabel != null)
          Chip(label: Text(product.unitsPerBoxLabel!)),
      ]),
      if (product.lowStock) ...[
        const SizedBox(height: 10),
        const Text('تنبيه: الكمية المتوفرة منخفضة',
            style:
                TextStyle(color: AppTheme.orange, fontWeight: FontWeight.bold)),
      ],
      if (product.description.trim().isNotEmpty) ...[
        const SizedBox(height: 18),
        Text(
          'الوصف',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(product.description),
      ],
      if (product.imageAttribution != null) ...[
        const SizedBox(height: 8),
        Text(product.imageAttribution!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey)),
      ],
      if (product.isOrderable) ...[
        const SizedBox(height: 18),
        Row(children: [
          const Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          QuantitySelector(
              quantity: quantity,
              min: product.minOrderQuantity,
              max: product.orderQuantityLimit,
              onChanged: onQuantityChanged),
        ]),
      ],
      const SizedBox(height: 18),
      FilledButton.icon(
          onPressed: onAddToCart,
          icon: const Icon(Icons.add_shopping_cart),
          label:
              Text(product.isOrderable ? 'إضافة للسلة' : 'غير متوفر حالياً')),
      OutlinedButton.icon(
          onPressed: onSupport,
          icon: const Icon(Icons.chat),
          label: Text(onSupport == null
              ? 'واتساب الدعم غير مهيأ'
              : 'استفسر عبر واتساب')),
    ]);
  }
}
