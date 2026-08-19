import 'dart:async';

import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('public order reference normalization', () {
    test('normalizes canonical, lowercase, and prefix-less forms', () {
      expect(normalizePublicOrderReference('AS-K7M4Q2P'), 'AS-K7M4Q2P');
      expect(normalizePublicOrderReference('as-k7m4q2p'), 'AS-K7M4Q2P');
      expect(normalizePublicOrderReference('K7M4Q2P'), 'AS-K7M4Q2P');
      expect(normalizePublicOrderReference(' as k7m4q2p '), 'AS-K7M4Q2P');
    });

    test('rejects invalid length and ambiguous characters', () {
      expect(normalizePublicOrderReference('AS-ABCDEFGH'), isNull);
      expect(normalizePublicOrderReference('AS-ABCD0EF'), isNull);
      expect(normalizePublicOrderReference('AS-ABCD1EF'), isNull);
      expect(normalizePublicOrderReference('AS-ABCDIEF'), isNull);
      expect(normalizePublicOrderReference(''), isNull);
    });

    test('keeps legacy sequential references canonical for lookup', () {
      expect(
        normalizePublicOrderReference('AS-20260819-000001'),
        'AS-20260819-000001',
      );
      expect(
        normalizePublicOrderReference('as-20260819-000001'),
        'AS-20260819-000001',
      );
      expect(
        normalizePublicOrderReference('20260819000001'),
        'AS-20260819-000001',
      );
    });
  });

  group('SupabaseOrdersRemoteGateway order embed', () {
    test('pins products to the active category FK, not archive FK', () {
      expect(
        SupabaseOrdersRemoteGateway.orderSelect,
        contains('categories!products_category_id_fkey'),
      );
      expect(
        SupabaseOrdersRemoteGateway.orderSelect,
        isNot(contains('products(*, categories(name))')),
      );
    });
  });

  group('SupabaseOrdersRemoteGateway transition boundary', () {
    test('uses the trusted transition function and preserves its response',
        () async {
      String? invokedFunction;
      Map<String, dynamic>? invokedBody;
      final gateway = SupabaseOrdersRemoteGateway(
        _testSupabaseClient(),
        functionInvoker: (functionName, body) async {
          invokedFunction = functionName;
          invokedBody = body;
          return const OrdersFunctionResponse(
            status: 200,
            data: {'ok': true},
          );
        },
      );

      final response = await gateway.transitionOrderStatus({
        'order_id': 'order-1',
        'status': 'confirmed',
      });

      expect(invokedFunction, 'transition-order-status');
      expect(invokedBody, {
        'order_id': 'order-1',
        'status': 'confirmed',
      });
      expect(response.status, 200);
      expect(response.data, {'ok': true});
    });

    test('maps a function rejection into a repository-readable response',
        () async {
      final gateway = SupabaseOrdersRemoteGateway(
        _testSupabaseClient(),
        functionInvoker: (_, __) async {
          throw const FunctionException(
            status: 409,
            details: {
              'ok': false,
              'error': {'code': 'INVALID_STATUS_TRANSITION'},
            },
          );
        },
      );

      final response = await gateway.transitionOrderStatus({
        'order_id': 'order-1',
        'status': 'delivered',
      });

      expect(response.status, 409);
      expect(response.data, {
        'ok': false,
        'error': {'code': 'INVALID_STATUS_TRANSITION'},
      });
    });

    test('wraps transport failures and enforces the request timeout', () async {
      final transportGateway = SupabaseOrdersRemoteGateway(
        _testSupabaseClient(),
        functionInvoker: (_, __) async {
          throw Exception('network unavailable');
        },
      );
      final timeoutGateway = SupabaseOrdersRemoteGateway(
        _testSupabaseClient(),
        functionInvoker: (_, __) => Completer<OrdersFunctionResponse>().future,
        requestTimeout: const Duration(milliseconds: 5),
      );

      await expectLater(
        transportGateway.transitionOrderStatus(const {}),
        throwsA(
          isA<OrdersTransportException>().having(
            (error) => error.cause,
            'cause',
            isA<Exception>(),
          ),
        ),
      );
      await expectLater(
        timeoutGateway.transitionOrderStatus(const {}),
        throwsA(
          isA<OrdersTransportException>().having(
            (error) => error.cause,
            'cause',
            isA<TimeoutException>(),
          ),
        ),
      );
    });
  });

  group('OrdersRepository remote boundary', () {
    test('sends only IDs and quantities and trusts returned pricing', () async {
      final gateway = _FakeGateway(
        placeResponses: [
          OrdersFunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'data': {
                'order': _remoteOrder(
                  unitPrice: 17,
                  subtotal: 34,
                  handlingFee: 3,
                  total: 37,
                ),
                'idempotent': false,
              },
            },
          ),
        ],
      );
      final repository = OrdersRepository(remote: gateway, demoSeed: const []);
      final product = _product(price: 999);

      final order = await repository.placeOrder(
        clientRequestId: 'request-1',
        customerId: 'must-not-be-sent',
        businessName: 'must-not-be-trusted',
        deliveryAddress: '  طرابلس - السراج  ',
        customerNote: '  اتصل قبل الوصول  ',
        items: [CartItem(product: product, quantity: 2)],
      );

      final body = gateway.placeBodies.single;
      expect(
        body.keys,
        unorderedEquals([
          'client_request_id',
          'delivery_address',
          'customer_note',
          'items',
        ]),
      );
      expect(body, isNot(contains('customer_id')));
      expect(body, isNot(contains('status')));
      expect(body, isNot(contains('subtotal')));
      expect(body, isNot(contains('total')));
      expect(body['delivery_address'], 'طرابلس - السراج');
      expect(body['customer_note'], 'اتصل قبل الوصول');
      expect(
        (body['items'] as List).single,
        {'product_id': 'product-1', 'quantity': 2},
      );

      expect(order.businessName, 'العميل المعتمد من الخادم');
      expect(order.items.single.unitPrice, 17);
      expect(order.subtotal, 34);
      expect(order.handlingFee, 3);
      expect(order.total, 37);
    });

    test('maps a server stock failure to an Arabic safe error', () async {
      final gateway = _FakeGateway(
        placeResponses: const [
          OrdersFunctionResponse(
            status: 422,
            data: {
              'ok': false,
              'error': {
                'code': 'INSUFFICIENT_STOCK',
                'message': 'insufficient stock',
              },
            },
          ),
        ],
      );
      final repository = OrdersRepository(remote: gateway, demoSeed: const []);

      expect(
        () => repository.placeOrder(
          clientRequestId: 'request-1',
          customerId: 'customer-1',
          items: [CartItem(product: _product(price: 20), quantity: 2)],
        ),
        throwsA(
          isA<OrdersRepositoryException>()
              .having((error) => error.code, 'code', 'INSUFFICIENT_STOCK')
              .having(
                (error) => error.isRetryable,
                'isRetryable',
                isFalse,
              )
              .having(
                (error) => error.message,
                'message',
                contains('المخزون'),
              ),
        ),
      );
    });

    test('maps maintenance mode to a clear retry-later message', () async {
      final gateway = _FakeGateway(
        placeResponses: const [
          OrdersFunctionResponse(
            status: 503,
            data: {
              'ok': false,
              'error': {
                'code': 'MAINTENANCE_MODE',
                'message': 'Orders are temporarily unavailable.',
              },
            },
          ),
        ],
      );
      final repository = OrdersRepository(remote: gateway, demoSeed: const []);

      expect(
        () => repository.placeOrder(
          clientRequestId: 'request-1',
          customerId: 'customer-1',
          items: [CartItem(product: _product(price: 20), quantity: 1)],
        ),
        throwsA(
          isA<OrdersRepositoryException>()
              .having((error) => error.code, 'code', 'MAINTENANCE_MODE')
              .having(
                (error) => error.isRetryable,
                'isRetryable',
                isTrue,
              )
              .having(
                (error) => error.message,
                'message',
                contains('صيانة'),
              ),
        ),
      );
    });

    test('classifies a transport failure as retryable', () async {
      final repository = OrdersRepository(
        remote: _TransportFailureGateway(),
        demoSeed: const [],
      );

      expect(
        () => repository.placeOrder(
          clientRequestId: 'request-1',
          customerId: 'customer-1',
          items: [CartItem(product: _product(price: 20), quantity: 1)],
        ),
        throwsA(
          isA<OrdersRepositoryException>()
              .having((error) => error.code, 'code', 'NETWORK_ERROR')
              .having(
                (error) => error.isRetryable,
                'isRetryable',
                isTrue,
              ),
        ),
      );
    });

    test('uses the transition function and returns its authoritative order',
        () async {
      final gateway = _FakeGateway(
        transitionResponses: [
          OrdersFunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'order': _remoteOrder(status: 'confirmed'),
            },
          ),
        ],
      );
      final repository = OrdersRepository(remote: gateway, demoSeed: const []);

      final order = await repository.transitionOrderStatus(
        'order-1',
        OrderStatus.confirmed,
        adminNote: 'تمت مراجعة المخزون',
      );

      expect(gateway.transitionBodies.single, {
        'order_id': 'order-1',
        'status': 'confirmed',
        'note': 'تمت مراجعة المخزون',
        'admin_note': 'تمت مراجعة المخزون',
      });
      expect(order.status, OrderStatus.confirmed);
    });

    test('sends expected_updated_at with a staff status change', () async {
      final gateway = _FakeGateway(
        transitionResponses: [
          OrdersFunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'order': _remoteOrder(status: 'confirmed'),
            },
          ),
        ],
      );
      final repository = OrdersRepository(remote: gateway, demoSeed: const []);
      final expected = DateTime.utc(2026, 8, 16, 9, 15);

      await repository.transitionOrderStatus(
        'order-1',
        OrderStatus.confirmed,
        expectedUpdatedAt: expected,
      );

      expect(
        gateway.transitionBodies.single['expected_updated_at'],
        expected.toIso8601String(),
      );
    });

    test('rejects a response that does not include an authoritative order',
        () async {
      final gateway = _FakeGateway(
        placeResponses: const [
          OrdersFunctionResponse(
            status: 200,
            data: {'ok': true, 'data': <String, dynamic>{}},
          ),
        ],
      );
      final repository = OrdersRepository(remote: gateway, demoSeed: const []);

      expect(
        () => repository.placeOrder(
          clientRequestId: 'request-1',
          customerId: 'customer-1',
          items: [CartItem(product: _product(price: 20), quantity: 1)],
        ),
        throwsA(
          isA<OrdersRepositoryException>().having(
            (error) => error.code,
            'code',
            'INVALID_SERVER_RESPONSE',
          ),
        ),
      );
    });
  });

  group('OrdersRepository demo mode', () {
    test('persists an immutable demo order and follows valid transitions',
        () async {
      final repository = OrdersRepository.demo(seed: const []);
      final product = _product(price: 25);

      final placed = await repository.placeOrder(
        clientRequestId: 'demo-request-1',
        customerId: 'customer-1',
        businessName: 'عميل تجريبي',
        deliveryAddress: 'طرابلس',
        items: [CartItem(product: product, quantity: 2)],
      );

      expect(placed.displayNumber, 'DEMO-1001');
      expect(placed.items.single, isA<OrderItem>());
      expect(placed.subtotal, 50);
      expect(placed.handlingFee, 0);
      expect(placed.total, 50);
      expect(
        await repository.ordersForCustomer('customer-1'),
        hasLength(1),
      );

      final confirmed = await repository.transitionOrderStatus(
        placed.id,
        OrderStatus.confirmed,
        adminNote: 'تم التأكيد',
      );
      expect(confirmed.status, OrderStatus.confirmed);
      expect(confirmed.statusHistory.last.fromStatus, OrderStatus.pending);
      expect(confirmed.statusHistory.last.toStatus, OrderStatus.confirmed);

      final skipped = await repository.transitionOrderStatus(
        confirmed.id,
        OrderStatus.ready,
        adminNote: 'تخطي التجهيز',
      );
      expect(skipped.status, OrderStatus.ready);
      expect(skipped.statusHistory.last.fromStatus, OrderStatus.confirmed);
      expect(skipped.statusHistory.last.toStatus, OrderStatus.ready);

      expect(
        () => repository.transitionOrderStatus(
          skipped.id,
          OrderStatus.preparing,
        ),
        throwsA(
          isA<OrdersRepositoryException>().having(
            (error) => error.code,
            'code',
            'INVALID_STATUS_TRANSITION',
          ),
        ),
      );
    });
  });
}

SupabaseClient _testSupabaseClient() {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
  );
}

class _FakeGateway implements OrdersRemoteGateway {
  _FakeGateway({
    this.placeResponses = const [],
    this.transitionResponses = const [],
  });

  final List<OrdersFunctionResponse> placeResponses;
  final List<OrdersFunctionResponse> transitionResponses;
  final List<Map<String, dynamic>> placeBodies = [];
  final List<Map<String, dynamic>> transitionBodies = [];
  int _placeIndex = 0;
  int _transitionIndex = 0;

  @override
  Future<List<Map<String, dynamic>>> allOrders() async => const [];

  @override
  Future<List<Map<String, dynamic>>> ordersForCustomer(
          String customerId) async =>
      const [];

  @override
  Future<OrdersFunctionResponse> placeOrder(Map<String, dynamic> body) async {
    placeBodies.add(body);
    return placeResponses[_placeIndex++];
  }

  @override
  Future<OrdersFunctionResponse> transitionOrderStatus(
      Map<String, dynamic> body) async {
    transitionBodies.add(body);
    return transitionResponses[_transitionIndex++];
  }

  @override
  Future<OrdersFunctionResponse> updateOrderPricing(Map<String, dynamic> body) {
    throw UnimplementedError();
  }
}

class _TransportFailureGateway implements OrdersRemoteGateway {
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
    throw const OrdersTransportException('network unavailable');
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

Product _product({required double price}) {
  return Product(
    id: 'product-1',
    nameAr: 'طعام قطط',
    sku: 'CAT-1',
    category: 'أغذية',
    animalType: 'قطط',
    brand: 'Brand',
    unitSize: '1 كجم',
    basePrice: price,
    stockQuantity: 100,
    minOrderQty: 1,
  );
}

Map<String, dynamic> _remoteOrder({
  String status = 'pending',
  double unitPrice = 20,
  double subtotal = 40,
  double handlingFee = 10,
  double total = 50,
}) {
  return {
    'id': 'order-1',
    'order_number': 'ORD-1',
    'client_request_id': 'request-1',
    'customer_id': 'customer-1',
    'customer_profile_id': 'profile-1',
    'business_name': 'العميل المعتمد من الخادم',
    'contact_person': 'أحمد',
    'contact_phone': '0910000000',
    'status': status,
    'subtotal': subtotal,
    'delivery_fee': 0,
    'handling_fee': handlingFee,
    'total': total,
    'created_at': '2026-07-12T10:00:00Z',
    'updated_at': '2026-07-12T10:00:00Z',
    'items': [
      {
        'id': 'line-1',
        'product_id': 'product-1',
        'product_name': 'طعام قطط',
        'product_sku': 'CAT-1',
        'unit_size': '1 كجم',
        'package_label': 'كرتون',
        'quantity': 2,
        'unit_price': unitPrice,
        'line_total': subtotal,
      },
    ],
  };
}
