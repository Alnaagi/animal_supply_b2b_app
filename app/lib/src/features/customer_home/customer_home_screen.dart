import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../core/refresh/screen_reload.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/category_icon_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/product_info_chip.dart';
import '../../core/widgets/shop_brand_logo.dart';
import '../../core/widgets/shop_loading.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../data/models/order.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import '../cart/added_to_cart_prompt.dart';
import '../cart/cart_controller.dart';
import '../notifications/notification_center_sheet.dart';
import 'offer_banner_carousel.dart';

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  Future<List<Product>>? _productsFuture;
  Future<List<ProductCategory>>? _categoriesFuture;
  Future<List<Order>>? _ordersFuture;
  Future<List<AppBanner>>? _bannersFuture;
  String? _homeCustomerKey;
  bool _reordering = false;

  void _ensureHomeFutures(String customerKey) {
    if (_productsFuture != null && _homeCustomerKey == customerKey) return;
    _homeCustomerKey = customerKey;
    final catalog = ref.read(catalogRepositoryProvider);
    _productsFuture = _asFuture(() => catalog.products());
    _categoriesFuture = _asFuture(() => catalog.productCategories());
    _ordersFuture = _asFuture(
      () => ref.read(ordersRepositoryProvider).ordersForCustomer(customerKey),
    );
    _bannersFuture = _asFuture(
      () => ref.read(adminRepositoryProvider).banners(),
    );
  }

  static Future<T> _asFuture<T>(Future<T> Function() load) {
    try {
      return load();
    } catch (error, stack) {
      return Future<T>.error(error, stack);
    }
  }

  Future<void> _reloadHome() async {
    _productsFuture = null;
    _categoriesFuture = null;
    _ordersFuture = null;
    _bannersFuture = null;
    ref.invalidate(unreadNotificationsCountProvider);
    _homeCustomerKey = null;
    setState(() {});
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final customerKey = user.customerId ?? user.id;
    _ensureHomeFutures(customerKey);
    await Future.wait<Object>([
      if (_productsFuture != null)
        _productsFuture!.onError((_, __) => const <Product>[]),
      if (_categoriesFuture != null)
        _categoriesFuture!.onError((_, __) => const <ProductCategory>[]),
      if (_ordersFuture != null)
        _ordersFuture!.onError((_, __) => const <Order>[]),
      if (_bannersFuture != null)
        _bannersFuture!.onError((_, __) => const <AppBanner>[]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final user =
        ref.watch(authControllerProvider.select((state) => state.user))!;
    final customerKey = user.customerId ?? user.id;
    _ensureHomeFutures(customerKey);
    listenForScreenReload(ref, _reloadHome);
    ref.listen<int>(networkRetryTickProvider, (previous, next) {
      if (previous != next) _reloadHome();
    });
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    final location = [
      user.city,
      user.area,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(
          ' - ',
        );

    return ShopRefreshIndicator(
      onRefresh: _reloadHome,
      child: ListView(
        key: const Key('customer-home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        children: [
          _HomeGreetingHeader(
            name: user.businessName ?? user.username,
            location: location,
            unread: unread,
            onSearch: () => context.go('/catalog'),
            onNotifications: () => showNotificationCenter(context, ref),
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<AppBanner>>(
            future: _bannersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _HomeSectionLoading(
                  label: 'جارٍ تحميل العروض...',
                  height: 88,
                );
              }
              if (snapshot.hasError) {
                return _HomeSectionNotice(
                  icon: Icons.image_not_supported_outlined,
                  title: 'تعذر تحميل العروض',
                  message: 'يمكنك متابعة تصفح المنتجات والطلب بشكل طبيعي.',
                  onRetry: _reloadHome,
                );
              }
              final banners = AppConfig.remoteBackendEnabled
                  ? HomeBannerSlide.fromAdminBanners(snapshot.data ?? const [])
                  : HomeBannerSlide.demo();
              if (banners.isEmpty) return const SizedBox.shrink();
              return Column(
                children: [
                  // Owns its own PageController/timer/setState so banner ticks
                  // never rebuild product lists below.
                  OfferBannerCarousel(banners: banners),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          FutureBuilder<List<Product>>(
            future: _productsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _HomeSectionLoading(
                  label: 'جارٍ تحميل المنتجات...',
                  height: 180,
                );
              }
              if (snapshot.hasError) {
                return _HomeSectionNotice(
                  icon: Icons.cloud_off_outlined,
                  title: 'تعذر تحميل المنتجات',
                  message:
                      'لم نجد كتالوجاً محفوظاً على هذا الجهاز. تحقق من الاتصال ثم أعد المحاولة.',
                  onRetry: _reloadHome,
                );
              }
              return FutureBuilder<List<ProductCategory>>(
                future: _categoriesFuture,
                builder: (context, categorySnapshot) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _productSections(
                      snapshot.data ?? const [],
                      categorySnapshot.data ?? const [],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Order>>(
            future: _ordersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _HomeSectionLoading(
                  label: 'جارٍ تحديث آخر الطلبات...',
                  height: 72,
                );
              }
              if (snapshot.hasError) {
                return _HomeSectionNotice(
                  icon: Icons.receipt_long_outlined,
                  title: 'تعذر تحديث آخر الطلبات',
                  message:
                      'الكتالوج والسلة ما زالا متاحين، ويمكنك مراجعة الطلبات لاحقاً.',
                  onRetry: _reloadHome,
                );
              }
              final orders = snapshot.data ?? const [];
              if (orders.isEmpty) return const SizedBox.shrink();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(children: [
                    const Icon(Icons.refresh, color: AppTheme.green),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            'إعادة آخر طلب (${orders.first.items.length} منتجات)',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                    FilledButton(
                      onPressed:
                          _reordering ? null : () => _reorder(orders.first),
                      child: _reordering
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('إعادة الطلب'),
                    ),
                  ]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _productSections(
    List<Product> products,
    List<ProductCategory> categoryMeta,
  ) {
    if (products.isEmpty) {
      return [
        const EmptyState(
          title: 'لا توجد منتجات متاحة',
          message: 'ستظهر المنتجات النشطة هنا بعد إضافتها من الإدارة.',
          icon: Icons.inventory_2_outlined,
        ),
      ];
    }

    final byName = <String, ProductCategory>{
      for (final category in categoryMeta)
        if (category.active && !category.isArchived) category.name: category,
    };
    final categories = <ProductCategory>[
      ...byName.values,
    ];
    for (final product in products) {
      final name = product.category.trim();
      if (name.isEmpty || byName.containsKey(name)) continue;
      final fallback = ProductCategory(
        id: product.categoryId ?? name,
        name: name,
      );
      byName[name] = fallback;
      categories.add(fallback);
    }
    final latest = products.take(12).toList(growable: false);
    final featured =
        products.where((p) => p.isFeatured).take(12).toList(growable: false);
    final discounted = products
        .where((p) => (p.discountPercent ?? 0) > 0)
        .take(12)
        .toList(growable: false);
    final topSelling =
        products.where((p) => p.isTopSelling).take(12).toList(growable: false);
    return [
      _SectionHeader(
        title: 'التصنيفات',
        count: categories.length,
        onTap: () => context.go('/catalog'),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 88,
        child: ListView.separated(
          key: const Key('customer-home-categories'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.only(end: 36),
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final category = categories[index];
            return _HomeCategoryTile(
              category: category,
              onTap: () => context.go(
                '/catalog?category=${Uri.encodeComponent(category.name)}',
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 14),
      if (featured.isNotEmpty) ...[
        _SectionHeader(
          title: '⭐ منتجات مميزة',
          count: featured.length,
          onTap: () => context.go('/catalog'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 350,
          child: ListView.separated(
            key: const Key('customer-home-featured'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(end: 28),
            itemCount: featured.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _HomeProductCard(product: featured[index]),
          ),
        ),
        const SizedBox(height: 14),
      ],
      _SectionHeader(
        title: topSelling.isEmpty ? 'الأكثر طلباً' : 'الأكثر طلباً',
        count: topSelling.isEmpty ? latest.length : topSelling.length,
        onTap: () => context.go('/catalog'),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 350,
        child: ListView.separated(
          key: const Key('customer-home-products'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.only(end: 28),
          itemCount: topSelling.isEmpty ? latest.length : topSelling.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) => _HomeProductCard(
            product: (topSelling.isEmpty ? latest : topSelling)[index],
          ),
        ),
      ),
      if (discounted.isNotEmpty) ...[
        const SizedBox(height: 14),
        _SectionHeader(
          title: '🔥 العروض',
          count: discounted.length,
          onTap: () => context.go('/offers'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 350,
          child: ListView.separated(
            key: const Key('customer-home-discounted'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(end: 28),
            itemCount: discounted.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _HomeProductCard(
              product: discounted[index],
              showDiscountBadge: true,
            ),
          ),
        ),
      ],
    ];
  }

  Future<void> _reorder(Order order) async {
    if (_reordering) return;
    setState(() => _reordering = true);

    var added = 0;
    var unavailable = 0;
    var adjusted = 0;
    var repriced = 0;
    final resolvedItems = <({Product product, int quantity})>[];

    try {
      final catalog = ref.read(catalogRepositoryProvider);
      for (final item in order.items) {
        final current = await catalog.productById(item.productId);
        if (!mounted) return;
        if (current == null ||
            !current.active ||
            current.isArchived ||
            !current.isOrderable) {
          unavailable++;
          continue;
        }

        final quantity = current.normalizeOrderQuantity(item.quantity);
        if (quantity != item.quantity) adjusted++;
        if ((current.price - item.unitPrice).abs() >= 0.005) repriced++;
        resolvedItems.add((product: current, quantity: quantity));
      }

      if (resolvedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('منتجات هذا الطلب غير متاحة حالياً لإضافتها من جديد.'),
          ),
        );
        return;
      }

      final cart = ref.read(cartControllerProvider.notifier);
      for (final item in resolvedItems) {
        cart.addQuantity(item.product, item.quantity);
        added++;
      }

      if (unavailable > 0 || adjusted > 0 || repriced > 0) {
        final parts = <String>[
          if (unavailable > 0) 'تعذر إضافة $unavailable منتج',
          if (adjusted > 0)
            'تم تعديل كمية $adjusted منتج حسب المخزون والحد الأدنى',
          if (repriced > 0) 'تم تحديث سعر $repriced منتج للسعر الحالي',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${parts.join('، ')}.')),
        );
      }
      if (added > 0 && mounted) {
        requestScreenReload(ref);
        context.go('/cart');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر التحقق من الأسعار والمخزون الحاليين. '
            'لم تتغير السلة، تحقق من الاتصال وحاول مجدداً.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }
}

class _HomeSectionLoading extends StatelessWidget {
  const _HomeSectionLoading({
    required this.label,
    required this.height,
  });

  final String label;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ShopLoading.compact(),
              const SizedBox(height: 10),
              Text(label),
            ],
          ),
        ),
      );
}

class _HomeSectionNotice extends StatelessWidget {
  const _HomeSectionNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(message),
                  ],
                ),
              ),
              if (onRetry != null)
                IconButton(
                  onPressed: onRetry,
                  tooltip: 'إعادة المحاولة',
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
        ),
      );
}

class _HomeGreetingHeader extends ConsumerWidget {
  const _HomeGreetingHeader({
    required this.name,
    required this.location,
    required this.unread,
    required this.onSearch,
    required this.onNotifications,
  });

  final String name;
  final String location;
  final int unread;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(shopBrandingProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ShopBrandLogo(
          key: const Key('customer-home-shop-logo'),
          logoUrl: branding.logoUrl,
          size: 64,
          backgroundColor: const Color(0xffe3f3eb),
          fallbackIconColor: AppTheme.green,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مرحباً، $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.darkGreen,
                      height: 1.15,
                    ),
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppTheme.darkGreen.withValues(alpha: .62),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.darkGreen.withValues(alpha: .68),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('customer-home-search'),
                tooltip: 'البحث في المنتجات',
                onPressed: onSearch,
                icon: const Icon(Icons.search, color: AppTheme.green),
              ),
              IconButton(
                key: const Key('customer-home-notifications'),
                tooltip: 'الإشعارات',
                onPressed: onNotifications,
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(
                    Icons.notifications_none,
                    color: AppTheme.green,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.count,
    this.onTap,
  });

  final String title;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.darkGreen,
                ),
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.green.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: AppTheme.green,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
        const SizedBox(width: 4),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: AppTheme.green,
          ),
          child: const Text(
            'عرض الكل',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _HomeCategoryTile extends StatelessWidget {
  const _HomeCategoryTile({
    required this.category,
    required this.onTap,
  });

  final ProductCategory category;
  final VoidCallback onTap;

  static const _palettes = <(Color, Color)>[
    (Color(0xffd9f0e6), Color(0xff146c4e)),
    (Color(0xfff4e6d4), Color(0xff8a623f)),
    (Color(0xffdceaf4), Color(0xff2b6488)),
    (Color(0xfff7e4d8), Color(0xffb25a2b)),
    (Color(0xffe7e4f4), Color(0xff5b4d8a)),
    (Color(0xffe8f1d8), Color(0xff4d6b2b)),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[category.name.hashCode.abs() % _palettes.length];
    return SizedBox(
      width: 70,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('customer-home-category-${category.name}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 62,
                height: 54,
                decoration: BoxDecoration(
                  color: palette.$1,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.green.withValues(alpha: .10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Center(
                  child: CategoryIconView.fromCategory(
                    category,
                    size: 32,
                    color: palette.$2,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  height: 1.15,
                  color: AppTheme.darkGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeProductCard extends ConsumerWidget {
  const _HomeProductCard(
      {required this.product, this.showDiscountBadge = false});
  final Product product;
  final bool showDiscountBadge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = AppTheme.darkGreen.withValues(alpha: .62);
    return InkWell(
      onTap: () => context.push('/product/${product.id}'),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 196,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 142,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImagePlaceholder(
                    category: product.category,
                    productId: product.id,
                    imageUrl: product.imageUrl,
                    expand: true,
                    borderRadius: BorderRadius.zero,
                  ),
                  if (showDiscountBadge && (product.discountPercent ?? 0) > 0)
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xff00897b),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'خصم ${product.discountPercent}٪',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        height: 1.2,
                        color: AppTheme.darkGreen,
                      ),
                    ),
                    if (product.brand.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        product.brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (product.unitSize.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.unitSize,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'سعر الجملة',
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    PriceText(price: product.price),
                    if (product.hasProductDiscount)
                      Text(
                        lyd(product.effectivePrice ?? product.basePrice),
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (product.retailUnitPrice != null)
                      Text(
                        'بيع الوحدة: '
                        '${product.retailUnitPrice!.toStringAsFixed(2)} د.ل',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: ProductChipWrap(
                            children: [
                              Tooltip(
                                message: product.isOrderable
                                    ? AddedToCartPromptCopy.orderActionTooltip
                                    : product.customerAvailabilityLabel,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: product.isOrderable
                                      ? () => addProductToCartThenPrompt(
                                            context: context,
                                            ref: ref,
                                            product: product,
                                          )
                                      : null,
                                  child: ProductInfoChip(
                                    product.customerAvailabilityLabel,
                                    color: product.isOrderable
                                        ? AppTheme.green
                                        : AppTheme.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          tooltip: 'إضافة ${product.name} إلى السلة',
                          visualDensity: VisualDensity.compact,
                          onPressed: product.isOrderable
                              ? () => addProductToCartThenPrompt(
                                    context: context,
                                    ref: ref,
                                    product: product,
                                  )
                              : null,
                          icon: const Icon(Icons.add, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
