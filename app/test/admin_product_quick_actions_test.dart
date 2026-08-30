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

  group('discount helpers', () {
    test('apply and clear discount follow base price model', () {
      const product = Product(
        id: 'p1',
        nameAr: 'منتج',
        sku: 'SKU1',
        category: 'قطط',
        animalType: 'قطط',
        brand: 'Brand',
        unitSize: '1',
        basePrice: 100,
        stockQuantity: 5,
        minOrderQty: 1,
      );
      final discounted = applyProductDiscount(product, 10);
      expect(discounted.discountPercent, 10);
      expect(discounted.price, closeTo(90, 0.001));
      final cleared = clearProductDiscount(discounted);
      expect(cleared.discountPercent, isNull);
      expect(cleared.price, 100);
    });

    test('clearProductDiscount serializes zero for Supabase persistence', () {
      const product = Product(
        id: 'p1',
        nameAr: 'منتج',
        sku: 'SKU1',
        category: 'قطط',
        animalType: 'قطط',
        brand: 'Brand',
        unitSize: '1',
        basePrice: 100,
        stockQuantity: 5,
        minOrderQty: 1,
      );
      final cleared = clearProductDiscount(applyProductDiscount(product, 10));
      expect(cleared.toSupabaseMap()['discount_percent'], 0);
    });

    test('bulk adjusted price never goes below zero', () {
      expect(bulkAdjustedPrice(10, percentDelta: -200), 0);
      expect(bulkAdjustedPrice(100, percentDelta: 10), closeTo(110, 0.001));
    });
  });

  testWidgets('quick price edit saves via repository', (tester) async {
    final repo = _TrackingCatalogRepository([
      _seedProduct(id: 'price-product', basePrice: 80),
    ]);

    await _pumpAdminProducts(tester, repo);
    expect(find.textContaining('80.00'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('admin-product-quick-price-price-product')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('admin-quick-price-field')),
      '95',
    );
    await tester.tap(find.byKey(const ValueKey('admin-quick-price-save')));
    await tester.pumpAndSettle();

    final product = (await repo.snapshot()).firstWhere(
      (item) => item.id == 'price-product',
    );
    expect(product.basePrice, 95);
    expect(find.textContaining('95.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discount preset applies discount', (tester) async {
    final repo = _TrackingCatalogRepository([
      _seedProduct(id: 'disc-product', basePrice: 200),
    ]);
    await _pumpAdminProducts(tester, repo);

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('admin-product-quick-discount-disc-product'),
      ),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('admin-product-quick-discount-disc-product')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-discount-preset-10')));
    await tester.tap(find.byKey(const ValueKey('admin-discount-apply')));
    await tester.pumpAndSettle();

    final product = (await repo.snapshot()).firstWhere(
      (item) => item.id == 'disc-product',
    );
    expect(product.discountPercent, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discount remove clears discount', (tester) async {
    final repo = _TrackingCatalogRepository([
      applyProductDiscount(
        _seedProduct(id: 'disc-product', basePrice: 200),
        10,
      ),
    ]);
    await _pumpAdminProducts(tester, repo);

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('admin-product-quick-discount-disc-product'),
      ),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('admin-product-quick-discount-disc-product')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-discount-remove')));
    await tester.pumpAndSettle();

    final product = (await repo.snapshot()).firstWhere(
      (item) => item.id == 'disc-product',
    );
    expect(product.discountPercent, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discount remove survives Supabase round-trip save',
      (tester) async {
    final repo = _SupabaseRoundTripCatalogRepository([
      applyProductDiscount(
        _seedProduct(id: 'disc-product', basePrice: 200),
        10,
      ),
    ]);
    await _pumpAdminProducts(tester, repo);

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('admin-product-quick-discount-disc-product'),
      ),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('admin-product-quick-discount-disc-product')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-discount-remove')));
    await tester.pumpAndSettle();

    final product = (await repo.snapshot()).firstWhere(
      (item) => item.id == 'disc-product',
    );
    expect(product.hasProductDiscount, isFalse);
    expect((product.discountPercent ?? 0), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('featured toggle rolls back when save fails', (tester) async {
    final repo = _FailingCatalogRepository([
      _seedProduct(id: 'feat-product', isFeatured: false),
    ]);
    await _pumpAdminProducts(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('admin-product-featured-feat-product')),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.star_border), findsWidgets);
    expect(find.textContaining('تم التراجع'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stock sheet prevents negative quantity', (tester) async {
    final repo = _TrackingCatalogRepository([
      _seedProduct(id: 'stock-product', stockQuantity: 2),
    ]);
    await _pumpAdminProducts(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('admin-product-quick-stock-stock-product')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin-stock-minus-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-stock-save')));
    await tester.pumpAndSettle();

    final product = (await repo.snapshot()).firstWhere(
      (item) => item.id == 'stock-product',
    );
    expect(product.stockQuantity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full edit and archive confirm still work', (tester) async {
    final repo = _TrackingCatalogRepository([
      _seedProduct(id: 'archive-product'),
    ]);
    await _pumpAdminProducts(tester, repo);

    await tester.tap(
      find.byKey(const ValueKey('admin-product-menu-archive-product')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعديل كامل'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل المنتج'), findsWidgets);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('admin-product-menu-archive-product')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('أرشفة'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد أرشفة المنتج'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi-select bulk discount shows confirmation summary',
      (tester) async {
    final repo = _TrackingCatalogRepository([
      _seedProduct(id: 'bulk-a'),
      _seedProduct(id: 'bulk-b'),
    ]);
    await _pumpAdminProducts(
      tester,
      repo,
      surfaceSize: const Size(646, 1200),
    );

    await tester.tap(
      find.byKey(const ValueKey('admin-products-multi-select-toggle')),
    );
    await tester.pumpAndSettle();

    for (final id in ['bulk-a', 'bulk-b']) {
      final checkbox = find.byKey(ValueKey('admin-product-select-$id'));
      await tester.scrollUntilVisible(
        checkbox,
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
    }

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('admin-bulk-discount')),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('admin-bulk-discount')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('معاينة وتأكيد'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 منتج /'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers quick filter shows discounted products only',
      (tester) async {
    final repo = _TrackingCatalogRepository([
      _seedProduct(id: 'plain'),
      applyProductDiscount(_seedProduct(id: 'offer'), 15),
    ]);
    await _pumpAdminProducts(tester, repo);

    await tester.tap(find.byKey(const ValueKey('admin-quick-filter-offers')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('admin-product-card-offer')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('admin-product-card-plain')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Product _seedProduct({
  required String id,
  double basePrice = 50,
  int stockQuantity = 10,
  bool isFeatured = false,
}) {
  return Product(
    id: id,
    nameAr: 'منتج $id',
    sku: 'SKU-$id',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'Brand',
    unitSize: '1 كجم',
    basePrice: basePrice,
    stockQuantity: stockQuantity,
    availableQuantity: stockQuantity,
    minOrderQty: 1,
    isFeatured: isFeatured,
  );
}

class _TrackingCatalogRepository extends CatalogRepository {
  _TrackingCatalogRepository(List<Product> seed) : super.demo(seed: seed);

  Future<List<Product>> snapshot() => products(includeInactive: true);
}

class _FailingCatalogRepository extends CatalogRepository {
  _FailingCatalogRepository(List<Product> seed) : super.demo(seed: seed);

  @override
  Future<Product> saveProduct(Product product) async {
    throw StateError('network fail');
  }
}

class _SupabaseRoundTripCatalogRepository extends _TrackingCatalogRepository {
  _SupabaseRoundTripCatalogRepository(super.seed);

  @override
  Future<Product> saveProduct(Product product) async {
    final payload = product.toSupabaseMap();
    final prior = (await products(includeInactive: true))
        .firstWhere((item) => item.id == product.id);
    // products.discount_percent is NOT NULL in Supabase; null payloads do not clear it.
    final persistedDiscount =
        payload['discount_percent'] ?? prior.discountPercent ?? 0;
    final saved = Product.fromSupabase({
      'id': product.id,
      'name': product.nameAr,
      'sku': product.sku,
      'category_name': product.category,
      'base_price': product.basePrice,
      'old_price': payload['old_price'] ?? prior.oldPrice,
      'discount_percent': persistedDiscount,
      'stock_quantity': product.stockQuantity,
      'min_order_quantity': product.minOrderQty,
      'active': product.isActive,
    });
    return super.saveProduct(saved);
  }
}

Future<void> _pumpAdminProducts(
  WidgetTester tester,
  CatalogRepository repository, {
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
        catalogRepositoryProvider.overrideWithValue(repository),
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
        id: 'quick-actions-admin',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
