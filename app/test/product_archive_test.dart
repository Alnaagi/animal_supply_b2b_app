import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({required bool active, DateTime? archivedAt}) => Product(
      id: 'product-1',
      nameAr: 'منتج',
      sku: 'SKU-1',
      category: 'قطط',
      animalType: 'قطط',
      brand: 'علامة',
      unitSize: '1 كجم',
      basePrice: 10,
      stockQuantity: 12,
      minOrderQty: 1,
      isActive: active,
      archivedAt: archivedAt,
    );

void main() {
  test('customer visibility can be disabled without archiving the product', () {
    final product = _product(active: false);
    final payload = product.toSupabaseMap();

    expect(payload['active'], isFalse);
    expect(payload['archived_at'], isNull);
    expect(product.isArchived, isFalse);
  });

  test('archive state remains independent from the visibility toggle', () {
    final archivedAt = DateTime.utc(2026, 7, 21);
    final product = _product(active: true, archivedAt: archivedAt);
    final payload = product.toSupabaseMap();

    expect(payload['active'], isTrue);
    expect(
      payload['archived_at'],
      archivedAt.toIso8601String(),
    );
    expect(product.isArchived, isTrue);
  });

  test('restoring clears only the archive marker when requested', () {
    final product = _product(
      active: false,
      archivedAt: DateTime.utc(2026, 7, 21),
    ).copyWith(clearArchivedAt: true);

    expect(product.isActive, isFalse);
    expect(product.archivedAt, isNull);
  });
}
