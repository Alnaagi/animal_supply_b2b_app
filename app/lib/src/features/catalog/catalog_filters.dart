import '../../data/models/product.dart';

enum CatalogAvailability {
  all,
  inStock,
  lowStock,
  outOfStock,
}

extension CatalogAvailabilityQuery on CatalogAvailability {
  String get queryValue => switch (this) {
        CatalogAvailability.all => 'all',
        CatalogAvailability.inStock => 'in_stock',
        CatalogAvailability.lowStock => 'low_stock',
        CatalogAvailability.outOfStock => 'out_of_stock',
      };
}

class CatalogFilters {
  const CatalogFilters({
    this.brand,
    this.animalType,
    this.unitSize,
    this.minimumPrice,
    this.maximumPrice,
    this.availability = CatalogAvailability.all,
  });

  final String? brand;
  final String? animalType;
  final String? unitSize;
  final double? minimumPrice;
  final double? maximumPrice;
  final CatalogAvailability availability;

  bool get isEmpty => activeCount == 0;

  int get activeCount => [
        brand,
        animalType,
        unitSize,
        minimumPrice,
        maximumPrice,
        availability == CatalogAvailability.all ? null : availability,
      ].where((value) => value != null).length;
}

List<Product> applyCatalogFilters(
  Iterable<Product> products,
  CatalogFilters filters,
) {
  return products.where((product) {
    if (filters.brand != null && product.brand != filters.brand) return false;
    if (filters.animalType != null &&
        product.animalType != filters.animalType) {
      return false;
    }
    if (filters.unitSize != null &&
        product.effectivePackageSize != filters.unitSize) {
      return false;
    }
    if (filters.minimumPrice != null && product.price < filters.minimumPrice!) {
      return false;
    }
    if (filters.maximumPrice != null && product.price > filters.maximumPrice!) {
      return false;
    }

    return switch (filters.availability) {
      CatalogAvailability.all => true,
      CatalogAvailability.inStock => product.isOrderable,
      CatalogAvailability.lowStock => product.lowStock,
      CatalogAvailability.outOfStock => !product.isOrderable,
    };
  }).toList(growable: false);
}
