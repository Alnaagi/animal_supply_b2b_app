import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';
import '../models/product.dart';

final localCacheProvider = Provider<LocalCache>((ref) => LocalCache());

/// Durable local snapshot store for catalog and cart.
///
/// Cached product prices are display estimates only. Authoritative pricing and
/// authorization always happen on the server when an order is placed.
class LocalCache {
  LocalCache({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const _productsKey = 'local_cache.products.v1';
  static const _productsKeyPrefix = 'local_cache.products.v2.';
  static const _productsQuarantineKeyPrefix =
      'local_cache.products.quarantine.v1.';
  static const _legacyCartKey = 'local_cache.cart.v1';
  static const _legacyPendingRequestKey = 'local_cache.pending_request.v1';
  static const _cartKeyPrefix = 'local_cache.cart.v2.';
  static const _pendingRequestKeyPrefix = 'local_cache.pending_request.v2.';
  static const _legacyQuarantineKey =
      'local_cache.quarantine.legacy_unowned.v1';

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;

  List<Product> _cachedProducts = [];
  final Map<String, List<Product>> _cachedProductsByOwner = {};
  final Set<String> _loadedProductOwners = {};
  final Map<String, List<CartItem>> _cachedCarts = {};
  final Set<String> _loadedCartOwners = {};
  final Map<String, ({String requestId, String fingerprint})?>
      _pendingRequests = {};
  final Set<String> _loadedPendingRequestOwners = {};
  Future<void>? _legacyQuarantineFuture;

  Future<SharedPreferences?> _store() async {
    if (_prefsOverride != null) return _prefsOverride;
    try {
      return _prefs ??=
          await (_storeLoader?.call() ?? SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveProducts(
    List<Product> products, {
    String? ownerProfileId,
  }) async {
    final owner = _normalizeOwner(ownerProfileId ?? '');
    if (owner == null) {
      _cachedProducts = [...products];
    } else {
      _cachedProductsByOwner[owner] = [...products];
      _loadedProductOwners.add(owner);
    }
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(
        owner == null ? _productsKey : _ownerKey(_productsKeyPrefix, owner),
        jsonEncode([for (final product in products) _productToJson(product)]),
      );
    } catch (_) {
      return false;
    }
  }

  Future<List<Product>> cachedProducts({String? ownerProfileId}) async {
    final owner = _normalizeOwner(ownerProfileId ?? '');
    if (owner == null && _cachedProducts.isNotEmpty) {
      return [..._cachedProducts];
    }
    if (owner != null && _loadedProductOwners.contains(owner)) {
      return [...?_cachedProductsByOwner[owner]];
    }
    final prefs = await _store();
    final key =
        owner == null ? _productsKey : _ownerKey(_productsKeyPrefix, owner);
    final raw = prefs?.getString(key);
    if (raw == null || raw.isEmpty) {
      if (owner != null) {
        _cachedProductsByOwner[owner] = const [];
        _loadedProductOwners.add(owner);
      }
      return const [];
    }
    List<Product> products;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Catalog cache must contain a list.');
      }
      products = [
        for (final row in decoded)
          if (row is Map)
            _productFromJson(Map<String, dynamic>.from(row))
          else
            throw const FormatException('Catalog cache row must be an object.'),
      ];
      if (products.any(
        (product) =>
            product.id.trim().isEmpty ||
            product.name.trim().isEmpty ||
            product.minOrderQty < 1 ||
            product.stockQuantity < 0 ||
            !product.basePrice.isFinite ||
            product.basePrice < 0,
      )) {
        throw const FormatException(
            'Catalog cache contains an invalid product.');
      }
    } catch (_) {
      await _quarantineCorruptProductSnapshot(
        prefs: prefs,
        sourceKey: key,
        raw: raw,
        ownerProfileId: owner,
      );
      products = const [];
    }
    if (owner == null) {
      _cachedProducts = products;
    } else {
      _cachedProductsByOwner[owner] = products;
      _loadedProductOwners.add(owner);
    }
    return [...products];
  }

  Future<void> _quarantineCorruptProductSnapshot({
    required SharedPreferences? prefs,
    required String sourceKey,
    required String raw,
    required String? ownerProfileId,
  }) async {
    if (prefs == null) return;
    final quarantineKey = ownerProfileId == null
        ? '${_productsQuarantineKeyPrefix}anonymous'
        : _ownerKey(_productsQuarantineKeyPrefix, ownerProfileId);
    try {
      await prefs.setString(
        quarantineKey,
        jsonEncode({
          'sourceKey': sourceKey,
          'reason': 'invalid_catalog_snapshot',
          'value': raw,
        }),
      );
      await prefs.remove(sourceKey);
    } catch (_) {
      // A corrupt cache must never prevent the catalog from falling back to an
      // empty snapshot, even when cleanup storage is also unavailable.
    }
  }

  Future<bool> saveCart({
    required String ownerProfileId,
    required List<CartItem> items,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return false;
    await _quarantineLegacyCustomerState();
    _cachedCarts[owner] = [...items];
    _loadedCartOwners.add(owner);
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(
        _ownerKey(_cartKeyPrefix, owner),
        jsonEncode([
          for (final item in items)
            {
              'quantity': item.quantity,
              'product': _productToJson(item.product),
            },
        ]),
      );
    } catch (_) {
      return false;
    }
  }

  Future<List<CartItem>> cachedCart({
    required String ownerProfileId,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return const [];
    await _quarantineLegacyCustomerState();
    if (_loadedCartOwners.contains(owner)) {
      return [...?_cachedCarts[owner]];
    }
    final prefs = await _store();
    final raw = prefs?.getString(_ownerKey(_cartKeyPrefix, owner));
    if (raw == null || raw.isEmpty) {
      _cachedCarts[owner] = const [];
      _loadedCartOwners.add(owner);
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _cachedCarts[owner] = const [];
      } else {
        _cachedCarts[owner] = [
          for (final row in decoded)
            if (row is Map)
              CartItem(
                product: _productFromJson(
                  Map<String, dynamic>.from(
                    (row['product'] as Map?) ?? const {},
                  ),
                ),
                quantity: (row['quantity'] as num?)?.toInt() ?? 1,
              ),
        ];
      }
    } catch (_) {
      _cachedCarts[owner] = const [];
    }
    _loadedCartOwners.add(owner);
    return [...?_cachedCarts[owner]];
  }

  Future<bool> savePendingRequest({
    required String ownerProfileId,
    required String? requestId,
    required String? fingerprint,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return false;
    await _quarantineLegacyCustomerState();
    _loadedPendingRequestOwners.add(owner);
    if (requestId == null || fingerprint == null) {
      _pendingRequests[owner] = null;
      final prefs = await _store();
      if (prefs == null) return false;
      try {
        return await prefs.remove(_ownerKey(_pendingRequestKeyPrefix, owner));
      } catch (_) {
        return false;
      }
    }
    _pendingRequests[owner] = (
      requestId: requestId,
      fingerprint: fingerprint,
    );
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(
        _ownerKey(_pendingRequestKeyPrefix, owner),
        jsonEncode({
          'request_id': requestId,
          'fingerprint': fingerprint,
        }),
      );
    } catch (_) {
      return false;
    }
  }

  Future<({String requestId, String fingerprint})?> pendingRequest({
    required String ownerProfileId,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return null;
    await _quarantineLegacyCustomerState();
    if (_loadedPendingRequestOwners.contains(owner)) {
      return _pendingRequests[owner];
    }
    final prefs = await _store();
    final raw = prefs?.getString(_ownerKey(_pendingRequestKeyPrefix, owner));
    if (raw == null || raw.isEmpty) {
      _pendingRequests[owner] = null;
      _loadedPendingRequestOwners.add(owner);
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final requestId = decoded['request_id']?.toString();
        final fingerprint = decoded['fingerprint']?.toString();
        if (requestId != null &&
            requestId.isNotEmpty &&
            fingerprint != null &&
            fingerprint.isNotEmpty) {
          final pending = (
            requestId: requestId,
            fingerprint: fingerprint,
          );
          _pendingRequests[owner] = pending;
          _loadedPendingRequestOwners.add(owner);
          return pending;
        }
      }
    } catch (_) {}
    _pendingRequests[owner] = null;
    _loadedPendingRequestOwners.add(owner);
    return null;
  }

  /// Kept for callers that still stage a draft order object locally.
  Future<void> saveDraftOrder(Order order) async {
    // Draft order rows are represented by the durable cart + outbox entries.
    // This method remains for API compatibility with earlier stubs.
  }

  Future<List<Order>> draftOrders() async => const [];

  Future<void> _quarantineLegacyCustomerState() {
    return _legacyQuarantineFuture ??= _quarantineLegacyCustomerStateBody();
  }

  Future<void> _quarantineLegacyCustomerStateBody() async {
    final prefs = await _store();
    if (prefs == null) return;
    final legacy = <String, String>{};
    for (final key in const [
      _legacyCartKey,
      _legacyPendingRequestKey,
    ]) {
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) legacy[key] = raw;
    }
    if (legacy.isEmpty) return;

    final quarantined = <String, dynamic>{};
    final existing = prefs.getString(_legacyQuarantineKey);
    if (existing != null && existing.isNotEmpty) {
      try {
        final decoded = jsonDecode(existing);
        if (decoded is Map) {
          quarantined.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    for (final entry in legacy.entries) {
      quarantined.putIfAbsent(entry.key, () => entry.value);
    }
    await prefs.setString(_legacyQuarantineKey, jsonEncode(quarantined));
    for (final key in legacy.keys) {
      await prefs.remove(key);
    }
  }

  static String? _normalizeOwner(String ownerProfileId) {
    final owner = ownerProfileId.trim();
    return owner.isEmpty ? null : owner;
  }

  static String _ownerKey(String prefix, String ownerProfileId) {
    final encoded =
        base64Url.encode(utf8.encode(ownerProfileId)).replaceAll('=', '');
    return '$prefix$encoded';
  }

  static Map<String, dynamic> _productToJson(Product product) => {
        'id': product.id,
        'nameAr': product.nameAr,
        'nameEn': product.nameEn,
        'sku': product.sku,
        'category': product.category,
        'categoryId': product.categoryId,
        'animalType': product.animalType,
        'brand': product.brand,
        'unitSize': product.unitSize,
        'packageSize': product.packageSize,
        'basePrice': product.basePrice,
        'effectivePrice': product.effectivePrice,
        'retailUnitPrice': product.retailUnitPrice,
        'oldPrice': product.oldPrice,
        'discountPercent': product.discountPercent,
        'stockQuantity': product.stockQuantity,
        'availableQuantity': product.availableQuantity,
        'stockTrackingEnabled': product.stockTrackingEnabled,
        'showStockQuantityToCustomers': product.showStockQuantityToCustomers,
        'hideWhenOutOfStock': product.hideWhenOutOfStock,
        'unitsPerBox': product.unitsPerBox,
        'minOrderQty': product.minOrderQty,
        'descriptionAr': product.descriptionAr,
        'imageUrl': product.imageUrl,
        'imageAttribution': product.imageAttribution,
        'sourceUrl': product.sourceUrl,
        'isActive': product.isActive,
        'isFeatured': product.isFeatured,
        'isTopSelling': product.isTopSelling,
        'archivedAt': product.archivedAt?.toIso8601String(),
        'archivedByCategoryId': product.archivedByCategoryId,
        'activeBeforeCategoryArchive': product.activeBeforeCategoryArchive,
        'createdAt': product.createdAt?.toIso8601String(),
        'updatedAt': product.updatedAt?.toIso8601String(),
        'packageOptions': product.packageOptions,
        'tags': product.tags,
      };

  static Product _productFromJson(Map<String, dynamic> json) {
    return Product(
      id: (json['id'] ?? '').toString(),
      nameAr: (json['nameAr'] ?? '').toString(),
      nameEn: json['nameEn']?.toString(),
      sku: (json['sku'] ?? '').toString(),
      category: (json['category'] ?? 'بدون تصنيف').toString(),
      categoryId: json['categoryId']?.toString(),
      animalType: (json['animalType'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      unitSize: (json['unitSize'] ?? '').toString(),
      packageSize: json['packageSize']?.toString(),
      basePrice: (json['basePrice'] as num?)?.toDouble() ?? 0,
      effectivePrice: (json['effectivePrice'] as num?)?.toDouble(),
      retailUnitPrice: (json['retailUnitPrice'] as num?)?.toDouble(),
      oldPrice: (json['oldPrice'] as num?)?.toDouble(),
      discountPercent: (json['discountPercent'] as num?)?.toInt(),
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
      availableQuantity: (json['availableQuantity'] as num?)?.toInt(),
      stockTrackingEnabled: json['stockTrackingEnabled'] != false,
      showStockQuantityToCustomers:
          json['showStockQuantityToCustomers'] == true,
      hideWhenOutOfStock: json['hideWhenOutOfStock'] == true,
      unitsPerBox: (json['unitsPerBox'] as num?)?.toInt(),
      minOrderQty: (json['minOrderQty'] as num?)?.toInt() ?? 1,
      descriptionAr: (json['descriptionAr'] ?? '').toString(),
      imageUrl: json['imageUrl']?.toString(),
      imageAttribution: json['imageAttribution']?.toString(),
      sourceUrl: json['sourceUrl']?.toString(),
      isActive: json['isActive'] != false,
      isFeatured: json['isFeatured'] == true,
      isTopSelling: json['isTopSelling'] == true,
      archivedAt: DateTime.tryParse(json['archivedAt']?.toString() ?? ''),
      archivedByCategoryId: json['archivedByCategoryId']?.toString(),
      activeBeforeCategoryArchive: json['activeBeforeCategoryArchive'] as bool?,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      packageOptions: [
        for (final option in (json['packageOptions'] as List? ?? const []))
          option.toString(),
      ],
      tags: [
        for (final tag in (json['tags'] as List? ?? const [])) tag.toString(),
      ],
    );
  }
}
