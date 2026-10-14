import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/core/support/order_whatsapp_copy.dart';
import 'package:animal_supply_b2b/src/data/local/admin_order_whatsapp_template_store.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('default template matches the generated invoice summary', () {
    final rendered = renderOrderWhatsappTemplate(
      template: defaultOrderWhatsappTemplate,
      order: _order(),
      fallbackBusinessName: 'عميل B2B',
      shopName: 'متجر الأعلاف',
    );

    expect(
      rendered,
      'طلب من: متجر الاختبار\n'
      'رقم الطلب: AS-K7M4Q2P\n'
      'الحالة: قيد المراجعة\n'
      '\n'
      'المنتجات:\n'
      '1. أكل قطط × 2 — 84.00 د.ل\n'
      '\n'
      'الإجمالي الفرعي: 84.00 د.ل\n'
      'التوصيل: 5.00 د.ل\n'
      'الإجمالي المعتمد: 89.00 د.ل\n'
      'عنوان التسليم: طرابلس، طريق المطار\n'
      'ملاحظة العميل: يفضل التسليم صباحاً.',
    );
    expect(rendered, isNot(contains('{shop_name}')));
    expect(rendered, isNot(contains('رابط الفاتورة')));
  });

  test('custom template applies placeholders including shop and invoice link',
      () {
    final rendered = renderOrderWhatsappTemplate(
      template:
          'من {shop_name} إلى {store_name}\nطلب {order_number} ({status})\n{items}\nالإجمالي {total} د.ل\n{invoice_link}',
      order: _order(),
      fallbackBusinessName: 'عميل B2B',
      shopName: 'متجر الأعلاف',
      invoiceLink: 'https://animal-supply-b2b.alnaagi-ai.workers.dev/login',
    );

    expect(rendered, contains('من متجر الأعلاف إلى متجر الاختبار'));
    expect(rendered, contains('طلب AS-K7M4Q2P (قيد المراجعة)'));
    expect(rendered, contains('1. أكل قطط × 2 — 84.00 د.ل'));
    expect(rendered, contains('الإجمالي 89.00 د.ل'));
    expect(
      rendered,
      contains('https://animal-supply-b2b.alnaagi-ai.workers.dev/login'),
    );
    expect(rendered, isNot(contains('password=')));
  });

  test('strips passwords from invoice links in custom templates', () {
    final rendered = renderOrderWhatsappTemplate(
      template: 'فاتورة: {invoice_link}',
      order: _order(),
      fallbackBusinessName: 'عميل B2B',
      invoiceLink: 'https://example.ly/invoice?password=secret&token=abc',
    );

    expect(rendered, contains('https://example.ly/invoice'));
    expect(rendered, isNot(contains('password=secret')));
  });

  test('per-order override wins over the global template', () {
    final message = resolveOrderWhatsappMessage(
      order: _order(),
      fallbackBusinessName: 'عميل B2B',
      shopName: 'متجر الأعلاف',
      template: 'قالب عام {order_number}',
      overrideText: 'رسالة خاصة للطلب AS-K7M4Q2P',
    );

    expect(message, 'رسالة خاصة للطلب AS-K7M4Q2P');
    expect(message, isNot(contains('قالب عام')));
  });

  test('empty override falls back to the applied template', () {
    final message = resolveOrderWhatsappMessage(
      order: _order(),
      fallbackBusinessName: 'عميل B2B',
      shopName: 'متجر الأعلاف',
      template: 'مرحباً {store_name} — طلب {order_number}',
      overrideText: '   ',
    );

    expect(message, 'مرحباً متجر الاختبار — طلب AS-K7M4Q2P');
  });

  test('template store round-trips globally and per order', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = AdminOrderWhatsappTemplateStore(prefs: prefs);
    final order = _order();

    expect(await store.loadTemplate(), defaultOrderWhatsappTemplate);
    expect(await store.loadOverride(order.id), isNull);

    expect(
      await store.saveTemplate('قالب {order_number} لمتجر {store_name}'),
      isTrue,
    );
    expect(await store.saveOverride(order.id, 'نص هذا الطلب فقط'), isTrue);

    expect(
      await store.resolve(
        order: order,
        fallbackBusinessName: 'عميل B2B',
        shopName: 'متجر الأعلاف',
      ),
      'نص هذا الطلب فقط',
    );

    expect(await store.clearOverride(order.id), isTrue);
    expect(
      await store.resolve(
        order: order,
        fallbackBusinessName: 'عميل B2B',
        shopName: 'متجر الأعلاف',
      ),
      'قالب AS-K7M4Q2P لمتجر متجر الاختبار',
    );

    expect(await store.resetTemplate(), isTrue);
    expect(await store.loadTemplate(), defaultOrderWhatsappTemplate);
  });
}

Order _order() {
  const product = Product(
    id: 'cat-001',
    nameAr: 'أكل قطط',
    sku: 'CAT-001',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'اختبار',
    unitSize: '2 كجم',
    basePrice: 42,
    stockQuantity: 10,
    minOrderQty: 1,
  );
  return Order(
    id: 'invoice-order',
    orderNumber: 'AS-K7M4Q2P',
    customerId: 'customer-test',
    businessName: 'متجر الاختبار',
    status: OrderStatus.pending,
    items: [
      const OrderItem(
        id: 'item-1',
        productId: 'cat-001',
        productName: 'أكل قطط',
        productSku: 'CAT-001',
        unitSize: '2 كجم',
        packageLabel: 'كيس 2 كجم',
        quantity: 2,
        unitPrice: 42,
        lineTotal: 84,
        product: product,
      ),
    ],
    createdAt: DateTime.utc(2026, 8, 14, 12),
    deliveryAddress: 'طرابلس، طريق المطار',
    customerNote: 'يفضل التسليم صباحاً.',
    deliveryFee: 5,
  );
}
