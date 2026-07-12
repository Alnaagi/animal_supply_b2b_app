import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connectivity/connectivity_provider.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/cart/cart_controller.dart';
import '../local/local_cache.dart';
import '../repositories/orders_repository.dart';
import 'sync_outbox.dart';

/// Flushes durable `place_order` outbox entries when connectivity returns.
///
/// Retries send only product_id/quantity + client_request_id (and notes).
/// Server remains authoritative for price, stock, customer, and status.
final outboxRetryCoordinatorProvider = Provider<OutboxRetryCoordinator>((ref) {
  final coordinator = OutboxRetryCoordinator(ref);
  ref
    ..onDispose(coordinator.dispose)
    ..listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      final online = next.asData?.value ?? false;
      final wasOffline = previous?.asData?.value == false;
      if (online && (wasOffline || previous == null)) {
        unawaited(coordinator.flushPendingPlaceOrders());
      }
    })
    ..listen<AuthState>(authControllerProvider, (previous, next) {
      final signedIn = next.user != null && previous?.user == null;
      if (signedIn) {
        unawaited(coordinator.flushIfOnline());
      }
    });
  unawaited(Future<void>(() async {
    await Future<void>.delayed(Duration.zero);
    await coordinator.flushIfOnline();
  }));
  return coordinator;
});

class OutboxRetryCoordinator {
  OutboxRetryCoordinator(this._ref);

  final Ref _ref;
  bool _flushing = false;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
  }

  Future<void> flushIfOnline() async {
    final results = await Connectivity().checkConnectivity();
    final online = results.any((item) => item != ConnectivityResult.none);
    if (online) {
      await flushPendingPlaceOrders();
    }
  }

  Future<void> flushPendingPlaceOrders() async {
    if (_disposed || _flushing) return;
    final user = _ref.read(authControllerProvider).user;
    if (user == null || user.role != 'customer') return;

    final outbox = _ref.read(syncOutboxProvider);
    final pending = await outbox.pending();
    final placeOrders = pending
        .where((entry) => entry.entityType == 'place_order')
        .toList(growable: false);
    if (placeOrders.isEmpty) return;

    _flushing = true;
    try {
      final orders = _ref.read(ordersRepositoryProvider);
      final cart = _ref.read(cartControllerProvider.notifier);
      final cache = _ref.read(localCacheProvider);

      for (final entry in placeOrders) {
        if (_disposed) return;
        final payload = entry.payload;
        final requestId =
            (payload['client_request_id'] ?? entry.id).toString().trim();
        final rawItems = payload['items'];
        if (requestId.isEmpty || rawItems is! List) {
          await outbox.remove(entry.id);
          continue;
        }

        final items = <Map<String, Object?>>[
          for (final row in rawItems)
            if (row is Map) Map<String, Object?>.from(row)
        ];

        try {
          await orders.placeOrderFromOutbox(
            clientRequestId: requestId,
            items: items,
            deliveryAddress: payload['delivery_address']?.toString() ?? '',
            customerNote: payload['customer_note']?.toString() ?? '',
            deliveryNote: payload['delivery_note']?.toString() ?? '',
            demoCustomerId: user.customerId ?? user.id,
            demoBusinessName: user.businessName ?? user.username,
          );

          final syncedItems = <({String productId, int quantity})>[
            for (final item in items)
              (
                productId: item['product_id']?.toString() ?? '',
                quantity: item['quantity'] is int
                    ? item['quantity'] as int
                    : item['quantity'] is num
                        ? (item['quantity'] as num).toInt()
                        : int.tryParse('${item['quantity']}') ?? 0,
              ),
          ].where((item) => item.productId.isNotEmpty && item.quantity > 0);

          await cart.acknowledgeSyncedOutboxOrder(
            requestId: requestId,
            items: syncedItems.toList(growable: false),
          );
          await outbox.remove(entry.id);
          final pendingRequest = await cache.pendingRequest();
          if (pendingRequest?.requestId == requestId) {
            await cache.savePendingRequest(requestId: null, fingerprint: null);
          }
        } on OrdersRepositoryException {
          // Keep the entry pending for a later reconnect/manual retry.
          return;
        } catch (_) {
          return;
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
