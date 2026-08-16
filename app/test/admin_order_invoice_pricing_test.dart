import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/core/support/customer_contact.dart';
import 'package:animal_supply_b2b/src/data/export/admin_order_invoice.dart';
import 'package:animal_supply_b2b/src/data/models/admin_order_pricing.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice HTML uses the effective delivery address and customer note', () {
    final html = AdminOrderInvoiceHtml.build(
      order: _order(deliveryAddress: ''),
      shopName: 'متجر الأعلاف',
    );
    expect(html, contains('فاتورة INV-1'));
    expect(html, contains('طرابلس - المقر'));
    expect(html, contains('يرجى الاتصال'));
    expect(html, contains('0912345678'));
    expect(html, contains('2026/8/16'));
    expect(html, contains('20.00'));
    expect(html, contains('25.00'));
    expect(html, contains('lang="en"'));
    expect(html, contains('font-feature-settings: "locl" 0'));
    expect(html, isNot(contains('٢٠')));
    expect(html, isNot(contains('٢٥')));
    expect(html, isNot(contains('٢٠٢٦')));
    expect(html, contains('window.print()'));
  });

  test('WhatsApp invoice share uses wa.me with the customer phone', () {
    final uri = CustomerContact.whatsappUri(
      phone: '0912345678',
      text: 'فاتورة INV-1',
    );
    expect(uri, isNotNull);
    expect(uri!.host, 'wa.me');
    expect(uri.path, contains('218912345678'));
    expect(uri.queryParameters['text'], 'فاتورة INV-1');
    expect(CustomerContact.telUri('0912345678')!.scheme, 'tel');
    expect(CustomerContact.whatsappUri(phone: '', text: 'x'), isNull);
  });

  test('pricing apply recalculates line totals and the approved total', () {
    final priced = AdminOrderPricing.apply(
      order: _order(),
      unitPrices: const [20],
      deliveryFee: 5,
      discountAmount: 3,
    );
    expect(priced.items.single.unitPrice, 20);
    expect(priced.items.single.lineTotal, 40);
    expect(priced.subtotal, 40);
    expect(priced.deliveryFee, 5);
    expect(priced.discountAmount, 3);
    expect(priced.total, 47);
  });

  test('pricing stays locked after delivery', () {
    expect(
      () => AdminOrderPricing.apply(
        order: _order(status: OrderStatus.delivered),
        unitPrices: const [20],
        deliveryFee: 0,
        discountAmount: 0,
      ),
      throwsA(isA<AdminOrderPricingException>()),
    );
  });
}

Order _order({
  OrderStatus status = OrderStatus.pending,
  String deliveryAddress = 'طرابلس، طريق المطار',
}) {
  const product = Product(
    id: 'feed',
    nameAr: 'علف',
    sku: 'FEED-1',
    category: 'أعلاف',
    animalType: 'أغنام',
    brand: 'اختبار',
    unitSize: '50 كجم',
    basePrice: 10,
    stockQuantity: 20,
    minOrderQty: 1,
  );
  return Order(
    id: 'order-1',
    orderNumber: 'INV-1',
    customerId: 'customer-1',
    businessName: 'متجر الاختبار',
    contactPhone: '0912345678',
    status: status,
    items: const [
      OrderItem(
        id: 'line-1',
        productId: 'feed',
        productName: 'علف',
        productSku: 'FEED-1',
        unitSize: '50 كجم',
        packageLabel: 'كيس',
        quantity: 2,
        unitPrice: 10,
        lineTotal: 20,
        product: product,
      ),
    ],
    createdAt: DateTime.utc(2026, 8, 16),
    deliveryAddress: deliveryAddress,
    customerDefaultAddress: 'طرابلس - المقر',
    customerNote: 'يرجى الاتصال',
    handlingFee: 5,
    deliveryFee: 0,
    discountAmount: 0,
    subtotal: 20,
    total: 25,
  );
}
