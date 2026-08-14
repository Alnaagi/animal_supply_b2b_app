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
  final ownerProfileId = ref.watch(
    authControllerProvider.select((auth) => auth.user?.id),
  );
  final controller = CartController(
    ref,
    ownerProfileId: ownerProfileId,
    cache: ref.watch(localCacheProvider),
    outbox: ref.watch(syncOutboxProvider),
  );
  unawaited(controller.hydrate());
  return controller;
});

class CartController extends StateNotifier<List<CartItem>> {
  CartController(
    this.ref, {
    required String? ownerProfileId,
    LocalCache? cache,
    SyncOutbox? outbox,
    List<CartItem> initialItems = const [],
  })  : _ownerProfileId = ownerProfileId,
        _cache = cache,
        _outbox = outbox,
        super(initialItems);

  final Ref ref;
  final String? _ownerProfileId;
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
    final ownerProfileId = _ownerProfileId;
    if (ownerProfileId == null || ownerProfileId.isEmpty) return;
    final cachedCart = await cache.cachedCart(
      ownerProfileId: ownerProfileId,
    );
    final pending = await cache.pendingRequest(
      ownerProfileId: ownerProfileId,
    );
    if (!mounted) return;
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
    if (!product.isOrderable) return;
    _invalidatePendingRequest();
    final safeQty = product.normalizeOrderQuantity(quantity);
    final index = state.indexWhere((item) => item.product.id == product.id);
    if (index == -1) {
      state = [...state, CartItem(product: product, quantity: safeQty)];
    } else {
      state = [
        for (final item in state)
          if (item.product.id == product.id)
            item.copyWith(
              quantity: product.normalizeOrderQuantity(item.quantity + safeQty),
            )
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
        else if (item.product.isOrderable)
          item.copyWith(
            quantity: item.product.normalizeOrderQuantity(qty),
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
    if (_ownerProfileId == null || user.id != _ownerProfileId) {
      throw const OrdersRepositoryException(
        code: 'AUTH_CONTEXT_CHANGED',
        message:
            'تغير حساب المستخدم. افتح السلة من الحساب الحالي وحاول مجدداً.',
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

      await _outbox?.remove(
        requestId,
        ownerProfileId: _ownerProfileId,
      );
      if (identical(state, submittedState)) {
        state = const [];
      } else {
        state = _removeSubmittedItems(state, submittedItems);
      }
      _invalidatePendingRequest();
      await _persistCart();
      await _persistPendingRequest();
      return order;
    } on OrdersRepositoryException catch (error) {
      final requestIsStillCurrent =
          _pendingRequestId == requestId && _pendingFingerprint == fingerprint;
      bool? queuedDurably;
      if (error.isRetryable && requestIsStillCurrent) {
        queuedDurably = await _enqueuePendingOrder(
          requestId: requestId,
          items: submittedItems,
          note: note,
          deliveryAddress: deliveryAddress,
          deliveryNote: deliveryNote,
        );
      } else if (!requestIsStillCurrent) {
        await _outbox?.remove(
          requestId,
          ownerProfileId: _ownerProfileId,
        );
      } else {
        await _outbox?.markFailed(
          requestId,
          ownerProfileId: _ownerProfileId,
          errorCode: error.code,
        );
      }
      final cartDurable = await _persistCart();
      final requestDurable = await _persistPendingRequest();
      if (queuedDurably == false || !cartDurable || !requestDurable) {
        throw const OrdersRepositoryException(
          code: 'LOCAL_STORAGE_UNAVAILABLE',
          message: 'تعذر حفظ الطلب بشكل دائم على هذا الجهاز. '
              'بقيت السلة في الجلسة الحالية فقط؛ لا تغلق التطبيق، '
              'تحقق من مساحة التخزين ثم أعد الإرسال.',
        );
      }
      rethrow;
    } catch (_) {
      await _outbox?.markFailed(
        requestId,
        ownerProfileId: _ownerProfileId,
        errorCode: 'UNEXPECTED_LOCAL_FAILURE',
      );
      await _persistCart();
      await _persistPendingRequest();
      rethrow;
    }
  }

  Future<bool> _enqueuePendingOrder({
    required String requestId,
    required List<CartItem> items,
    required String note,
    required String deliveryAddress,
    required String deliveryNote,
  }) async {
    final outbox = _outbox;
    if (outbox == null) return false;
    return outbox.enqueue(
      SyncOutboxEntry(
        id: requestId,
        ownerProfileId: _ownerProfileId!,
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

  /// Cancels a still-visible queued request before the customer edits the cart.
  ///
  /// The current cart is intentionally preserved. A stale request is never
  /// replayed or restored blindly from product IDs.
  Future<bool> discardQueuedOrderForEditing({
    required String requestId,
    required CustomerQueuedOrderState expectedState,
  }) async {
    await hydrate();
    final user = ref.read(authControllerProvider).user;
    final ownerProfileId = _ownerProfileId;
    final outbox = _outbox;
    if (user == null ||
        !user.isCustomer ||
        ownerProfileId == null ||
        user.id != ownerProfileId ||
        outbox == null) {
      return false;
    }

    final discarded = await outbox.discardPlaceOrderForEditing(
      requestId,
      ownerProfileId: ownerProfileId,
      expectedState: expectedState,
    );
    if (!discarded) return false;

    if (_pendingRequestId == requestId) {
      _pendingRequestId = null;
      _pendingFingerprint = null;
      await _persistPendingRequest();
    }
    return true;
  }

  Future<bool> _persistCart() async {
    final ownerProfileId = _ownerProfileId;
    if (ownerProfileId == null || ownerProfileId.isEmpty) return false;
    return await _cache?.saveCart(
          ownerProfileId: ownerProfileId,
          items: state,
        ) ??
        false;
  }

  Future<bool> _persistPendingRequest() async {
    final ownerProfileId = _ownerProfileId;
    if (ownerProfileId == null || ownerProfileId.isEmpty) return false;
    return await _cache?.savePendingRequest(
          ownerProfileId: ownerProfileId,
          requestId: _pendingRequestId,
          fingerprint: _pendingFingerprint,
        ) ??
        false;
  }

  void _invalidatePendingRequest() {
    final requestId = _pendingRequestId;
    _pendingRequestId = null;
    _pendingFingerprint = null;
    if (requestId != null && _ownerProfileId != null) {
      unawaited(
        _outbox?.remove(
          requestId,
          ownerProfileId: _ownerProfileId,
        ),
      );
    }
    unawaited(_persistPendingRequest());
  }

  /// Clears local pending state after a successful outbox flush.
  Future<void> acknowledgeSyncedOutboxOrder({
    required String requestId,
    required List<({String productId, int quantity})> items,
  }) async {
    final submittedQuantities = {
      for (final item in items) item.productId: item.quantity,
    };
    state = [
      for (final item in state)
        if (!submittedQuantities.containsKey(item.product.id))
          item
        else if (item.quantity - submittedQuantities[item.product.id]! >=
            item.product.minOrderQuantity)
          item.copyWith(
            quantity: item.quantity - submittedQuantities[item.product.id]!,
          ),
    ];
    if (_pendingRequestId == requestId) {
      _pendingRequestId = null;
      _pendingFingerprint = null;
    }
    await _persistCart();
    await _persistPendingRequest();
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
