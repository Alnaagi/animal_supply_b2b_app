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
    required this.stockQuantity,
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
  final double? oldPrice;
  final int? discountPercent;
  final int stockQuantity;
  final int minOrderQty;
  final String descriptionAr;
  final String? imageUrl;
  final String? imageAttribution;
  final String? sourceUrl;
  final bool isActive;
  final bool isFeatured;
  final bool isTopSelling;
  final List<String> packageOptions;
  final List<String> tags;

  String get name => nameAr;
  double get price => basePrice;
  int get minOrderQuantity => minOrderQty;
  String get description => descriptionAr;
  String get effectivePackageSize => packageSize ?? unitSize;
  bool get active => isActive;
  bool get inStock => stockQuantity > 0;
  bool get lowStock => stockQuantity > 0 && stockQuantity <= 10;

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
    double? oldPrice,
    int? discountPercent,
    int? stockQuantity,
    int? minOrderQty,
    String? descriptionAr,
    String? imageUrl,
    String? imageAttribution,
    String? sourceUrl,
    bool? isActive,
    bool? isFeatured,
    bool? isTopSelling,
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
      oldPrice: oldPrice ?? this.oldPrice,
      discountPercent: discountPercent ?? this.discountPercent,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minOrderQty: minOrderQty ?? this.minOrderQty,
      descriptionAr: descriptionAr ?? this.descriptionAr,
      imageUrl: imageUrl ?? this.imageUrl,
      imageAttribution: imageAttribution ?? this.imageAttribution,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      isActive: isActive ?? this.isActive,
      isFeatured: isFeatured ?? this.isFeatured,
      isTopSelling: isTopSelling ?? this.isTopSelling,
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
        'old_price': oldPrice,
        'discount_percent': discountPercent,
        'stock_quantity': stockQuantity,
        'min_order_quantity': minOrderQty,
        'image_url': imageUrl,
        'source_url': sourceUrl,
        'tags': tags,
        'active': isActive,
        'is_featured': isFeatured,
        'is_top_selling': isTopSelling,
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
      basePrice: ((row['base_price'] ?? 0) as num).toDouble(),
      oldPrice: row['old_price'] == null
          ? null
          : (row['old_price'] as num).toDouble(),
      discountPercent: row['discount_percent'] as int?,
      stockQuantity: (row['stock_quantity'] ?? 0) as int,
      minOrderQty: (row['min_order_quantity'] ?? 1) as int,
      descriptionAr: (row['description'] ?? '').toString(),
      imageUrl: row['image_url']?.toString(),
      sourceUrl: row['source_url']?.toString(),
      isActive: row['active'] != false,
      isFeatured: row['is_featured'] == true,
      isTopSelling: row['is_top_selling'] == true,
      tags: [
        for (final tag in (row['tags'] as List? ?? const [])) tag.toString()
      ],
    );
  }
}
