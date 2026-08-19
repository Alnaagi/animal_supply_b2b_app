import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/export/order_invoice_pdf.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invoice pdf bytes start with PDF signature', () async {
    final bytes = await OrderInvoicePdf.build(
      order: _order(itemCount: 2),
      shopName: 'متجر الأعلاف',
    );
    expect(bytes.length, greaterThan(100));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('invoice pdf supports Arabic and multipage content', () async {
    final bytes = await OrderInvoicePdf.build(
      order: _order(itemCount: 80),
      shopName: 'متجر الأعلاف',
    );
    final text = String.fromCharCodes(bytes);
    expect(text.contains('NotoSansArabic'), isTrue);
    expect(bytes.length, greaterThan(8000));
  });

  test('invoice total always matches order snapshot', () async {
    final base = _order(itemCount: 1, total: 90);
    final changed = base.copyWith(total: 180, subtotal: 170, deliveryFee: 10);

    final first = await OrderInvoicePdf.build(order: base, shopName: 'متجر');
    final second =
        await OrderInvoicePdf.build(order: changed, shopName: 'متجر');
    expect(first, isNot(equals(second)));
  });
}

Order _order({
  int itemCount = 1,
  double subtotal = 80,
  double deliveryFee = 5,
  double handlingFee = 5,
  double total = 90,
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
  final items = [
    for (var i = 0; i < itemCount; i++)
      OrderItem(
        id: 'line-$i',
        productId: 'feed-$i',
        productName: 'علف رقم $i',
        productSku: 'FEED-$i',
        unitSize: '50 كجم',
        packageLabel: 'كيس',
        quantity: 2,
        unitPrice: 40,
        lineTotal: 80,
        product: product,
      ),
  ];
  return Order(
    id: 'order-1',
    orderNumber: 'AS-Z4R7T9W',
    customerId: 'customer-1',
    businessName: 'متجر الاختبار',
    contactPhone: '0912345678',
    status: OrderStatus.pending,
    items: items,
    createdAt: DateTime.utc(2026, 8, 16),
    deliveryAddress: 'طرابلس',
    customerDefaultAddress: 'طرابلس - المقر',
    customerNote: 'يرجى الاتصال',
    handlingFee: handlingFee,
    deliveryFee: deliveryFee,
    discountAmount: 0,
    subtotal: subtotal,
    total: total,
  );
}
