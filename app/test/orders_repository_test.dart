import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
                (error) => error.message,
                'message',
                contains('المخزون'),
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
      expect(placed.handlingFee, 10);
      expect(placed.total, 60);
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

      expect(
        () => repository.transitionOrderStatus(
          placed.id,
          OrderStatus.delivered,
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
