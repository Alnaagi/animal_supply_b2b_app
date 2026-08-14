import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_products_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'admin switches detailed, compact, and grid product views without overflow',
    (tester) async {
      await _pumpAdminProducts(
        tester,
        surfaceSize: const Size(646, 838),
      );

      expect(
        find.byKey(const ValueKey('admin-product-card-budget')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-product-compact-budget')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('admin-product-grid-budget')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-products-view-compact')),
      );

      expect(
        find.byKey(const ValueKey('admin-product-compact-budget')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-product-grid-budget')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-products-view-grid')),
      );

      expect(
        find.byKey(const ValueKey('admin-product-grid-budget')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-product-compact-budget')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'price descending sort applies to the complete demo result set',
    (tester) async {
      await _pumpAdminProducts(
        tester,
        surfaceSize: const Size(646, 838),
      );

      expect(
        _resultCardKeys(tester),
        const [
          'admin-product-card-budget',
          'admin-product-card-other-low',
          'admin-product-card-target-low',
          'admin-product-card-premium',
        ],
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-products-sort-button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('admin-products-sort-price_desc')),
      );
      await tester.pumpAndSettle();

      expect(
        _resultCardKeys(tester),
        const [
          'admin-product-card-premium',
          'admin-product-card-target-low',
          'admin-product-card-other-low',
          'admin-product-card-budget',
        ],
      );
      expect(find.text('السعر: الأعلى أولاً'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'brand and low-stock filters combine, show chips, and clear cleanly',
    (tester) async {
      await _pumpAdminProducts(
        tester,
        surfaceSize: const Size(646, 838),
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-products-filter-button')),
      );
      expect(
        find.byKey(const ValueKey('admin-products-filter-sheet')),
        findsOneWidget,
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-products-filter-brand')),
      );
      await tester.tap(find.text('شركة الهدف').hitTestable().last);
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.byKey(
          const ValueKey('admin-products-filter-availability-all'),
        ),
      );
      await tester.tap(find.text('مخزون منخفض').hitTestable().last);
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-products-apply-filters')),
      );

      expect(
        _resultCardKeys(tester),
        const ['admin-product-card-target-low'],
      );
      final activeFilters =
          find.byKey(const ValueKey('admin-products-active-filters'));
      expect(activeFilters, findsOneWidget);
      expect(
        find.descendant(
          of: activeFilters,
          matching: find.text('الشركة: شركة الهدف'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: activeFilters,
          matching: find.text('المخزون: منخفض'),
        ),
        findsOneWidget,
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('clear-admin-product-filters')),
      );

      expect(
        _resultCardKeys(tester),
        const [
          'admin-product-card-budget',
          'admin-product-card-other-low',
          'admin-product-card-target-low',
          'admin-product-card-premium',
        ],
      );
      expect(activeFilters, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '390px RTL grid and product filter sheet remain inside the viewport',
    (tester) async {
      const surfaceSize = Size(390, 844);
      await _pumpAdminProducts(
        tester,
        surfaceSize: surfaceSize,
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-products-view-grid')),
      );

      final gridProduct =
          find.byKey(const ValueKey('admin-product-grid-budget'));
      await tester.ensureVisible(gridProduct);
      await tester.pumpAndSettle();

      expect(gridProduct, findsOneWidget);
      expect(
        Directionality.of(tester.element(gridProduct)),
        TextDirection.rtl,
      );
      final gridRect = tester.getRect(gridProduct);
      expect(gridRect.left, greaterThanOrEqualTo(0));
      expect(gridRect.right, lessThanOrEqualTo(surfaceSize.width));
      expect(tester.takeException(), isNull);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-products-filter-button')),
      );

      final sheet = find.byKey(const ValueKey('admin-products-filter-sheet'));
      expect(sheet, findsOneWidget);
      expect(Directionality.of(tester.element(sheet)), TextDirection.rtl);
      final sheetRect = tester.getRect(sheet);
      expect(sheetRect.left, greaterThanOrEqualTo(0));
      expect(sheetRect.right, lessThanOrEqualTo(surfaceSize.width));
      expect(sheetRect.height, lessThanOrEqualTo(surfaceSize.height));

      await tester.ensureVisible(
        find.byKey(
          const ValueKey('admin-products-filter-availability-all'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('admin-products-apply-filters')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpAdminProducts(
  WidgetTester tester, {
  required Size surfaceSize,
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
          CatalogRepository.demo(seed: _products),
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

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<String> _resultCardKeys(WidgetTester tester) {
  final results = tester.widget<Column>(
    find.byKey(const ValueKey('admin-products-results')),
  );
  return [
    for (final child in results.children)
      if (child.key case ValueKey<String>(value: final value)) value,
  ];
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'browse-controls-admin',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}

final _products = [
  Product(
    id: 'budget',
    nameAr: 'منتج اقتصادي',
    sku: 'BUDGET-1',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'شركة أخرى',
    unitSize: '1 كجم',
    basePrice: 40,
    stockQuantity: 18,
    minOrderQty: 1,
    createdAt: DateTime.utc(2026, 8, 14, 12),
  ),
  Product(
    id: 'other-low',
    nameAr: 'منتج منخفض من شركة أخرى',
    sku: 'OTHER-LOW-1',
    category: 'كلاب',
    animalType: 'كلاب',
    brand: 'شركة أخرى',
    unitSize: '2 كجم',
    basePrice: 90,
    stockQuantity: 3,
    minOrderQty: 1,
    createdAt: DateTime.utc(2026, 8, 14, 11),
  ),
  Product(
    id: 'target-low',
    nameAr: 'منتج الهدف منخفض المخزون',
    sku: 'TARGET-LOW-1',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'شركة الهدف',
    unitSize: '2 كجم',
    basePrice: 220,
    stockQuantity: 5,
    minOrderQty: 1,
    createdAt: DateTime.utc(2026, 8, 14, 10),
  ),
  Product(
    id: 'premium',
    nameAr: 'منتج فاخر مرتفع السعر',
    sku: 'PREMIUM-1',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'شركة الهدف',
    unitSize: '5 كجم',
    basePrice: 300,
    stockQuantity: 30,
    minOrderQty: 1,
    createdAt: DateTime.utc(2026, 8, 14, 9),
  ),
];
