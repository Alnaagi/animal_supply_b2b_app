import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/local_cache.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/repositories/orders_repository.dart';
import '../../data/sync/sync_outbox.dart';
import '../auth/auth_controller.dart';

final cartControllerProvider =
    StateNotifierProvider<CartController, List<CartItem>>((ref) {
  final controller = CartController(
    ref,
    cache: ref.watch(localCacheProvider),
    outbox: ref.watch(syncOutboxProvider),
  );
  unawaited(controller.hydrate());
  return controller;
});

class CartController extends StateNotifier<List<CartItem>> {
  CartController(
    this.ref, {
    LocalCache? cache,
    SyncOutbox? outbox,
    List<CartItem> initialItems = const [],
  })  : _cache = cache,
        _outbox = outbox,
        super(initialItems);

  final Ref ref;
  final LocalCache? _cache;
  final SyncOutbox? _outbox;
  String? _pendingRequestId;
  String? _pendingFingerprint;
  Future<void>? _hydrateFuture;

  Future<void> hydrate() {
    final cache = _cache;
    if (cache == null) return Future.value();
    return _hydrateFuture ??= _hydrateBody(cache);
  }

  Future<void> _hydrateBody(LocalCache cache) async {
    final cachedCart = await cache.cachedCart();
    final pending = await cache.pendingRequest();
    // Never clobber newer in-memory cart/pending state if hydrate finishes late.
    if (cachedCart.isNotEmpty && state.isEmpty) {
      state = cachedCart;
    }
    if (_pendingRequestId == null && pending != null) {
      _pendingRequestId = pending.requestId;
      _pendingFingerprint = pending.fingerprint;
    }
  }

  void add(Product product) {
    addQuantity(product, product.minOrderQuantity);
  }

  void addQuantity(Product product, int quantity) {
    if (!product.inStock || product.stockQuantity < product.minOrderQuantity) {
      return;
    }
    _invalidatePendingRequest();
    final safeQty =
        quantity.clamp(product.minOrderQuantity, product.stockQuantity);
    final index = state.indexWhere((item) => item.product.id == product.id);
    if (index == -1) {
      state = [...state, CartItem(product: product, quantity: safeQty)];
    } else {
      state = [
        for (final item in state)
          if (item.product.id == product.id)
            item.copyWith(
                quantity: (item.quantity + safeQty)
                    .clamp(product.minOrderQuantity, product.stockQuantity))
          else
            item,
      ];
    }
    unawaited(_persistCart());
  }

  void updateQty(String productId, int qty) {
    _invalidatePendingRequest();
    state = [
      for (final item in state)
        if (item.product.id != productId)
          item
        else if (item.product.stockQuantity >= item.product.minOrderQuantity)
          item.copyWith(
            quantity: qty.clamp(
              item.product.minOrderQuantity,
              item.product.stockQuantity,
            ),
          )
        else
          item,
    ];
    unawaited(_persistCart());
  }

  void remove(String productId) {
    _invalidatePendingRequest();
    state = state.where((item) => item.product.id != productId).toList();
    unawaited(_persistCart());
  }

  void clear() {
    _invalidatePendingRequest();
    state = const [];
    unawaited(_persistCart());
  }

  Future<Order> submit({
    String note = '',
    String deliveryAddress = '',
    String deliveryNote = '',
  }) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) {
      throw const OrdersRepositoryException(
        code: 'AUTH_REQUIRED',
        message: 'انتهت جلسة الدخول. سجل الدخول من جديد ثم أعد المحاولة.',
      );
    }

    final submittedState = state;
    final submittedItems = List<CartItem>.unmodifiable(submittedState);
    final fingerprint = _fingerprint(
      submittedItems,
      note: note,
      deliveryAddress: deliveryAddress,
      deliveryNote: deliveryNote,
    );
    if (_pendingFingerprint != fingerprint || _pendingRequestId == null) {
      _pendingFingerprint = fingerprint;
      _pendingRequestId = const Uuid().v4();
    }
    final requestId = _pendingRequestId!;
    await _persistPendingRequest();

    try {
      final order = await ref.read(ordersRepositoryProvider).placeOrder(
            clientRequestId: requestId,
            customerId: user.customerId ?? user.id,
            businessName: user.businessName ?? user.username,
            items: submittedItems,
            deliveryAddress: deliveryAddress,
            customerNote: note,
            deliveryNote: deliveryNote,
          );

      await _outbox?.remove(requestId);
      if (identical(state, submittedState)) {
        state = const [];
      } else {
        state = _removeSubmittedItems(state, submittedItems);
      }
      _invalidatePendingRequest();
      await _persistCart();
      await _persistPendingRequest();
      return order;
    } catch (error) {
      await _enqueuePendingOrder(
        requestId: requestId,
        items: submittedItems,
        note: note,
        deliveryAddress: deliveryAddress,
        deliveryNote: deliveryNote,
      );
      await _persistCart();
      await _persistPendingRequest();
      rethrow;
    }
  }

  Future<void> _enqueuePendingOrder({
    required String requestId,
    required List<CartItem> items,
    required String note,
    required String deliveryAddress,
    required String deliveryNote,
  }) async {
    final outbox = _outbox;
    if (outbox == null) return;
    await outbox.enqueue(
      SyncOutboxEntry(
        id: requestId,
        entityType: 'place_order',
        payload: {
          'client_request_id': requestId,
          'delivery_address': deliveryAddress,
          'customer_note': note,
          'delivery_note': deliveryNote,
          // Quantities only — server recomputes price/stock/auth on retry.
          'items': [
            for (final item in items)
              {
                'product_id': item.product.id,
                'quantity': item.quantity,
              },
          ],
          'pending_locally': true,
        },
      ),
    );
  }

  Future<void> _persistCart() async {
    await _cache?.saveCart(state);
  }

  Future<void> _persistPendingRequest() async {
    await _cache?.savePendingRequest(
      requestId: _pendingRequestId,
      fingerprint: _pendingFingerprint,
    );
  }

  void _invalidatePendingRequest() {
    _pendingRequestId = null;
    _pendingFingerprint = null;
    unawaited(_persistPendingRequest());
  }

  static String _fingerprint(
    List<CartItem> items, {
    required String note,
    required String deliveryAddress,
    required String deliveryNote,
  }) {
    final itemFingerprint = [
      for (final item in items) '${item.product.id}:${item.quantity}',
    ].join('|');
    return '$itemFingerprint\n'
        '${deliveryAddress.trim()}\n'
        '${deliveryNote.trim()}\n'
        '${note.trim()}';
  }

  static List<CartItem> _removeSubmittedItems(
    List<CartItem> current,
    List<CartItem> submitted,
  ) {
    final submittedQuantities = {
      for (final item in submitted) item.product.id: item.quantity,
    };
    return [
      for (final item in current)
        if (!submittedQuantities.containsKey(item.product.id))
          item
        else if (item.quantity - submittedQuantities[item.product.id]! >=
            item.product.minOrderQuantity)
          item.copyWith(
            quantity: item.quantity - submittedQuantities[item.product.id]!,
          ),
    ];
  }
}
