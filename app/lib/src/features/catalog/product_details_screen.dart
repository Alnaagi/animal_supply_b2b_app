import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/support/whatsapp_support.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/customer_product_summary.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/quantity_selector.dart';
import '../../core/widgets/shop_skeleton.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../cart/added_to_cart_prompt.dart';

const _productDesktopBreakpoint = AppBreakpoints.expanded;
const _productPageMaxWidth = 1240.0;
const _productPurchasePanelWidth = 352.0;

class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({required this.productId, super.key});
  final String productId;

  @override
  ConsumerState<ProductDetailsScreen> createState() =>
      _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  int? quantity;
  int _productLoadGeneration = 0;
  late Future<Product?> _productFuture;
  Future<List<Product>>? _relatedProductsFuture;

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
      _relatedProductsFuture = null;
      _productFuture = _loadProduct();
    }
  }

  Future<Product?> _loadProduct() async {
    final loadGeneration = ++_productLoadGeneration;
    final requestedProductId = widget.productId;
    final product = await ref
        .read(catalogRepositoryProvider)
        .productById(requestedProductId);
    if (!mounted ||
        loadGeneration != _productLoadGeneration ||
        requestedProductId != widget.productId) {
      return product;
    }
    _relatedProductsFuture =
        product == null ? null : _loadRelatedProducts(product);
    return product;
  }

  Future<List<Product>> _loadRelatedProducts(Product product) async {
    final products = await ref.read(catalogRepositoryProvider).products();
    final candidatesById = <String, Product>{};
    for (final candidate in products) {
      if (candidate.id == product.id ||
          !candidate.active ||
          candidate.isArchived) {
        continue;
      }
      candidatesById.putIfAbsent(candidate.id, () => candidate);
    }

    final sameCategory = <Product>[];
    final fallback = <Product>[];
    for (final candidate in candidatesById.values) {
      if (_sameRelatedValue(candidate.category, product.category)) {
        sameCategory.add(candidate);
      } else {
        fallback.add(candidate);
      }
    }
    sameCategory.sort((a, b) => _compareRelatedProducts(a, b, product));
    fallback.sort((a, b) => _compareRelatedProducts(a, b, product));

    final related = <Product>[...sameCategory.take(8)];
    if (related.length < 8) {
      related.addAll(fallback.take(8 - related.length));
    }
    return related;
  }

  int _compareRelatedProducts(
    Product first,
    Product second,
    Product product,
  ) {
    final byRelevance = _relatedProductScore(second, product)
        .compareTo(_relatedProductScore(first, product));
    if (byRelevance != 0) return byRelevance;
    final byName = first.name.trim().toLowerCase().compareTo(
          second.name.trim().toLowerCase(),
        );
    if (byName != 0) return byName;
    return first.id.compareTo(second.id);
  }

  int _relatedProductScore(Product candidate, Product product) {
    var score = 0;
    if (_sameRelatedValue(candidate.animalType, product.animalType)) {
      score += 16;
    }
    if (_sameRelatedValue(candidate.brand, product.brand)) score += 8;
    if (candidate.isFeatured) score += 4;
    if (candidate.isTopSelling) score += 2;
    if (candidate.isOrderable) score += 1;
    return score;
  }

  bool _sameRelatedValue(String first, String second) {
    final normalizedFirst = first.trim().toLowerCase();
    final normalizedSecond = second.trim().toLowerCase();
    return normalizedFirst.isNotEmpty && normalizedFirst == normalizedSecond;
  }

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
        '${CustomerProductCardCopy.retail}: '
            '${product.retailUnitPrice!.toStringAsFixed(2)} LYD',
      'الحد الأدنى لطلب الجملة: ${product.minOrderQuantity}',
      if (product.unitsPerBoxLabel != null) product.unitsPerBoxLabel!,
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
    final desktop =
        MediaQuery.sizeOf(context).width >= _productDesktopBreakpoint;
    final supportPhone = settings?.supportWhatsapp.trim().isNotEmpty == true
        ? settings!.supportWhatsapp
        : AppConfig.supportWhatsapp;
    return FutureBuilder<Product?>(
      future: _productFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ShopSkeleton(
            semanticLabel: 'جارٍ تحميل تفاصيل المنتج',
            child: Scaffold(
              appBar: _appBar(),
              body: _ProductDetailsSkeleton(desktop: desktop),
              bottomNavigationBar:
                  desktop ? null : const _ProductActionsSkeleton(),
            ),
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
        final onAddToCart = product.isOrderable
            ? () => addProductToCartThenPrompt(
                  context: context,
                  ref: ref,
                  product: product,
                  quantity: quantity,
                )
            : null;
        return Scaffold(
          appBar: _appBar(product: product),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= _productDesktopBreakpoint;
              if (desktop) {
                return _DesktopProductDetailsLayout(
                  product: product,
                  quantity: quantity!,
                  relatedProductsFuture: _relatedProductsFuture!,
                  onQuantityChanged: (value) =>
                      setState(() => quantity = value),
                  onAddToCart: onAddToCart,
                  onSupport: onSupport,
                );
              }
              final wideOverview = constraints.maxWidth >= 760;
              final overview = _ProductOverviewCard(
                product: product,
                imageHeight: wideOverview
                    ? 420
                    : (constraints.maxHeight * .26).clamp(180.0, 200.0),
                wide: wideOverview,
                includePrice: true,
              );
              final details = _ProductDetailsCards(
                product: product,
                compact: !wideOverview,
                desktop: false,
                relatedProductsFuture: _relatedProductsFuture!,
              );
              if (wideOverview) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      children: [
                        overview,
                        details,
                      ],
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  overview,
                  details,
                ],
              );
            },
          ),
          bottomNavigationBar: desktop
              ? null
              : _ProductActionsBar(
                  product: product,
                  quantity: quantity!,
                  onQuantityChanged: (value) =>
                      setState(() => quantity = value),
                  onAddToCart: onAddToCart,
                  onSupport: onSupport,
                ),
        );
      },
    );
  }
}

class _DesktopProductDetailsLayout extends StatelessWidget {
  const _DesktopProductDetailsLayout({
    required this.product,
    required this.quantity,
    required this.relatedProductsFuture,
    required this.onQuantityChanged,
    required this.onAddToCart,
    required this.onSupport,
  });

  final Product product;
  final int quantity;
  final Future<List<Product>> relatedProductsFuture;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback? onAddToCart;
  final VoidCallback? onSupport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _productPageMaxWidth),
        child: SingleChildScrollView(
          key: const Key('product-details-desktop-scroll'),
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
          child: Row(
            key: const Key('product-details-desktop-layout'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _productPurchasePanelWidth,
                child: _ProductPurchasePanel(
                  product: product,
                  quantity: quantity,
                  onQuantityChanged: onQuantityChanged,
                  onAddToCart: onAddToCart,
                  onSupport: onSupport,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, mainConstraints) {
                    final splitOverview = mainConstraints.maxWidth >= 760;
                    return Column(
                      key: const Key('product-details-main-column'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProductOverviewCard(
                          product: product,
                          imageHeight: splitOverview ? 420 : 340,
                          wide: splitOverview,
                          includePrice: false,
                        ),
                        _ProductDetailsCards(
                          product: product,
                          compact: !splitOverview,
                          desktop: true,
                          relatedProductsFuture: relatedProductsFuture,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductDetailsSkeleton extends StatelessWidget {
  const _ProductDetailsSkeleton({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('product-details-skeleton'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget buildOverview({
            required bool split,
            required bool includePrice,
            required double imageHeight,
          }) {
            final image = ShopSkeletonBox(
              key: const Key('product-details-skeleton-image'),
              width: double.infinity,
              height: imageHeight,
              borderRadius: 0,
            );
            final details = _ProductDetailsSkeletonCards(
              compact: !split,
              includePrice: includePrice,
            );
            return DecoratedBox(
              key: const Key('product-details-skeleton-overview'),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.hero),
                border: Border.all(color: scheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: .06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.hero),
                child: split
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 380, child: image),
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: BorderDirectional(
                                  start: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              ),
                              child: details,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          image,
                          Divider(
                            height: 1,
                            color: scheme.outlineVariant,
                          ),
                          details,
                        ],
                      ),
              ),
            );
          }

          if (desktop) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _productPageMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: _productPurchasePanelWidth,
                        child: _ProductPurchasePanelSkeleton(),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, mainConstraints) {
                            final split = mainConstraints.maxWidth >= 760;
                            return buildOverview(
                              split: split,
                              includePrice: false,
                              imageHeight: split ? 420 : 340,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final wide = constraints.maxWidth >= 760;
          final overview = buildOverview(
            split: wide,
            includePrice: true,
            imageHeight:
                wide ? 420 : (constraints.maxHeight * .26).clamp(180.0, 200.0),
          );
          if (wide) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  children: [
                    overview,
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              overview,
            ],
          );
        },
      ),
    );
  }
}

class _ProductDetailsSkeletonCards extends StatelessWidget {
  const _ProductDetailsSkeletonCards({
    required this.compact,
    this.includePrice = true,
  });

  final bool compact;
  final bool includePrice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: const Key('product-details-skeleton-info'),
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 22,
            compact ? 10 : 22,
            compact ? 16 : 22,
            compact ? 10 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShopSkeletonBox(width: 116, height: 26, borderRadius: 999),
                  ShopSkeletonBox(width: 92, height: 26, borderRadius: 999),
                ],
              ),
              SizedBox(height: compact ? 6 : 14),
              const _ProductSkeletonLine(widthFactor: .92, height: 24),
              SizedBox(height: compact ? 4 : 6),
              _ProductSkeletonLine(
                widthFactor: .62,
                height: compact ? 18 : 24,
              ),
              SizedBox(height: compact ? 8 : 18),
              const _ProductSkeletonLine(widthFactor: .38, height: 14),
              SizedBox(height: compact ? 6 : 8),
              Row(
                children: [
                  Expanded(
                    child: ShopSkeletonBox(
                      height: compact ? 58 : 62,
                      borderRadius: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ShopSkeletonBox(
                      height: compact ? 58 : 62,
                      borderRadius: 14,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 6 : 8),
              Row(
                children: [
                  Expanded(
                    child: ShopSkeletonBox(
                      height: compact ? 58 : 62,
                      borderRadius: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ShopSkeletonBox(
                      height: compact ? 58 : 62,
                      borderRadius: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (includePrice) ...[
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            key: const Key('product-details-skeleton-price'),
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 22,
              compact ? 8 : 20,
              compact ? 16 : 22,
              compact ? 8 : 20,
            ),
            child: compact
                ? const Row(
                    children: [
                      Expanded(
                        child: ShopSkeletonBox(height: 56, borderRadius: 12),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: ShopSkeletonBox(height: 56, borderRadius: 12),
                      ),
                    ],
                  )
                : const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShopSkeletonBox(width: 88, height: 18),
                                SizedBox(height: 5),
                                ShopSkeletonBox(width: 130, height: 12),
                              ],
                            ),
                          ),
                          ShopSkeletonBox(width: 132, height: 36),
                        ],
                      ),
                      SizedBox(height: 16),
                      ShopSkeletonBox(height: 54, borderRadius: 16),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

class _ProductPurchasePanelSkeleton extends StatelessWidget {
  const _ProductPurchasePanelSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('product-details-desktop-purchase-skeleton'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                ShopSkeletonBox(width: 44, height: 44, borderRadius: 14),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShopSkeletonBox(width: 150, height: 18),
                      SizedBox(height: 6),
                      ShopSkeletonBox(width: 112, height: 12),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(height: 1, color: scheme.outlineVariant),
            ),
            const Column(
              key: Key('product-details-skeleton-price'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShopSkeletonBox(width: 96, height: 16),
                SizedBox(height: 8),
                ShopSkeletonBox(width: 176, height: 36),
                SizedBox(height: 14),
                ShopSkeletonBox(height: 62, borderRadius: 16),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(height: 1, color: scheme.outlineVariant),
            ),
            const ShopSkeletonBox(height: 44, borderRadius: 22),
            const SizedBox(height: 12),
            const ShopSkeletonBox(height: 52, borderRadius: 16),
            const SizedBox(height: 10),
            const ShopSkeletonBox(height: 48, borderRadius: 16),
          ],
        ),
      ),
    );
  }
}

class _ProductSkeletonLine extends StatelessWidget {
  const _ProductSkeletonLine({
    required this.widthFactor,
    required this.height,
  });

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: ShopSkeletonBox(height: height, borderRadius: height / 2),
    );
  }
}

class _ProductActionsSkeleton extends StatelessWidget {
  const _ProductActionsSkeleton();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('product-details-skeleton-actions'),
      color: scheme.surface,
      elevation: 16,
      shadowColor: scheme.shadow.withValues(alpha: .18),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            compact ? 8 : 12,
            16,
            compact ? 8 : 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact)
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 104,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShopSkeletonBox(width: 42, height: 10),
                          SizedBox(height: 5),
                          ShopSkeletonBox(
                            height: 44,
                            borderRadius: 22,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ShopSkeletonBox(height: 48, borderRadius: 14),
                    ),
                  ],
                )
              else ...[
                const Row(
                  children: [
                    ShopSkeletonBox(width: 54, height: 14),
                    Spacer(),
                    ShopSkeletonBox(
                      width: 132,
                      height: 44,
                      borderRadius: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const ShopSkeletonBox(height: 52, borderRadius: 14),
              ],
              SizedBox(height: compact ? 6 : 8),
              ShopSkeletonBox(
                height: compact ? 44 : 48,
                borderRadius: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductOverviewCard extends StatelessWidget {
  const _ProductOverviewCard({
    required this.product,
    required this.imageHeight,
    required this.wide,
    required this.includePrice,
  });

  final Product product;
  final double imageHeight;
  final bool wide;
  final bool includePrice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = _ProductHero(product: product, height: imageHeight);
    final details = _ProductOverviewDetails(
      product: product,
      compact: !wide,
      includePrice: includePrice,
    );
    return Card(
      key: const Key('product-details-overview-card'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      surfaceTintColor: scheme.surfaceTint.withValues(alpha: 0),
      elevation: 2,
      shadowColor: scheme.shadow.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.hero),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 380, child: image),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: details,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                image,
                Divider(
                  height: 1,
                  color: scheme.outlineVariant,
                ),
                details,
              ],
            ),
    );
  }
}

class _ProductOverviewDetails extends StatelessWidget {
  const _ProductOverviewDetails({
    required this.product,
    required this.compact,
    required this.includePrice,
  });

  final Product product;
  final bool compact;
  final bool includePrice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProductInfoCard(product: product, compact: compact),
        if (includePrice) ...[
          Divider(
            height: 1,
            indent: compact ? 16 : 22,
            endIndent: compact ? 16 : 22,
            color: scheme.outlineVariant,
          ),
          _ProductPriceCard(product: product, compact: compact),
        ],
      ],
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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('product-details-image-card'),
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProductImagePlaceholder(
            key: const Key('product-details-image'),
            category: product.category,
            productId: product.id,
            imageUrl: product.imageUrl,
            semanticLabel: 'صورة ${product.name}',
            expand: true,
            fit: BoxFit.contain,
            backgroundColor: scheme.surface,
            borderRadius: BorderRadius.zero,
          ),
        ],
      ),
    );
  }
}

class _ProductDetailsCards extends StatelessWidget {
  const _ProductDetailsCards({
    required this.product,
    required this.compact,
    required this.desktop,
    required this.relatedProductsFuture,
  });

  final Product product;
  final bool compact;
  final bool desktop;
  final Future<List<Product>> relatedProductsFuture;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (product.description.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: compact ? 12 : 16),
            child: _ProductDescriptionCard(
              product: product,
              compact: compact,
            ),
          ),
        FutureBuilder<List<Product>>(
          future: relatedProductsFuture,
          builder: (context, snapshot) {
            final related = snapshot.data;
            if (related == null || related.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(top: compact ? 20 : 24),
              child: _RelatedProductsSection(
                products: related,
                desktop: desktop,
              ),
            );
          },
        ),
        if (product.imageAttribution != null) ...[
          const SizedBox(height: 8),
          Text(
            product.imageAttribution!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class _ProductInfoCard extends StatelessWidget {
  const _ProductInfoCard({required this.product, required this.compact});

  final Product product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brand = product.brand.trim();
    final category = product.category.trim();
    final animalType = product.animalType.trim();
    return Padding(
      key: const Key('product-details-info-card'),
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 22,
        compact ? 10 : 22,
        compact ? 16 : 22,
        compact ? 10 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            product.name,
            maxLines: compact ? 2 : 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                  fontSize: compact ? 20 : null,
                  height: compact ? 1.18 : 1.28,
                ),
          ),
          SizedBox(height: compact ? 6 : 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (brand.isNotEmpty)
                _ProductMetaTag(
                  icon: Icons.storefront_outlined,
                  label: 'الشركة',
                  value: brand,
                ),
              if (category.isNotEmpty)
                _ProductMetaTag(
                  icon: Icons.category_outlined,
                  label: 'التصنيف',
                  value: category,
                ),
              if (animalType.isNotEmpty && animalType != category)
                _ProductMetaTag(
                  icon: Icons.pets_outlined,
                  label: 'مخصص لـ',
                  value: animalType,
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    Icons.fact_check_outlined,
                    size: 16,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تفاصيل الشراء والتعبئة',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: compact ? 13.5 : null,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      compact
                          ? 'الحد الأدنى، وحدة الطلب، ومحتوى العبوة.'
                          : 'راجع وحدة الطلب والحد الأدنى ومحتوى العبوة قبل الإضافة للسلة.',
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: compact ? 1.25 : 1.4,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 10),
          _ProductFactsPanel(product: product),
          if (product.lowStock) ...[
            SizedBox(height: compact ? 10 : 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'تنبيه: الكمية المتوفرة منخفضة',
                        style: TextStyle(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductMetaTag extends StatelessWidget {
  const _ProductMetaTag({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onPrimaryContainer),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '$label: $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductFactsPanel extends StatelessWidget {
  const _ProductFactsPanel({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final hasCarton = product.hasUnitsPerBox;
    final minimumOrderUnit = hasCarton
        ? (product.minOrderQuantity == 1 ? 'صندوق' : 'صناديق')
        : (product.minOrderQuantity == 1 ? 'وحدة طلب' : 'وحدات طلب');
    final minimumPieces =
        hasCarton ? product.minOrderQuantity * product.unitsPerBox! : null;
    final packageSize = product.packageSize?.trim() ?? '';
    final unitSize = product.unitSize.trim();
    final facts = <Widget>[
      _ProductFact(
        icon: Icons.shopping_cart_checkout_rounded,
        label: 'الحد الأدنى القابل للطلب',
        value: '${product.minOrderQuantity} $minimumOrderUnit',
        detail:
            minimumPieces == null ? null : 'يعادل $minimumPieces قطعة إجمالاً',
      ),
      if (hasCarton)
        _ProductFact(
          icon: Icons.inventory_2_outlined,
          label: 'محتوى كل صندوق',
          value: '${product.unitsPerBox!} قطعة',
          detail: 'وحدة الطلب: صندوق كامل',
        ),
      if (packageSize.isNotEmpty)
        _ProductFact(
          icon: Icons.all_inbox_outlined,
          label: 'تعبئة المنتج',
          value: packageSize,
        ),
      if (unitSize.isNotEmpty && unitSize != packageSize)
        _ProductFact(
          icon: Icons.scale_outlined,
          label: packageSize.isEmpty ? 'حجم العبوة' : 'حجم الوحدة',
          value: unitSize,
        ),
      if (product.sku.trim().isNotEmpty)
        _ProductFact(
          icon: Icons.qr_code_2_rounded,
          label: 'رمز المنتج',
          value: product.sku,
          valueTextDirection: TextDirection.ltr,
        ),
    ];
    return DecoratedBox(
      key: const Key('product-details-purchase-facts'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth >= 260 && textScale <= 1.2 ? 2 : 1;
          const gap = 1.0;
          final width = columns == 2
              ? (constraints.maxWidth - gap) / 2
              : constraints.maxWidth;
          return ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.medium),
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final fact in facts)
                  SizedBox(
                    width: width,
                    child: ColoredBox(
                      color: scheme.surface,
                      child: fact,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProductFact extends StatelessWidget {
  const _ProductFact({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.valueTextDirection,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final TextDirection? valueTextDirection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 58),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SizedBox.square(
                dimension: 28,
                child: Icon(
                  icon,
                  size: 16,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Directionality(
                    textDirection:
                        valueTextDirection ?? Directionality.of(context),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (detail case final detail?) ...[
                    const SizedBox(height: 1),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPriceCard extends StatelessWidget {
  const _ProductPriceCard({required this.product, required this.compact});

  final Product product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final comparisonPrice = product.hasProductDiscount
        ? product.effectivePrice ?? product.basePrice
        : product.oldPrice;
    if (compact) {
      return _CompactProductPriceBand(
        product: product,
        comparisonPrice: comparisonPrice,
      );
    }
    return Padding(
      key: const Key('product-details-price-card'),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سعر الجملة',
                      key: const Key('product-details-wholesale-label'),
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'سعر شراء التاجر',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (product.hasProductDiscount) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            child: Text(
                              'خصم ${(product.discountPercent!.truncate() == product.discountPercent! ? product.discountPercent!.toInt() : product.discountPercent!.toStringAsFixed(1))}٪',
                              style: TextStyle(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        lyd(product.price),
                        key: const Key('product-details-wholesale-price'),
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 38,
                          height: 1.1,
                        ),
                      ),
                    ),
                    if (comparisonPrice != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        lyd(comparisonPrice),
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (product.retailUnitPrice != null) ...[
            const SizedBox(height: 16),
            DecoratedBox(
              key: const Key('product-details-retail-banner'),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .58),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.trending_up_rounded,
                          size: 18,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            CustomerProductCardCopy.retail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: scheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            CustomerProductCardCopy.retailUnitHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          lyd(product.retailUnitPrice!),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactProductPriceBand extends StatelessWidget {
  const _CompactProductPriceBand({
    required this.product,
    required this.comparisonPrice,
  });

  final Product product;
  final double? comparisonPrice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final retailPrice = product.retailUnitPrice;
    final discountLabel = product.hasProductDiscount
        ? '${product.discountPercent!.toStringAsFixed(0)}٪ خصم'
        : null;
    return Padding(
      key: const Key('product-details-price-card'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'سعر الجملة',
                        key: const Key('product-details-wholesale-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 12,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (discountLabel != null)
                      Text(
                        discountLabel,
                        style: TextStyle(
                          color: scheme.tertiary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    lyd(product.price),
                    key: const Key('product-details-wholesale-price'),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 23,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (comparisonPrice != null)
                  Text(
                    lyd(comparisonPrice!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  'سعر شراء التاجر',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (retailPrice != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 1,
                height: 54,
                child: ColoredBox(color: scheme.outlineVariant),
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: const Key('product-details-retail-banner'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CustomerProductCardCopy.retail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        lyd(retailPrice),
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 20,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      CustomerProductCardCopy.retailUnitHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 9.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RelatedProductsSection extends StatelessWidget {
  const _RelatedProductsSection({
    required this.products,
    required this.desktop,
  });

  final List<Product> products;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight = 236.0 + ((textScale - 1).clamp(0, 1) * 44);
    return Column(
      key: const Key('product-details-related-products'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DecoratedBox(
              key: const Key('product-details-related-icon'),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.widgets_rounded,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'منتجات ذات صلة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/catalog'),
              child: const Text('عرض الكل'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (desktop)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 4 : 3;
              const gap = 14.0;
              final width =
                  (constraints.maxWidth - (gap * (columns - 1))) / columns;
              return Wrap(
                key: const Key('product-details-related-grid'),
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final product in products)
                    SizedBox(
                      width: width,
                      height: cardHeight,
                      child: _RelatedProductCard(product: product),
                    ),
                ],
              );
            },
          )
        else
          SizedBox(
            key: const Key('product-details-related-list'),
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(start: 2, end: 6),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: 160,
                child: _RelatedProductCard(product: products[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _RelatedProductCard extends ConsumerWidget {
  const _RelatedProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final openLabel = 'فتح تفاصيل ${product.name}';
    final addLabel = 'إضافة ${product.name} إلى السلة';
    return Card(
      key: Key('related-product-card-${product.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: scheme.shadow.withValues(alpha: .08),
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProductImagePlaceholder(
                        category: product.category,
                        productId: product.id,
                        imageUrl: product.imageUrl,
                        semanticLabel: 'صورة ${product.name}',
                        expand: true,
                        backgroundColor: scheme.surface,
                        borderRadius: BorderRadius.zero,
                      ),
                      if (product.hasProductDiscount)
                        PositionedDirectional(
                          top: 6,
                          start: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              child: Text(
                                'خصم ${product.discountPercent!.toStringAsFixed(0)}٪',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 62, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lyd(product.price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Semantics(
              button: true,
              label: openLabel,
              excludeSemantics: true,
              child: Tooltip(
                message: openLabel,
                child: InkWell(
                  onTap: () => context.push('/product/${product.id}'),
                  mouseCursor: SystemMouseCursors.click,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: 8,
            bottom: 8,
            child: Semantics(
              button: true,
              enabled: product.isOrderable,
              label: addLabel,
              excludeSemantics: true,
              child: Tooltip(
                message: product.isOrderable
                    ? addLabel
                    : '${product.name} غير متوفر للطلب حالياً',
                child: IconButton.filled(
                  key: Key('related-product-add-${product.id}'),
                  onPressed: product.isOrderable
                      ? () => addProductToCartThenPrompt(
                            context: context,
                            ref: ref,
                            product: product,
                          )
                      : null,
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(44),
                    minimumSize: const Size.square(44),
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPurchasePanel extends StatelessWidget {
  const _ProductPurchasePanel({
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('product-details-purchase-panel'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: scheme.shadow.withValues(alpha: .10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: SizedBox.square(
                    dimension: 44,
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'خيارات الشراء',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        product.isOrderable
                            ? 'حدد الكمية ثم أضف المنتج للسلة'
                            : 'هذا المنتج غير متوفر للطلب حالياً',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          _ProductPriceCard(product: product, compact: false),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (product.isOrderable) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'الكمية المطلوبة',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ),
                      QuantitySelector(
                        key: const Key('product-details-quantity'),
                        quantity: quantity,
                        min: product.minOrderQuantity,
                        max: product.orderQuantityLimit,
                        onChanged: onQuantityChanged,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('product-details-whatsapp'),
                  onPressed: onSupport,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.chat_outlined),
                  label: Text(
                    onSupport == null
                        ? 'واتساب الدعم غير مهيأ'
                        : 'استفسر عبر واتساب',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'سيتم تأكيد السعر والمخزون النهائي عند مراجعة الطلب.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductDescriptionCard extends StatelessWidget {
  const _ProductDescriptionCard({
    required this.product,
    required this.compact,
  });

  final Product product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: scheme.shadow.withValues(alpha: .08),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 16,
          compact ? 12 : 16,
          compact ? 14 : 16,
          compact ? 10 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الوصف',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
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
    final compact = MediaQuery.sizeOf(context).width < 600;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('product-details-actions'),
      color: scheme.surface,
      elevation: 8,
      shadowColor: scheme.shadow.withValues(alpha: .16),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            compact ? 8 : 12,
            16,
            compact ? 8 : 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (product.isOrderable && compact) ...[
                Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الكمية',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        QuantitySelector(
                          key: const Key('product-details-quantity'),
                          quantity: quantity,
                          min: product.minOrderQuantity,
                          max: product.orderQuantityLimit,
                          onChanged: onQuantityChanged,
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('product-details-add-to-cart'),
                        onPressed: onAddToCart,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('إضافة للسلة'),
                      ),
                    ),
                  ],
                ),
              ] else if (product.isOrderable) ...[
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
                FilledButton.icon(
                  key: const Key('product-details-add-to-cart'),
                  onPressed: onAddToCart,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('إضافة للسلة'),
                ),
              ] else ...[
                FilledButton.icon(
                  key: const Key('product-details-add-to-cart'),
                  onPressed: onAddToCart,
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(compact ? 48 : 52),
                  ),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('غير متوفر حالياً'),
                ),
              ],
              SizedBox(height: compact ? 6 : 8),
              OutlinedButton.icon(
                key: const Key('product-details-whatsapp'),
                onPressed: onSupport,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(compact ? 44 : 48),
                ),
                icon: const Icon(Icons.chat_outlined),
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
