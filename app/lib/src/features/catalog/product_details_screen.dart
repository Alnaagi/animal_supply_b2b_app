import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/support/whatsapp_support.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/product_info_chip.dart';
import '../../core/widgets/quantity_selector.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../cart/added_to_cart_prompt.dart';

const _wholesaleBlack = Color(0xff111111);

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
    final shopName = ref.watch(shopBrandingProvider).shopName;
    final supportPhone = settings?.supportWhatsapp.trim().isNotEmpty == true
        ? settings!.supportWhatsapp
        : AppConfig.supportWhatsapp;
    return FutureBuilder<Product?>(
      future: _productFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: _appBar(),
            body: const ShopLoading.page(),
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
        final onSupport = WhatsAppSupport.isConfiguredFor(supportPhone)
            ? () => _openProductSupport(
                  product,
                  shopName: shopName,
                  supportPhone: supportPhone,
                )
            : null;
        return Scaffold(
          appBar: _appBar(product: product),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;
              final hero = _ProductHero(
                product: product,
                height: wide
                    ? 420
                    : (constraints.maxWidth * 0.92).clamp(300.0, 380.0),
              );
              final details = _ProductDetailsCards(product: product);
              if (wide) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: hero),
                            const SizedBox(width: 24),
                            Expanded(flex: 2, child: details),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                children: [
                  hero,
                  const SizedBox(height: 14),
                  details,
                ],
              );
            },
          ),
          bottomNavigationBar: _ProductActionsBar(
            product: product,
            quantity: quantity!,
            onQuantityChanged: (value) => setState(() => quantity = value),
            onAddToCart: product.isOrderable
                ? () => addProductToCartThenPrompt(
                      context: context,
                      ref: ref,
                      product: product,
                      quantity: quantity,
                    )
                : null,
            onSupport: onSupport,
          ),
        );
      },
    );
  }
}

class _ProductHero extends StatelessWidget {
  const _ProductHero({
    required this.product,
    required this.height,
  });

  final Product product;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('product-details-image-card'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: ProductImagePlaceholder(
          key: const Key('product-details-image'),
          category: product.category,
          productId: product.id,
          imageUrl: product.imageUrl,
          semanticLabel: 'صورة ${product.name}',
          expand: true,
          fit: BoxFit.contain,
          borderRadius: BorderRadius.zero,
        ),
      ),
    );
  }
}

class _ProductDetailsCards extends StatelessWidget {
  const _ProductDetailsCards({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProductInfoCard(product: product),
        const SizedBox(height: 12),
        _ProductPriceCard(product: product),
        if (product.description.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _ProductDescriptionCard(product: product),
        ],
        if (product.imageAttribution != null) ...[
          const SizedBox(height: 8),
          Text(
            product.imageAttribution!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }
}

class _ProductInfoCard extends StatelessWidget {
  const _ProductInfoCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('product-details-info-card'),
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: .08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              product.name,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkGreen,
                    height: 1.25,
                  ),
            ),
            if (product.brand.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'الشركة: ${product.brand}',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 14),
            ProductChipWrap(spacing: 8, runSpacing: 8, children: [
              ProductInfoChip(
                product.customerAvailabilityLabel,
                color: product.isOrderable ? AppTheme.green : AppTheme.red,
              ),
              ProductInfoChip(
                'الحد الأدنى للجملة: ${product.minOrderQuantity}',
              ),
              if (product.unitsPerBoxLabel != null)
                ProductInfoChip(product.unitsPerBoxLabel!),
            ]),
            if (product.lowStock) ...[
              const SizedBox(height: 12),
              const Text(
                'تنبيه: الكمية المتوفرة منخفضة',
                style: TextStyle(
                  color: AppTheme.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductPriceCard extends StatelessWidget {
  const _ProductPriceCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('product-details-price-card'),
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: .08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'سعر الجملة',
                  key: Key('product-details-wholesale-label'),
                  style: TextStyle(
                    color: _wholesaleBlack,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
                if (product.hasProductDiscount) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff00897b),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'خصم ${(product.discountPercent!.truncate() == product.discountPercent! ? product.discountPercent!.toInt() : product.discountPercent!.toStringAsFixed(1))}٪',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  lyd(product.price),
                  key: const Key('product-details-wholesale-price'),
                  style: TextStyle(
                    color: product.hasProductDiscount
                        ? const Color(0xff00897b)
                        : _wholesaleBlack,
                    fontWeight: FontWeight.w900,
                    fontSize: 30,
                    height: 1.15,
                  ),
                ),
                if (product.hasProductDiscount)
                  Text(
                    lyd(product.effectivePrice ?? product.basePrice),
                    style: TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  )
                else if (product.oldPrice != null)
                  Text(
                    lyd(product.oldPrice!),
                    style: TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
            if (product.retailUnitPrice != null) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                key: const Key('product-details-retail-banner'),
                decoration: BoxDecoration(
                  color: const Color(0xffe7f6ee),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.green.withValues(alpha: .18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        color: AppTheme.green.withValues(alpha: .9),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'سعر بيع الوحدة المقترح للتاجر',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      Text(
                        lyd(product.retailUnitPrice!),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductDescriptionCard extends StatelessWidget {
  const _ProductDescriptionCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: .08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الوصف',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkGreen,
                  ),
            ),
            const SizedBox(height: 6),
            Text(product.description),
          ],
        ),
      ),
    );
  }
}

class _ProductActionsBar extends StatelessWidget {
  const _ProductActionsBar({
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
    return Material(
      key: const Key('product-details-actions'),
      color: Colors.white,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: .18),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (product.isOrderable) ...[
                Row(
                  children: [
                    const Text(
                      'الكمية',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    QuantitySelector(
                      key: const Key('product-details-quantity'),
                      quantity: quantity,
                      min: product.minOrderQuantity,
                      max: product.orderQuantityLimit,
                      onChanged: onQuantityChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                key: const Key('product-details-add-to-cart'),
                onPressed: onAddToCart,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(
                  product.isOrderable ? 'إضافة للسلة' : 'غير متوفر حالياً',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('product-details-whatsapp'),
                onPressed: onSupport,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: AppTheme.green,
                  side: const BorderSide(color: AppTheme.green),
                ),
                icon: const Icon(Icons.chat),
                label: Text(
                  onSupport == null
                      ? 'واتساب الدعم غير مهيأ'
                      : 'استفسر عبر واتساب',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
