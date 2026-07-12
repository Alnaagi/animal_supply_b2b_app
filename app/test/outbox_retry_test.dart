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
    expect(await outbox.pending(), hasLength(1));

    await container
        .read(outboxRetryCoordinatorProvider)
        .flushPendingPlaceOrders();

    expect(await outbox.pending(), isEmpty);
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
  });
}

class _LoggedInAuthController extends AuthController {
  _LoggedInAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'profile-1',
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: 'customer-1',
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
