class Product {
  const Product({
    required this.id,
    required this.nameAr,
    this.nameEn,
    required this.sku,
    required this.category,
    this.categoryId,
    required this.animalType,
    required this.brand,
    required this.unitSize,
    this.packageSize,
    required this.basePrice,
    this.effectivePrice,
    this.retailUnitPrice,
    required this.stockQuantity,
    this.availableQuantity,
    this.stockTrackingEnabled = true,
    this.showStockQuantityToCustomers = false,
    this.hideWhenOutOfStock = false,
    this.unitsPerBox,
    required this.minOrderQty,
    this.descriptionAr = '',
    this.imageUrl,
    this.imageAttribution,
    this.sourceUrl,
    this.oldPrice,
    this.discountPercent,
    this.isActive = true,
    this.isFeatured = false,
    this.isTopSelling = false,
    this.archivedAt,
    this.archivedByCategoryId,
    this.activeBeforeCategoryArchive,
    this.createdAt,
    this.updatedAt,
    this.packageOptions = const [],
    this.tags = const [],
  });

  final String id;
  final String nameAr;
  final String? nameEn;
  final String sku;
  final String category;
  final String? categoryId;
  final String animalType;
  final String brand;
  final String unitSize;
  final String? packageSize;
  final double basePrice;
  final double? effectivePrice;
  final double? retailUnitPrice;
  final double? oldPrice;
  final double? discountPercent;
  final int stockQuantity;
  final int? availableQuantity;
  final bool stockTrackingEnabled;
  final bool showStockQuantityToCustomers;
  final bool hideWhenOutOfStock;
  final int? unitsPerBox;
  final int minOrderQty;
  final String descriptionAr;
  final String? imageUrl;
  final String? imageAttribution;
  final String? sourceUrl;
  final bool isActive;
  final bool isFeatured;
  final bool isTopSelling;
  final DateTime? archivedAt;
  final String? archivedByCategoryId;
  final bool? activeBeforeCategoryArchive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> packageOptions;
  final List<String> tags;

  String get name => nameAr;

  /// Effective wholesale price after product-level discount.
  double get discountedPrice {
    final base = effectivePrice ?? basePrice;
    final pct = discountPercent ?? 0;
    if (pct <= 0) return base;
    return base * (1 - pct / 100);
  }

  bool get hasProductDiscount => (discountPercent ?? 0) > 0;

  double get price => discountedPrice;
  int get minOrderQuantity => minOrderQty;
  String get description => descriptionAr;
  String get effectivePackageSize => packageSize ?? unitSize;
  bool get active => isActive;
  bool get isArchived => archivedAt != null;
  bool get hasUnitsPerBox => unitsPerBox != null && unitsPerBox! > 0;
  String? get unitsPerBoxLabel =>
      hasUnitsPerBox ? '$unitsPerBox قطعة في الصندوق' : null;
  static const untrackedOrderQuantityLimit = 1000000;
  int get orderableStockQuantity => stockTrackingEnabled
      ? (availableQuantity ?? stockQuantity).clamp(0, stockQuantity).toInt()
      : untrackedOrderQuantityLimit;
  int? get orderQuantityLimit =>
      stockTrackingEnabled ? orderableStockQuantity : null;
  int get reservedQuantity =>
      stockTrackingEnabled ? stockQuantity - orderableStockQuantity : 0;
  bool get inStock => !stockTrackingEnabled || orderableStockQuantity > 0;
  bool get isOrderable =>
      !stockTrackingEnabled || orderableStockQuantity >= minOrderQuantity;
  bool get lowStock =>
      stockTrackingEnabled &&
      orderableStockQuantity > 0 &&
      orderableStockQuantity <= 10;
  bool get hiddenFromCustomerBecauseOutOfStock =>
      stockTrackingEnabled && hideWhenOutOfStock && !isOrderable;
  String get customerAvailabilityLabel {
    if (!isOrderable) return 'غير متوفر حالياً';
    if (stockTrackingEnabled && showStockQuantityToCustomers) {
      return 'متوفر $orderableStockQuantity';
    }
    return 'متوفر للطلب';
  }

  int normalizeOrderQuantity(int requested) {
    final minimum = minOrderQuantity;
    final normalized = requested < minimum ? minimum : requested;
    final maximum = orderQuantityLimit ?? untrackedOrderQuantityLimit;
    return normalized.clamp(minimum, maximum).toInt();
  }

  Product copyWith({
    String? id,
    String? nameAr,
    String? nameEn,
    String? sku,
    String? category,
    String? categoryId,
    String? animalType,
    String? brand,
    String? unitSize,
    String? packageSize,
    double? basePrice,
    double? effectivePrice,
    double? retailUnitPrice,
    bool clearRetailUnitPrice = false,
    double? oldPrice,
    double? discountPercent,
    int? stockQuantity,
    int? availableQuantity,
    bool? stockTrackingEnabled,
    bool? showStockQuantityToCustomers,
    bool? hideWhenOutOfStock,
    int? unitsPerBox,
    bool clearUnitsPerBox = false,
    int? minOrderQty,
    String? descriptionAr,
    String? imageUrl,
    String? imageAttribution,
    String? sourceUrl,
    bool? isActive,
    bool? isFeatured,
    bool? isTopSelling,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    String? archivedByCategoryId,
    bool clearArchivedByCategoryId = false,
    bool? activeBeforeCategoryArchive,
    bool clearActiveBeforeCategoryArchive = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? packageOptions,
    List<String>? tags,
  }) {
    return Product(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      sku: sku ?? this.sku,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      animalType: animalType ?? this.animalType,
      brand: brand ?? this.brand,
      unitSize: unitSize ?? this.unitSize,
      packageSize: packageSize ?? this.packageSize,
      basePrice: basePrice ?? this.basePrice,
      effectivePrice: effectivePrice ?? this.effectivePrice,
      retailUnitPrice:
          clearRetailUnitPrice ? null : retailUnitPrice ?? this.retailUnitPrice,
      oldPrice: oldPrice ?? this.oldPrice,
      discountPercent: discountPercent ?? this.discountPercent,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      availableQuantity: availableQuantity ?? this.availableQuantity,
      stockTrackingEnabled: stockTrackingEnabled ?? this.stockTrackingEnabled,
      showStockQuantityToCustomers:
          showStockQuantityToCustomers ?? this.showStockQuantityToCustomers,
      hideWhenOutOfStock: hideWhenOutOfStock ?? this.hideWhenOutOfStock,
      unitsPerBox: clearUnitsPerBox ? null : unitsPerBox ?? this.unitsPerBox,
      minOrderQty: minOrderQty ?? this.minOrderQty,
      descriptionAr: descriptionAr ?? this.descriptionAr,
      imageUrl: imageUrl ?? this.imageUrl,
      imageAttribution: imageAttribution ?? this.imageAttribution,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      isActive: isActive ?? this.isActive,
      isFeatured: isFeatured ?? this.isFeatured,
      isTopSelling: isTopSelling ?? this.isTopSelling,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
      archivedByCategoryId: clearArchivedByCategoryId
          ? null
          : archivedByCategoryId ?? this.archivedByCategoryId,
      activeBeforeCategoryArchive: clearActiveBeforeCategoryArchive
          ? null
          : activeBeforeCategoryArchive ?? this.activeBeforeCategoryArchive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      packageOptions: packageOptions ?? this.packageOptions,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toSupabaseMap({String? categoryUuid}) => {
        'name': nameAr,
        'name_en': nameEn,
        'sku': sku,
        'brand': brand,
        'description': descriptionAr,
        'animal_type': animalType,
        'unit_size': unitSize,
        'package_size': packageSize,
        'base_price': basePrice,
        'retail_unit_price': retailUnitPrice,
        'old_price': oldPrice,
        // DB stores 0 for "no discount"; null must not be sent on update.
        'discount_percent': (discountPercent ?? 0) <= 0 ? 0 : discountPercent,
        'stock_quantity': stockQuantity,
        'stock_tracking_enabled': stockTrackingEnabled,
        'show_stock_quantity_to_customers': showStockQuantityToCustomers,
        'hide_when_out_of_stock': hideWhenOutOfStock,
        'units_per_box': unitsPerBox,
        'min_order_quantity': minOrderQty,
        'image_url': imageUrl,
        'source_url': sourceUrl,
        'tags': tags,
        'active': isActive,
        'is_featured': isFeatured,
        'is_top_selling': isTopSelling,
        'archived_at': archivedAt?.toIso8601String(),
        if (categoryUuid != null) 'category_id': categoryUuid,
      };

  factory Product.fromSupabase(Map<String, dynamic> row) {
    final category = row['categories'];
    return Product(
      id: row['id'].toString(),
      nameAr: (row['name'] ?? '').toString(),
      nameEn: row['name_en']?.toString(),
      sku: (row['sku'] ?? '').toString(),
      category: category is Map
          ? (category['name'] ?? 'بدون تصنيف').toString()
          : (row['category_name'] ?? 'بدون تصنيف').toString(),
      categoryId: row['category_id']?.toString(),
      animalType: (row['animal_type'] ?? '').toString(),
      brand: (row['brand'] ?? '').toString(),
      unitSize: (row['unit_size'] ?? '').toString(),
      packageSize: row['package_size']?.toString(),
      basePrice: _asDouble(row['base_price']),
      effectivePrice: _asNullableDouble(row['effective_price']),
      retailUnitPrice: _asNullableDouble(row['retail_unit_price']),
      oldPrice: _asNullableDouble(row['old_price']),
      discountPercent: _asNullableDouble(row['discount_percent']),
      stockQuantity: (row['stock_quantity'] as num?)?.toInt() ?? 0,
      availableQuantity: (row['available_quantity'] as num?)?.toInt(),
      stockTrackingEnabled: row['stock_tracking_enabled'] != false,
      showStockQuantityToCustomers:
          row['show_stock_quantity_to_customers'] == true,
      hideWhenOutOfStock: row['hide_when_out_of_stock'] == true,
      unitsPerBox: (row['units_per_box'] as num?)?.toInt(),
      minOrderQty: (row['min_order_quantity'] ?? 1) as int,
      descriptionAr: (row['description'] ?? '').toString(),
      imageUrl: row['image_url']?.toString(),
      sourceUrl: row['source_url']?.toString(),
      isActive: row['active'] != false,
      isFeatured: row['is_featured'] == true,
      isTopSelling: row['is_top_selling'] == true,
      archivedAt: DateTime.tryParse(row['archived_at']?.toString() ?? ''),
      archivedByCategoryId: row['archived_by_category_id']?.toString(),
      activeBeforeCategoryArchive:
          row['active_before_category_archive'] as bool?,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
      tags: [
        for (final tag in (row['tags'] as List? ?? const [])) tag.toString()
      ],
    );
  }

  static double _asDouble(Object? value) => _asNullableDouble(value) ?? 0;

  static double? _asNullableDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
