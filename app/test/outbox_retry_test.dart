import 'package:animal_supply_b2b/src/data/local/local_cache.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/data/sync/outbox_retry_coordinator.dart';
import 'package:animal_supply_b2b/src/data/sync/sync_outbox.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('outbox flush retries place-order with product ids only', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    final outbox = SyncOutbox(prefs: prefs);
    final gateway = _RetryGateway();
    final repository = OrdersRepository(remote: gateway, demoSeed: const []);
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(cache),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith((ref) => _LoggedInAuthController()),
        ordersRepositoryProvider.overrideWithValue(repository),
        // Avoid auto-flush from cart provider activation during setup.
        outboxRetryCoordinatorProvider.overrideWith((ref) {
          return OutboxRetryCoordinator(ref);
        }),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(cartControllerProvider.notifier);
    await controller.hydrate();
    controller.addQuantity(_product(), 2);

    await expectLater(
      controller.submit(deliveryAddress: 'طرابلس'),
      throwsA(isA<OrdersRepositoryException>()),
    );
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      hasLength(1),
    );

    await container
        .read(outboxRetryCoordinatorProvider)
        .flushPendingPlaceOrders();

    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );
    expect(container.read(cartControllerProvider), isEmpty);
    expect(gateway.bodies, hasLength(2));
    final retryBody = gateway.bodies.last;
    expect(retryBody['client_request_id'], isNotEmpty);
    expect(retryBody['items'], [
      {'product_id': 'product-1', 'quantity': 2},
    ]);
    expect(retryBody.containsKey('total'), isFalse);
    expect(retryBody.containsKey('unit_price'), isFalse);
    expect(retryBody.containsKey('customer_id'), isFalse);
    expect(
      gateway.bodies.first['client_request_id'],
      retryBody['client_request_id'],
    );
    final notice = container.read(outboxSyncNoticeProvider);
    expect(notice?.ownerProfileId, 'profile-1');
    expect(notice?.requestId, retryBody['client_request_id']);
    expect(notice?.orderNumber, 'ORD-RETRY-1');
  });

  test('an account never flushes another account outbox entries', () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    await outbox.enqueue(
      _queuedEntry(
        id: 'request-a',
        ownerProfileId: 'profile-a',
        productId: 'product-a',
      ),
    );
    final gateway = _RecordingGateway();
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(LocalCache(prefs: prefs)),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith(
          (ref) => _LoggedInAuthController(
            profileId: 'profile-b',
            customerId: 'customer-b',
          ),
        ),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository(remote: gateway, demoSeed: const []),
        ),
        outboxRetryCoordinatorProvider.overrideWith(
          (ref) => OutboxRetryCoordinator(ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(outboxRetryCoordinatorProvider)
        .flushPendingPlaceOrders();

    expect(gateway.bodies, isEmpty);
    expect(
      await outbox.pending(ownerProfileId: 'profile-b'),
      isEmpty,
    );
    expect(
      await outbox.pending(ownerProfileId: 'profile-a'),
      hasLength(1),
    );
  });

  test('permanent poison entry does not block a later valid order', () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    await outbox.enqueue(
      _queuedEntry(
        id: 'bad-request',
        ownerProfileId: 'profile-1',
        productId: 'bad-product',
      ),
    );
    await outbox.enqueue(
      _queuedEntry(
        id: 'good-request',
        ownerProfileId: 'profile-1',
        productId: 'product-1',
      ),
    );
    final gateway = _PoisonThenSuccessGateway();
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(LocalCache(prefs: prefs)),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith(
          (ref) => _LoggedInAuthController(),
        ),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository(remote: gateway, demoSeed: const []),
        ),
        outboxRetryCoordinatorProvider.overrideWith(
          (ref) => OutboxRetryCoordinator(ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(outboxRetryCoordinatorProvider)
        .flushPendingPlaceOrders();

    expect(
      gateway.bodies.map((body) => body['client_request_id']),
      ['bad-request', 'good-request'],
    );
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );
    final failed = await outbox.failed(ownerProfileId: 'profile-1');
    expect(failed, hasLength(1));
    expect(failed.single.id, 'bad-request');
    expect(failed.single.errorCode, 'INSUFFICIENT_STOCK');
  });

  test('retryable failure stays pending without blocking a later order',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    await outbox.enqueue(
      _queuedEntry(
        id: 'retry-later',
        ownerProfileId: 'profile-1',
        productId: 'product-retry',
      ),
    );
    await outbox.enqueue(
      _queuedEntry(
        id: 'send-now',
        ownerProfileId: 'profile-1',
        productId: 'product-1',
      ),
    );
    final gateway = _RetryableThenSuccessGateway();
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(LocalCache(prefs: prefs)),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith(
          (ref) => _LoggedInAuthController(),
        ),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository(remote: gateway, demoSeed: const []),
        ),
        outboxRetryCoordinatorProvider.overrideWith(
          (ref) => OutboxRetryCoordinator(ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(outboxRetryCoordinatorProvider)
        .flushPendingPlaceOrders();

    expect(
      gateway.bodies.map((body) => body['client_request_id']),
      ['retry-later', 'send-now'],
    );
    final pending = await outbox.pending(ownerProfileId: 'profile-1');
    expect(pending, hasLength(1));
    expect(pending.single.id, 'retry-later');
    expect(
      await outbox.failed(ownerProfileId: 'profile-1'),
      isEmpty,
    );
  });

  test('online retry uses capped exponential backoff until success', () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    await outbox.enqueue(
      _queuedEntry(
        id: 'retry-with-backoff',
        ownerProfileId: 'profile-1',
        productId: 'product-1',
      ),
    );
    final gateway = _RetryNTimesGateway(failuresBeforeSuccess: 3);
    final scheduler = _ManualRetryScheduler();
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(LocalCache(prefs: prefs)),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith(
          (ref) => _LoggedInAuthController(),
        ),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository(remote: gateway, demoSeed: const []),
        ),
        outboxRetryCoordinatorProvider.overrideWith(
          (ref) => OutboxRetryCoordinator(
            ref,
            retryScheduler: scheduler.schedule,
            connectivityCheck: () async => true,
            initialRetryDelay: const Duration(seconds: 1),
            maximumRetryDelay: const Duration(seconds: 2),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final coordinator = container.read(outboxRetryCoordinatorProvider);
    await coordinator.flushPendingPlaceOrders();
    expect(gateway.bodies, hasLength(1));
    expect(scheduler.delays, [const Duration(seconds: 1)]);

    expect(await scheduler.fireNext(), isTrue);
    expect(gateway.bodies, hasLength(2));
    expect(
      scheduler.delays,
      [const Duration(seconds: 1), const Duration(seconds: 2)],
    );

    expect(await scheduler.fireNext(), isTrue);
    expect(gateway.bodies, hasLength(3));
    expect(
      scheduler.delays,
      [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 2),
      ],
    );

    expect(await scheduler.fireNext(), isTrue);
    expect(gateway.bodies, hasLength(4));
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );
    expect(scheduler.hasActiveHandle, isFalse);
  });

  test('account switch cancels scheduled retry and callback rechecks owner',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    await outbox.enqueue(
      _queuedEntry(
        id: 'owned-by-a',
        ownerProfileId: 'profile-a',
        productId: 'product-a',
      ),
    );
    final gateway = _AlwaysRetryGateway();
    final scheduler = _ManualRetryScheduler();
    final auth = _LoggedInAuthController(
      profileId: 'profile-a',
      customerId: 'customer-a',
    );
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(LocalCache(prefs: prefs)),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith((ref) => auth),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository(remote: gateway, demoSeed: const []),
        ),
        outboxRetryCoordinatorProvider.overrideWith(
          (ref) => OutboxRetryCoordinator(
            ref,
            retryScheduler: scheduler.schedule,
            connectivityCheck: () async => true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final coordinator = container.read(outboxRetryCoordinatorProvider);
    await coordinator.flushPendingPlaceOrders();
    expect(gateway.bodies, hasLength(1));
    expect(scheduler.hasActiveHandle, isTrue);

    auth.switchTo(profileId: 'profile-b', customerId: 'customer-b');
    coordinator.handleAuthOwnerChanged();

    expect(scheduler.hasActiveHandle, isFalse);
    expect(await scheduler.fireNext(), isFalse);
    expect(gateway.bodies, hasLength(1));
    expect(
      await outbox.pending(ownerProfileId: 'profile-a'),
      hasLength(1),
    );
  });

  test('new pending entry can schedule timed retry without a reconnect event',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    await outbox.enqueue(
      _queuedEntry(
        id: 'newly-queued',
        ownerProfileId: 'profile-1',
        productId: 'product-1',
      ),
    );
    final gateway = _RecordingGateway();
    final scheduler = _ManualRetryScheduler();
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(LocalCache(prefs: prefs)),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith(
          (ref) => _LoggedInAuthController(),
        ),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository(remote: gateway, demoSeed: const []),
        ),
        outboxRetryCoordinatorProvider.overrideWith(
          (ref) => OutboxRetryCoordinator(
            ref,
            retryScheduler: scheduler.schedule,
            connectivityCheck: () async => true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final coordinator = container.read(outboxRetryCoordinatorProvider);
    await coordinator.schedulePendingPlaceOrdersFor(
      ownerProfileId: 'profile-1',
    );

    expect(gateway.bodies, isEmpty);
    expect(scheduler.hasActiveHandle, isTrue);
    expect(await scheduler.fireNext(), isTrue);
    expect(gateway.bodies, hasLength(1));
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );
  });

  test('legacy unowned outbox entries are quarantined and never retried',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sync_outbox.entries.v1',
      '''
      [
        {
          "id": "legacy-request",
          "entityType": "place_order",
          "status": "pending",
          "payload": {
            "client_request_id": "legacy-request",
            "items": [{"product_id": "product-1", "quantity": 1}]
          }
        }
      ]
      ''',
    );
    final outbox = SyncOutbox(prefs: prefs);

    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );
    expect(prefs.getString('sync_outbox.entries.v1'), isNull);
    expect(prefs.getString('sync_outbox.quarantine.v1'), isNotNull);
  });
}

class _LoggedInAuthController extends AuthController {
  _LoggedInAuthController({
    String profileId = 'profile-1',
    String customerId = 'customer-1',
  }) {
    state = AuthState(
      user: AppUser(
        id: profileId,
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: customerId,
      ),
    );
  }

  void switchTo({
    required String profileId,
    required String customerId,
  }) {
    state = AuthState(
      user: AppUser(
        id: profileId,
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: customerId,
      ),
    );
  }
}

class _RetryGateway implements OrdersRemoteGateway {
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<List<Map<String, dynamic>>> allOrders() async => const [];

  @override
  Future<List<Map<String, dynamic>>> ordersForCustomer(
          String customerId) async =>
      const [];

  @override
  Future<OrdersFunctionResponse> placeOrder(Map<String, dynamic> body) async {
    bodies.add(Map<String, dynamic>.from(body));
    if (bodies.length == 1) {
      return const OrdersFunctionResponse(
        status: 503,
        data: {
          'ok': false,
          'error': {
            'code': 'SERVICE_UNAVAILABLE',
            'message': 'temporarily unavailable',
          },
        },
      );
    }
    return OrdersFunctionResponse(
      status: 200,
      data: {
        'ok': true,
        'data': {
          'order': {
            'id': 'order-1',
            'order_number': 'ORD-RETRY-1',
            'client_request_id': body['client_request_id'],
            'customer_id': 'customer-1',
            'business_name': 'متجر الاختبار',
            'status': 'pending',
            'subtotal': 40,
            'delivery_fee': 0,
            'handling_fee': 10,
            'total': 50,
            'delivery_address': 'طرابلس',
            'created_at': '2026-07-12T12:00:00Z',
            'items': [
              {
                'id': 'line-1',
                'product_id': 'product-1',
                'product_name': 'طعام قطط',
                'product_sku': 'CAT-1',
                'unit_size': '1 كجم',
                'package_label': 'كرتون',
                'quantity': 2,
                'unit_price': 20,
                'line_total': 40,
              },
            ],
          },
        },
      },
    );
  }

  @override
  Future<OrdersFunctionResponse> transitionOrderStatus(
      Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  @override
  Future<OrdersFunctionResponse> updateOrderPricing(Map<String, dynamic> body) {
    throw UnimplementedError();
  }
}

class _RecordingGateway implements OrdersRemoteGateway {
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<List<Map<String, dynamic>>> allOrders() async => const [];

  @override
  Future<List<Map<String, dynamic>>> ordersForCustomer(
    String customerId,
  ) async =>
      const [];

  @override
  Future<OrdersFunctionResponse> placeOrder(
    Map<String, dynamic> body,
  ) async {
    bodies.add(Map<String, dynamic>.from(body));
    return _successResponse(body);
  }

  @override
  Future<OrdersFunctionResponse> transitionOrderStatus(
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<OrdersFunctionResponse> updateOrderPricing(
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
  }
}

class _PoisonThenSuccessGateway extends _RecordingGateway {
  @override
  Future<OrdersFunctionResponse> placeOrder(
    Map<String, dynamic> body,
  ) async {
    bodies.add(Map<String, dynamic>.from(body));
    if (body['client_request_id'] == 'bad-request') {
      return const OrdersFunctionResponse(
        status: 422,
        data: {
          'ok': false,
          'error': {
            'code': 'INSUFFICIENT_STOCK',
            'message': 'insufficient stock',
          },
        },
      );
    }
    return _successResponse(body);
  }
}

class _RetryableThenSuccessGateway extends _RecordingGateway {
  @override
  Future<OrdersFunctionResponse> placeOrder(
    Map<String, dynamic> body,
  ) async {
    bodies.add(Map<String, dynamic>.from(body));
    if (body['client_request_id'] == 'retry-later') {
      return const OrdersFunctionResponse(
        status: 503,
        data: {
          'ok': false,
          'error': {
            'code': 'SERVICE_UNAVAILABLE',
            'message': 'temporarily unavailable',
          },
        },
      );
    }
    return _successResponse(body);
  }
}

class _RetryNTimesGateway extends _RecordingGateway {
  _RetryNTimesGateway({required this.failuresBeforeSuccess});

  final int failuresBeforeSuccess;

  @override
  Future<OrdersFunctionResponse> placeOrder(
    Map<String, dynamic> body,
  ) async {
    bodies.add(Map<String, dynamic>.from(body));
    if (bodies.length <= failuresBeforeSuccess) {
      return const OrdersFunctionResponse(
        status: 503,
        data: {
          'ok': false,
          'error': {
            'code': 'SERVICE_UNAVAILABLE',
            'message': 'temporarily unavailable',
          },
        },
      );
    }
    return _successResponse(body);
  }
}

class _AlwaysRetryGateway extends _RetryNTimesGateway {
  _AlwaysRetryGateway() : super(failuresBeforeSuccess: 1 << 20);
}

class _ManualRetryScheduler {
  final List<Duration> delays = [];
  final List<_ManualRetryHandle> _handles = [];

  bool get hasActiveHandle => _handles.any((handle) => handle.isActive);

  OutboxRetryHandle schedule(
    Duration delay,
    OutboxRetryCallback callback,
  ) {
    delays.add(delay);
    final handle = _ManualRetryHandle(callback);
    _handles.add(handle);
    return handle;
  }

  Future<bool> fireNext() async {
    for (final handle in _handles) {
      if (handle.isActive) {
        await handle.fire();
        return true;
      }
    }
    return false;
  }
}

class _ManualRetryHandle implements OutboxRetryHandle {
  _ManualRetryHandle(this._callback);

  final OutboxRetryCallback _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    _active = false;
  }

  Future<void> fire() async {
    if (!_active) return;
    _active = false;
    await _callback();
  }
}

OrdersFunctionResponse _successResponse(Map<String, dynamic> body) {
  final items = body['items'] as List? ?? const [];
  final firstItem =
      items.isEmpty ? const <String, dynamic>{} : items.first as Map;
  final productId = firstItem['product_id']?.toString() ?? 'product-1';
  final quantity = (firstItem['quantity'] as num?)?.toInt() ?? 1;
  return OrdersFunctionResponse(
    status: 200,
    data: {
      'ok': true,
      'data': {
        'order': {
          'id': 'order-${body['client_request_id']}',
          'order_number': 'ORD-${body['client_request_id']}',
          'client_request_id': body['client_request_id'],
          'customer_id': 'customer-1',
          'business_name': 'متجر الاختبار',
          'status': 'pending',
          'subtotal': 20 * quantity,
          'delivery_fee': 0,
          'handling_fee': 0,
          'total': 20 * quantity,
          'delivery_address': body['delivery_address'] ?? '',
          'created_at': '2026-07-21T12:00:00Z',
          'items': [
            {
              'id': 'line-${body['client_request_id']}',
              'product_id': productId,
              'product_name': 'منتج اختبار',
              'product_sku': 'TEST-1',
              'unit_size': '1 كجم',
              'package_label': 'كرتون',
              'quantity': quantity,
              'unit_price': 20,
              'line_total': 20 * quantity,
            },
          ],
        },
      },
    },
  );
}

SyncOutboxEntry _queuedEntry({
  required String id,
  required String ownerProfileId,
  required String productId,
}) {
  return SyncOutboxEntry(
    id: id,
    ownerProfileId: ownerProfileId,
    entityType: 'place_order',
    payload: {
      'client_request_id': id,
      'delivery_address': 'طرابلس',
      'items': [
        {'product_id': productId, 'quantity': 1},
      ],
    },
  );
}

Product _product() {
  return const Product(
    id: 'product-1',
    nameAr: 'طعام قطط',
    sku: 'CAT-1',
    category: 'أغذية',
    animalType: 'قطط',
    brand: 'Brand',
    unitSize: '1 كجم',
    basePrice: 20,
    stockQuantity: 100,
    minOrderQty: 1,
  );
}
