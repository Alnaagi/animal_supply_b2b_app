import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/customer_product_summary.dart';
import '../../core/widgets/category_icon_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../core/widgets/shop_skeleton.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../data/models/storefront_config.dart';
import '../customer_home/offer_banner_carousel.dart';
import 'storefront_home_data.dart';

/// Shared storefront home renderer used by customer home and admin preview.
class StorefrontHomeRenderer extends ConsumerWidget {
  const StorefrontHomeRenderer({
    required this.config,
    required this.data,
    required this.actions,
    this.interactionMode = StorefrontInteractionMode.live,
    this.renderMode = StorefrontRenderMode.customer,
    this.scrollKey = const Key('customer-home-scroll'),
    this.priceResolver,
    super.key,
  });

  final StorefrontConfig config;
  final StorefrontHomeData data;
  final StorefrontHomeActions actions;
  final StorefrontInteractionMode interactionMode;
  final StorefrontRenderMode renderMode;
  final Key scrollKey;
  final double Function(Product product)? priceResolver;

  bool get isPreview => interactionMode == StorefrontInteractionMode.preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = config.style;
    final spacing = style.sectionSpacing * style.densityScale;
    final children = <Widget>[];

    for (final section in config.sections) {
      if (!section.visible) continue;
      final widget = _buildSection(context, ref, section, spacing);
      if (widget != null) {
        if (children.isNotEmpty) children.add(SizedBox(height: spacing));
        children.add(widget);
      }
    }

    if (children.isEmpty) {
      children.add(
        const EmptyState(
          title: 'لا توجد أقسام ظاهرة',
          message: 'فعّل قسماً واحداً على الأقل من مصمم المتجر.',
          icon: Icons.view_quilt_outlined,
        ),
      );
    }

    final scrollable = LayoutBuilder(
      builder: (context, constraints) {
        final gutter = _homeHorizontalGutter(constraints.maxWidth);
        return SingleChildScrollView(
          key: scrollKey,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: 10,
            bottom: 20 * style.densityScale,
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: gutter, end: gutter),
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                key: const Key('customer-home-content-frame'),
                constraints: const BoxConstraints(maxWidth: 1440),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (actions.onRefresh == null || isPreview) {
      return scrollable;
    }
    return ShopRefreshIndicator(
      onRefresh: () async => actions.onRefresh!(),
      child: scrollable,
    );
  }

  Widget? _buildSection(
    BuildContext context,
    WidgetRef ref,
    StorefrontSectionConfig section,
    double spacing,
  ) {
    switch (section.type) {
      case StorefrontSectionType.header:
        return _buildHeader(context, ref, section);
      case StorefrontSectionType.banner:
        return _buildBanner(context, section);
      case StorefrontSectionType.categories:
        return _buildCategories(context, section, spacing);
      case StorefrontSectionType.featuredProducts:
        return _buildProductSection(
          context,
          ref,
          section,
          selector: _ProductSelector.featured,
        );
      case StorefrontSectionType.bestSelling:
        return _buildProductSection(
          context,
          ref,
          section,
          selector: _ProductSelector.bestSelling,
        );
      case StorefrontSectionType.offers:
        return _buildProductSection(
          context,
          ref,
          section,
          selector: _ProductSelector.offers,
        );
      case StorefrontSectionType.latestProducts:
        return _buildProductSection(
          context,
          ref,
          section,
          selector: _ProductSelector.latest,
        );
      case StorefrontSectionType.recentOrder:
        return _buildRecentOrder(context, section);
    }
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    StorefrontSectionConfig section,
  ) {
    final theme = config.theme;
    final showSearch = section.settingBool('showSearch', fallback: true);
    final showNotifications =
        section.settingBool('showNotifications', fallback: true);
    final showLocation = section.settingBool('showLocation', fallback: true);
    final isAdminPreview = renderMode == StorefrontRenderMode.adminPreview;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compactHeader = viewportWidth < 360;
    const actionSize = 44.0;

    return Container(
      key: const Key('customer-home-greeting-card'),
      padding: EdgeInsets.symmetric(
        horizontal: compactHeader ? 10 : 12,
        vertical: compactHeader ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(config.style.cardRadius),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: .08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'مرحباً، ${data.userName}',
                  maxLines: isAdminPreview ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.textColor,
                        height: 1.15,
                        fontSize: compactHeader ? 17 : 19,
                      ),
                ),
                if (showLocation && data.userLocation.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: theme.primaryColor.withValues(alpha: .70),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          data.userLocation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textColor.withValues(alpha: .68),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (showSearch || showNotifications) ...[
            SizedBox(width: compactHeader ? 8 : 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSearch)
                  _HeaderActionButton(
                    key: const Key('customer-home-search'),
                    size: actionSize,
                    tooltip: isPreview
                        ? 'معاينة — البحث معطّل'
                        : 'البحث في المنتجات',
                    onPressed: isPreview ? null : actions.onSearch,
                    theme: theme,
                    icon: Icon(Icons.search, color: theme.primaryColor),
                  ),
                if (showSearch && showNotifications)
                  SizedBox(width: compactHeader ? 4 : 6),
                if (showNotifications)
                  _HeaderActionButton(
                    key: const Key('customer-home-notifications'),
                    size: actionSize,
                    tooltip:
                        isPreview ? 'معاينة — الإشعارات معطّلة' : 'الإشعارات',
                    onPressed: isPreview ? null : actions.onNotifications,
                    theme: theme,
                    icon: Badge(
                      isLabelVisible: data.unreadNotifications > 0,
                      label: Text(
                        data.unreadNotifications > 99
                            ? '99+'
                            : '${data.unreadNotifications}',
                      ),
                      child: Icon(
                        Icons.notifications_none,
                        color: theme.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildBanner(BuildContext context, StorefrontSectionConfig section) {
    final configuredHeight =
        section.settingInt('height', fallback: 88).toDouble();
    if (data.bannersLoading) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final height = HomeBannerBreakpoints.resolveHeight(
            constraints.maxWidth,
            configuredHeight: configuredHeight,
          );
          return _HomeSectionLoading(
            key: const Key('customer-home-banner-skeleton'),
            label: 'جارٍ تحميل العروض...',
            height: height,
          );
        },
      );
    }
    if (data.bannersError) {
      return _HomeSectionNotice(
        icon: Icons.image_not_supported_outlined,
        title: 'تعذر تحميل العروض',
        message: 'يمكنك متابعة تصفح المنتجات والطلب بشكل طبيعي.',
        onRetry: isPreview ? null : actions.onRetryBanners,
        theme: config.theme,
      );
    }

    final banners = AppConfig.remoteBackendEnabled ||
            renderMode == StorefrontRenderMode.adminPreview
        ? HomeBannerSlide.fromAdminBanners(data.banners)
        : HomeBannerSlide.demo();
    if (banners.isEmpty) return null;

    final autoPlay = section.settingBool('autoPlay', fallback: true);
    final interval =
        section.settingInt('intervalSeconds', fallback: 5, max: 30);
    final showIndicators =
        section.settingBool('showIndicators', fallback: true);
    final radius = section.settingInt('borderRadius', fallback: 18).toDouble();

    return OfferBannerCarousel(
      banners: banners,
      height: configuredHeight,
      autoPlay: autoPlay && !isPreview,
      intervalSeconds: interval,
      showIndicators: showIndicators,
      borderRadius: radius,
      interactionEnabled: !isPreview,
    );
  }

  Widget? _buildCategories(
    BuildContext context,
    StorefrontSectionConfig section,
    double spacing,
  ) {
    if (data.productsLoading) {
      return const _HomeSectionLoading(
        key: Key('customer-home-categories-skeleton'),
        label: 'جارٍ تحميل المنتجات...',
        height: 118,
      );
    }
    if (data.productsError) {
      return _HomeSectionNotice(
        icon: Icons.cloud_off_outlined,
        title: 'تعذر تحميل المنتجات',
        message:
            'لم نجد كتالوجاً محفوظاً على هذا الجهاز. تحقق من الاتصال ثم أعد المحاولة.',
        onRetry: isPreview ? null : actions.onRetryProducts,
        theme: config.theme,
      );
    }
    if (data.products.isEmpty) {
      return const EmptyState(
        title: 'لا توجد منتجات متاحة',
        message: 'ستظهر المنتجات النشطة هنا بعد إضافتها من الإدارة.',
        icon: Icons.inventory_2_outlined,
      );
    }

    final categories = _resolveCategories(data.products, data.categories);
    final maxVisible = section.settingInt('maxVisible', fallback: 20, max: 50);
    final visibleCategories = categories.take(maxVisible).toList();
    final title =
        _cleanSectionTitle(section.settingString('title', 'التصنيفات'));
    final showCount = section.settingBool('showCount', fallback: true);

    return _HomeSectionSurface(
      key: const Key('customer-home-categories-section'),
      theme: config.theme,
      style: config.style,
      compactPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final desktopGrid = width >= 700;
          final compactMetrics = _CompactCategoryStripMetrics.resolve(width);
          final density =
              config.style.densityScale.clamp(.92, 1.04).toDouble();

          Widget categoryTile(ProductCategory category, double tileWidth) {
            return _HomeCategoryTile(
              category: category,
              theme: config.theme,
              style: config.style,
              tileWidth: tileWidth,
              compact: !desktopGrid,
              onTap: isPreview
                  ? null
                  : () => actions.onCategoryTap?.call(category),
            );
          }

          final categoryContent = desktopGrid
              ? _DesktopCategoryGrid(
                  key: const Key('customer-home-categories'),
                  categories: visibleCategories,
                  availableWidth: width,
                  tileBuilder: categoryTile,
                )
              : SizedBox(
                  key: const Key('customer-home-categories'),
                  height: compactMetrics.railHeight * density,
                  child: _AutoSlidingCategoryRail(
                    key: const Key('customer-home-categories-auto-rail'),
                    categories: visibleCategories,
                    metrics: compactMetrics,
                    autoPlay: !isPreview,
                    interactionEnabled: !isPreview,
                    tileBuilder: categoryTile,
                  ),
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (desktopGrid)
                _SectionHeader(
                  icon: Icons.category_outlined,
                  title: title,
                  countLabel: showCount
                      ? _categoryCountLabel(visibleCategories.length)
                      : null,
                  onTap: isPreview || actions.onSectionViewAll == null
                      ? null
                      : () => actions.onSectionViewAll!('/catalog'),
                  theme: config.theme,
                )
              else
                _CompactSectionHeader(
                  title: title,
                  countLabel: showCount
                      ? _categoryCountLabel(visibleCategories.length)
                      : null,
                  onTap: isPreview || actions.onSectionViewAll == null
                      ? null
                      : () => actions.onSectionViewAll!('/catalog'),
                  theme: config.theme,
                ),
              SizedBox(height: desktopGrid ? spacing * 0.55 : 6),
              categoryContent,
            ],
          );
        },
      ),
    );
  }

  Widget? _buildProductSection(
    BuildContext context,
    WidgetRef ref,
    StorefrontSectionConfig section, {
    required _ProductSelector selector,
  }) {
    if (data.productsLoading) {
      return _HomeSectionLoading(
        key: Key('customer-home-${selector.key}-skeleton'),
        label: 'جارٍ تحميل ${selector.defaultTitle}...',
        height: 196,
      );
    }
    if (data.productsError) return null;

    final products = _selectProducts(data.products, section, selector);
    final hideWhenEmpty = section.settingBool('hideWhenEmpty',
        fallback: selector != _ProductSelector.latest);
    if (products.isEmpty && hideWhenEmpty) return null;

    final title = _cleanSectionTitle(
      section.settingString('title', selector.defaultTitle),
    );
    final showAddToCart =
        section.settingBool('showAddToCart', fallback: true) && !isPreview;
    final showDiscountBadge = section.settingBool(
      'showDiscountBadge',
      fallback: selector == _ProductSelector.offers,
    );
    final viewAll = isPreview || actions.onSectionViewAll == null
        ? null
        : () => actions.onSectionViewAll!(selector.viewAllRoute);
    final countLabel = _productCountLabel(products.length);

    return _HomeSectionSurface(
      key: Key('customer-home-${selector.key}-section'),
      theme: config.theme,
      style: config.style,
      compactPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactChrome = constraints.maxWidth < 700;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compactChrome)
                _CompactSectionHeader(
                  title: title,
                  countLabel: countLabel,
                  onTap: viewAll,
                  theme: config.theme,
                )
              else
                _SectionHeader(
                  icon: selector.icon,
                  title: title,
                  countLabel: countLabel,
                  onTap: viewAll,
                  theme: config.theme,
                ),
              SizedBox(
                height: compactChrome
                    ? 6
                    : config.style.sectionSpacing * 0.55,
              ),
              if (products.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: compactChrome ? 12 : 18,
                  ),
                  child: Text(
                    'لا توجد منتجات في هذا القسم حالياً.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: config.theme.textColor.withValues(alpha: .7),
                      fontWeight: FontWeight.w600,
                      fontSize: compactChrome ? 12.5 : 14,
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final layout = _HomeProductSectionLayout.resolve(
                      constraints.maxWidth,
                      productCount: products.length,
                      densityScale: config.style.densityScale,
                      productImageRatio: config.style.productImageRatio,
                    );
                    final visible = layout.usesHorizontalPeek
                        ? products
                        : products.take(layout.visibleCount).toList();

                    Widget productCard(Product product) {
                      return SizedBox(
                        width: layout.cardWidth,
                        height: layout.cardHeight,
                        child: layout.usesWideCards
                            ? _HomeWideProductCard(
                                key: Key(
                                  'customer-home-product-${product.id}',
                                ),
                                product: product,
                                config: config,
                                showDiscountBadge: showDiscountBadge,
                                showAddToCart: showAddToCart,
                                cardWidth: layout.cardWidth,
                                cardHeight: layout.cardHeight,
                                price: priceResolver?.call(product) ??
                                    product.price,
                                onTap: isPreview
                                    ? null
                                    : () =>
                                        actions.onProductTap?.call(product),
                                onAddToCart: showAddToCart
                                    ? () =>
                                        actions.onAddToCart?.call(product)
                                    : null,
                              )
                            : _HomeProductCard(
                                key: Key(
                                  'customer-home-product-${product.id}',
                                ),
                                product: product,
                                config: config,
                                showDiscountBadge: showDiscountBadge,
                                showAddToCart: showAddToCart,
                                imageHeight: layout.imageHeight,
                                cardWidth: layout.cardWidth,
                                cardHeight: layout.cardHeight,
                                price: priceResolver?.call(product) ??
                                    product.price,
                                onTap: isPreview
                                    ? null
                                    : () =>
                                        actions.onProductTap?.call(product),
                                onAddToCart: showAddToCart
                                    ? () =>
                                        actions.onAddToCart?.call(product)
                                    : null,
                              ),
                      );
                    }

                    if (layout.usesHorizontalPeek) {
                      return KeyedSubtree(
                        key: Key('customer-home-${selector.key}'),
                        child: SizedBox(
                          key: Key(
                            'customer-home-${selector.key}-peek-rail',
                          ),
                          height: layout.cardHeight,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                SizedBox(width: layout.gap),
                            itemBuilder: (context, index) =>
                                productCard(visible[index]),
                          ),
                        ),
                      );
                    }

                    return KeyedSubtree(
                      key: Key('customer-home-${selector.key}'),
                      child: Wrap(
                        key: layout.usesWideCards
                            ? Key(
                                'customer-home-${selector.key}-wide-product-layout',
                              )
                            : null,
                        alignment: layout.centerCards
                            ? WrapAlignment.center
                            : WrapAlignment.start,
                        spacing: layout.gap,
                        runSpacing: layout.gap,
                        children: [
                          for (final product in visible) productCard(product),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget? _buildRecentOrder(
      BuildContext context, StorefrontSectionConfig section) {
    if (data.ordersLoading) {
      return const _HomeSectionLoading(
        key: Key('customer-home-recent-order-skeleton'),
        label: 'جارٍ تحديث آخر الطلبات...',
        height: 72,
      );
    }
    if (data.ordersError) {
      return _HomeSectionNotice(
        icon: Icons.receipt_long_outlined,
        title: 'تعذر تحديث آخر الطلبات',
        message:
            'الكتالوج والسلة ما زالا متاحين، ويمكنك مراجعة الطلبات لاحقاً.',
        onRetry: isPreview ? null : actions.onRetryOrders,
        theme: config.theme,
      );
    }
    if (data.recentOrders.isEmpty) return null;

    final order = data.recentOrders.first;
    final showCount = section.settingBool('showItemCount', fallback: true);
    final title = _cleanSectionTitle(
      section.settingString('title', 'إعادة آخر طلب'),
    );
    final itemCountLabel =
        showCount ? _productCountLabel(order.items.length) : null;

    return _HomeSectionSurface(
      key: const Key('customer-home-recent-order-section'),
      theme: config.theme,
      style: config.style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            icon: Icons.replay_rounded,
            title: title,
            description:
                'راجع آخر طلب وأعد إضافة نفس المنتجات إلى السلة بخطوة واحدة.',
            countLabel: itemCountLabel,
            theme: config.theme,
          ),
          SizedBox(height: config.style.sectionSpacing * 0.65),
          _RecentOrderSummary(
            orderNumber: order.displayNumber,
            itemCountLabel: _productCountLabel(order.items.length),
            totalLabel: lyd(order.total),
            theme: config.theme,
            buttonRadius: config.style.buttonRadius,
            reordering: data.reordering,
            isPreview: isPreview,
            onPressed: isPreview || data.reordering || actions.onReorder == null
                ? null
                : () => actions.onReorder!(order),
          ),
        ],
      ),
    );
  }

  List<ProductCategory> _resolveCategories(
    List<Product> products,
    List<ProductCategory> categoryMeta,
  ) {
    final byName = <String, ProductCategory>{
      for (final category in categoryMeta)
        if (category.active && !category.isArchived) category.name: category,
    };
    final categories = <ProductCategory>[...byName.values];
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
    return categories;
  }

  List<Product> _selectProducts(
    List<Product> products,
    StorefrontSectionConfig section,
    _ProductSelector selector,
  ) {
    final maxItems = section.settingInt('maxItems', fallback: 12, max: 24);
    switch (selector) {
      case _ProductSelector.featured:
        return products.where((p) => p.isFeatured).take(maxItems).toList();
      case _ProductSelector.offers:
        return products
            .where((p) => (p.discountPercent ?? 0) > 0)
            .take(maxItems)
            .toList();
      case _ProductSelector.bestSelling:
        // Source: manual is_top_selling flag — see storefrontBestSellingSourceDoc.
        final topSelling =
            products.where((p) => p.isTopSelling).take(maxItems).toList();
        if (topSelling.isNotEmpty) return topSelling;
        if (section.settingBool('fallbackToLatest', fallback: true)) {
          return products.take(maxItems).toList();
        }
        return topSelling;
      case _ProductSelector.latest:
        return products.take(maxItems).toList();
    }
  }
}

double _homeHorizontalGutter(double width) {
  if (width < 360) return 12;
  if (width < 600) return 16;
  if (width < 1024) return 24;
  return 32;
}

String _cleanSectionTitle(String value) {
  return value
      .replaceAll('⭐', '')
      .replaceAll('🔥', '')
      .replaceAll('✨', '')
      .trim();
}

String _categoryCountLabel(int count) {
  if (count == 1) return 'تصنيف واحد';
  if (count == 2) return 'تصنيفان';
  if (count >= 3 && count <= 10) return '$count تصنيفات';
  return '$count تصنيفاً';
}

String _productCountLabel(int count) {
  if (count == 1) return 'منتج واحد';
  if (count == 2) return 'منتجان';
  if (count >= 3 && count <= 10) return '$count منتجات';
  return '$count منتجاً';
}

Color _contentColorFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

enum _ProductSelector {
  featured(
    'featured',
    'منتجات مميزة',
    '/catalog',
    Icons.workspace_premium_outlined,
  ),
  bestSelling(
    'products',
    'الأكثر طلباً',
    '/catalog',
    Icons.trending_up_rounded,
  ),
  offers(
    'discounted',
    'العروض',
    '/offers',
    Icons.local_offer_outlined,
  ),
  latest(
    'latest',
    'أحدث المنتجات',
    '/catalog',
    Icons.new_releases_outlined,
  );

  const _ProductSelector(
    this.key,
    this.defaultTitle,
    this.viewAllRoute,
    this.icon,
  );

  final String key;
  final String defaultTitle;
  final String viewAllRoute;
  final IconData icon;
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    super.key,
    required this.size,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
    required this.icon,
  });

  final double size;
  final String tooltip;
  final VoidCallback? onPressed;
  final StorefrontThemeConfig theme;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.cardColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: .16),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        visualDensity: VisualDensity.compact,
        icon: icon,
      ),
    );
  }
}

class _HomeSectionLoading extends StatelessWidget {
  const _HomeSectionLoading({
    required this.label,
    required this.height,
    super.key,
  });

  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final compact = height <= 88;
    return ShopSkeleton(
      semanticLabel: label,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShopSkeletonBox(
                width: compact ? 104 : 142,
                height: compact ? 13 : 17,
                borderRadius: 999,
              ),
              SizedBox(height: compact ? 8 : 12),
              Expanded(
                child: ShopSkeletonBox(
                  height: double.infinity,
                  borderRadius: compact ? 14 : 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSectionNotice extends StatelessWidget {
  const _HomeSectionNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    required this.theme,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final StorefrontThemeConfig theme;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: theme.primaryColor),
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

class _HomeSectionSurface extends StatelessWidget {
  const _HomeSectionSurface({
    super.key,
    required this.theme,
    required this.style,
    required this.child,
    this.compactPadding,
  });

  final StorefrontThemeConfig theme;
  final StorefrontStyleConfig style;
  final Widget child;
  final EdgeInsetsGeometry? compactPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        padding: compactPadding != null && constraints.maxWidth < 700
            ? compactPadding
            : EdgeInsets.all(style.densityScale < 1 ? 12 : 16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(style.cardRadius + 2),
          border: Border.all(
            color: theme.primaryColor.withValues(alpha: .12),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.description,
    this.countLabel,
    this.onTap,
    required this.theme,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? countLabel;
  final VoidCallback? onTap;
  final StorefrontThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    Widget heading() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: Key('customer-home-section-icon-${icon.codePoint}'),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 23, color: theme.primaryColor),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.textColor,
                        height: 1.18,
                      ),
                ),
                if (description != null && description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textColor.withValues(alpha: .68),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.32,
                    ),
                  ),
                ],
                if (countLabel != null) ...[
                  const SizedBox(height: 7),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      child: Text(
                        countLabel!,
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    final viewAll = onTap == null
        ? null
        : TextButton.icon(
            key: Key('customer-home-view-all-$title'),
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(96, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              foregroundColor: theme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: theme.primaryColor.withValues(alpha: .16),
                ),
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text(
              'عرض الكل',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 470) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading(),
              if (viewAll != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: viewAll,
                ),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading()),
            if (viewAll != null) ...[
              const SizedBox(width: 12),
              viewAll,
            ],
          ],
        );
      },
    );
  }
}

class _CompactCategoryStripMetrics {
  const _CompactCategoryStripMetrics({
    required this.tileWidth,
    required this.gap,
    required this.edgePadding,
    required this.imageSize,
    required this.railHeight,
  });

  final double tileWidth;
  final double gap;
  final double edgePadding;
  final double imageSize;
  final double railHeight;

  double get step => tileWidth + gap;

  /// Compact phone strip: ~4.5 equal tiles so products stay in the first viewport.
  static _CompactCategoryStripMetrics resolve(double width) {
    const edgePadding = 2.0;
    final gap = width < 360 ? 8.0 : 10.0;
    const minimumTileWidth = 68.0;
    final usableWidth = (width - edgePadding * 2).clamp(0.0, width);
    final visibleSlots =
        ((usableWidth + gap) / (minimumTileWidth + gap)).floor().clamp(3, 6);
    final tileWidth =
        ((usableWidth - gap * (visibleSlots - 1)) / visibleSlots)
            .clamp(minimumTileWidth, 86.0)
            .toDouble();
    final imageSize = tileWidth;
    // Square art + tight label row (single line).
    final railHeight = imageSize + 4 + 15;
    return _CompactCategoryStripMetrics(
      tileWidth: tileWidth,
      gap: gap,
      edgePadding: edgePadding,
      imageSize: imageSize,
      railHeight: railHeight,
    );
  }
}

/// Slim mobile header — title + optional count + compact "عرض الكل".
class _CompactSectionHeader extends StatelessWidget {
  const _CompactSectionHeader({
    required this.title,
    required this.theme,
    this.countLabel,
    this.onTap,
  });

  final String title;
  final StorefrontThemeConfig theme;
  final String? countLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = theme.textColor.withValues(alpha: .58);
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      height: 1.1,
                      color: theme.textColor,
                    ),
                  ),
                ),
                if (countLabel != null && countLabel!.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    countLabel!,
                    maxLines: 1,
                    style: TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      height: 1.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            TextButton(
              key: Key('customer-home-view-all-$title'),
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: theme.primaryColor,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                'عرض الكل',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Gentle timed horizontal auto-slide; pauses while the user interacts.
class _AutoSlidingCategoryRail extends StatefulWidget {
  const _AutoSlidingCategoryRail({
    super.key,
    required this.categories,
    required this.metrics,
    required this.tileBuilder,
    this.autoPlay = true,
    this.interactionEnabled = true,
  });

  final List<ProductCategory> categories;
  final _CompactCategoryStripMetrics metrics;
  final Widget Function(ProductCategory category, double tileWidth) tileBuilder;
  final bool autoPlay;
  final bool interactionEnabled;

  @override
  State<_AutoSlidingCategoryRail> createState() =>
      _AutoSlidingCategoryRailState();
}

class _AutoSlidingCategoryRailState extends State<_AutoSlidingCategoryRail> {
  static const _tickInterval = Duration(milliseconds: 2600);
  static const _slideDuration = Duration(milliseconds: 720);
  static const _resumeAfterIdle = Duration(milliseconds: 3800);

  late final ScrollController _controller;
  Timer? _timer;
  Timer? _resumeTimer;
  bool _paused = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reduceMotion == reduceMotion && _timer != null) return;
    _reduceMotion = reduceMotion;
    _scheduleAutoPlay();
  }

  @override
  void didUpdateWidget(covariant _AutoSlidingCategoryRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.categories.length != widget.categories.length) {
      _scheduleAutoPlay();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resumeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleAutoPlay() {
    _timer?.cancel();
    _timer = null;
    if (!widget.autoPlay ||
        _reduceMotion ||
        widget.categories.length < 4) {
      return;
    }
    _timer = Timer.periodic(_tickInterval, (_) => _advance());
  }

  void _pauseForUser() {
    if (!widget.interactionEnabled) return;
    _paused = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeAfterIdle, () {
      if (!mounted) return;
      _paused = false;
    });
  }

  Future<void> _advance() async {
    if (!mounted || _paused || _reduceMotion || !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    final max = position.maxScrollExtent;
    if (max <= 4) return;

    final step = widget.metrics.step;
    final atEnd = position.pixels >= max - 2;
    final target = atEnd ? 0.0 : (position.pixels + step).clamp(0.0, max);
    await _controller.animateTo(
      target,
      duration: atEnd ? const Duration(milliseconds: 900) : _slideDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _pauseForUser();
        }
        return false;
      },
      child: Listener(
        onPointerDown: (_) => _pauseForUser(),
        child: ListView.separated(
          key: const Key('customer-home-categories-list'),
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: widget.interactionEnabled
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: metrics.edgePadding),
          itemCount: widget.categories.length,
          separatorBuilder: (_, __) => SizedBox(width: metrics.gap),
          itemBuilder: (context, index) {
            final category = widget.categories[index];
            return Align(
              alignment: Alignment.topCenter,
              child: widget.tileBuilder(category, metrics.tileWidth),
            );
          },
        ),
      ),
    );
  }
}

class _DesktopCategoryGrid extends StatelessWidget {
  const _DesktopCategoryGrid({
    super.key,
    required this.categories,
    required this.availableWidth,
    required this.tileBuilder,
  });

  final List<ProductCategory> categories;
  final double availableWidth;
  final Widget Function(ProductCategory category, double tileWidth) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final columns = availableWidth >= 1320
        ? 10
        : availableWidth >= 1080
            ? 8
            : availableWidth >= 880
                ? 6
                : 5;
    const gap = 12.0;
    final tileWidth = (availableWidth - (columns - 1) * gap) / columns;
    return Wrap(
      spacing: gap,
      runSpacing: 14,
      children: [
        for (final category in categories) tileBuilder(category, tileWidth),
      ],
    );
  }
}

class _HomeCategoryTile extends StatelessWidget {
  const _HomeCategoryTile({
    required this.category,
    required this.theme,
    required this.style,
    this.tileWidth = 78,
    this.compact = false,
    this.onTap,
  });

  final ProductCategory category;
  final StorefrontThemeConfig theme;
  final StorefrontStyleConfig style;
  final double tileWidth;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final toneIndex = category.name.hashCode.abs() % 3;
    final accent = switch (toneIndex) {
      0 => theme.primaryColor,
      1 => theme.secondaryColor,
      _ => Color.lerp(theme.primaryColor, theme.secondaryColor, .5)!,
    };
    final frameColor = Color.alphaBlend(
      accent.withValues(alpha: compact ? .07 : .09),
      theme.cardColor,
    );
    final imageSize = tileWidth;
    final artworkInset = compact
        ? (tileWidth * .08).clamp(5.0, 8.0)
        : (tileWidth * .09).clamp(7.0, 11.0);
    final radius = BorderRadius.circular(
      compact ? (style.cardRadius * .78).clamp(12.0, 16.0) : style.cardRadius * .9,
    );
    return SizedBox(
      width: tileWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('customer-home-category-${category.name}'),
          borderRadius: radius,
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: Key('customer-home-category-frame-${category.id}'),
                width: imageSize,
                height: imageSize,
                decoration: BoxDecoration(
                  color: frameColor,
                  borderRadius: radius,
                  border: Border.all(
                    color: accent.withValues(alpha: compact ? .12 : .14),
                  ),
                  boxShadow: compact
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: .06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  key: Key(
                    'customer-home-category-artwork-inset-${category.id}',
                  ),
                  padding: EdgeInsets.all(artworkInset),
                  child: CategoryIconView.fromCategory(
                    category,
                    size: imageSize - artworkInset * 2,
                    color: accent,
                    imageFit: BoxFit.contain,
                    circularImage: false,
                    expand: true,
                    expandedGlyphScale: compact ? .46 : .48,
                  ),
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              Text(
                category.name,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: compact
                      ? (tileWidth < 74 ? 10.5 : 11)
                      : (tileWidth < 88 ? 11 : 12),
                  height: compact ? 1.1 : 1.15,
                  color: theme.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentOrderSummary extends StatelessWidget {
  const _RecentOrderSummary({
    required this.orderNumber,
    required this.itemCountLabel,
    required this.totalLabel,
    required this.theme,
    required this.buttonRadius,
    required this.reordering,
    required this.isPreview,
    this.onPressed,
  });

  final String orderNumber;
  final String itemCountLabel;
  final String totalLabel;
  final StorefrontThemeConfig theme;
  final double buttonRadius;
  final bool reordering;
  final bool isPreview;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final muted = theme.textColor.withValues(alpha: .66);
    final reference = orderNumber.trim().isEmpty ? '—' : orderNumber.trim();
    final details = Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _RecentOrderDetail(
          icon: Icons.tag_rounded,
          label: 'رقم الطلب',
          value: reference,
          theme: theme,
        ),
        _RecentOrderDetail(
          icon: Icons.inventory_2_outlined,
          label: 'المحتوى',
          value: itemCountLabel,
          theme: theme,
        ),
        _RecentOrderDetail(
          icon: Icons.payments_outlined,
          label: 'الإجمالي',
          value: totalLabel,
          theme: theme,
        ),
      ],
    );
    final button = FilledButton.icon(
      key: const Key('customer-home-reorder-action'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(148, 48),
        backgroundColor: theme.primaryColor,
        foregroundColor: _contentColorFor(theme.primaryColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),
      icon: reordering
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_shopping_cart_rounded, size: 20),
      label: Text(
        isPreview ? 'معاينة' : 'إضافة للسلة مجدداً',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          theme.primaryColor.withValues(alpha: .055),
          theme.cardColor,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'سيتم استخدام الكميات نفسها، ويمكنك تعديلها داخل السلة.',
                  style: TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                details,
                const SizedBox(height: 12),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _RecentOrderDetail extends StatelessWidget {
  const _RecentOrderDetail({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final StorefrontThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: theme.primaryColor),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: theme.textColor.withValues(alpha: .58),
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Responsive product-section metrics for denser homepage grids.
///
/// Phone (<600) with 3+ products uses a horizontal peek rail: two full cards
/// plus ~18px of the next card on the trailing edge (left in RTL) so shoppers
/// know more products scroll horizontally. Tablet/desktop keep multi-column
/// grids; sparse desktop sections still use wide cards.
class _HomeProductSectionLayout {
  const _HomeProductSectionLayout({
    required this.columns,
    required this.rows,
    required this.gap,
    required this.cardWidth,
    required this.imageHeight,
    required this.cardHeight,
    this.usesWideCards = false,
    this.centerCards = false,
    this.usesHorizontalPeek = false,
    this.peekExtent = 0,
  });

  final int columns;
  final int rows;
  final double gap;
  final double cardWidth;
  final double imageHeight;
  final double cardHeight;
  final bool usesWideCards;
  final bool centerCards;
  final bool usesHorizontalPeek;
  /// Visible strip of the next off-screen card on phone peek rails.
  final double peekExtent;

  int get visibleCount => columns * rows;

  /// Phone content width breakpoint shared with compact section chrome.
  static const double phoneBreakpoint = 600;

  /// How much of the third card peeks past the trailing edge on phone.
  static const double phonePeekExtent = 18;

  static _HomeProductSectionLayout resolve(
    double width, {
    required int productCount,
    required double densityScale,
    required double productImageRatio,
  }) {
    final usesWideCards = width >= 980 && productCount > 0 && productCount <= 3;
    if (usesWideCards) {
      const gap = 16.0;
      const minimumWideCardWidth = 390.0;
      var columns = productCount;
      while (columns > 1 &&
          (width - gap * (columns - 1)) / columns < minimumWideCardWidth) {
        columns--;
      }
      final rows = (productCount / columns).ceil();
      final cardWidth = columns == 1
          ? width.clamp(0.0, 760.0).toDouble()
          : (width - gap * (columns - 1)) / columns;
      final cardHeight = (214 * densityScale * productImageRatio)
          .clamp(204.0, 238.0)
          .toDouble();
      return _HomeProductSectionLayout(
        columns: columns,
        rows: rows,
        gap: gap,
        cardWidth: cardWidth,
        imageHeight: cardHeight,
        cardHeight: cardHeight,
        usesWideCards: true,
        centerCards: columns == 1 || productCount % columns != 0,
      );
    }

    final compactChrome = width < phoneBreakpoint;
    // Phone with overflow: 2 full cards + peek of the third (scroll hint).
    final usesHorizontalPeek = compactChrome && productCount > 2;
    const columnsPhone = 2;
    final columns = compactChrome
        ? columnsPhone
        : width < 800
            ? 3
            : width < 1080
                ? 4
                : width < 1320
                    ? 5
                    : 6;
    // Phone: one compact row so the next product section enters the viewport.
    final rows = compactChrome ? 1 : 2;
    final gap = compactChrome
        ? 8.0
        : width < 1080
            ? 10.0
            : 12.0;
    final peek = usesHorizontalPeek ? phonePeekExtent : 0.0;
    // Viewport ≈ card + gap + card + gap + peek → shrink cards slightly.
    final cardWidth = usesHorizontalPeek
        ? (width - gap * 2 - peek) / columnsPhone
        : (width - gap * (columns - 1)) / columns;
    // Phone: shorter image so cards stay dense; keep a usable rounded photo panel
    // (≥100px after the small inset used for rounded corners).
    final imageHeight = (cardWidth *
            (compactChrome ? 0.74 : 0.76) *
            productImageRatio *
            densityScale)
        .clamp(compactChrome ? 108.0 : 88.0, compactChrome ? 120.0 : 164.0)
        .toDouble();
    // Text and pricing use a fixed vertical budget so mixed product names,
    // optional metadata, and discounts never make neighboring cards uneven.
    final detailsHeight = compactChrome
        ? 118.0
        : cardWidth < 174
            ? 140.0
            : 152.0;
    return _HomeProductSectionLayout(
      columns: columns,
      rows: rows,
      gap: gap,
      cardWidth: cardWidth,
      imageHeight: imageHeight,
      cardHeight: imageHeight + detailsHeight,
      usesHorizontalPeek: usesHorizontalPeek,
      peekExtent: peek,
    );
  }
}

/// Desktop treatment for intentionally sparse sections.
///
/// One to three products use the section width as horizontal cards instead of
/// looking like an incomplete row of narrow catalog tiles. Compact and tablet
/// layouts continue to use [_HomeProductCard].
class _HomeWideProductCard extends StatelessWidget {
  const _HomeWideProductCard({
    super.key,
    required this.product,
    required this.config,
    required this.cardWidth,
    required this.cardHeight,
    this.showDiscountBadge = false,
    this.showAddToCart = true,
    this.price,
    this.onTap,
    this.onAddToCart,
  });

  final Product product;
  final StorefrontConfig config;
  final double cardWidth;
  final double cardHeight;
  final bool showDiscountBadge;
  final bool showAddToCart;
  final double? price;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = config.theme;
    final style = config.style;
    final muted = theme.textColor.withValues(alpha: .62);
    final displayPrice = price ?? product.price;
    final mediaWidth = (cardWidth * .36).clamp(142.0, 224.0).toDouble();
    final compact = cardWidth < 500;
    final metaParts = <String>[
      if (product.brand.trim().isNotEmpty) product.brand.trim(),
      if (product.unitSize.trim().isNotEmpty) product.unitSize.trim(),
    ];
    final meta = metaParts.join(' · ');

    Widget priceLine(
      String label,
      String value, {
      required Color color,
    }) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: color,
                  fontSize: compact ? 15 : 17,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(style.cardRadius),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(style.cardRadius),
          boxShadow: style.cardBoxShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: Key('customer-home-wide-media-${product.id}'),
              width: mediaWidth,
              decoration: BoxDecoration(
                color: Colors.white,
                border: BorderDirectional(
                  end: BorderSide(
                    color: theme.primaryColor.withValues(alpha: .09),
                  ),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: ProductImagePlaceholder(
                      category: product.category,
                      productId: product.id,
                      imageUrl: product.imageUrl,
                      expand: true,
                      borderRadius: BorderRadius.circular(
                        (style.cardRadius * .72).clamp(10.0, 14.0),
                      ),
                      fit: BoxFit.contain,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  if (showDiscountBadge && (product.discountPercent ?? 0) > 0)
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'خصم ${product.discountPercent}٪',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(compact ? 13 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.w900,
                        height: 1.22,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted,
                          fontSize: compact ? 10.5 : 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Container(
                      key: Key('customer-home-pricing-${product.id}'),
                      width: double.infinity,
                      padding: EdgeInsets.all(compact ? 10 : 12),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          theme.primaryColor.withValues(alpha: .06),
                          theme.cardColor,
                        ),
                        borderRadius: BorderRadius.circular(
                          (style.cardRadius * .62).clamp(10, 16),
                        ),
                        border: Border.all(
                          color: theme.primaryColor.withValues(alpha: .10),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          priceLine(
                            CustomerProductCardCopy.wholesale,
                            lyd(displayPrice),
                            color: theme.primaryColor,
                          ),
                          if (product.retailUnitPrice != null) ...[
                            const SizedBox(width: 10),
                            Container(
                              width: 1,
                              height: 38,
                              color: theme.primaryColor.withValues(alpha: .12),
                            ),
                            const SizedBox(width: 10),
                            priceLine(
                              CustomerProductCardCopy.retail,
                              lyd(product.retailUnitPrice!),
                              color: theme.secondaryColor,
                            ),
                          ],
                          if (showAddToCart) ...[
                            const SizedBox(width: 10),
                            IconButton.filled(
                              key: Key(
                                'customer-home-add-to-cart-${product.id}',
                              ),
                              tooltip: 'إضافة ${product.name} إلى السلة',
                              style: IconButton.styleFrom(
                                minimumSize: const Size.square(48),
                                fixedSize: const Size.square(48),
                                padding: EdgeInsets.zero,
                                backgroundColor: theme.primaryColor,
                                foregroundColor:
                                    _contentColorFor(theme.primaryColor),
                                disabledBackgroundColor:
                                    theme.primaryColor.withValues(alpha: .20),
                                disabledForegroundColor:
                                    theme.textColor.withValues(alpha: .38),
                              ),
                              onPressed:
                                  product.isOrderable ? onAddToCart : null,
                              icon: const Icon(
                                Icons.add_shopping_cart_rounded,
                                size: 20,
                              ),
                            ),
                          ],
                        ],
                      ),
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

class _HomeProductCard extends StatelessWidget {
  const _HomeProductCard({
    super.key,
    required this.product,
    required this.config,
    this.showDiscountBadge = false,
    this.showAddToCart = true,
    this.imageHeight = 118,
    this.cardWidth = 168,
    this.cardHeight = 276,
    this.price,
    this.onTap,
    this.onAddToCart,
  });

  final Product product;
  final StorefrontConfig config;
  final bool showDiscountBadge;
  final bool showAddToCart;
  final double imageHeight;
  final double cardWidth;
  final double cardHeight;
  final double? price;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = config.theme;
    final style = config.style;
    final muted = theme.textColor.withValues(alpha: .62);
    final displayPrice = price ?? product.price;
    final metaParts = <String>[
      if (product.brand.trim().isNotEmpty) product.brand.trim(),
      if (product.unitSize.trim().isNotEmpty) product.unitSize.trim(),
    ];
    final meta = metaParts.join(' · ');
    final compact = cardWidth < 174;
    final actionSize = compact ? 44.0 : 48.0;
    final nameHeight = compact ? 28.0 : 34.0;
    final metaHeight = compact ? 12.0 : 14.0;
    final imageInset = compact ? 5.0 : 6.0;
    final imageRadius = BorderRadius.circular(
      (style.cardRadius * .72).clamp(10.0, 14.0),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(style.cardRadius),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(style.cardRadius),
          boxShadow: style.cardBoxShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      imageInset,
                      imageInset,
                      imageInset,
                      0,
                    ),
                    child: ProductImagePlaceholder(
                      category: product.category,
                      productId: product.id,
                      imageUrl: product.imageUrl,
                      expand: true,
                      borderRadius: imageRadius,
                      fit: BoxFit.contain,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  if (showDiscountBadge && (product.discountPercent ?? 0) > 0)
                    PositionedDirectional(
                      top: imageInset + 2,
                      start: imageInset + 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'خصم ${product.discountPercent}٪',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 7 : 9,
                  compact ? 5 : 7,
                  compact ? 7 : 9,
                  compact ? 6 : 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: nameHeight,
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: compact ? 12.5 : 13.5,
                            height: 1.15,
                            color: theme.textColor,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 3),
                    SizedBox(
                      height: metaHeight,
                      child: meta.isEmpty
                          ? const SizedBox.shrink()
                          : Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: muted,
                                fontSize: compact ? 10.5 : 11,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                    ),
                    SizedBox(height: compact ? 4 : 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              key: Key('customer-home-pricing-${product.id}'),
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 6 : 8,
                                vertical: compact ? 4 : 6,
                              ),
                              decoration: BoxDecoration(
                                color: Color.alphaBlend(
                                  theme.primaryColor.withValues(alpha: .06),
                                  theme.cardColor,
                                ),
                                borderRadius: BorderRadius.circular(
                                  (style.cardRadius * .58).clamp(9, 14),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: cardWidth,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        CustomerProductCardCopy.wholesale,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: compact ? 9.5 : 10,
                                          fontWeight: FontWeight.w700,
                                          height: 1.05,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        lyd(displayPrice),
                                        maxLines: 1,
                                        textDirection: TextDirection.rtl,
                                        style: TextStyle(
                                          color: theme.primaryColor,
                                          fontSize: compact ? 13.5 : 14.5,
                                          fontWeight: FontWeight.w900,
                                          height: 1.05,
                                        ),
                                      ),
                                      if (product.hasProductDiscount)
                                        Text(
                                          lyd(
                                            product.effectivePrice ??
                                                product.basePrice,
                                          ),
                                          maxLines: 1,
                                          textDirection: TextDirection.rtl,
                                          style: TextStyle(
                                            decoration:
                                                TextDecoration.lineThrough,
                                            color: muted,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            height: 1,
                                          ),
                                        ),
                                      if (product.retailUnitPrice != null) ...[
                                        SizedBox(height: compact ? 2 : 3),
                                        Text(
                                          CustomerProductCardCopy.retail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: muted,
                                            fontSize: compact ? 9 : 9.5,
                                            fontWeight: FontWeight.w700,
                                            height: 1,
                                          ),
                                        ),
                                        Text(
                                          lyd(product.retailUnitPrice!),
                                          maxLines: 1,
                                          textDirection: TextDirection.rtl,
                                          style: TextStyle(
                                            color: theme.secondaryColor,
                                            fontSize: compact ? 11.5 : 12.5,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (showAddToCart) ...[
                            SizedBox(width: compact ? 5 : 6),
                            Align(
                              alignment: Alignment.center,
                              child: IconButton.filled(
                                key: Key(
                                  'customer-home-add-to-cart-${product.id}',
                                ),
                                tooltip: 'إضافة ${product.name} إلى السلة',
                                style: IconButton.styleFrom(
                                  minimumSize: Size.square(actionSize),
                                  fixedSize: Size.square(actionSize),
                                  padding: EdgeInsets.zero,
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: _contentColorFor(
                                    theme.primaryColor,
                                  ),
                                  disabledBackgroundColor: theme.primaryColor
                                      .withValues(alpha: .20),
                                  disabledForegroundColor: theme.textColor
                                      .withValues(alpha: .38),
                                ),
                                onPressed:
                                    product.isOrderable ? onAddToCart : null,
                                icon: Icon(
                                  Icons.add_shopping_cart_rounded,
                                  size: compact ? 18 : 20,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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
