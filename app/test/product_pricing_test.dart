import 'dart:convert';

import 'package:animal_supply_b2b/src/data/local/local_cache.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/demo_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('catalog mapping displays effective price without replacing base price',
      () {
    final product = Product.fromSupabase({
      'id': 'product-1',
      'name': 'علف اختبار',
      'sku': 'TEST-1',
      'category_name': 'أعلاف',
      'base_price': 25,
      'effective_price': 17.5,
      'stock_quantity': 10,
      'min_order_quantity': 2,
    });

    expect(product.category, 'أعلاف');
    expect(product.basePrice, 25);
    expect(product.effectivePrice, 17.5);
    expect(product.price, 17.5);
    expect(product.toSupabaseMap()['base_price'], 25);
    expect(product.toSupabaseMap(), isNot(contains('effective_price')));
  });

  test('catalog mapping falls back to base price without an effective price',
      () {
    final product = Product.fromSupabase({
      'id': 'product-1',
      'name': 'علف اختبار',
      'sku': 'TEST-1',
      'base_price': '25.50',
      'stock_quantity': 10,
      'min_order_quantity': 1,
    });

    expect(product.basePrice, 25.5);
    expect(product.effectivePrice, isNull);
    expect(product.price, 25.5);
    expect(product.retailUnitPrice, isNull);
    expect(product.unitsPerBox, isNull);
    expect(product.stockTrackingEnabled, isTrue);
    expect(product.hideWhenOutOfStock, isFalse);
  });

  test('product mapping preserves wholesale display and stock controls', () {
    final product = Product.fromSupabase({
      'id': 'product-controls',
      'name': 'مكمل غذائي',
      'sku': 'SUP-1',
      'category_name': 'مكملات',
      'base_price': 120,
      'retail_unit_price': '15.50',
      'stock_quantity': 0,
      'stock_tracking_enabled': false,
      'hide_when_out_of_stock': true,
      'units_per_box': 12,
      'min_order_quantity': 3,
    });

    expect(product.basePrice, 120);
    expect(product.retailUnitPrice, 15.5);
    expect(product.unitsPerBox, 12);
    expect(product.unitsPerBoxLabel, '12 قطعة في الصندوق');
    expect(product.stockTrackingEnabled, isFalse);
    expect(product.hideWhenOutOfStock, isTrue);
    expect(product.isOrderable, isTrue);

    final payload = product.toSupabaseMap();
    expect(payload['base_price'], 120);
    expect(payload['retail_unit_price'], 15.5);
    expect(payload['units_per_box'], 12);
    expect(payload['stock_tracking_enabled'], isFalse);
    expect(payload['hide_when_out_of_stock'], isTrue);
  });

  test('offline cache preserves pricing, box, and stock-control fields',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    const product = Product(
      id: 'product-1',
      nameAr: 'علف اختبار',
      sku: 'TEST-1',
      category: 'أعلاف',
      animalType: 'ماشية',
      brand: 'اختبار',
      unitSize: 'كيس',
      basePrice: 25,
      effectivePrice: 17.5,
      retailUnitPrice: 3.25,
      stockQuantity: 0,
      stockTrackingEnabled: false,
      hideWhenOutOfStock: true,
      unitsPerBox: 24,
      minOrderQty: 2,
    );

    await cache.saveProducts(
      [product],
      ownerProfileId: 'customer-profile-1',
    );

    final restored = LocalCache(prefs: prefs);
    final cached = (await restored.cachedProducts(
      ownerProfileId: 'customer-profile-1',
    ))
        .single;
    expect(cached.basePrice, 25);
    expect(cached.effectivePrice, 17.5);
    expect(cached.price, 17.5);
    expect(cached.retailUnitPrice, 3.25);
    expect(cached.unitsPerBox, 24);
    expect(cached.stockTrackingEnabled, isFalse);
    expect(cached.hideWhenOutOfStock, isTrue);
    expect(cached.isOrderable, isTrue);
    expect(
      await restored.cachedProducts(
        ownerProfileId: 'customer-profile-2',
      ),
      isEmpty,
    );
  });

  test('legacy cached product rows receive safe stock-control defaults',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'local_cache.products.v1',
      jsonEncode([
        {
          'id': 'legacy-product',
          'nameAr': 'منتج قديم',
          'sku': 'LEGACY-1',
          'category': 'عام',
          'animalType': '',
          'brand': 'شركة قديمة',
          'unitSize': '',
          'basePrice': 10,
          'stockQuantity': 0,
          'minOrderQty': 2,
        },
      ]),
    );

    final product = (await LocalCache(prefs: prefs).cachedProducts()).single;

    expect(product.retailUnitPrice, isNull);
    expect(product.unitsPerBox, isNull);
    expect(product.stockTrackingEnabled, isTrue);
    expect(product.hideWhenOutOfStock, isFalse);
    expect(product.isOrderable, isFalse);
  });

  test('catalog mapping uses reservation-adjusted availability', () {
    final product = Product.fromSupabase({
      'id': 'product-availability',
      'name': 'منتج',
      'sku': 'AVL-1',
      'category_name': 'أغذية',
      'base_price': 10,
      'stock_quantity': 20,
      'available_quantity': 7,
      'min_order_quantity': 2,
      'active': true,
    });
    expect(product.stockQuantity, 20);
    expect(product.orderableStockQuantity, 7);
    expect(product.reservedQuantity, 13);
  });

  test('demo catalog applies the customer discount without replacing base price',
      () {
    expect(demoProducts, isNotEmpty);
    for (final product in demoProducts) {
      expect(product.retailUnitPrice, isNotNull);
      expect(product.retailUnitPrice, greaterThan(product.basePrice));
      final expected =
          (product.basePrice * (100 - demoCustomer.discountPercent)).round() /
              100;
      expect(product.price, expected < 0.01 ? 0.01 : expected);
      expect(product.effectivePrice, product.price);
      expect(product.basePrice, greaterThan(product.price));
    }
  });

  test('demo admin sorting and filtering use base prices', () async {
    final repository = CatalogRepository.demo(seed: const [
      Product(
        id: 'discounted-high-base',
        nameAr: 'أ',
        sku: 'A',
        category: 'اختبار',
        animalType: '',
        brand: '',
        unitSize: 'قطعة',
        basePrice: 100,
        effectivePrice: 10,
        stockQuantity: 10,
        minOrderQty: 1,
      ),
      Product(
        id: 'discounted-low-base',
        nameAr: 'ب',
        sku: 'B',
        category: 'اختبار',
        animalType: '',
        brand: '',
        unitSize: 'قطعة',
        basePrice: 50,
        effectivePrice: 40,
        stockQuantity: 10,
        minOrderQty: 1,
      ),
    ]);

    final customerPage = await repository.productsPageSorted(
      sort: 'price_asc',
    );
    expect(customerPage.products.first.id, 'discounted-high-base');

    final adminPage = await repository.productsPageSorted(
      includeInactive: true,
      sort: 'price_asc',
      minimumPrice: 45,
    );
    expect(
      adminPage.products.map((product) => product.id),
      ['discounted-low-base', 'discounted-high-base'],
    );
  });
}
