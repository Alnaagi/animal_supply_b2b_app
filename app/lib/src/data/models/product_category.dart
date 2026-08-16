class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.active = true,
    this.archivedAt,
    this.productCount = 0,
    this.archivedProductCount = 0,
    this.iconKey,
    this.iconUrl,
    this.updatedAt,
  });

  final String id;
  final String name;
  final bool active;
  final DateTime? archivedAt;
  final int productCount;
  final int archivedProductCount;
  final String? iconKey;
  final String? iconUrl;
  final DateTime? updatedAt;

  bool get isArchived => archivedAt != null;

  bool get hasIcon {
    final key = iconKey?.trim() ?? '';
    final url = iconUrl?.trim() ?? '';
    return key.isNotEmpty || url.isNotEmpty;
  }

  ProductCategory copyWith({
    String? id,
    String? name,
    bool? active,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    int? productCount,
    int? archivedProductCount,
    String? iconKey,
    String? iconUrl,
    bool clearIconKey = false,
    bool clearIconUrl = false,
    DateTime? updatedAt,
  }) {
    return ProductCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      active: active ?? this.active,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
      productCount: productCount ?? this.productCount,
      archivedProductCount: archivedProductCount ?? this.archivedProductCount,
      iconKey: clearIconKey ? null : iconKey ?? this.iconKey,
      iconUrl: clearIconUrl ? null : iconUrl ?? this.iconUrl,
      updatedAt: updatedAt ?? this.updatedAt,
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
      iconKey: _optionalText(row['icon_key']),
      iconUrl: _optionalText(row['icon_url']),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
