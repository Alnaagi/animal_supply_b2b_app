import 'package:animal_supply_b2b/src/data/local/local_cache.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
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

  test('failed submit keeps cart and retry reuses the idempotency key',
      () async {
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
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(cartControllerProvider.notifier);
    await controller.hydrate();
    controller.addQuantity(_product(), 2);

    await expectLater(
      controller.submit(
        note: 'اتصل قبل الوصول',
        deliveryAddress: 'طرابلس',
      ),
      throwsA(isA<OrdersRepositoryException>()),
    );
    expect(container.read(cartControllerProvider), hasLength(1));
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      hasLength(1),
    );
    expect(await outbox.pending(ownerProfileId: 'profile-1'),
        everyElement(predicate((entry) {
      final item = entry as SyncOutboxEntry;
      return item.entityType == 'place_order' &&
          item.ownerProfileId == 'profile-1' &&
          item.payload['pending_locally'] == true;
    })));

    final order = await controller.submit(
      note: 'اتصل قبل الوصول',
      deliveryAddress: 'طرابلس',
    );

    expect(order.displayNumber, 'ORD-RETRY-1');
    expect(container.read(cartControllerProvider), isEmpty);
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );
    expect(gateway.bodies, hasLength(2));
    expect(
      gateway.bodies.first['client_request_id'],
      gateway.bodies.last['client_request_id'],
    );
  });

  test('cart and pending request survive local cache restore', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    final outbox = SyncOutbox(prefs: prefs);
    final gateway = _RetryGateway();
    final repository = OrdersRepository(remote: gateway, demoSeed: const []);

    final first = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(cache),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith((ref) => _LoggedInAuthController()),
        ordersRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final firstController = first.read(cartControllerProvider.notifier);
    await firstController.hydrate();
    firstController.addQuantity(_product(), 2);
    await expectLater(
      firstController.submit(deliveryAddress: 'طرابلس'),
      throwsA(isA<OrdersRepositoryException>()),
    );
    final pendingBefore = await cache.pendingRequest(
      ownerProfileId: 'profile-1',
    );
    expect(pendingBefore, isNotNull);
    first.dispose();

    final restoredCache = LocalCache(prefs: prefs);
    final restoredOutbox = SyncOutbox(prefs: prefs);
    final second = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(restoredCache),
        syncOutboxProvider.overrideWithValue(restoredOutbox),
        authControllerProvider.overrideWith((ref) => _LoggedInAuthController()),
        ordersRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(second.dispose);

    final secondController = second.read(cartControllerProvider.notifier);
    await secondController.hydrate();
    expect(second.read(cartControllerProvider), hasLength(1));
    expect(
      await restoredOutbox.pending(ownerProfileId: 'profile-1'),
      hasLength(1),
    );

    final order = await secondController.submit(deliveryAddress: 'طرابلس');
    expect(order.displayNumber, 'ORD-RETRY-1');
    expect(
      gateway.bodies.first['client_request_id'],
      gateway.bodies.last['client_request_id'],
    );
  });

  test('catalog cache restores products after save', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    await cache.saveProducts([_product()]);

    final restored = LocalCache(prefs: prefs);
    final products = await restored.cachedProducts();
    expect(products, hasLength(1));
    expect(products.single.id, 'product-1');
    expect(products.single.basePrice, 20);
  });

  test('corrupt owner catalog cache is quarantined without breaking fallback',
      () async {
    final prefs = await SharedPreferences.getInstance();
    const ownerKey = 'local_cache.products.v2.cHJvZmlsZS0x';
    const quarantineKey = 'local_cache.products.quarantine.v1.cHJvZmlsZS0x';
    await prefs.setString(
      ownerKey,
      '{"not":"a product list"}',
    );

    final cache = LocalCache(prefs: prefs);
    expect(
      await cache.cachedProducts(ownerProfileId: 'profile-1'),
      isEmpty,
    );
    expect(prefs.getString(ownerKey), isNull);
    expect(
        prefs.getString(quarantineKey), contains('invalid_catalog_snapshot'));
  });

  test('untracked stock permits bulk ordering while the cart enforces MOQ',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(LocalCache(prefs: prefs)),
        syncOutboxProvider.overrideWithValue(SyncOutbox(prefs: prefs)),
        authControllerProvider.overrideWith((ref) => _LoggedInAuthController()),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository.demo(seed: const []),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(cartControllerProvider.notifier);
    await controller.hydrate();
    const untracked = Product(
      id: 'untracked-product',
      nameAr: 'منتج جملة غير متتبع',
      sku: 'UNTRACKED-1',
      category: 'أغذية',
      animalType: 'قطط',
      brand: 'شركة',
      unitSize: 'صندوق',
      basePrice: 120,
      stockQuantity: 0,
      stockTrackingEnabled: false,
      minOrderQty: 6,
    );

    controller.addQuantity(untracked, 1);
    expect(container.read(cartControllerProvider).single.quantity, 6);

    controller.updateQty(untracked.id, 24);
    expect(container.read(cartControllerProvider).single.quantity, 24);

    controller.updateQty(untracked.id, 2);
    expect(container.read(cartControllerProvider).single.quantity, 6);

    const trackedBelowMinimum = Product(
      id: 'tracked-below-minimum',
      nameAr: 'منتج غير متوفر للحد الأدنى',
      sku: 'TRACKED-1',
      category: 'أغذية',
      animalType: 'قطط',
      brand: 'شركة',
      unitSize: 'صندوق',
      basePrice: 80,
      stockQuantity: 4,
      minOrderQty: 5,
    );
    controller.add(trackedBelowMinimum);

    expect(
      container.read(cartControllerProvider).map((item) => item.product.id),
      ['untracked-product'],
    );
  });

  test('cart and pending state are isolated across account switches', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    final outbox = SyncOutbox(prefs: prefs);
    final auth = _SwitchableAuthController(
      user: _customerUser(
        profileId: 'profile-a',
        customerId: 'customer-a',
        username: 'customer-a',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(cache),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith((ref) => auth),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository.demo(seed: const []),
        ),
      ],
    );
    addTearDown(container.dispose);

    final firstController = container.read(cartControllerProvider.notifier);
    await firstController.hydrate();
    firstController.addQuantity(_product(), 2);
    await cache.saveCart(
      ownerProfileId: 'profile-a',
      items: container.read(cartControllerProvider),
    );
    await cache.savePendingRequest(
      ownerProfileId: 'profile-a',
      requestId: 'request-a',
      fingerprint: 'fingerprint-a',
    );
    await outbox.enqueue(
      const SyncOutboxEntry(
        id: 'request-a',
        ownerProfileId: 'profile-a',
        entityType: 'place_order',
        payload: {
          'client_request_id': 'request-a',
          'items': [
            {'product_id': 'product-1', 'quantity': 2},
          ],
        },
      ),
    );

    auth.use(
      _customerUser(
        profileId: 'profile-b',
        customerId: 'customer-b',
        username: 'customer-b',
      ),
    );
    final secondController = container.read(cartControllerProvider.notifier);
    await secondController.hydrate();

    expect(container.read(cartControllerProvider), isEmpty);
    expect(
      await cache.pendingRequest(ownerProfileId: 'profile-b'),
      isNull,
    );
    expect(
      await outbox.pending(ownerProfileId: 'profile-b'),
      isEmpty,
    );
    expect(
      await outbox.pending(ownerProfileId: 'profile-a'),
      hasLength(1),
    );

    auth.use(
      _customerUser(
        profileId: 'profile-a',
        customerId: 'customer-a',
        username: 'customer-a',
      ),
    );
    final restoredController = container.read(cartControllerProvider.notifier);
    await restoredController.hydrate();
    expect(container.read(cartControllerProvider), hasLength(1));
    expect(container.read(cartControllerProvider).single.quantity, 2);
  });

  test('legacy unowned cart and pending request are quarantined', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'local_cache.cart.v1',
      '[{"quantity":2,"product":{"id":"legacy-product"}}]',
    );
    await prefs.setString(
      'local_cache.pending_request.v1',
      '{"request_id":"legacy-request","fingerprint":"legacy"}',
    );

    final cache = LocalCache(prefs: prefs);

    expect(
      await cache.cachedCart(ownerProfileId: 'profile-1'),
      isEmpty,
    );
    expect(
      await cache.pendingRequest(ownerProfileId: 'profile-1'),
      isNull,
    );
    expect(prefs.getString('local_cache.cart.v1'), isNull);
    expect(prefs.getString('local_cache.pending_request.v1'), isNull);
    expect(
      prefs.getString('local_cache.quarantine.legacy_unowned.v1'),
      isNotNull,
    );
  });

  test('permanent order rejection is not queued for automatic retry', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    final outbox = SyncOutbox(prefs: prefs);
    final repository = OrdersRepository(
      remote: _PermanentFailureGateway(),
      demoSeed: const [],
    );
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(cache),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith((ref) => _LoggedInAuthController()),
        ordersRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(cartControllerProvider.notifier);
    await controller.hydrate();
    controller.addQuantity(_product(), 2);

    await expectLater(
      controller.submit(deliveryAddress: 'طرابلس'),
      throwsA(
        isA<OrdersRepositoryException>()
            .having((error) => error.code, 'code', 'INSUFFICIENT_STOCK')
            .having((error) => error.isRetryable, 'isRetryable', isFalse),
      ),
    );

    expect(container.read(cartControllerProvider), hasLength(1));
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );
  });

  test('storage failure never claims a retryable order is saved offline',
      () async {
    final cache = LocalCache(storeLoader: () async => null);
    final outbox = SyncOutbox(storeLoader: () async => null);
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(cache),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith((ref) => _LoggedInAuthController()),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository(remote: _RetryGateway(), demoSeed: const []),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(cartControllerProvider.notifier);
    await controller.hydrate();
    controller.addQuantity(_product(), 2);

    await expectLater(
      controller.submit(deliveryAddress: 'طرابلس'),
      throwsA(
        isA<OrdersRepositoryException>()
            .having(
              (error) => error.code,
              'code',
              'LOCAL_STORAGE_UNAVAILABLE',
            )
            .having(
              (error) => error.message,
              'message',
              contains('الجلسة الحالية فقط'),
            ),
      ),
    );

    expect(container.read(cartControllerProvider), hasLength(1));
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      hasLength(1),
      reason: 'The current process may still retry while it remains open.',
    );
  });

  test('editing the cart cancels the previously queued request', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    final outbox = SyncOutbox(prefs: prefs);
    final gateway = _RetryGateway();
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(cache),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith((ref) => _LoggedInAuthController()),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository(remote: gateway, demoSeed: const []),
        ),
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
    final firstRequestId =
        gateway.bodies.single['client_request_id']?.toString();
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      hasLength(1),
    );

    controller.updateQty('product-1', 3);
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );

    await controller.submit(deliveryAddress: 'طرابلس');
    final secondRequestId =
        gateway.bodies.last['client_request_id']?.toString();

    expect(firstRequestId, isNotEmpty);
    expect(secondRequestId, isNotEmpty);
    expect(secondRequestId, isNot(firstRequestId));
    expect(
      await outbox.pending(ownerProfileId: 'profile-1'),
      isEmpty,
    );
  });
}

class _LoggedInAuthController extends AuthController {
  _LoggedInAuthController() {
    state = AuthState(
      user: _customerUser(
        profileId: 'profile-1',
        customerId: 'customer-1',
        username: 'customer',
      ),
    );
  }
}

class _SwitchableAuthController extends AuthController {
  _SwitchableAuthController({required AppUser user}) {
    state = AuthState(user: user);
  }

  void use(AppUser user) {
    state = AuthState(user: user);
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
            'customer_note': 'اتصل قبل الوصول',
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
}

class _PermanentFailureGateway implements OrdersRemoteGateway {
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

  @override
  Future<OrdersFunctionResponse> transitionOrderStatus(
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
  }
}

AppUser _customerUser({
  required String profileId,
  required String customerId,
  required String username,
}) {
  return AppUser(
    id: profileId,
    username: username,
    role: 'customer',
    businessName: 'متجر الاختبار',
    customerId: customerId,
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
