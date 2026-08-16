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

  testWidgets('customer home clusters actions and denser shop tiles',
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
          adminRepositoryProvider.overrideWithValue(_EmptyBannersRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CustomerHomeScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مرحباً، متجر الاختبار'), findsOneWidget);
    expect(find.text('طرابلس - حي الأندلس'), findsOneWidget);
    expect(find.text('التصنيفات'), findsOneWidget);
    expect(find.text('أعلاف'), findsOneWidget);
    expect(find.text('قطط'), findsOneWidget);
    expect(find.text('أدوية'), findsOneWidget);
    expect(find.byType(CategoryIconView), findsWidgets);
    expect(find.byKey(const Key('customer-home-shop-logo')), findsOneWidget);
    expect(find.text('علف دجاج جملة'), findsOneWidget);
    expect(find.text('25 كجم'), findsOneWidget);
    expect(find.text('عرض الكل'), findsNWidgets(2));

    final search = tester.getRect(find.byKey(const Key('customer-home-search')));
    expect(search.left, greaterThanOrEqualTo(12));
    expect(search.width, greaterThanOrEqualTo(40));
    expect(search.height, greaterThanOrEqualTo(40));

    final title = tester.getRect(find.text('التصنيفات'));
    final viewAll = tester.getRect(find.text('عرض الكل').first);
    expect((title.left - viewAll.right).abs(), lessThan(88));

    final feedTile = tester.getRect(
      find.byKey(const Key('customer-home-category-أعلاف')),
    );
    expect(feedTile.width, greaterThanOrEqualTo(72));
    expect(feedTile.width, lessThan(110));
    expect(feedTile.height, greaterThanOrEqualTo(88));
    expect(feedTile.height, lessThan(120));

    final nameStyle = tester.widget<Text>(find.text('علف دجاج جملة')).style;
    expect(nameStyle?.fontSize, greaterThanOrEqualTo(15));
    expect(nameStyle?.fontWeight, FontWeight.w900);
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
        stockQuantity: 40,
        minOrderQty: 2,
      ),
      Product(
        id: 'cat-1',
        nameAr: 'أكل قطط جاف',
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

class _EmptyBannersRepository extends AdminRepository {
  @override
  Future<List<AppBanner>> banners({bool includeInactive = false}) async {
    return const [];
  }
}
