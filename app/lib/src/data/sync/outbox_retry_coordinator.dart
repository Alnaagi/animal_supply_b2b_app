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
  final outboxChanges = ref.read(syncOutboxProvider).ownerChanges.listen(
    (ownerProfileId) {
      unawaited(
        coordinator.schedulePendingPlaceOrdersFor(
          ownerProfileId: ownerProfileId,
        ),
      );
    },
  );
  ref
    ..onDispose(() {
      unawaited(outboxChanges.cancel());
      coordinator.dispose();
    })
    ..listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      final online = next.asData?.value ?? false;
      final wasOffline = previous?.asData?.value == false;
      final hadConnectivityValue = previous?.asData != null;
      coordinator.handleConnectivityChanged(online);
      if (online && (wasOffline || !hadConnectivityValue)) {
        unawaited(coordinator.flushPendingPlaceOrders());
      }
    })
    ..listen<AuthState>(authControllerProvider, (previous, next) {
      final ownerChanged = next.user?.id != previous?.user?.id;
      if (ownerChanged) {
        coordinator.handleAuthOwnerChanged();
      }
      if (next.user != null && ownerChanged) {
        unawaited(coordinator.flushIfOnline());
      }
    });
  unawaited(Future<void>(() async {
    await Future<void>.delayed(Duration.zero);
    await coordinator.flushIfOnline();
  }));
  return coordinator;
});

final outboxSyncNoticeProvider =
    StateProvider<OutboxSyncNotice?>((ref) => null);

class OutboxSyncNotice {
  const OutboxSyncNotice({
    required this.ownerProfileId,
    required this.requestId,
    required this.orderNumber,
  });

  final String ownerProfileId;
  final String requestId;
  final String orderNumber;
}

abstract interface class OutboxRetryHandle {
  bool get isActive;

  void cancel();
}

typedef OutboxRetryCallback = Future<void> Function();
typedef OutboxRetryScheduler = OutboxRetryHandle Function(
  Duration delay,
  OutboxRetryCallback callback,
);
typedef OutboxConnectivityCheck = Future<bool> Function();

class OutboxRetryCoordinator {
  OutboxRetryCoordinator(
    this._ref, {
    OutboxRetryScheduler? retryScheduler,
    OutboxConnectivityCheck? connectivityCheck,
    this.initialRetryDelay = const Duration(seconds: 5),
    this.maximumRetryDelay = const Duration(minutes: 5),
  })  : _retryScheduler = retryScheduler ?? _scheduleTimer,
        _connectivityCheck = connectivityCheck ?? _hasNetworkConnection {
    if (initialRetryDelay <= Duration.zero) {
      throw ArgumentError.value(
        initialRetryDelay,
        'initialRetryDelay',
        'Must be greater than zero.',
      );
    }
    if (maximumRetryDelay < initialRetryDelay) {
      throw ArgumentError.value(
        maximumRetryDelay,
        'maximumRetryDelay',
        'Must be greater than or equal to initialRetryDelay.',
      );
    }
    _ref.onDispose(dispose);
  }

  final Ref _ref;
  final OutboxRetryScheduler _retryScheduler;
  final OutboxConnectivityCheck _connectivityCheck;
  final Duration initialRetryDelay;
  final Duration maximumRetryDelay;
  bool _flushing = false;
  bool _disposed = false;
  bool? _knownOnline;
  OutboxRetryHandle? _retryHandle;
  String? _scheduledOwnerProfileId;
  int _retryRound = 0;

  void dispose() {
    _disposed = true;
    _cancelScheduledRetry(resetBackoff: true);
  }

  void handleConnectivityChanged(bool online) {
    _knownOnline = online;
    if (!online) {
      _cancelScheduledRetry(resetBackoff: false);
    }
  }

  void handleAuthOwnerChanged() {
    _cancelScheduledRetry(resetBackoff: true);
  }

  Future<void> flushIfOnline() async {
    final online = await _connectivityCheck();
    _knownOnline = online;
    if (online) {
      await flushPendingPlaceOrders();
    } else {
      _cancelScheduledRetry(resetBackoff: false);
    }
  }

  Future<void> flushPendingPlaceOrders() async {
    await _flushPendingPlaceOrders(resetBackoff: true);
  }

  Future<void> schedulePendingPlaceOrdersFor({
    required String ownerProfileId,
  }) async {
    if (_disposed || _flushing || _knownOnline == false) return;
    final user = _ref.read(authControllerProvider).user;
    if (user == null ||
        !user.isCustomer ||
        user.id != ownerProfileId ||
        ownerProfileId.trim().isEmpty) {
      if (_scheduledOwnerProfileId == ownerProfileId) {
        _cancelScheduledRetry(resetBackoff: true);
      }
      return;
    }

    final hasPending = await _hasPendingPlaceOrders(ownerProfileId);
    if (_disposed || _flushing) return;
    final currentUser = _ref.read(authControllerProvider).user;
    if (currentUser?.id != ownerProfileId || !currentUser!.isCustomer) {
      return;
    }
    if (!hasPending) {
      if (_scheduledOwnerProfileId == ownerProfileId) {
        _cancelScheduledRetry(resetBackoff: true);
      }
      return;
    }
    _scheduleRetry(ownerProfileId);
  }

  Future<void> _flushPendingPlaceOrders({
    required bool resetBackoff,
  }) async {
    if (_disposed || _flushing) return;
    final user = _ref.read(authControllerProvider).user;
    if (user == null || user.role != 'customer') return;
    final ownerProfileId = user.id;
    _cancelScheduledRetry(resetBackoff: resetBackoff);

    final outbox = _ref.read(syncOutboxProvider);
    final pending = await outbox.pending(ownerProfileId: ownerProfileId);
    final placeOrders = pending
        .where(
          (entry) =>
              entry.entityType == 'place_order' &&
              entry.ownerProfileId == ownerProfileId,
        )
        .toList(growable: false);
    if (placeOrders.isEmpty) {
      _retryRound = 0;
      return;
    }

    _flushing = true;
    try {
      final orders = _ref.read(ordersRepositoryProvider);
      final cache = _ref.read(localCacheProvider);

      for (final entry in placeOrders) {
        if (_disposed) return;
        final currentUser = _ref.read(authControllerProvider).user;
        if (currentUser?.id != ownerProfileId ||
            currentUser?.role != 'customer') {
          return;
        }
        final payload = entry.payload;
        final requestId =
            (payload['client_request_id'] ?? entry.id).toString().trim();
        final rawItems = payload['items'];
        if (requestId.isEmpty || rawItems is! List) {
          await outbox.markFailed(
            entry.id,
            ownerProfileId: ownerProfileId,
            errorCode: 'INVALID_OUTBOX_PAYLOAD',
          );
          continue;
        }

        final items = <Map<String, Object?>>[
          for (final row in rawItems)
            if (row is Map) Map<String, Object?>.from(row)
        ];

        try {
          final order = await orders.placeOrderFromOutbox(
            clientRequestId: requestId,
            items: items,
            deliveryAddress: payload['delivery_address']?.toString() ?? '',
            customerNote: payload['customer_note']?.toString() ?? '',
            deliveryNote: payload['delivery_note']?.toString() ?? '',
            demoCustomerId: user.customerId ?? user.id,
            demoBusinessName: user.businessName ?? user.username,
          );

          final userAfterRequest = _ref.read(authControllerProvider).user;
          if (userAfterRequest?.id != ownerProfileId ||
              userAfterRequest?.role != 'customer') {
            // Keep the idempotent request pending for its owning account.
            // Never mutate another account's cart after a session switch.
            return;
          }

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

          final removedDurably = await outbox.remove(
            entry.id,
            ownerProfileId: ownerProfileId,
          );
          if (!removedDurably) {
            // The server accepted an idempotent order, but local queue removal
            // was not durable. Keep the cart/request state intact and reconcile
            // the same request again after device storage recovers.
            continue;
          }
          await _ref
              .read(cartControllerProvider.notifier)
              .acknowledgeSyncedOutboxOrder(
                requestId: requestId,
                items: syncedItems.toList(growable: false),
              );
          final pendingRequest = await cache.pendingRequest(
            ownerProfileId: ownerProfileId,
          );
          if (pendingRequest?.requestId == requestId) {
            await cache.savePendingRequest(
              ownerProfileId: ownerProfileId,
              requestId: null,
              fingerprint: null,
            );
          }
          _ref.read(outboxSyncNoticeProvider.notifier).state = OutboxSyncNotice(
            ownerProfileId: ownerProfileId,
            requestId: requestId,
            orderNumber: order.displayNumber,
          );
        } on OrdersRepositoryException catch (error) {
          if (!error.isRetryable) {
            await outbox.markFailed(
              entry.id,
              ownerProfileId: ownerProfileId,
              errorCode: error.code,
            );
          }
          // A failed entry must not block independent later orders.
          continue;
        } catch (_) {
          await outbox.markFailed(
            entry.id,
            ownerProfileId: ownerProfileId,
            errorCode: 'UNEXPECTED_RETRY_FAILURE',
          );
          continue;
        }
      }
    } finally {
      _flushing = false;
    }

    if (_disposed) return;
    final currentUser = _ref.read(authControllerProvider).user;
    if (currentUser?.id != ownerProfileId || !currentUser!.isCustomer) {
      _cancelScheduledRetry(resetBackoff: true);
      return;
    }
    if (await _hasPendingPlaceOrders(ownerProfileId)) {
      _scheduleRetry(ownerProfileId);
    } else {
      _retryRound = 0;
    }
  }

  Future<bool> _hasPendingPlaceOrders(String ownerProfileId) async {
    final pending = await _ref
        .read(syncOutboxProvider)
        .pending(ownerProfileId: ownerProfileId);
    return pending.any(
      (entry) =>
          entry.ownerProfileId == ownerProfileId &&
          entry.entityType == 'place_order',
    );
  }

  void _scheduleRetry(String ownerProfileId) {
    if (_disposed || _knownOnline == false) return;
    final existing = _retryHandle;
    if (existing?.isActive == true &&
        _scheduledOwnerProfileId == ownerProfileId) {
      return;
    }
    existing?.cancel();

    final delay = _retryDelay(_retryRound);
    _retryRound++;
    _scheduledOwnerProfileId = ownerProfileId;
    _retryHandle = _retryScheduler(delay, () async {
      _retryHandle = null;
      _scheduledOwnerProfileId = null;
      if (_disposed) return;

      final user = _ref.read(authControllerProvider).user;
      if (user?.id != ownerProfileId || !user!.isCustomer) {
        _retryRound = 0;
        return;
      }

      final online = await _connectivityCheck();
      _knownOnline = online;
      if (!online) return;
      await _flushPendingPlaceOrders(resetBackoff: false);
    });
  }

  Duration _retryDelay(int round) {
    var milliseconds = initialRetryDelay.inMilliseconds;
    for (var i = 0; i < round; i++) {
      if (milliseconds >= maximumRetryDelay.inMilliseconds) {
        return maximumRetryDelay;
      }
      milliseconds *= 2;
    }
    if (milliseconds > maximumRetryDelay.inMilliseconds) {
      return maximumRetryDelay;
    }
    return Duration(milliseconds: milliseconds);
  }

  void _cancelScheduledRetry({required bool resetBackoff}) {
    _retryHandle?.cancel();
    _retryHandle = null;
    _scheduledOwnerProfileId = null;
    if (resetBackoff) {
      _retryRound = 0;
    }
  }

  static Future<bool> _hasNetworkConnection() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((item) => item != ConnectivityResult.none);
  }

  static OutboxRetryHandle _scheduleTimer(
    Duration delay,
    OutboxRetryCallback callback,
  ) {
    return _TimerOutboxRetryHandle(delay, callback);
  }
}

class _TimerOutboxRetryHandle implements OutboxRetryHandle {
  _TimerOutboxRetryHandle(
    Duration delay,
    OutboxRetryCallback callback,
  ) {
    _timer = Timer(delay, () {
      _active = false;
      unawaited(callback());
    });
  }

  late final Timer _timer;
  bool _active = true;

  @override
  bool get isActive => _active && _timer.isActive;

  @override
  void cancel() {
    _active = false;
    _timer.cancel();
  }
}
