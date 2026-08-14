import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Order model', () {
    test('uses immutable line snapshots and authoritative totals', () {
      final order = Order.fromMap({
        'id': 'order-1',
        'order_number': 'ORD-2026-0001',
        'client_request_id': 'request-1',
        'customer_id': 'customer-1',
        'customer_profile_id': 'profile-1',
        'business_name': 'متجر طرابلس للحيوانات',
        'contact_person': 'محمد',
        'contact_phone': '0910000000',
        'status': 'confirmed',
        'subtotal': 85,
        'delivery_fee': 5,
        'handling_fee': 10,
        'total': 100,
        'delivery_address': 'طرابلس - حي الأندلس',
        'created_at': '2026-07-12T10:00:00Z',
        'updated_at': '2026-07-12T10:05:00Z',
        'items': [
          {
            'id': 'line-1',
            'product_id': 'product-1',
            'product_name': 'طعام قطط وقت الطلب',
            'product_sku': 'CAT-001',
            'unit_size': '10 كجم',
            'package_label': 'كيس 10 كجم',
            'quantity': 2,
            'unit_price': 42.5,
            'line_total': 85,
            'products': {
              'id': 'product-1',
              'name': 'اسم المنتج الحالي',
              'sku': 'CAT-001-NEW',
              'brand': 'Brand',
              'animal_type': 'قطط',
              'unit_size': '12 كجم',
              'package_size': 'كيس 12 كجم',
              'base_price': 999,
              'stock_quantity': 20,
              'min_order_quantity': 1,
              'active': true,
              'categories': {'name': 'أغذية'},
            },
          },
        ],
        'status_history': [
          {
            'id': 'history-1',
            'from_status': 'pending',
            'to_status': 'confirmed',
            'note': 'تمت المراجعة',
            'changed_by': 'admin-1',
            'changed_at': '2026-07-12T10:05:00Z',
          },
        ],
      });

      expect(order.displayNumber, 'ORD-2026-0001');
      expect(order.businessName, 'متجر طرابلس للحيوانات');
      expect(order.subtotal, 85);
      expect(order.deliveryFee, 5);
      expect(order.handlingFee, 10);
      expect(order.total, 100);
      expect(order.status, OrderStatus.confirmed);
      expect(order.items, hasLength(1));

      final line = order.items.single;
      expect(line.productName, 'طعام قطط وقت الطلب');
      expect(line.productSku, 'CAT-001');
      expect(line.packageLabel, 'كيس 10 كجم');
      expect(line.unitPrice, 42.5);
      expect(line.lineTotal, 85);
      expect(line.product.name, 'اسم المنتج الحالي');
      expect(line.product.price, 999);
      expect(line.canReorder, isTrue);

      expect(order.statusHistory, hasLength(1));
      expect(order.statusHistory.single.fromStatus, OrderStatus.pending);
      expect(order.statusHistory.single.toStatus, OrderStatus.confirmed);
    });

    test('parses database snapshot aliases and customer relationship', () {
      final order = Order.fromSupabase({
        'id': 'order-2',
        'customer_id': 'customer-2',
        'status': 'pending',
        'handling_fee': 10,
        'created_at': '2026-07-12T11:00:00Z',
        'business_name_snapshot': 'شركة النخبة وقت الطلب',
        'contact_person_snapshot': 'سالم وقت الطلب',
        'contact_phone_snapshot': '0921111111',
        'business_customers': {
          'profile_id': 'profile-2',
          'business_name': 'شركة النخبة',
          'contact_person': 'سالم',
          'phone': '0920000000',
          'city': 'طرابلس',
          'area': 'السراج',
          'address': 'الطريق الرئيسي',
        },
        'order_items': [
          {
            'id': 'line-2',
            'product_id': 'deleted-product',
            'product_name_snapshot': 'منتج تاريخي',
            'product_sku_snapshot': 'OLD-1',
            'unit_size_snapshot': '5 كجم',
            'package_label_snapshot': 'كرتون 4 أكياس',
            'quantity': 3,
            'unit_price': 20,
            'line_total': 60,
          },
        ],
      });

      expect(order.businessName, 'شركة النخبة وقت الطلب');
      expect(order.contactPerson, 'سالم وقت الطلب');
      expect(order.contactPhone, '0921111111');
      expect(order.customerProfileId, 'profile-2');
      expect(order.deliveryAddress, 'طرابلس - السراج - الطريق الرئيسي');
      expect(order.items.single.productName, 'منتج تاريخي');
      expect(order.items.single.productSku, 'OLD-1');
      expect(order.items.single.canReorder, isFalse);
      expect(order.subtotal, 60);
      expect(order.total, 70);
    });
  });

  group('Cart pricing', () {
    test('uses one shared estimate for cart and checkout', () {
      final first = _product(id: 'p1', price: 25);
      final second = _product(id: 'p2', price: 40);
      final summary = CartPricingSummary.estimate([
        CartItem(product: first, quantity: 2),
        CartItem(product: second, quantity: 1),
      ], handlingFee: 10);

      expect(summary.subtotal, 90);
      expect(summary.handlingFee, 10);
      expect(summary.deliveryFee, 0);
      expect(summary.total, 100);
    });

    test('has no handling estimate for an empty cart', () {
      final summary = CartPricingSummary.estimate(const []);
      expect(summary.total, 0);
      expect(summary.handlingFee, 0);
    });

    test('reports the remaining minimum-order amount', () {
      const summary = CartPricingSummary(
        subtotal: 70,
        handlingFee: 5,
        deliveryFee: 5,
      );
      expect(summary.meetsMinimum(100), isFalse);
      expect(summary.amountNeededForMinimum(100), 30);
      expect(summary.meetsMinimum(70), isTrue);
      expect(summary.amountNeededForMinimum(70), 0);
    });
  });

  test('allowed status transitions match the server workflow', () {
    expect(
      allowedOrderTransitions(OrderStatus.pending),
      [OrderStatus.confirmed, OrderStatus.cancelled],
    );
    expect(
      allowedOrderTransitions(OrderStatus.ready),
      [OrderStatus.delivered, OrderStatus.cancelled],
    );
    expect(allowedOrderTransitions(OrderStatus.delivered), isEmpty);
    expect(allowedOrderTransitions(OrderStatus.cancelled), isEmpty);
  });
}

Product _product({
  required String id,
  required double price,
}) {
  return Product(
    id: id,
    nameAr: 'منتج $id',
    sku: 'SKU-$id',
    category: 'أغذية',
    animalType: 'قطط',
    brand: 'Brand',
    unitSize: '1 كجم',
    basePrice: price,
    stockQuantity: 100,
    minOrderQty: 1,
  );
}
