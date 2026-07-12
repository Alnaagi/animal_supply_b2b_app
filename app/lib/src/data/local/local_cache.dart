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
  LocalCache({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const _productsKey = 'local_cache.products.v1';
  static const _cartKey = 'local_cache.cart.v1';
  static const _pendingRequestKey = 'local_cache.pending_request.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  List<Product> _cachedProducts = [];
  List<CartItem> _cachedCart = [];
  String? _pendingRequestId;
  String? _pendingFingerprint;

  Future<SharedPreferences?> _store() async {
    if (_prefsOverride != null) return _prefsOverride;
    try {
      return _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProducts(List<Product> products) async {
    _cachedProducts = [...products];
    final prefs = await _store();
    if (prefs == null) return;
    await prefs.setString(
      _productsKey,
      jsonEncode([for (final product in products) _productToJson(product)]),
    );
  }

  Future<List<Product>> cachedProducts() async {
    if (_cachedProducts.isNotEmpty) return [..._cachedProducts];
    final prefs = await _store();
    final raw = prefs?.getString(_productsKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    _cachedProducts = [
      for (final row in decoded)
        if (row is Map) _productFromJson(Map<String, dynamic>.from(row)),
    ];
    return [..._cachedProducts];
  }

  Future<void> saveCart(List<CartItem> items) async {
    _cachedCart = [...items];
    final prefs = await _store();
    if (prefs == null) return;
    await prefs.setString(
      _cartKey,
      jsonEncode([
        for (final item in items)
          {
            'quantity': item.quantity,
            'product': _productToJson(item.product),
          },
      ]),
    );
  }

  Future<List<CartItem>> cachedCart() async {
    if (_cachedCart.isNotEmpty) return [..._cachedCart];
    final prefs = await _store();
    final raw = prefs?.getString(_cartKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    _cachedCart = [
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
    return [..._cachedCart];
  }

  Future<void> savePendingRequest({
    required String? requestId,
    required String? fingerprint,
  }) async {
    _pendingRequestId = requestId;
    _pendingFingerprint = fingerprint;
    final prefs = await _store();
    if (prefs == null) return;
    if (requestId == null || fingerprint == null) {
      await prefs.remove(_pendingRequestKey);
      return;
    }
    await prefs.setString(
      _pendingRequestKey,
      jsonEncode({
        'request_id': requestId,
        'fingerprint': fingerprint,
      }),
    );
  }

  Future<({String requestId, String fingerprint})?> pendingRequest() async {
    if (_pendingRequestId != null && _pendingFingerprint != null) {
      return (
        requestId: _pendingRequestId!,
        fingerprint: _pendingFingerprint!,
      );
    }
    final prefs = await _store();
    final raw = prefs?.getString(_pendingRequestKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final requestId = decoded['request_id']?.toString();
    final fingerprint = decoded['fingerprint']?.toString();
    if (requestId == null ||
        requestId.isEmpty ||
        fingerprint == null ||
        fingerprint.isEmpty) {
      return null;
    }
    _pendingRequestId = requestId;
    _pendingFingerprint = fingerprint;
    return (requestId: requestId, fingerprint: fingerprint);
  }

  /// Kept for callers that still stage a draft order object locally.
  Future<void> saveDraftOrder(Order order) async {
    // Draft order rows are represented by the durable cart + outbox entries.
    // This method remains for API compatibility with earlier stubs.
  }

  Future<List<Order>> draftOrders() async => const [];

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
        'oldPrice': product.oldPrice,
        'discountPercent': product.discountPercent,
        'stockQuantity': product.stockQuantity,
        'minOrderQty': product.minOrderQty,
        'descriptionAr': product.descriptionAr,
        'imageUrl': product.imageUrl,
        'imageAttribution': product.imageAttribution,
        'sourceUrl': product.sourceUrl,
        'isActive': product.isActive,
        'isFeatured': product.isFeatured,
        'isTopSelling': product.isTopSelling,
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
      oldPrice: (json['oldPrice'] as num?)?.toDouble(),
      discountPercent: (json['discountPercent'] as num?)?.toInt(),
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
      minOrderQty: (json['minOrderQty'] as num?)?.toInt() ?? 1,
      descriptionAr: (json['descriptionAr'] ?? '').toString(),
      imageUrl: json['imageUrl']?.toString(),
      imageAttribution: json['imageAttribution']?.toString(),
      sourceUrl: json['sourceUrl']?.toString(),
      isActive: json['isActive'] != false,
      isFeatured: json['isFeatured'] == true,
      isTopSelling: json['isTopSelling'] == true,
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
