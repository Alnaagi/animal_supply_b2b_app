import '../../data/models/admin_models.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';

enum StorefrontInteractionMode {
  /// Customer live shop — cart, checkout, navigation enabled.
  live,

  /// Admin preview — no cart/checkout/order side effects.
  preview,
}

enum StorefrontRenderMode {
  customer,
  adminPreview,
}

class StorefrontPreviewUser {
  const StorefrontPreviewUser({
    required this.displayName,
    this.location = '',
    this.customerKey,
  });

  final String displayName;
  final String location;
  final String? customerKey;
}

class StorefrontHomeData {
  const StorefrontHomeData({
    this.products = const [],
    this.categories = const [],
    this.banners = const [],
    this.recentOrders = const [],
    this.unreadNotifications = 0,
    this.userName = '',
    this.userLocation = '',
    this.productsLoading = false,
    this.categoriesLoading = false,
    this.bannersLoading = false,
    this.ordersLoading = false,
    this.productsError = false,
    this.categoriesError = false,
    this.bannersError = false,
    this.ordersError = false,
    this.reordering = false,
  });

  final List<Product> products;
  final List<ProductCategory> categories;
  final List<AppBanner> banners;
  final List<Order> recentOrders;
  final int unreadNotifications;
  final String userName;
  final String userLocation;
  final bool productsLoading;
  final bool categoriesLoading;
  final bool bannersLoading;
  final bool ordersLoading;
  final bool productsError;
  final bool categoriesError;
  final bool bannersError;
  final bool ordersError;
  final bool reordering;

  StorefrontHomeData copyWith({
    List<Product>? products,
    List<ProductCategory>? categories,
    List<AppBanner>? banners,
    List<Order>? recentOrders,
    int? unreadNotifications,
    String? userName,
    String? userLocation,
    bool? productsLoading,
    bool? categoriesLoading,
    bool? bannersLoading,
    bool? ordersLoading,
    bool? productsError,
    bool? categoriesError,
    bool? bannersError,
    bool? ordersError,
    bool? reordering,
  }) {
    return StorefrontHomeData(
      products: products ?? this.products,
      categories: categories ?? this.categories,
      banners: banners ?? this.banners,
      recentOrders: recentOrders ?? this.recentOrders,
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      userName: userName ?? this.userName,
      userLocation: userLocation ?? this.userLocation,
      productsLoading: productsLoading ?? this.productsLoading,
      categoriesLoading: categoriesLoading ?? this.categoriesLoading,
      bannersLoading: bannersLoading ?? this.bannersLoading,
      ordersLoading: ordersLoading ?? this.ordersLoading,
      productsError: productsError ?? this.productsError,
      categoriesError: categoriesError ?? this.categoriesError,
      bannersError: bannersError ?? this.bannersError,
      ordersError: ordersError ?? this.ordersError,
      reordering: reordering ?? this.reordering,
    );
  }
}

typedef StorefrontVoidCallback = void Function();
typedef StorefrontProductTap = void Function(Product product);
typedef StorefrontCategoryTap = void Function(ProductCategory category);
typedef StorefrontReorderTap = void Function(Order order);

class StorefrontHomeActions {
  const StorefrontHomeActions({
    this.onRefresh,
    this.onSearch,
    this.onNotifications,
    this.onProductTap,
    this.onCategoryTap,
    this.onSectionViewAll,
    this.onReorder,
    this.onRetryProducts,
    this.onRetryBanners,
    this.onRetryOrders,
    this.onAddToCart,
  });

  final StorefrontVoidCallback? onRefresh;
  final StorefrontVoidCallback? onSearch;
  final StorefrontVoidCallback? onNotifications;
  final StorefrontProductTap? onProductTap;
  final StorefrontCategoryTap? onCategoryTap;
  final void Function(String route)? onSectionViewAll;
  final StorefrontReorderTap? onReorder;
  final StorefrontVoidCallback? onRetryProducts;
  final StorefrontVoidCallback? onRetryBanners;
  final StorefrontVoidCallback? onRetryOrders;
  final StorefrontProductTap? onAddToCart;
}
