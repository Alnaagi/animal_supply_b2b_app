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
    'mobile product card stays compact while preserving operational details',
    (tester) async {
      const product = Product(
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
      );

      await _pumpAdminProducts(tester, [product]);

      final card =
          find.byKey(const ValueKey('admin-product-card-compact-product'));
      expect(card, findsOneWidget);
      expect(tester.getSize(card).height, lessThanOrEqualTo(200));

      expect(
        find.descendant(of: card, matching: find.text('ظاهر للعملاء')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('متاح للطلب')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('العدد للعملاء: مخفي'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('يبقى ظاهراً عند النفاد'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('12 في الصندوق')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('المخزون 34')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('المتاح 28')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('محجوز 6')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('أقل طلب 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('96.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('120.00')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-product-menu-compact-product')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('admin-product-menu-compact-product')),
      );
      await tester.pumpAndSettle();

      expect(find.text('تعديل'), findsOneWidget);
      expect(find.text('أرشفة المنتج'), findsOneWidget);
    },
  );

  testWidgets(
    '390px RTL mobile keeps category manager, card, and product form usable',
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
      await tester.ensureVisible(card);
      expect(card, findsOneWidget);
      expect(tester.getSize(card).width, lessThanOrEqualTo(390));
      expect(
        Directionality.of(tester.element(card)),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);

      final manager = find.byKey(const ValueKey('manage-categories-button'));
      await tester.ensureVisible(manager);
      await tester.tap(manager);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('إدارة التصنيفات'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(TextButton, 'إغلاق'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('منتج جديد'));
      await tester.pumpAndSettle();

      final scrollbar = find.byKey(const ValueKey('product-form-scrollbar'));
      expect(
        find.byKey(const ValueKey('product-form-scroll-hint')),
        findsOneWidget,
      );
      expect(scrollbar, findsOneWidget);
      expect(
        tester
            .widget<Scrollbar>(scrollbar)
            .controller!
            .position
            .maxScrollExtent,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('archived untracked card keeps its state and restore action',
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

    final card =
        find.byKey(const ValueKey('admin-product-card-archived-product'));
    expect(card, findsOneWidget);
    expect(tester.getSize(card).height, lessThanOrEqualTo(200));
    expect(
      find.descendant(of: card, matching: find.text('مؤرشف')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('المخزون غير متتبع')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('المخزون 9')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('العدد للعملاء: مخفي'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('admin-product-menu-archived-product')),
    );
    await tester.pumpAndSettle();

    expect(find.text('استعادة ونشر المنتج'), findsOneWidget);
  });
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
