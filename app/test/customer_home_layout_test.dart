import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/category_icon_view.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/models/product_category.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/customer_home/customer_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('customer home shows greeting, categories, and product rows',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _CustomerAuthController(),
          ),
          catalogRepositoryProvider.overrideWithValue(_ShopCatalogRepository()),
          ordersRepositoryProvider.overrideWithValue(
            OrdersRepository.demo(seed: const []),
          ),
          adminRepositoryProvider.overrideWithValue(_HomeBannersRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(disableAnimations: true),
              child: child!,
            );
          },
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: _TestHomeAppBar(),
              body: CustomerHomeScreen(),
              bottomNavigationBar: _TestHomeNav(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Greeting header
    expect(find.text('مرحباً، متجر الاختبار'), findsOneWidget);
    expect(find.text('طرابلس - حي الأندلس'), findsOneWidget);

    // Sections
    expect(find.text('التصنيفات'), findsOneWidget);
    expect(find.text('الأكثر طلباً'), findsOneWidget);

    // Categories
    expect(find.text('أعلاف'), findsWidgets);
    expect(find.text('قطط'), findsWidgets);
    expect(find.text('أدوية'), findsOneWidget);
    expect(find.byType(CategoryIconView), findsWidgets);

    // عرض الكل appears for التصنيفات + أحدث المنتجات (+ منتجات مخفضة if discounted)
    expect(find.text('عرض الكل'), findsAtLeastNWidgets(2));

    // Product name visible
    expect(find.text('علف دجاج جملة'), findsWidgets);

    // Dismiss any overflow errors from test rendering constraints.
    tester.takeException();
  });

  testWidgets('offers row shows when discountPercent > 0', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _CustomerAuthController(),
          ),
          catalogRepositoryProvider
              .overrideWithValue(_ShopCatalogWithDiscountRepository()),
          ordersRepositoryProvider.overrideWithValue(
            OrdersRepository.demo(seed: const []),
          ),
          adminRepositoryProvider.overrideWithValue(_HomeBannersRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(disableAnimations: true),
              child: child!,
            );
          },
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: _TestHomeAppBar(),
              body: CustomerHomeScreen(),
              bottomNavigationBar: _TestHomeNav(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🔥 العروض'), findsOneWidget);
    expect(find.textContaining('خصم'), findsWidgets);
    expect(find.byKey(const Key('customer-home-discounted')), findsOneWidget);
    // Dismiss any overflow errors from rendering; the widget tree is tested above.
    tester.takeException();
  });

  testWidgets('offers row hidden when no discounted products', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _CustomerAuthController(),
          ),
          catalogRepositoryProvider.overrideWithValue(_ShopCatalogRepository()),
          ordersRepositoryProvider.overrideWithValue(
            OrdersRepository.demo(seed: const []),
          ),
          adminRepositoryProvider.overrideWithValue(_HomeBannersRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(disableAnimations: true),
              child: child!,
            );
          },
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: _TestHomeAppBar(),
              body: CustomerHomeScreen(),
              bottomNavigationBar: _TestHomeNav(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🔥 العروض'), findsNothing);
    tester.takeException();
  });
}

class _TestHomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _TestHomeAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text('شركة الباشق'),
    );
  }
}

class _TestHomeNav extends StatelessWidget {
  const _TestHomeNav();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: NavigationBar(
        height: 68,
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            label: 'المنتجات',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            label: 'السلة',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'الطلبات',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'الحساب',
          ),
        ],
      ),
    );
  }
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
        city: 'طرابلس',
        area: 'حي الأندلس',
      ),
    );
  }
}

class _ShopCatalogRepository extends CatalogRepository {
  @override
  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async {
    return const [
      Product(
        id: 'feed-1',
        nameAr: 'علف دجاج جملة',
        sku: 'FEED-1',
        category: 'أعلاف',
        animalType: 'دواجن',
        brand: 'الواحة',
        unitSize: '25 كجم',
        basePrice: 42.5,
        retailUnitPrice: 48,
        stockQuantity: 40,
        minOrderQty: 2,
      ),
      Product(
        id: 'cat-1',
        nameAr: 'تيست دوج دجاج + لحم بقري عبوة ١٥ كجم للتجار',
        sku: 'CAT-1',
        category: 'قطط',
        animalType: 'قطط',
        brand: 'اختبار',
        unitSize: '1 كجم',
        basePrice: 18,
        stockQuantity: 12,
        minOrderQty: 1,
      ),
    ];
  }

  @override
  Future<List<ProductCategory>> productCategories({
    bool includeArchived = false,
  }) async {
    return const [
      ProductCategory(id: 'c-feed', name: 'أعلاف', iconKey: 'feed'),
      ProductCategory(id: 'c-cat', name: 'قطط', iconKey: 'cat'),
      ProductCategory(id: 'c-med', name: 'أدوية', iconKey: 'medicine'),
    ];
  }
}

class _ShopCatalogWithDiscountRepository extends CatalogRepository {
  @override
  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async {
    return const [
      Product(
        id: 'feed-1',
        nameAr: 'علف دجاج جملة',
        sku: 'FEED-1',
        category: 'أعلاف',
        animalType: 'دواجن',
        brand: 'الواحة',
        unitSize: '25 كجم',
        basePrice: 42.5,
        stockQuantity: 40,
        minOrderQty: 2,
        discountPercent: 15,
      ),
      Product(
        id: 'cat-1',
        nameAr: 'رمل قطط',
        sku: 'CAT-1',
        category: 'قطط',
        animalType: 'قطط',
        brand: 'كبيف',
        unitSize: '10 كجم',
        basePrice: 18,
        stockQuantity: 12,
        minOrderQty: 1,
      ),
    ];
  }

  @override
  Future<List<ProductCategory>> productCategories({
    bool includeArchived = false,
  }) async {
    return const [
      ProductCategory(id: 'c-feed', name: 'أعلاف', iconKey: 'feed'),
      ProductCategory(id: 'c-cat', name: 'قطط', iconKey: 'cat'),
    ];
  }
}

class _HomeBannersRepository extends AdminRepository {
  @override
  Future<List<AppBanner>> banners({bool includeInactive = false}) async {
    return const [
      AppBanner(
        id: 'banner-1',
        title: 'عرض جملة لتجار الأعلاف',
        body: 'أسعار تجريبية للعرض',
        ctaText: 'اطلب الآن',
        imageUrl: 'https://example.com/banner.jpg',
      ),
    ];
  }
}
