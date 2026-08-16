import 'dart:convert';

import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/local/local_cache.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_products_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
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

  group('product inventory visibility', () {
    test('Supabase mapping and payload preserve customer quantity visibility',
        () {
      final visible = Product.fromSupabase({
        'id': 'visible-stock',
        'name': 'منتج ظاهر المخزون',
        'sku': 'VISIBLE-1',
        'category_name': 'أعلاف',
        'brand': 'المورد',
        'animal_type': 'أغنام',
        'unit_size': 'كيس',
        'base_price': 30,
        'stock_quantity': 18,
        'available_quantity': 12,
        'stock_tracking_enabled': true,
        'show_stock_quantity_to_customers': true,
        'min_order_quantity': 2,
      });
      final hiddenByDefault = Product.fromSupabase({
        'id': 'legacy-row',
        'name': 'منتج قديم',
        'sku': 'LEGACY-1',
        'category_name': 'عام',
        'base_price': 10,
        'stock_quantity': 4,
        'min_order_quantity': 1,
      });

      expect(visible.showStockQuantityToCustomers, isTrue);
      expect(
        visible.toSupabaseMap()['show_stock_quantity_to_customers'],
        isTrue,
      );
      expect(hiddenByDefault.showStockQuantityToCustomers, isFalse);
    });

    test('offline cache preserves visibility and legacy rows default to hidden',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = LocalCache(prefs: prefs);
      final visible = _existingProduct.copyWith(
        showStockQuantityToCustomers: true,
      );

      await cache.saveProducts(
        [visible],
        ownerProfileId: 'customer-stock-visibility',
      );

      final restored = LocalCache(prefs: prefs);
      final cached = (await restored.cachedProducts(
        ownerProfileId: 'customer-stock-visibility',
      ))
          .single;
      expect(cached.showStockQuantityToCustomers, isTrue);

      SharedPreferences.setMockInitialValues({
        'local_cache.products.v1': jsonEncode([
          {
            'id': 'legacy-cached-product',
            'nameAr': 'منتج مخزن قديماً',
            'sku': 'CACHE-LEGACY-1',
            'category': 'عام',
            'animalType': '',
            'brand': 'المورد',
            'unitSize': '',
            'basePrice': 12,
            'stockQuantity': 9,
            'minOrderQty': 1,
          },
        ]),
      });
      final legacyPrefs = await SharedPreferences.getInstance();
      final legacy = (await LocalCache(
        prefs: legacyPrefs,
      ).cachedProducts())
          .single;

      expect(legacy.showStockQuantityToCustomers, isFalse);
    });

    test('customer availability hides or shows only the exact quantity', () {
      final hidden = _existingProduct.copyWith(
        stockQuantity: 20,
        availableQuantity: 13,
        showStockQuantityToCustomers: false,
      );
      final visible = hidden.copyWith(showStockQuantityToCustomers: true);
      final untracked = visible.copyWith(stockTrackingEnabled: false);

      expect(hidden.customerAvailabilityLabel, 'متوفر للطلب');
      expect(hidden.customerAvailabilityLabel, isNot(contains('13')));
      expect(visible.customerAvailabilityLabel, 'متوفر 13');
      expect(untracked.customerAvailabilityLabel, 'متوفر للطلب');
    });
  });

  testWidgets(
      'mobile admin dialog keeps scroll affordances and supports categories '
      'with required internal stock', (tester) async {
    final repository = _RecordingCatalogRepository();
    await _pumpAdminProducts(tester, repository);
    await tester.tap(find.byTooltip('منتج جديد'));
    await tester.pumpAndSettle();

    final scrollHint = find.byKey(const ValueKey('product-form-scroll-hint'));
    final scrollbarFinder =
        find.byKey(const ValueKey('product-form-scrollbar'));
    final scrollView = find.byKey(const ValueKey('product-form-scroll-view'));
    final stockField = find.byKey(const ValueKey('product-stock-field'));
    final trackingSwitch =
        find.byKey(const ValueKey('product-track-stock-switch'));
    final quantityVisibilitySwitch = find.byKey(
      const ValueKey('product-show-stock-quantity-switch'),
    );

    expect(scrollHint, findsOneWidget);
    expect(scrollbarFinder, findsOneWidget);
    final scrollbar = tester.widget<Scrollbar>(scrollbarFinder);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.trackVisibility, isTrue);
    expect(scrollbar.controller, isNotNull);
    expect(scrollbar.controller!.position.maxScrollExtent, greaterThan(0));

    expect(stockField, findsOneWidget);
    expect(tester.widget<TextField>(stockField).controller!.text, isEmpty);
    expect(quantityVisibilitySwitch, findsOneWidget);
    expect(quantityVisibilitySwitch, isNot(trackingSwitch));
    expect(
      tester.widget<SwitchListTile>(trackingSwitch).value,
      isFalse,
    );
    expect(
      tester.widget<SwitchListTile>(quantityVisibilitySwitch).onChanged,
      isNull,
    );

    final categoryField = find.byKey(const ValueKey('product-category-field'));
    final existingCategoryCount = find.text('أعلاف').evaluate().length;
    await tester.tap(categoryField);
    await tester.enterText(categoryField, 'أع');
    await tester.pumpAndSettle();

    final offeredCategories = find.text('أعلاف');
    expect(
      offeredCategories.evaluate().length,
      greaterThan(existingCategoryCount),
    );
    await tester.tap(offeredCategories.last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(categoryField).controller!.text,
      'أعلاف',
    );

    await tester.ensureVisible(trackingSwitch);
    await tester.tap(trackingSwitch);
    await tester.pumpAndSettle();

    expect(stockField, findsOneWidget);
    expect(quantityVisibilitySwitch, findsOneWidget);
    expect(tester.widget<SwitchListTile>(trackingSwitch).value, isTrue);
    expect(
      tester.widget<SwitchListTile>(quantityVisibilitySwitch).onChanged,
      isNotNull,
    );
    expect(scrollHint, findsOneWidget);
    expect(scrollView, findsOneWidget);
  });

  testWidgets(
      'blank stock is rejected and saved demo product carries new category, '
      'stock, and customer visibility', (tester) async {
    final repository = _RecordingCatalogRepository();
    await _pumpAdminProducts(tester, repository);
    await tester.tap(find.byTooltip('منتج جديد'));
    await tester.pumpAndSettle();

    final categoryField = find.byKey(const ValueKey('product-category-field'));
    final scrollView = find.byKey(const ValueKey('product-form-scroll-view'));
    final stockField = find.byKey(const ValueKey('product-stock-field'));
    final quantityVisibilitySwitch = find.byKey(
      const ValueKey('product-show-stock-quantity-switch'),
    );

    await tester.enterText(
      find.byKey(const ValueKey('product-name-field')),
      'خلطة طيور تجريبية',
    );
    await tester.enterText(categoryField, 'مستلزمات طيور');
    await tester.enterText(
      find.byKey(const ValueKey('product-company-field')),
      'شركة الاختبار',
    );
    await tester.enterText(
      find.byKey(const ValueKey('product-price-field')),
      '45.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('product-retail-price-field')),
      '52',
    );
    await tester.enterText(
      find.byKey(const ValueKey('product-bulk-minimum-field')),
      '3',
    );

    final trackingSwitch =
        find.byKey(const ValueKey('product-track-stock-switch'));
    await tester.ensureVisible(trackingSwitch);
    expect(tester.widget<SwitchListTile>(trackingSwitch).value, isFalse);
    await tester.tap(trackingSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(trackingSwitch).value, isTrue);

    await tester.ensureVisible(quantityVisibilitySwitch);
    await tester.tap(quantityVisibilitySwitch);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(quantityVisibilitySwitch).value,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'حفظ المنتج'));
    await tester.pumpAndSettle();

    expect(repository.savedProduct, isNull);
    expect(
      find.byKey(const ValueKey('product-form-validation')),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(stockField).decoration!.errorText,
      'أدخل كمية مخزون صحيحة لا تقل عن صفر.',
    );
    expect(tester.widget<TextField>(stockField).focusNode!.hasFocus, isTrue);

    final scrollViewRect = tester.getRect(scrollView);
    final stockRect = tester.getRect(stockField);
    expect(
      scrollViewRect.overlaps(stockRect),
      isTrue,
      reason: 'invalid stock field should be scrolled into view',
    );

    await tester.enterText(stockField, '37');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ المنتج'));
    await tester.pumpAndSettle();

    final saved = repository.savedProduct;
    expect(saved, isNotNull);
    expect(saved!.category, 'مستلزمات طيور');
    expect(saved.categoryId, isNull);
    expect(saved.stockQuantity, 37);
    expect(saved.stockTrackingEnabled, isTrue);
    expect(saved.showStockQuantityToCustomers, isTrue);
    expect(saved.minOrderQty, 3);
  });

  testWidgets(
      'invalid product fields show inline errors and focus the first one',
      (tester) async {
    final repository = _RecordingCatalogRepository();
    await _pumpAdminProducts(tester, repository);
    await tester.tap(find.byTooltip('منتج جديد'));
    await tester.pumpAndSettle();

    final nameField = find.byKey(const ValueKey('product-name-field'));
    final categoryField = find.byKey(const ValueKey('product-category-field'));
    final companyField = find.byKey(const ValueKey('product-company-field'));
    final priceField = find.byKey(const ValueKey('product-price-field'));

    await tester.tap(find.widgetWithText(FilledButton, 'حفظ المنتج'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('product-form-validation')), findsNothing);
    expect(
      tester.widget<TextField>(nameField).decoration!.errorText,
      'أدخل اسم المنتج.',
    );
    expect(
      tester.widget<TextField>(categoryField).decoration!.errorText,
      'اختر تصنيفاً أو اكتب اسم تصنيف جديد.',
    );
    expect(
      tester.widget<TextField>(companyField).decoration!.errorText,
      'أدخل اسم الشركة.',
    );
    expect(
      tester.widget<TextField>(priceField).decoration!.errorText,
      'أدخل سعر جملة صحيحاً أكبر من صفر.',
    );
    expect(tester.widget<TextField>(nameField).focusNode!.hasFocus, isTrue);
    expect(repository.savedProduct, isNull);
  });
}

Future<void> _pumpAdminProducts(
  WidgetTester tester,
  _RecordingCatalogRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(646, 838));
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

class _RecordingCatalogRepository extends CatalogRepository {
  _RecordingCatalogRepository() : super.demo(seed: const [_existingProduct]);

  Product? savedProduct;

  @override
  Future<Product> saveProduct(Product product) async {
    savedProduct = product;
    return product;
  }
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'product-inventory-admin',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}

const _existingProduct = Product(
  id: 'existing-category-product',
  nameAr: 'علف موجود',
  sku: 'EXISTING-1',
  category: 'أعلاف',
  animalType: 'أغنام',
  brand: 'المورد',
  unitSize: 'كيس',
  basePrice: 30,
  stockQuantity: 20,
  availableQuantity: 13,
  minOrderQty: 2,
);
