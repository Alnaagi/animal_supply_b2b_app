import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_product_discount_helpers.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_products_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'operational card shows hierarchy, quick actions, and discount badge',
    (tester) async {
      final product = applyProductDiscount(
        const Product(
          id: 'compact-product',
          nameAr: 'رويال كانين طعام قطط بالغة Fit 32 - 2 كجم',
          sku: 'RC-CAT-FIT32-2KG',
          category: 'قطط',
          animalType: 'قطط',
          brand: 'Royal Canin',
          unitSize: '2 كجم',
          basePrice: 96,
          retailUnitPrice: 120,
          stockQuantity: 34,
          availableQuantity: 28,
          showStockQuantityToCustomers: false,
          hideWhenOutOfStock: false,
          unitsPerBox: 12,
          minOrderQty: 2,
          isFeatured: true,
        ),
        13,
      );

      await _pumpAdminProducts(tester, [product]);

      final card =
          find.byKey(const ValueKey('admin-product-card-compact-product'));
      await tester.scrollUntilVisible(
        card,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);

      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Royal Canin • قطط'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('admin-product-discount-badge-compact-product'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-product-quick-price-compact-product')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('admin-product-quick-discount-compact-product'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-product-quick-stock-compact-product')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overflow menu opens full edit dialog', (tester) async {
    const product = Product(
      id: 'tap-edit-product',
      nameAr: 'منتج للضغط والتعديل',
      sku: 'TAP-EDIT-1',
      category: 'قطط',
      animalType: 'قطط',
      brand: 'العلامة',
      unitSize: '1 كجم',
      basePrice: 40,
      stockQuantity: 11,
      availableQuantity: 11,
      unitsPerBox: 10,
      minOrderQty: 1,
    );

    await _pumpAdminProducts(tester, [product]);

    await tester.tap(
      find.byKey(const ValueKey('admin-product-menu-tap-edit-product')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعديل كامل'));
    await tester.pumpAndSettle();

    expect(find.text('تعديل المنتج'), findsWidgets);
    expect(find.text('صورة المنتج'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '390px RTL mobile keeps quick filters and card usable',
    (tester) async {
      const product = Product(
        id: 'narrow-mobile-product',
        nameAr: 'طعام قطط متكامل للاختبار على شاشة هاتف ضيقة',
        sku: 'NARROW-1',
        category: 'قطط',
        categoryId: 'cats',
        animalType: 'قطط',
        brand: 'شركة الاختبار',
        unitSize: '2 كجم',
        basePrice: 64,
        retailUnitPrice: 78,
        stockQuantity: 24,
        availableQuantity: 20,
        showStockQuantityToCustomers: true,
        unitsPerBox: 12,
        minOrderQty: 2,
      );

      await _pumpAdminProducts(
        tester,
        [product],
        surfaceSize: const Size(390, 844),
      );

      final card = find.byKey(
        const ValueKey('admin-product-card-narrow-mobile-product'),
      );
      await tester.scrollUntilVisible(
        card,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(tester.getSize(card).width, lessThanOrEqualTo(390));
      expect(
        Directionality.of(tester.element(card)),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('archived product shows restore in overflow menu',
      (tester) async {
    final product = Product(
      id: 'archived-product',
      nameAr: 'منتج مؤرشف',
      sku: 'ARCHIVED-1',
      category: 'عام',
      animalType: 'قطط',
      brand: 'المورد',
      unitSize: 'قطعة',
      basePrice: 20,
      stockQuantity: 9,
      stockTrackingEnabled: false,
      minOrderQty: 1,
      isActive: false,
      archivedAt: DateTime.utc(2026, 8, 14),
    );

    await _pumpAdminProducts(tester, [product]);

    await tester.tap(
      find.byKey(const ValueKey('admin-product-menu-archived-product')),
    );
    await tester.pumpAndSettle();

    expect(find.text('استعادة ونشر المنتج'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'category chips wrap onto new lines instead of scrolling off-screen',
    (tester) async {
      const surface = Size(390, 844);
      const products = [
        Product(
          id: 'wrap-dry-cat',
          nameAr: 'اكل جاف للقطط',
          sku: 'WRAP-DRY',
          category: 'اكل جاف للقطط',
          animalType: 'قطط',
          brand: 'العلامة',
          unitSize: '2 كجم',
          basePrice: 40,
          stockQuantity: 10,
          minOrderQty: 1,
        ),
        Product(
          id: 'wrap-wet',
          nameAr: 'اكل رطب',
          sku: 'WRAP-WET',
          category: 'اكل رطب',
          animalType: 'قطط',
          brand: 'العلامة',
          unitSize: '85 جم',
          basePrice: 12,
          stockQuantity: 20,
          minOrderQty: 1,
        ),
      ];

      await _pumpAdminProducts(tester, products, surfaceSize: surface);

      final wrap = find.byKey(const ValueKey('admin-products-category-chips'));
      expect(wrap, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpAdminProducts(
  WidgetTester tester,
  List<Product> products, {
  Size surfaceSize = const Size(646, 838),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/admin/products',
    routes: [
      GoRoute(
        path: '/admin/products',
        builder: (context, state) => const AdminProductsScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _AdminAuthController(),
        ),
        catalogRepositoryProvider.overrideWithValue(
          CatalogRepository.demo(seed: products),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'card-layout-admin',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
