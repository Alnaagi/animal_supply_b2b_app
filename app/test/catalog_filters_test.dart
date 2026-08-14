import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/catalog/catalog_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final products = [
    _product(
      id: 'available',
      brand: 'ألف',
      animalType: 'قطط',
      packageSize: '1 كجم',
      price: 20,
      stock: 30,
    ),
    _product(
      id: 'low',
      brand: 'باء',
      animalType: 'كلاب',
      packageSize: '5 كجم',
      price: 40,
      stock: 8,
    ),
    _product(
      id: 'reserved',
      brand: 'ألف',
      animalType: 'قطط',
      packageSize: '1 كجم',
      price: 60,
      stock: 20,
      available: 0,
    ),
  ];

  test('combines product attributes, price, and authoritative availability',
      () {
    final result = applyCatalogFilters(
      products,
      const CatalogFilters(
        brand: 'ألف',
        animalType: 'قطط',
        unitSize: '1 كجم',
        minimumPrice: 50,
        availability: CatalogAvailability.outOfStock,
      ),
    );

    expect(result.map((product) => product.id), ['reserved']);
  });

  test('low-stock filter excludes unavailable and healthy stock', () {
    final result = applyCatalogFilters(
      products,
      const CatalogFilters(availability: CatalogAvailability.lowStock),
    );

    expect(result.map((product) => product.id), ['low']);
  });

  test('untracked products remain orderable and never appear as sold out', () {
    final untracked = _product(
      id: 'untracked',
      brand: 'جيم',
      animalType: 'طيور',
      packageSize: 'صندوق',
      price: 80,
      stock: 0,
      minimumOrder: 12,
      stockTrackingEnabled: false,
      hideWhenOutOfStock: true,
    );

    expect(
      applyCatalogFilters(
        [untracked],
        const CatalogFilters(availability: CatalogAvailability.inStock),
      ),
      [untracked],
    );
    expect(
      applyCatalogFilters(
        [untracked],
        const CatalogFilters(availability: CatalogAvailability.outOfStock),
      ),
      isEmpty,
    );
  });

  test(
      'customer catalog hides configured unavailable products but keeps '
      'visible sold-out products', () async {
    final repository = CatalogRepository.demo(
      seed: [
        _product(
          id: 'sold-out-visible',
          brand: 'ألف',
          animalType: 'قطط',
          packageSize: 'صندوق',
          price: 20,
          stock: 0,
        ),
        _product(
          id: 'below-moq-visible',
          brand: 'ألف',
          animalType: 'قطط',
          packageSize: 'صندوق',
          price: 25,
          stock: 2,
          minimumOrder: 3,
        ),
        _product(
          id: 'sold-out-hidden',
          brand: 'ألف',
          animalType: 'قطط',
          packageSize: 'صندوق',
          price: 30,
          stock: 0,
          hideWhenOutOfStock: true,
        ),
        _product(
          id: 'untracked',
          brand: 'ألف',
          animalType: 'قطط',
          packageSize: 'صندوق',
          price: 35,
          stock: 0,
          minimumOrder: 12,
          stockTrackingEnabled: false,
          hideWhenOutOfStock: true,
        ),
        _product(
          id: 'inactive',
          brand: 'ألف',
          animalType: 'قطط',
          packageSize: 'صندوق',
          price: 40,
          stock: 10,
          active: false,
        ),
        _product(
          id: 'archived',
          brand: 'ألف',
          animalType: 'قطط',
          packageSize: 'صندوق',
          price: 45,
          stock: 10,
          archivedAt: DateTime.utc(2026, 7, 21),
        ),
      ],
    );

    final visible = await repository.productsPage();
    expect(
      visible.products.map((product) => product.id),
      ['sold-out-visible', 'below-moq-visible', 'untracked'],
    );

    final unavailable =
        await repository.productsPage(availability: 'out_of_stock');
    expect(
      unavailable.products.map((product) => product.id),
      ['sold-out-visible', 'below-moq-visible'],
    );

    final available = await repository.productsPage(availability: 'in_stock');
    expect(available.products.map((product) => product.id), ['untracked']);

    final admin = await repository.productsPage(includeInactive: true);
    expect(
      admin.products.map((product) => product.id),
      [
        'sold-out-visible',
        'below-moq-visible',
        'sold-out-hidden',
        'untracked',
        'inactive',
        'archived',
      ],
    );
  });
}

Product _product({
  required String id,
  required String brand,
  required String animalType,
  required String packageSize,
  required double price,
  required int stock,
  int? available,
  int minimumOrder = 1,
  bool stockTrackingEnabled = true,
  bool hideWhenOutOfStock = false,
  bool active = true,
  DateTime? archivedAt,
}) {
  return Product(
    id: id,
    nameAr: id,
    sku: 'SKU-$id',
    category: 'اختبار',
    animalType: animalType,
    brand: brand,
    unitSize: packageSize,
    packageSize: packageSize,
    basePrice: price,
    stockQuantity: stock,
    availableQuantity: available,
    stockTrackingEnabled: stockTrackingEnabled,
    hideWhenOutOfStock: hideWhenOutOfStock,
    minOrderQty: minimumOrder,
    isActive: active,
    archivedAt: archivedAt,
  );
}
