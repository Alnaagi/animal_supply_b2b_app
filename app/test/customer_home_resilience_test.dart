import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/models/product_category.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_controller.dart';
import 'package:animal_supply_b2b/src/features/customer_home/customer_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('cached catalog stays usable when banners and recent orders fail',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _CustomerAuthController(),
          ),
          catalogRepositoryProvider.overrideWithValue(
            _CachedCatalogRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(
            _FailingOrdersRepository(),
          ),
          adminRepositoryProvider.overrideWithValue(
            _FailingBannersRepository(),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CustomerHomeScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل العروض'), findsOneWidget);
    expect(find.text('تعذر تحميل المنتجات'), findsNothing);
    expect(find.text('التصنيفات'), findsOneWidget);

    final homeScroll = find.byKey(const Key('customer-home-scroll'));
    await tester.drag(homeScroll, const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(find.text('منتج محفوظ للاختبار'), findsOneWidget);

    await tester.drag(homeScroll, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحديث آخر الطلبات'), findsOneWidget);
  });

  testWidgets('home reorder resolves current price, MOQ, and available stock',
      (tester) async {
    final catalog = _ReorderCatalogRepository();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _CustomerAuthController(),
        ),
        catalogRepositoryProvider.overrideWithValue(catalog),
        ordersRepositoryProvider.overrideWithValue(
          _PreviousOrderRepository(),
        ),
        adminRepositoryProvider.overrideWithValue(
          _FailingBannersRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: CustomerHomeScreen()),
        ),
        GoRoute(
          path: '/cart',
          builder: (context, state) => const Scaffold(body: Text('صفحة السلة')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final homeScroll = find.byKey(const Key('customer-home-scroll'));
    await tester.drag(homeScroll, const Offset(0, -700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إعادة الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('صفحة السلة'), findsOneWidget);
    final cart = container.read(cartControllerProvider);
    expect(cart, hasLength(1));
    expect(cart.single.product.id, 'current-product');
    expect(cart.single.product.price, 18);
    expect(cart.single.quantity, 3);
    expect(find.textContaining('تم تعديل كمية 1 منتج'), findsOneWidget);
    expect(find.textContaining('تم تحديث سعر 1 منتج'), findsOneWidget);
  });

  testWidgets('home reorder lookup failure leaves the cart unchanged',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _CustomerAuthController(),
        ),
        catalogRepositoryProvider.overrideWithValue(
          _FailingLookupCatalogRepository(),
        ),
        ordersRepositoryProvider.overrideWithValue(
          _PreviousOrderRepository(),
        ),
        adminRepositoryProvider.overrideWithValue(
          _FailingBannersRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: CustomerHomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('customer-home-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إعادة الطلب'));
    await tester.pumpAndSettle();

    expect(container.read(cartControllerProvider), isEmpty);
    expect(find.textContaining('لم تتغير السلة'), findsOneWidget);
  });
}

class _CustomerAuthController extends AuthController {
  _CustomerAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'profile-1',
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: 'customer-1',
      ),
    );
  }
}

class _CachedCatalogRepository extends CatalogRepository {
  @override
  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async {
    return const [
      Product(
        id: 'cached-product',
        nameAr: 'منتج محفوظ للاختبار',
        sku: 'CACHE-1',
        category: 'قطط',
        animalType: 'قطط',
        brand: 'اختبار',
        unitSize: '1 كجم',
        basePrice: 25,
        stockQuantity: 10,
        minOrderQty: 1,
        isTopSelling: true,
      ),
    ];
  }

  @override
  Future<List<ProductCategory>> productCategories({
    bool includeArchived = false,
  }) async {
    return const [
      ProductCategory(id: 'cat-1', name: 'قطط', iconKey: 'cat'),
    ];
  }
}

class _FailingOrdersRepository extends OrdersRepository {
  _FailingOrdersRepository() : super.demo(seed: const []);

  @override
  Future<List<Order>> ordersForCustomer(String customerId) async {
    throw StateError('orders unavailable');
  }
}

class _FailingBannersRepository extends AdminRepository {
  @override
  Future<List<AppBanner>> banners({bool includeInactive = false}) async {
    throw StateError('banners unavailable');
  }
}

class _ReorderCatalogRepository extends CatalogRepository {
  @override
  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async =>
      const [];

  @override
  Future<Product?> productById(String id) async => const Product(
        id: 'current-product',
        nameAr: 'المنتج الحالي',
        sku: 'CURRENT-1',
        category: 'قطط',
        animalType: 'قطط',
        brand: 'اختبار',
        unitSize: '1 كجم',
        basePrice: 20,
        effectivePrice: 18,
        stockQuantity: 10,
        availableQuantity: 4,
        minOrderQty: 3,
      );

  @override
  Future<List<ProductCategory>> productCategories({
    bool includeArchived = false,
  }) async =>
      const [];
}

class _FailingLookupCatalogRepository extends _ReorderCatalogRepository {
  @override
  Future<Product?> productById(String id) async {
    throw StateError('catalog unavailable');
  }
}

class _PreviousOrderRepository extends OrdersRepository {
  _PreviousOrderRepository() : super.demo(seed: const []);

  @override
  Future<List<Order>> ordersForCustomer(String customerId) async {
    const staleProduct = Product(
      id: 'current-product',
      nameAr: 'اسم سابق',
      sku: 'OLD-1',
      category: 'قطط',
      animalType: 'قطط',
      brand: 'اختبار',
      unitSize: '1 كجم',
      basePrice: 10,
      stockQuantity: 100,
      minOrderQty: 1,
    );
    return [
      Order(
        id: 'order-1',
        customerId: customerId,
        status: OrderStatus.delivered,
        createdAt: DateTime(2026, 7, 20),
        items: const [
          OrderItem(
            productId: 'current-product',
            productName: 'اسم سابق',
            productSku: 'OLD-1',
            unitSize: '1 كجم',
            packageLabel: 'كيس',
            quantity: 1,
            unitPrice: 10,
            lineTotal: 10,
            product: staleProduct,
          ),
        ],
      ),
    ];
  }
}
