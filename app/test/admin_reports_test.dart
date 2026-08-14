import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds delivered-sales rankings and keeps balances explicitly manual',
      () {
    final product = _product(
      id: 'feed',
      name: 'علف',
      available: 5,
    );
    final report = buildAdminReportData(
      products: [
        product,
        _product(id: 'empty', name: 'دواء', available: 0),
      ],
      customers: const [
        BusinessCustomer(
          id: 'customer-1',
          businessName: 'متجر طرابلس',
          username: 'tripoli',
          creditLimit: 1000,
          outstandingBalance: 125,
        ),
      ],
      orders: [
        _order(
          id: 'delivered',
          status: OrderStatus.delivered,
          product: product,
          quantity: 3,
          unitPrice: 20,
          createdAt: DateTime(2026, 7, 22, 9),
        ),
        _order(
          id: 'cancelled',
          status: OrderStatus.cancelled,
          product: product,
          quantity: 10,
          unitPrice: 20,
          createdAt: DateTime(2026, 7, 22, 10),
        ),
      ],
      from: DateTime(2026, 7, 22),
      to: DateTime(2026, 7, 22, 23, 59),
    );

    expect(report.periodOrderCount, 2);
    expect(report.deliveredOrderCount, 1);
    expect(report.cancelledOrderCount, 1);
    expect(report.salesTotal, 60);
    expect(report.averageOrderValue, 60);
    expect(report.topCustomers.single.businessName, 'متجر طرابلس');
    expect(report.topCustomers.single.orderCount, 1);
    expect(report.topProducts.single.quantity, 3);
    expect(report.outstandingBalance, 125);
    expect(report.outstandingCustomers.single.creditLimit, 1000);
    expect(
      report.lowStockProducts.map((row) => row.productId),
      ['empty', 'feed'],
    );
  });

  test('excludes orders outside the selected reporting period', () {
    final product = _product(id: 'feed', name: 'علف', available: 50);
    final report = buildAdminReportData(
      products: [product],
      customers: const [],
      orders: [
        _order(
          id: 'old',
          status: OrderStatus.delivered,
          product: product,
          quantity: 1,
          unitPrice: 20,
          createdAt: DateTime(2026, 6, 1),
        ),
      ],
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 22),
    );

    expect(report.periodOrderCount, 0);
    expect(report.salesTotal, 0);
    expect(report.topCustomers, isEmpty);
  });

  test('parses bounded dashboard aggregate snapshots', () {
    final data = AdminDashboardData.fromRpc({
      'stats': {
        'total_customers': 12,
        'active_customers': 9,
        'pending_orders': 3,
        'today_orders': 4,
        'low_stock_count': 2,
        'month_sales': '1250.50',
      },
      'pending_orders': [
        {
          'id': 'order-1',
          'order_number': 'ORB-1001',
          'business_name': 'متجر طرابلس',
          'item_count': 2,
          'total': 140,
          'created_at': '2026-07-22T08:30:00Z',
        },
      ],
      'low_stock_products': [
        {
          'product_id': 'feed',
          'product_name': 'علف',
          'sku': 'SKU-feed',
          'available_quantity': 4,
        },
      ],
    });

    expect(data.stats.totalCustomers, 12);
    expect(data.stats.monthSales, 1250.5);
    expect(data.pendingOrders.single.displayNumber, 'ORB-1001');
    expect(data.pendingOrders.single.itemCount, 2);
    expect(data.lowStockProducts.single.availableQuantity, 4);
  });

  test('parses server-side operational report rows', () {
    final report = AdminReportData.fromRpc({
      'period_order_count': 5,
      'delivered_order_count': 3,
      'cancelled_order_count': 1,
      'sales_total': '420.00',
      'average_order_value': 140,
      'outstanding_balance': 75,
      'top_customers': [
        {
          'customer_id': 'customer-1',
          'business_name': 'متجر طرابلس',
          'order_count': 3,
          'sales_total': 420,
        },
      ],
      'top_products': [
        {
          'product_id': 'feed',
          'product_name': 'علف',
          'sku': 'SKU-feed',
          'quantity': 9,
          'sales_total': 420,
        },
      ],
      'low_stock_products': const [],
      'outstanding_customers': const [],
    });

    expect(report.periodOrderCount, 5);
    expect(report.salesTotal, 420);
    expect(report.topCustomers.single.orderCount, 3);
    expect(report.topProducts.single.quantity, 9);
  });
}

Product _product({
  required String id,
  required String name,
  required int available,
}) {
  return Product(
    id: id,
    nameAr: name,
    sku: 'SKU-$id',
    category: 'اختبار',
    animalType: 'ماشية',
    brand: 'اختبار',
    unitSize: 'كيس',
    basePrice: 20,
    stockQuantity: 50,
    availableQuantity: available,
    minOrderQty: 1,
  );
}

Order _order({
  required String id,
  required OrderStatus status,
  required Product product,
  required int quantity,
  required double unitPrice,
  required DateTime createdAt,
}) {
  return Order(
    id: id,
    customerId: 'customer-1',
    businessName: 'متجر طرابلس',
    status: status,
    createdAt: createdAt,
    items: [
      OrderItem(
        productId: product.id,
        productName: product.name,
        productSku: product.sku,
        unitSize: product.unitSize,
        packageLabel: product.effectivePackageSize,
        quantity: quantity,
        unitPrice: unitPrice,
        lineTotal: quantity * unitPrice,
        product: product,
      ),
    ],
    subtotal: quantity * unitPrice,
    total: quantity * unitPrice,
  );
}
