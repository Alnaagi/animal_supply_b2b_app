import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local/local_cache.dart';
import '../models/product.dart';
import '../models/product_category.dart';
import '../remote/supabase_clients.dart';
import 'demo_data.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(cache: ref.watch(localCacheProvider)),
);

enum CatalogPageSource { remote, offlineSnapshot, demo }

class CategoryArchivedException implements Exception {
  const CategoryArchivedException(this.categoryName);

  final String categoryName;

  @override
  String toString() => 'Category "$categoryName" is archived.';
}

class CategoryRestoreRequiredException implements Exception {
  const CategoryRestoreRequiredException();

  @override
  String toString() =>
      'This product was archived with its category; restore the category first.';
}

class CatalogPage {
  const CatalogPage({
    required this.products,
    required this.hasMore,
    required this.nextOffset,
    required this.snapshotAt,
    required this.source,
    required this.offlineSnapshotCount,
  });

  final List<Product> products;
  final bool hasMore;
  final int nextOffset;
  final DateTime snapshotAt;
  final CatalogPageSource source;
  final int offlineSnapshotCount;

  bool get isOfflineSnapshot => source == CatalogPageSource.offlineSnapshot;
  bool get isDemo => source == CatalogPageSource.demo;
}

class CatalogFilterOptions {
  const CatalogFilterOptions({
    this.categories = const [],
    this.brands = const [],
    this.animalTypes = const [],
    this.unitSizes = const [],
    this.isOfflineSnapshot = false,
  });

  final List<String> categories;
  final List<String> brands;
  final List<String> animalTypes;
  final List<String> unitSizes;
  final bool isOfflineSnapshot;
}

class CatalogRemotePage {
  const CatalogRemotePage({
    required this.rows,
    required this.hasMore,
    required this.nextOffset,
    required this.snapshotAt,
  });

  final List<Map<String, dynamic>> rows;
  final bool hasMore;
  final int nextOffset;
  final DateTime snapshotAt;
}

abstract interface class CatalogPagedRemoteGateway {
  String? get ownerProfileId;

  Future<CatalogRemotePage> productsPage({
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    DateTime? snapshotAt,
    required int offset,
    required int limit,
  });

  Future<CatalogFilterOptions> filterOptions({
    required bool includeInactive,
  });
}

abstract interface class CatalogSortedPagedRemoteGateway {
  Future<CatalogRemotePage> productsPageSorted({
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    required String sort,
    DateTime? snapshotAt,
    required int offset,
    required int limit,
  });
}

class SupabaseCatalogPagedRemoteGateway
    implements CatalogPagedRemoteGateway, CatalogSortedPagedRemoteGateway {
  const SupabaseCatalogPagedRemoteGateway(this.client);

  final SupabaseClient client;

  @override
  String? get ownerProfileId => client.auth.currentUser?.id;

  @override
  Future<CatalogRemotePage> productsPage({
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    DateTime? snapshotAt,
    required int offset,
    required int limit,
  }) {
    return _productsPage(
      query: query,
      category: category,
      brand: brand,
      animalType: animalType,
      unitSize: unitSize,
      minimumPrice: minimumPrice,
      maximumPrice: maximumPrice,
      availability: availability,
      includeInactive: includeInactive,
      snapshotAt: snapshotAt,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<CatalogRemotePage> productsPageSorted({
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    required String sort,
    DateTime? snapshotAt,
    required int offset,
    required int limit,
  }) {
    return _productsPage(
      query: query,
      category: category,
      brand: brand,
      animalType: animalType,
      unitSize: unitSize,
      minimumPrice: minimumPrice,
      maximumPrice: maximumPrice,
      availability: availability,
      includeInactive: includeInactive,
      sort: _normalizedCatalogSort(sort),
      snapshotAt: snapshotAt,
      offset: offset,
      limit: limit,
    );
  }

  Future<CatalogRemotePage> _productsPage({
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    String? sort,
    DateTime? snapshotAt,
    required int offset,
    required int limit,
  }) async {
    final response = await client.rpc(
      'catalog_products_page',
      params: {
        'p_query': query,
        'p_category': category,
        'p_brand': brand,
        'p_animal_type': animalType,
        'p_unit_size': unitSize,
        'p_min_price': minimumPrice,
        'p_max_price': maximumPrice,
        'p_availability': availability,
        'p_include_inactive': includeInactive,
        if (sort != null) 'p_sort': sort,
        'p_snapshot_at': snapshotAt?.toUtc().toIso8601String(),
        'p_offset': offset,
        'p_limit': limit,
      },
    );
    final payload = _asMap(response);
    if (payload == null) {
      throw StateError('Invalid catalog_products_page response.');
    }
    final rawProducts = payload['products'];
    if (rawProducts is! List) {
      throw StateError('Invalid catalog_products_page products.');
    }
    final returnedSnapshot =
        DateTime.tryParse(payload['snapshot_at']?.toString() ?? '');
    if (returnedSnapshot == null) {
      throw StateError('Invalid catalog_products_page snapshot.');
    }
    return CatalogRemotePage(
      rows: [
        for (final row in rawProducts)
          if (_asMap(row) case final mapped?) mapped,
      ],
      hasMore: payload['has_more'] == true,
      nextOffset: (payload['next_offset'] as num?)?.toInt() ?? offset,
      snapshotAt: returnedSnapshot.toUtc(),
    );
  }

  @override
  Future<CatalogFilterOptions> filterOptions({
    required bool includeInactive,
  }) async {
    final response = await client.rpc(
      'catalog_product_filter_options',
      params: {'p_include_inactive': includeInactive},
    );
    final payload = _asMap(response);
    if (payload == null) {
      throw StateError('Invalid catalog_product_filter_options response.');
    }
    return CatalogFilterOptions(
      categories: _asStringList(payload['categories']),
      brands: _asStringList(payload['brands']),
      animalTypes: _asStringList(payload['animal_types']),
      unitSizes: _asStringList(payload['unit_sizes']),
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return _distinctSorted(value.map((item) => item.toString()));
}

String? _nonEmptyOrNull(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String _validatedCategoryName(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty ||
      name.length > 120 ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(name)) {
    throw ArgumentError.value(
      rawName,
      'name',
      'Category name must contain 1 to 120 printable characters.',
    );
  }
  return name;
}

String _normalizedAvailability(String value) {
  return switch (value.trim().toLowerCase()) {
    'in_stock' => 'in_stock',
    'low_stock' => 'low_stock',
    'out_of_stock' => 'out_of_stock',
    _ => 'all',
  };
}

String _normalizedCatalogSort(String value) {
  return switch (value.trim().toLowerCase()) {
    'oldest' => 'oldest',
    'name_asc' => 'name_asc',
    'price_asc' => 'price_asc',
    'price_desc' => 'price_desc',
    'stock_asc' => 'stock_asc',
    'stock_desc' => 'stock_desc',
    _ => 'newest',
  };
}

List<String> _distinctSorted(Iterable<String> values) {
  final result = <String>{
    for (final value in values)
      if (value.trim().isNotEmpty) value.trim(),
  }.toList()
    ..sort();
  return result;
}

List<Product> _sortProductsNewest(Iterable<Product> products) {
  final indexed = products.toList(growable: false).indexed.toList();
  indexed.sort((first, second) {
    final firstCreated = first.$2.createdAt;
    final secondCreated = second.$2.createdAt;
    if (firstCreated != null && secondCreated != null) {
      final byDate = secondCreated.compareTo(firstCreated);
      if (byDate != 0) return byDate;
      final byId = second.$2.id.compareTo(first.$2.id);
      if (byId != 0) return byId;
    } else if (firstCreated != null) {
      return -1;
    } else if (secondCreated != null) {
      return 1;
    }
    return first.$1.compareTo(second.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

List<Product> _sortProductsForCatalog(
  Iterable<Product> products, {
  required String sort,
}) {
  final normalizedSort = _normalizedCatalogSort(sort);
  if (normalizedSort == 'newest') {
    return _sortProductsNewest(products);
  }
  final indexed = products.toList(growable: false).indexed.toList();
  indexed.sort((first, second) {
    final firstProduct = first.$2;
    final secondProduct = second.$2;
    final comparison = switch (normalizedSort) {
      'oldest' => _compareProductDatesOldest(firstProduct, secondProduct),
      'name_asc' => _compareProductNames(firstProduct, secondProduct),
      'price_asc' => firstProduct.price.compareTo(secondProduct.price),
      'price_desc' => secondProduct.price.compareTo(firstProduct.price),
      'stock_asc' => _compareTrackedStock(firstProduct, secondProduct),
      'stock_desc' => _compareTrackedStock(
          firstProduct,
          secondProduct,
          descending: true,
        ),
      _ => 0,
    };
    if (comparison != 0) return comparison;
    final byName = _compareProductNames(firstProduct, secondProduct);
    if (byName != 0) return byName;
    final byId = firstProduct.id.compareTo(secondProduct.id);
    return byId != 0 ? byId : first.$1.compareTo(second.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

int _compareProductDatesOldest(Product first, Product second) {
  final firstCreated = first.createdAt;
  final secondCreated = second.createdAt;
  if (firstCreated != null && secondCreated != null) {
    return firstCreated.compareTo(secondCreated);
  }
  if (firstCreated != null) return -1;
  if (secondCreated != null) return 1;
  return 0;
}

int _compareProductNames(Product first, Product second) {
  final byArabic = first.name.trim().toLowerCase().compareTo(
        second.name.trim().toLowerCase(),
      );
  if (byArabic != 0) return byArabic;
  final byEnglish = (first.nameEn ?? '').trim().toLowerCase().compareTo(
        (second.nameEn ?? '').trim().toLowerCase(),
      );
  if (byEnglish != 0) return byEnglish;
  final byBrand = first.brand.trim().toLowerCase().compareTo(
        second.brand.trim().toLowerCase(),
      );
  if (byBrand != 0) return byBrand;
  return first.id.compareTo(second.id);
}

int _compareTrackedStock(
  Product first,
  Product second, {
  bool descending = false,
}) {
  if (first.stockTrackingEnabled != second.stockTrackingEnabled) {
    return first.stockTrackingEnabled ? -1 : 1;
  }
  if (!first.stockTrackingEnabled) return 0;
  final comparison =
      first.orderableStockQuantity.compareTo(second.orderableStockQuantity);
  return descending ? -comparison : comparison;
}

class CatalogRepository {
  CatalogRepository({
    LocalCache? cache,
    CatalogPagedRemoteGateway? pagedRemote,
    List<Product>? demoSeed,
  })  : _cache = cache,
        _pagedRemote = pagedRemote ?? _configuredPagedRemote(),
        _demoProducts = [...(demoSeed ?? demoProducts)] {
    _initializeDemoCategories();
  }

  CatalogRepository.demo({
    LocalCache? cache,
    List<Product>? seed,
  })  : _cache = cache,
        _pagedRemote = null,
        _demoProducts = [...(seed ?? demoProducts)] {
    _initializeDemoCategories();
  }

  final LocalCache? _cache;
  final CatalogPagedRemoteGateway? _pagedRemote;
  final List<Product> _demoProducts;
  final List<ProductCategory> _demoCategories = [];

  static const defaultPageSize = 50;
  static const offlineSnapshotLimit = 200;

  static CatalogPagedRemoteGateway? _configuredPagedRemote() {
    final client = supabaseClient;
    return client == null ? null : SupabaseCatalogPagedRemoteGateway(client);
  }

  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final rows = await _catalogRows();
        final products =
            rows.map<Product>((row) => Product.fromSupabase(row)).toList();
        await _saveRemoteProducts(products);
        return _filterProducts(
          products,
          query: query,
          category: category,
          includeInactive: includeInactive,
        );
      } catch (_) {
        final cached = await _cachedRemoteProducts();
        if (cached.isNotEmpty) {
          return _filterProducts(
            cached,
            query: query,
            category: category,
            includeInactive: includeInactive,
          );
        }
        rethrow;
      }
    }
    final demo = includeInactive
        ? List<Product>.of(_demoProducts)
        : _demoProducts.where((p) => p.active && !p.isArchived).toList();
    await _saveDemoSnapshot();
    return _filterProducts(
      demo,
      query: query,
      category: category,
      includeInactive: includeInactive,
    );
  }

  Future<CatalogPage> productsPage({
    String query = '',
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    String availability = 'all',
    bool includeInactive = false,
    DateTime? snapshotAt,
    int offset = 0,
    int pageSize = defaultPageSize,
  }) {
    return _productsPage(
      query: query,
      category: category,
      brand: brand,
      animalType: animalType,
      unitSize: unitSize,
      minimumPrice: minimumPrice,
      maximumPrice: maximumPrice,
      availability: availability,
      includeInactive: includeInactive,
      sort: 'newest',
      snapshotAt: snapshotAt,
      offset: offset,
      pageSize: pageSize,
      requestRemoteSort: false,
    );
  }

  Future<CatalogPage> productsPageSorted({
    String query = '',
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    String availability = 'all',
    bool includeInactive = false,
    String sort = 'newest',
    DateTime? snapshotAt,
    int offset = 0,
    int pageSize = defaultPageSize,
  }) {
    return _productsPage(
      query: query,
      category: category,
      brand: brand,
      animalType: animalType,
      unitSize: unitSize,
      minimumPrice: minimumPrice,
      maximumPrice: maximumPrice,
      availability: availability,
      includeInactive: includeInactive,
      sort: _normalizedCatalogSort(sort),
      snapshotAt: snapshotAt,
      offset: offset,
      pageSize: pageSize,
      requestRemoteSort: true,
    );
  }

  Future<CatalogPage> _productsPage({
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    required String sort,
    DateTime? snapshotAt,
    required int offset,
    required int pageSize,
    required bool requestRemoteSort,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safePageSize = pageSize.clamp(1, 100).toInt();
    final normalizedSort = _normalizedCatalogSort(sort);
    final remote = _pagedRemote;
    if (remote != null) {
      try {
        final CatalogRemotePage page;
        if (requestRemoteSort && remote is CatalogSortedPagedRemoteGateway) {
          final sortedRemote = remote as CatalogSortedPagedRemoteGateway;
          page = await sortedRemote.productsPageSorted(
            query: query.trim(),
            category: _nonEmptyOrNull(category),
            brand: _nonEmptyOrNull(brand),
            animalType: _nonEmptyOrNull(animalType),
            unitSize: _nonEmptyOrNull(unitSize),
            minimumPrice: minimumPrice,
            maximumPrice: maximumPrice,
            availability: _normalizedAvailability(availability),
            includeInactive: includeInactive,
            sort: normalizedSort,
            snapshotAt: snapshotAt?.toUtc(),
            offset: safeOffset,
            limit: safePageSize,
          );
        } else if (requestRemoteSort) {
          throw StateError(
            'The configured catalog gateway does not support sorting.',
          );
        } else {
          page = await remote.productsPage(
            query: query.trim(),
            category: _nonEmptyOrNull(category),
            brand: _nonEmptyOrNull(brand),
            animalType: _nonEmptyOrNull(animalType),
            unitSize: _nonEmptyOrNull(unitSize),
            minimumPrice: minimumPrice,
            maximumPrice: maximumPrice,
            availability: _normalizedAvailability(availability),
            includeInactive: includeInactive,
            snapshotAt: snapshotAt?.toUtc(),
            offset: safeOffset,
            limit: safePageSize,
          );
        }
        final products =
            page.rows.map(Product.fromSupabase).toList(growable: false);
        if (!includeInactive &&
            products.any(
              (product) =>
                  !product.active ||
                  product.isArchived ||
                  product.hiddenFromCustomerBecauseOutOfStock,
            )) {
          throw StateError(
            'Catalog page returned a customer-hidden product.',
          );
        }
        await _mergeRemoteProducts(products);
        return CatalogPage(
          products: products.take(safePageSize).toList(growable: false),
          hasMore: page.hasMore,
          nextOffset: page.nextOffset,
          snapshotAt: page.snapshotAt,
          source: CatalogPageSource.remote,
          offlineSnapshotCount: 0,
        );
      } catch (_) {
        final cached = await _cachedRemoteProducts();
        if (cached.isEmpty) rethrow;
        return _localPage(
          cached,
          query: query,
          category: category,
          brand: brand,
          animalType: animalType,
          unitSize: unitSize,
          minimumPrice: minimumPrice,
          maximumPrice: maximumPrice,
          availability: availability,
          includeInactive: includeInactive,
          sort: normalizedSort,
          snapshotAt: snapshotAt,
          offset: safeOffset,
          pageSize: safePageSize,
          pageSource: CatalogPageSource.offlineSnapshot,
        );
      }
    }

    final visibleDemo = List<Product>.of(_demoProducts);
    await _saveDemoSnapshot();
    return _localPage(
      visibleDemo,
      query: query,
      category: category,
      brand: brand,
      animalType: animalType,
      unitSize: unitSize,
      minimumPrice: minimumPrice,
      maximumPrice: maximumPrice,
      availability: availability,
      includeInactive: includeInactive,
      sort: normalizedSort,
      snapshotAt: snapshotAt,
      offset: safeOffset,
      pageSize: safePageSize,
      pageSource: CatalogPageSource.demo,
    );
  }

  Future<CatalogFilterOptions> filterOptions({
    bool includeInactive = false,
  }) async {
    final remote = _pagedRemote;
    if (remote != null) {
      try {
        final options = await remote.filterOptions(
          includeInactive: includeInactive,
        );
        if (!includeInactive) return options;
        final activeCategories = await productCategories();
        return CatalogFilterOptions(
          categories: _distinctSorted(
            activeCategories.map((category) => category.name),
          ),
          brands: options.brands,
          animalTypes: options.animalTypes,
          unitSizes: options.unitSizes,
          isOfflineSnapshot: options.isOfflineSnapshot,
        );
      } catch (_) {
        final cached = await _cachedRemoteProducts();
        if (cached.isEmpty) rethrow;
        final options = _filterOptionsFromProducts(
          cached,
          includeInactive: includeInactive,
          isOfflineSnapshot: true,
        );
        if (!includeInactive) return options;
        final activeCategories = await productCategories();
        return CatalogFilterOptions(
          categories: _distinctSorted(
            activeCategories.map((category) => category.name),
          ),
          brands: options.brands,
          animalTypes: options.animalTypes,
          unitSizes: options.unitSizes,
          isOfflineSnapshot: true,
        );
      }
    }
    final options = _filterOptionsFromProducts(
      _demoProducts,
      includeInactive: includeInactive,
    );
    if (!includeInactive) return options;
    return CatalogFilterOptions(
      categories: _distinctSorted(
        _demoCategories
            .where((category) => category.active && !category.isArchived)
            .map((category) => category.name),
      ),
      brands: options.brands,
      animalTypes: options.animalTypes,
      unitSizes: options.unitSizes,
    );
  }

  Future<List<String>> categories() async {
    final values = await productCategories();
    return [for (final category in values) category.name];
  }

  Future<List<ProductCategory>> productCategories({
    bool includeArchived = false,
  }) async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final categoryRows = await client
            .from('categories')
            .select('id,name,active,archived_at')
            .order('name');
        final productRows = await client
            .from('products')
            .select('category_id,archived_by_category_id');
        final productCounts = <String, int>{};
        final archivedByCategoryCounts = <String, int>{};
        for (final rawRow in productRows) {
          final categoryId = rawRow['category_id']?.toString();
          if (categoryId != null && categoryId.isNotEmpty) {
            productCounts.update(categoryId, (count) => count + 1,
                ifAbsent: () => 1);
          }
          final archivedByCategoryId =
              rawRow['archived_by_category_id']?.toString();
          if (archivedByCategoryId != null && archivedByCategoryId.isNotEmpty) {
            archivedByCategoryCounts.update(
              archivedByCategoryId,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }
        }
        final result = [
          for (final rawRow in categoryRows)
            ProductCategory.fromSupabase(
              Map<String, dynamic>.from(rawRow),
              productCount: productCounts[rawRow['id'].toString()] ?? 0,
              archivedProductCount:
                  archivedByCategoryCounts[rawRow['id'].toString()] ?? 0,
            ),
        ];
        return result
            .where(
              (category) =>
                  includeArchived || (category.active && !category.isArchived),
            )
            .toList(growable: false);
      } catch (_) {
        final cached = await _cachedRemoteProducts();
        if (cached.isNotEmpty) {
          return _categoriesFromProducts(
            cached,
            includeArchived: includeArchived,
          );
        }
        rethrow;
      }
    }
    _refreshDemoCategoryCounts();
    return _demoCategories
        .where(
          (category) =>
              includeArchived || (category.active && !category.isArchived),
        )
        .toList(growable: false);
  }

  Future<ProductCategory> createCategory(String rawName) async {
    final name = _validatedCategoryName(rawName);
    final client = supabaseClient;
    if (client != null) {
      final existing = await client
          .from('categories')
          .select('id,name,active,archived_at')
          .ilike('name', name)
          .limit(1)
          .maybeSingle();
      if (existing != null) {
        final category = ProductCategory.fromSupabase(existing);
        if (category.isArchived) {
          throw CategoryArchivedException(category.name);
        }
        if (!category.active) {
          final updated = await client
              .from('categories')
              .update({'active': true})
              .eq('id', category.id)
              .select('id,name,active,archived_at')
              .single();
          return ProductCategory.fromSupabase(updated);
        }
        return category;
      }
      final inserted = await client
          .from('categories')
          .insert({'name': name, 'active': true})
          .select('id,name,active,archived_at')
          .single();
      return ProductCategory.fromSupabase(inserted);
    }

    for (final category in _demoCategories) {
      if (category.name.toLowerCase() != name.toLowerCase()) continue;
      if (category.isArchived) {
        throw CategoryArchivedException(category.name);
      }
      if (!category.active) {
        final index =
            _demoCategories.indexWhere((item) => item.id == category.id);
        _demoCategories[index] = category.copyWith(active: true);
        return _demoCategories[index];
      }
      return category;
    }
    final created = ProductCategory(
      id: 'local-category-${const Uuid().v4()}',
      name: name,
    );
    _demoCategories.add(created);
    _sortDemoCategories();
    return created;
  }

  Future<void> archiveCategory(String id) async {
    final client = supabaseClient;
    if (client != null) {
      await client.rpc(
        'admin_archive_category',
        params: {'p_category_id': id},
      );
      return;
    }
    final index = _demoCategories.indexWhere((category) => category.id == id);
    if (index == -1) {
      throw StateError('Category not found.');
    }
    final category = _demoCategories[index];
    if (category.isArchived) return;
    final archivedAt = DateTime.now();
    _demoCategories[index] = category.copyWith(
      active: false,
      archivedAt: archivedAt,
    );
    for (var productIndex = 0;
        productIndex < _demoProducts.length;
        productIndex++) {
      final product = _demoProducts[productIndex];
      final belongsToCategory = product.categoryId == id ||
          (product.categoryId == null && product.category == category.name);
      if (!belongsToCategory || product.isArchived) continue;
      _demoProducts[productIndex] = product.copyWith(
        isActive: false,
        archivedAt: archivedAt,
        archivedByCategoryId: id,
        activeBeforeCategoryArchive: product.active,
      );
    }
    _refreshDemoCategoryCounts();
    await _saveDemoSnapshot();
  }

  Future<void> restoreCategory(String id) async {
    final client = supabaseClient;
    if (client != null) {
      await client.rpc(
        'admin_restore_category',
        params: {'p_category_id': id},
      );
      return;
    }
    final index = _demoCategories.indexWhere((category) => category.id == id);
    if (index == -1) {
      throw StateError('Category not found.');
    }
    _demoCategories[index] = _demoCategories[index].copyWith(
      active: true,
      clearArchivedAt: true,
    );
    for (var productIndex = 0;
        productIndex < _demoProducts.length;
        productIndex++) {
      final product = _demoProducts[productIndex];
      if (product.archivedByCategoryId != id) continue;
      _demoProducts[productIndex] = product.copyWith(
        isActive: product.activeBeforeCategoryArchive ?? true,
        clearArchivedAt: true,
        clearArchivedByCategoryId: true,
        clearActiveBeforeCategoryArchive: true,
      );
    }
    _refreshDemoCategoryCounts();
    await _saveDemoSnapshot();
  }

  Future<List<Product>> archivedProducts() async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final rows = await client
            .from('products')
            .select('*, categories(name)')
            .not('archived_at', 'is', null)
            .order('archived_at', ascending: false)
            .order('id', ascending: false);
        final products = [
          for (final row in rows)
            Product.fromSupabase(Map<String, dynamic>.from(row)),
        ];
        await _mergeRemoteProducts(products);
        return products;
      } catch (_) {
        final cached = await _cachedRemoteProducts();
        if (cached.isEmpty) rethrow;
        return _sortProductsNewest(
          cached.where((product) => product.isArchived),
        );
      }
    }
    return _sortProductsNewest(
      _demoProducts.where((product) => product.isArchived),
    );
  }

  Future<Product?> productById(String id) async {
    final client = supabaseClient;
    if (client != null) {
      try {
        final rows = await _catalogRows(productId: id);
        if (rows.isEmpty) return null;
        final product = Product.fromSupabase(rows.first);
        await _cacheProduct(product);
        return product;
      } catch (_) {
        final cached = await _cachedRemoteProducts();
        for (final product in cached) {
          if (product.id == id &&
              product.active &&
              !product.isArchived &&
              !product.hiddenFromCustomerBecauseOutOfStock) {
            return product;
          }
        }
        rethrow;
      }
    }
    for (final product in _demoProducts) {
      if (product.id == id &&
          product.active &&
          !product.isArchived &&
          !product.hiddenFromCustomerBecauseOutOfStock) {
        return product;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _catalogRows({
    String? productId,
  }) async {
    final client = supabaseClient;
    if (client == null) return const [];
    final dynamic response = productId == null
        ? await client.rpc('catalog_products')
        : await client.rpc(
            'catalog_products',
            params: {'p_product_id': productId},
          );
    if (response is! List) {
      throw StateError('Invalid catalog_products response.');
    }
    return response.map<Map<String, dynamic>>((row) {
      if (row is! Map) {
        throw StateError('Invalid catalog_products row.');
      }
      return Map<String, dynamic>.from(row);
    }).toList(growable: false);
  }

  Future<void> _cacheProduct(Product product) async {
    final cache = _cache;
    final ownerProfileId = _cacheOwnerProfileId;
    if (cache == null || ownerProfileId == null) return;
    final products = await cache.cachedProducts(ownerProfileId: ownerProfileId);
    final updated = _sortProductsNewest([
      product,
      for (final cached in products)
        if (cached.id != product.id) cached,
    ]).take(offlineSnapshotLimit).toList();
    await cache.saveProducts(
      updated,
      ownerProfileId: ownerProfileId,
    );
  }

  Future<List<Product>> _cachedRemoteProducts() async {
    final cache = _cache;
    final ownerProfileId = _cacheOwnerProfileId;
    if (cache == null || ownerProfileId == null) return const [];
    final cached = await cache.cachedProducts(ownerProfileId: ownerProfileId);
    return _sortProductsNewest(cached)
        .take(offlineSnapshotLimit)
        .toList(growable: false);
  }

  Future<void> _saveRemoteProducts(List<Product> products) async {
    final cache = _cache;
    final ownerProfileId = _cacheOwnerProfileId;
    if (cache == null || ownerProfileId == null) return;
    await cache.saveProducts(
      _sortProductsNewest(products)
          .take(offlineSnapshotLimit)
          .toList(growable: false),
      ownerProfileId: ownerProfileId,
    );
  }

  Future<void> _mergeRemoteProducts(List<Product> products) async {
    if (products.isEmpty) return;
    final cache = _cache;
    final ownerProfileId = _cacheOwnerProfileId;
    if (cache == null || ownerProfileId == null) return;
    final existing = await cache.cachedProducts(ownerProfileId: ownerProfileId);
    final incomingIds = products.map((product) => product.id).toSet();
    final merged = _sortProductsNewest([
      ...products,
      for (final product in existing)
        if (!incomingIds.contains(product.id)) product,
    ]).take(offlineSnapshotLimit).toList(growable: false);
    await cache.saveProducts(merged, ownerProfileId: ownerProfileId);
  }

  Future<void> _saveDemoSnapshot() async {
    final cache = _cache;
    if (cache == null) return;
    await cache.saveProducts(
      _sortProductsNewest(
        _demoProducts.where(
          (product) =>
              product.active &&
              !product.isArchived &&
              !product.hiddenFromCustomerBecauseOutOfStock,
        ),
      ).take(offlineSnapshotLimit).toList(growable: false),
    );
  }

  Future<Product> saveProduct(Product product) async {
    final client = supabaseClient;
    if (client != null) {
      final categoryId = await _categoryIdFor(product.category);
      final map = product.toSupabaseMap(categoryUuid: categoryId);
      final saved =
          product.id.startsWith('demo-') || product.id.startsWith('local-')
              ? await client
                  .from('products')
                  .insert(map)
                  .select('*, categories(name)')
                  .single()
              : await client
                  .from('products')
                  .update(map)
                  .eq('id', product.id)
                  .select('*, categories(name)')
                  .single();
      return Product.fromSupabase(saved);
    }
    var categoryIndex = _demoCategories.indexWhere(
      (category) =>
          category.name.toLowerCase() == product.category.toLowerCase(),
    );
    if (categoryIndex == -1) {
      final created = await createCategory(product.category);
      categoryIndex =
          _demoCategories.indexWhere((category) => category.id == created.id);
    }
    final resolvedCategory = _demoCategories[categoryIndex];
    if (resolvedCategory.isArchived) {
      throw CategoryArchivedException(resolvedCategory.name);
    }
    final normalizedProduct = product.copyWith(
      category: resolvedCategory.name,
      categoryId: resolvedCategory.id,
    );
    final index =
        _demoProducts.indexWhere((item) => item.id == normalizedProduct.id);
    if (index == -1) {
      _demoProducts.insert(0, normalizedProduct);
    } else {
      _demoProducts[index] = normalizedProduct;
    }
    _refreshDemoCategoryCounts();
    await _saveDemoSnapshot();
    return normalizedProduct;
  }

  Future<void> archiveProduct(String id) async {
    final client = supabaseClient;
    if (client != null) {
      await client.from('products').update({
        'active': false,
        'archived_at': DateTime.now().toIso8601String()
      }).eq('id', id);
      return;
    }
    final index = _demoProducts.indexWhere((product) => product.id == id);
    if (index != -1) {
      _demoProducts[index] = _demoProducts[index].copyWith(
        isActive: false,
        archivedAt: DateTime.now(),
        clearArchivedByCategoryId: true,
        clearActiveBeforeCategoryArchive: true,
      );
    }
    _refreshDemoCategoryCounts();
    await _saveDemoSnapshot();
  }

  Future<void> restoreProduct(String id) async {
    final client = supabaseClient;
    if (client != null) {
      final product = await client
          .from('products')
          .select('archived_by_category_id')
          .eq('id', id)
          .single();
      if (product['archived_by_category_id'] != null) {
        throw const CategoryRestoreRequiredException();
      }
      await client.from('products').update({
        'active': true,
        'archived_at': null,
      }).eq('id', id);
      return;
    }
    final index = _demoProducts.indexWhere((product) => product.id == id);
    if (index != -1) {
      if (_demoProducts[index].archivedByCategoryId != null) {
        throw const CategoryRestoreRequiredException();
      }
      _demoProducts[index] = _demoProducts[index].copyWith(
        isActive: true,
        clearArchivedAt: true,
        clearArchivedByCategoryId: true,
        clearActiveBeforeCategoryArchive: true,
      );
    }
    _refreshDemoCategoryCounts();
    await _saveDemoSnapshot();
  }

  List<Product> _filterProducts(
    Iterable<Product> products, {
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    String availability = 'all',
    bool includeInactive = false,
  }) {
    final q = query.trim().toLowerCase();
    final normalizedAvailability = _normalizedAvailability(availability);
    return products.where((p) {
      if (!includeInactive &&
          (!p.active ||
              p.isArchived ||
              p.hiddenFromCustomerBecauseOutOfStock)) {
        return false;
      }
      if (category != null && p.category != category) return false;
      if (brand != null && p.brand != brand) return false;
      if (animalType != null && p.animalType != animalType) return false;
      if (unitSize != null && p.effectivePackageSize != unitSize) return false;
      if (minimumPrice != null && p.price < minimumPrice) return false;
      if (maximumPrice != null && p.price > maximumPrice) return false;
      if (q.isNotEmpty &&
          !p.name.toLowerCase().contains(q) &&
          !p.brand.toLowerCase().contains(q) &&
          (!includeInactive ||
              (!p.category.toLowerCase().contains(q) &&
                  !(p.nameEn?.toLowerCase().contains(q) ?? false) &&
                  !p.sku.toLowerCase().contains(q) &&
                  !p.tags.any((tag) => tag.toLowerCase().contains(q))))) {
        return false;
      }
      return switch (normalizedAvailability) {
        'in_stock' => p.isOrderable,
        'low_stock' => p.lowStock,
        'out_of_stock' => !p.isOrderable,
        _ => true,
      };
    }).toList(growable: false);
  }

  CatalogPage _localPage(
    Iterable<Product> products, {
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    required String sort,
    DateTime? snapshotAt,
    required int offset,
    required int pageSize,
    required CatalogPageSource pageSource,
  }) {
    final bounded = _sortProductsNewest(products)
        .take(offlineSnapshotLimit)
        .toList(growable: false);
    final filtered = _filterProducts(
      bounded,
      query: query,
      category: _nonEmptyOrNull(category),
      brand: _nonEmptyOrNull(brand),
      animalType: _nonEmptyOrNull(animalType),
      unitSize: _nonEmptyOrNull(unitSize),
      minimumPrice: minimumPrice,
      maximumPrice: maximumPrice,
      availability: availability,
      includeInactive: includeInactive,
    );
    final sorted = _sortProductsForCatalog(
      filtered,
      sort: sort,
    );
    final candidates = offset >= sorted.length
        ? const <Product>[]
        : sorted.skip(offset).take(pageSize + 1).toList(growable: false);
    final hasMore = candidates.length > pageSize;
    final page = candidates.take(pageSize).toList(growable: false);
    return CatalogPage(
      products: page,
      hasMore: hasMore,
      nextOffset: offset + page.length,
      snapshotAt: (snapshotAt ?? DateTime.now()).toUtc(),
      source: pageSource,
      offlineSnapshotCount: bounded.length,
    );
  }

  CatalogFilterOptions _filterOptionsFromProducts(
    Iterable<Product> source, {
    required bool includeInactive,
    bool isOfflineSnapshot = false,
  }) {
    final products = _filterProducts(
      _sortProductsNewest(source).take(offlineSnapshotLimit),
      query: '',
      includeInactive: includeInactive,
    );
    return CatalogFilterOptions(
      categories: _distinctSorted(
        products.map((product) => product.category),
      ),
      brands: _distinctSorted(products.map((product) => product.brand)),
      animalTypes:
          _distinctSorted(products.map((product) => product.animalType)),
      unitSizes: _distinctSorted(
        products.map((product) => product.effectivePackageSize),
      ),
      isOfflineSnapshot: isOfflineSnapshot,
    );
  }

  List<ProductCategory> _categoriesFromProducts(
    Iterable<Product> products, {
    required bool includeArchived,
  }) {
    final grouped = <String, List<Product>>{};
    for (final product in products) {
      final key = product.categoryId?.trim().isNotEmpty == true
          ? product.categoryId!.trim()
          : 'name:${product.category.trim().toLowerCase()}';
      grouped.putIfAbsent(key, () => []).add(product);
    }
    final categories = <ProductCategory>[
      for (final entry in grouped.entries)
        ProductCategory(
          id: entry.key,
          name: entry.value.first.category,
          active: !entry.value.any(
            (product) => product.archivedByCategoryId == entry.key,
          ),
          archivedAt: entry.value
              .where((product) => product.archivedByCategoryId == entry.key)
              .map((product) => product.archivedAt)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (latest, value) =>
                    latest == null || value.isAfter(latest) ? value : latest,
              ),
          productCount: entry.value.length,
          archivedProductCount: entry.value
              .where((product) => product.archivedByCategoryId == entry.key)
              .length,
        ),
    ]..sort((first, second) => first.name.compareTo(second.name));
    return categories
        .where(
          (category) =>
              includeArchived || (category.active && !category.isArchived),
        )
        .toList(growable: false);
  }

  void _initializeDemoCategories() {
    _demoCategories
      ..clear()
      ..addAll(
        _categoriesFromProducts(
          _demoProducts,
          includeArchived: true,
        ).map((category) {
          if (!category.id.startsWith('name:')) return category;
          return category.copyWith(id: 'demo-category-${const Uuid().v4()}');
        }),
      );
    for (var index = 0; index < _demoProducts.length; index++) {
      final product = _demoProducts[index];
      if (product.categoryId?.trim().isNotEmpty == true) continue;
      final category = _demoCategories.firstWhere(
        (item) =>
            item.name.toLowerCase() == product.category.trim().toLowerCase(),
      );
      _demoProducts[index] = product.copyWith(categoryId: category.id);
    }
    _refreshDemoCategoryCounts();
  }

  void _refreshDemoCategoryCounts() {
    for (var index = 0; index < _demoCategories.length; index++) {
      final category = _demoCategories[index];
      final products = _demoProducts.where(
        (product) =>
            product.categoryId == category.id ||
            (product.categoryId == null && product.category == category.name),
      );
      _demoCategories[index] = category.copyWith(
        productCount: products.length,
        archivedProductCount: products
            .where(
              (product) => product.archivedByCategoryId == category.id,
            )
            .length,
      );
    }
    _sortDemoCategories();
  }

  void _sortDemoCategories() {
    _demoCategories.sort(
      (first, second) => first.name.compareTo(second.name),
    );
  }

  String? get _cacheOwnerProfileId =>
      _pagedRemote?.ownerProfileId ?? supabaseClient?.auth.currentUser?.id;

  Future<String?> _categoryIdFor(String categoryName) async {
    final client = supabaseClient;
    if (client == null) return null;
    final normalizedName = _validatedCategoryName(categoryName);
    final existing = await client
        .from('categories')
        .select('id,name,active,archived_at')
        .ilike('name', normalizedName)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      final category = ProductCategory.fromSupabase(existing);
      if (category.isArchived) {
        throw CategoryArchivedException(category.name);
      }
      if (!category.active) {
        await client
            .from('categories')
            .update({'active': true}).eq('id', category.id);
      }
      return category.id;
    }
    final inserted = await client
        .from('categories')
        .insert({'name': normalizedName, 'active': true})
        .select('id')
        .single();
    return inserted['id'].toString();
  }
}
