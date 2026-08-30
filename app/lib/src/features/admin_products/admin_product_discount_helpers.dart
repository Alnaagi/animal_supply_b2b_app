import '../../data/models/product.dart';

/// Applies a product-level discount using [basePrice] as the reference price.
/// Does not invent parallel pricing: strikethrough in customer UI uses base price.
Product applyProductDiscount(Product product, double percent) {
  if (percent <= 0) return clearProductDiscount(product);
  final clamped = percent.clamp(0, 100).toDouble();
  return product.copyWith(
    discountPercent: clamped,
    oldPrice: product.oldPrice ?? product.basePrice,
  );
}

Product clearProductDiscount(Product product) {
  return Product(
    id: product.id,
    nameAr: product.nameAr,
    nameEn: product.nameEn,
    sku: product.sku,
    category: product.category,
    categoryId: product.categoryId,
    animalType: product.animalType,
    brand: product.brand,
    unitSize: product.unitSize,
    packageSize: product.packageSize,
    basePrice: product.basePrice,
    effectivePrice: product.effectivePrice,
    retailUnitPrice: product.retailUnitPrice,
    oldPrice: null,
    discountPercent: null,
    stockQuantity: product.stockQuantity,
    availableQuantity: product.availableQuantity,
    stockTrackingEnabled: product.stockTrackingEnabled,
    showStockQuantityToCustomers: product.showStockQuantityToCustomers,
    hideWhenOutOfStock: product.hideWhenOutOfStock,
    unitsPerBox: product.unitsPerBox,
    minOrderQty: product.minOrderQty,
    descriptionAr: product.descriptionAr,
    imageUrl: product.imageUrl,
    imageAttribution: product.imageAttribution,
    sourceUrl: product.sourceUrl,
    isActive: product.isActive,
    isFeatured: product.isFeatured,
    isTopSelling: product.isTopSelling,
    archivedAt: product.archivedAt,
    archivedByCategoryId: product.archivedByCategoryId,
    activeBeforeCategoryArchive: product.activeBeforeCategoryArchive,
    createdAt: product.createdAt,
    updatedAt: product.updatedAt,
    packageOptions: product.packageOptions,
    tags: product.tags,
  );
}

double discountedPreviewPrice(Product product, double percent) {
  if (percent <= 0) return product.basePrice;
  return product.basePrice * (1 - percent.clamp(0, 100) / 100);
}

double bulkAdjustedPrice(double currentPrice, {required double percentDelta}) {
  final next = currentPrice * (1 + percentDelta / 100);
  return next < 0 ? 0 : next;
}

String adminStockStatusLabel(Product product) {
  if (!product.stockTrackingEnabled) return 'غير متتبع';
  if (!product.isOrderable) return 'نفد المخزون';
  if (product.lowStock) return 'مخزون منخفض';
  return 'متوفر';
}
