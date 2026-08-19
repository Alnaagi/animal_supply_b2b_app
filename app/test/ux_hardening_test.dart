import 'package:animal_supply_b2b/src/core/widgets/quantity_selector.dart';
import 'package:animal_supply_b2b/src/core/widgets/responsive_field_group.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/change_password_screen.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_screen.dart';
import 'package:animal_supply_b2b/src/features/catalog/catalog_screen.dart';
import 'package:animal_supply_b2b/src/features/catalog/product_details_screen.dart';
import 'package:animal_supply_b2b/src/features/customer_home/customer_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catalog distinguishes a load failure and retries successfully',
      (tester) async {
    final repository = _RetryingCatalogRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CatalogScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-load-error')), findsOneWidget);
    expect(find.text('تعذر تحميل المنتجات'), findsOneWidget);
    expect(find.text('لا توجد منتجات'), findsNothing);

    await tester.tap(find.byKey(const Key('catalog-retry-button')));
    await tester.pumpAndSettle();

    expect(repository.productCalls, 2);
    expect(find.byKey(const Key('catalog-load-error')), findsNothing);
    expect(find.text(_product.name), findsOneWidget);
    expect(
      find.byTooltip('إضافة ${_product.name} إلى السلة'),
      findsOneWidget,
    );
  });

  testWidgets(
      'product details distinguishes a load failure and retries successfully',
      (tester) async {
    final repository = _RetryingProductRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ProductDetailsScreen(productId: 'product-1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('product-details-load-error')),
      findsOneWidget,
    );
    expect(find.text('تعذر تحميل تفاصيل المنتج'), findsOneWidget);
    expect(find.text('المنتج غير موجود'), findsNothing);

    await tester.tap(find.byKey(const Key('product-details-retry-button')));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(
      find.byKey(const Key('product-details-load-error')),
      findsNothing,
    );
    expect(find.text(_product.name), findsOneWidget);
    expect(find.byTooltip('نسخ بيانات المنتج'), findsOneWidget);
  });

  testWidgets('demo notice is explicit and exposed to assistive technology',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DemoModeNotice()),
      ),
    );

    expect(
      find.byKey(const Key('customer-demo-mode-notice')),
      findsOneWidget,
    );
    expect(find.text(DemoModeNotice.message), findsOneWidget);
    expect(
      find.bySemanticsLabel(DemoModeNotice.message),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('quantity controls expose Arabic labels and current value',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var changedTo = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuantitySelector(
            quantity: 2,
            min: 1,
            max: 5,
            onChanged: (value) => changedTo = value,
          ),
        ),
      ),
    );

    expect(find.byTooltip('تقليل الكمية'), findsOneWidget);
    expect(find.byTooltip('زيادة الكمية'), findsOneWidget);
    expect(find.bySemanticsLabel('الكمية الحالية: 2'), findsOneWidget);

    await tester.tap(find.byTooltip('زيادة الكمية'));
    expect(changedTo, 3);
    semantics.dispose();
  });

  testWidgets('cart removal control has a product-specific Arabic label',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartControllerProvider.overrideWith(
            (ref) => CartController(
              ref,
              ownerProfileId: null,
              initialItems: const [
                CartItem(product: _product, quantity: 2),
              ],
            ),
          ),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CartScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('حذف ${_product.name} من السلة'),
      findsOneWidget,
    );
  });

  testWidgets('password visibility control exposes its current action',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ChangePasswordScreen()),
      ),
    );
    await tester.pump();

    final toggle = find.byTooltip('إظهار كلمة المرور');
    expect(toggle, findsOneWidget);
    final visibilityButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'إظهار كلمة المرور',
    );
    expect(visibilityButton, findsOneWidget);
    final iconButton = tester.widget<IconButton>(visibilityButton);
    iconButton.onPressed!.call();
    await tester.pump();
    expect(find.byTooltip('إخفاء كلمة المرور'), findsOneWidget);
  });

  testWidgets('related form fields stack at phone width', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ResponsiveFieldGroup(
                columns: 3,
                children: [
                  SizedBox(key: Key('field-a'), height: 48),
                  SizedBox(key: Key('field-b'), height: 48),
                  SizedBox(key: Key('field-c'), height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final a = tester.getTopLeft(find.byKey(const Key('field-a')));
    final b = tester.getTopLeft(find.byKey(const Key('field-b')));
    final c = tester.getTopLeft(find.byKey(const Key('field-c')));
    expect(b.dy, greaterThan(a.dy));
    expect(c.dy, greaterThan(b.dy));
  });

  testWidgets('product placeholders expose an Arabic image label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProductImagePlaceholder(
            category: 'أعلاف',
            semanticLabel: 'صورة علف تجريبي',
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('صورة علف تجريبي'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('generated products use the icon without probing a missing asset',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProductImagePlaceholder(
            category: 'عام',
            productId: 'local-generated-product',
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.inventory_2), findsOneWidget);
  });
}

class _RetryingCatalogRepository extends CatalogRepository {
  int productCalls = 0;

  @override
  Future<CatalogPage> productsPage({
    String query = '',
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    String availability = 'all',
    bool includeInactive = false,
    DateTime? snapshotAt,
    int offset = 0,
    int pageSize = CatalogRepository.defaultPageSize,
  }) async {
    productCalls++;
    if (productCalls == 1) throw StateError('catalog unavailable');
    return CatalogPage(
      products: const [_product],
      hasMore: false,
      nextOffset: offset + 1,
      snapshotAt: snapshotAt ?? DateTime.utc(2026, 7, 22),
      source: CatalogPageSource.demo,
      offlineSnapshotCount: 1,
    );
  }

  @override
  Future<List<String>> categories() async => const ['أعلاف'];
}

class _RetryingProductRepository extends CatalogRepository {
  int calls = 0;

  @override
  Future<Product?> productById(String id) async {
    calls++;
    if (calls == 1) throw StateError('product unavailable');
    return _product;
  }
}

const _product = Product(
  id: 'product-1',
  nameAr: 'منتج بعد إعادة المحاولة',
  sku: 'RETRY-1',
  category: 'أعلاف',
  animalType: 'أغنام',
  brand: 'اختبار',
  unitSize: '25 كجم',
  basePrice: 40,
  stockQuantity: 100,
  minOrderQty: 1,
  descriptionAr: 'منتج مخصص لاختبار حالة إعادة المحاولة.',
);
