import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/refresh/screen_reload.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../data/models/storefront_config.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../../data/repositories/storefront_repository.dart';
import '../auth/auth_controller.dart';
import '../cart/added_to_cart_prompt.dart';
import '../cart/cart_controller.dart';
import '../notifications/notification_center_sheet.dart';
import '../storefront/storefront_home_data.dart';
import '../storefront/storefront_home_renderer.dart';
import '../storefront/storefront_theme_scope.dart';

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
  Future<StorefrontHomeData>? _homeDataFuture;
  StorefrontHomeData? _homeData;
  String? _homeCustomerKey;
  int _homeLoadGeneration = 0;
  bool _reordering = false;

  void _ensureHomeFutures(String customerKey) {
    if (_productsFuture != null && _homeCustomerKey == customerKey) return;
    _homeCustomerKey = customerKey;
    final generation = ++_homeLoadGeneration;
    final catalog = ref.read(catalogRepositoryProvider);
    final user = ref.read(authControllerProvider).user!;
    final location = [
      user.city,
      user.area,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' - ');
    final previous = _homeData;
    _homeData = StorefrontHomeData(
      products: previous?.products ?? const <Product>[],
      categories: previous?.categories ?? const <ProductCategory>[],
      banners: previous?.banners ?? const <AppBanner>[],
      recentOrders: previous?.recentOrders ?? const <Order>[],
      unreadNotifications: previous?.unreadNotifications ?? 0,
      userName: user.businessName ?? user.username,
      userLocation: location,
      productsLoading: true,
      categoriesLoading: previous?.categories.isEmpty ?? true,
      bannersLoading: previous?.banners.isEmpty ?? true,
      ordersLoading: previous?.recentOrders.isEmpty ?? true,
    );
    _productsFuture = _asFuture(() => catalog.products());
    _categoriesFuture = _asFuture(() => catalog.productCategories());
    _ordersFuture = _asFuture(
      () => ref.read(ordersRepositoryProvider).ordersForCustomer(customerKey),
    );
    _bannersFuture = _asFuture(
      () => ref.read(adminRepositoryProvider).banners(),
    );
    unawaited(_paintCachedProducts(generation, catalog));
    _homeDataFuture = _bindHomeSections(generation);
  }

  Future<void> _paintCachedProducts(
    int generation,
    CatalogRepository catalog,
  ) async {
    final cached = await catalog.peekCachedProducts();
    if (!mounted || generation != _homeLoadGeneration || cached.isEmpty) {
      return;
    }
    final current = _homeData;
    if (current == null || current.products.isNotEmpty) return;
    setState(() {
      _homeData = current.copyWith(products: cached, productsLoading: true);
    });
  }

  Future<StorefrontHomeData> _bindHomeSections(int generation) async {
    void apply(StorefrontHomeData Function(StorefrontHomeData current) update) {
      if (!mounted || generation != _homeLoadGeneration) return;
      final current = _homeData;
      if (current == null) return;
      setState(() => _homeData = update(current));
    }

    // Attach listeners synchronously so section failures stay independent.
    final productsDone = _settle(
      _productsFuture ?? Future<List<Product>>.value(const <Product>[]),
    ).then((result) {
      apply((current) {
        final next = result.value ?? current.products;
        return current.copyWith(
          products: next,
          productsLoading: false,
          productsError: result.error && next.isEmpty,
        );
      });
    });
    final categoriesDone = _settle(
      _categoriesFuture ??
          Future<List<ProductCategory>>.value(const <ProductCategory>[]),
    ).then((result) {
      apply((current) => current.copyWith(
            categories: result.value ?? current.categories,
            categoriesLoading: false,
            categoriesError: result.error && current.categories.isEmpty,
          ));
    });
    final ordersDone = _settle(
      _ordersFuture ?? Future<List<Order>>.value(const <Order>[]),
    ).then((result) {
      apply((current) => current.copyWith(
            recentOrders: result.value ?? current.recentOrders,
            ordersLoading: false,
            ordersError: result.error,
          ));
    });
    final bannersDone = _settle(
      _bannersFuture ?? Future<List<AppBanner>>.value(const <AppBanner>[]),
    ).then((result) {
      apply((current) => current.copyWith(
            banners: result.value ?? current.banners,
            bannersLoading: false,
            bannersError: result.error,
          ));
    });

    await Future.wait([
      productsDone,
      categoriesDone,
      ordersDone,
      bannersDone,
    ]);
    return _homeData ?? const StorefrontHomeData();
  }

  static Future<({T? value, bool error})> _settle<T>(Future<T> future) {
    return future.then(
      (value) => (value: value, error: false),
      onError: (Object _, StackTrace __) => (value: null, error: true),
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
    _homeDataFuture = null;
    ref.invalidate(unreadNotificationsCountProvider);
    ref.invalidate(publishedStorefrontConfigProvider);
    _homeCustomerKey = null;
    setState(() {});
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    final customerKey = user.customerId ?? user.id;
    _ensureHomeFutures(customerKey);
    await _homeDataFuture;
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
    final location = [
      user.city,
      user.area,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' - ');

    final configAsync = ref.watch(publishedStorefrontConfigProvider);
    final config = configAsync.valueOrNull ?? StorefrontDefaults.bundled;

    final data = _homeData ??
        StorefrontHomeData(
          userName: user.businessName ?? user.username,
          userLocation: location,
          productsLoading: true,
          categoriesLoading: true,
          bannersLoading: true,
          ordersLoading: true,
        );

    return StorefrontThemeScope(
      config: config,
      child: StorefrontHomeRenderer(
        config: config,
        data: data.copyWith(
          unreadNotifications:
              ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0,
          reordering: _reordering,
        ),
        interactionMode: StorefrontInteractionMode.live,
        renderMode: StorefrontRenderMode.customer,
        actions: StorefrontHomeActions(
          onRefresh: _reloadHome,
          onSearch: () => context.go('/catalog'),
          onNotifications: () => showNotificationCenter(context, ref),
          onProductTap: (product) => context.push('/product/${product.id}'),
          onCategoryTap: (category) => context.go(
            '/catalog?category=${Uri.encodeComponent(category.name)}',
          ),
          onSectionViewAll: (route) => context.go(route),
          onReorder: _reorder,
          onRetryProducts: _reloadHome,
          onRetryBanners: _reloadHome,
          onRetryOrders: _reloadHome,
          onAddToCart: (product) => addProductToCartThenPrompt(
            context: context,
            ref: ref,
            product: product,
          ),
        ),
      ),
    );
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
            content: Text(
              'منتجات هذا الطلب غير متاحة حالياً لإضافتها من جديد.',
            ),
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
