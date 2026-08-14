class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.active = true,
    this.archivedAt,
    this.productCount = 0,
    this.archivedProductCount = 0,
  });

  final String id;
  final String name;
  final bool active;
  final DateTime? archivedAt;
  final int productCount;
  final int archivedProductCount;

  bool get isArchived => archivedAt != null;

  ProductCategory copyWith({
    String? id,
    String? name,
    bool? active,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    int? productCount,
    int? archivedProductCount,
  }) {
    return ProductCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      active: active ?? this.active,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
      productCount: productCount ?? this.productCount,
      archivedProductCount: archivedProductCount ?? this.archivedProductCount,
    );
  }

  factory ProductCategory.fromSupabase(
    Map<String, dynamic> row, {
    int productCount = 0,
    int archivedProductCount = 0,
  }) {
    return ProductCategory(
      id: row['id'].toString(),
      name: (row['name'] ?? '').toString(),
      active: row['active'] != false,
      archivedAt: DateTime.tryParse(row['archived_at']?.toString() ?? ''),
      productCount: productCount,
      archivedProductCount: archivedProductCount,
    );
  }
}
