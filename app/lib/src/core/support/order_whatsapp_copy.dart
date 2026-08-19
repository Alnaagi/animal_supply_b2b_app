import '../../data/models/order.dart';
import 'customer_invite_copy.dart';

const defaultOrderWhatsappTemplate = '''طلب من: {business_name}
رقم الطلب: {order_number}
الحالة: {status}

المنتجات:
{items}

الإجمالي الفرعي: {subtotal} د.ل
{discount_line}{delivery_line}{handling_line}الإجمالي المعتمد: {total} د.ل
{address_line}ملاحظة العميل: {customer_note}
{invoice_line}''';

const orderWhatsappTemplatePlaceholders = <String>[
  '{order_number}',
  '{shop_name}',
  '{store_name}',
  '{business_name}',
  '{status}',
  '{items}',
  '{subtotal}',
  '{discount}',
  '{delivery_fee}',
  '{handling_fee}',
  '{total}',
  '{address}',
  '{customer_note}',
  '{invoice_link}',
  '{contact_person}',
  '{phone}',
];

class OrderWhatsappMessageValues {
  const OrderWhatsappMessageValues({
    required this.orderNumber,
    required this.shopName,
    required this.businessName,
    required this.status,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.deliveryFee,
    required this.handlingFee,
    required this.total,
    required this.address,
    required this.customerNote,
    required this.invoiceLink,
    required this.contactPerson,
    required this.phone,
  });

  final String orderNumber;
  final String shopName;
  final String businessName;
  final String status;
  final String items;
  final String subtotal;
  final String discount;
  final String deliveryFee;
  final String handlingFee;
  final String total;
  final String address;
  final String customerNote;
  final String invoiceLink;
  final String contactPerson;
  final String phone;

  String get storeName => businessName;

  String get discountLine =>
      discount.trim().isEmpty ? '' : 'الخصم: $discount د.ل\n';

  String get deliveryLine =>
      deliveryFee.trim().isEmpty ? '' : 'التوصيل: $deliveryFee د.ل\n';

  String get handlingLine =>
      handlingFee.trim().isEmpty ? '' : 'المناولة: $handlingFee د.ل\n';

  String get addressLine =>
      address.trim().isEmpty ? '' : 'عنوان التسليم: $address\n';

  String get invoiceLine =>
      invoiceLink.trim().isEmpty ? '' : 'رابط الفاتورة: $invoiceLink\n';
}

OrderWhatsappMessageValues orderWhatsappValues({
  required Order order,
  required String fallbackBusinessName,
  String shopName = '',
  String invoiceLink = '',
}) {
  final businessName = order.businessName.trim().isNotEmpty
      ? order.businessName.trim()
      : fallbackBusinessName.trim();
  return OrderWhatsappMessageValues(
    orderNumber: order.displayNumber,
    shopName: shopName.trim(),
    businessName: businessName.isEmpty ? 'عميل B2B' : businessName,
    status: order.status.label,
    items: [
      for (var i = 0; i < order.items.length; i++)
        '${i + 1}. ${order.items[i].productName} × ${order.items[i].quantity} — ${order.items[i].lineTotal.toStringAsFixed(2)} د.ل',
    ].join('\n'),
    subtotal: order.subtotal.toStringAsFixed(2),
    discount:
        order.discountAmount > 0 ? order.discountAmount.toStringAsFixed(2) : '',
    deliveryFee:
        order.deliveryFee > 0 ? order.deliveryFee.toStringAsFixed(2) : '',
    handlingFee:
        order.handlingFee > 0 ? order.handlingFee.toStringAsFixed(2) : '',
    total: order.total.toStringAsFixed(2),
    address: order.effectiveDeliveryAddress,
    customerNote: order.customerNote.trim().isEmpty
        ? 'لا توجد'
        : order.customerNote.trim(),
    invoiceLink: invoiceLink.trim(),
    contactPerson: order.contactPerson.trim(),
    phone: order.contactPhone.trim(),
  );
}

String renderOrderWhatsappTemplate({
  required String template,
  required Order order,
  required String fallbackBusinessName,
  String shopName = '',
  String invoiceLink = '',
}) {
  final values = orderWhatsappValues(
    order: order,
    fallbackBusinessName: fallbackBusinessName,
    shopName: shopName,
    invoiceLink: invoiceLink,
  );
  return applyOrderWhatsappTemplate(template: template, values: values);
}

String applyOrderWhatsappTemplate({
  required String template,
  required OrderWhatsappMessageValues values,
}) {
  final source =
      template.trim().isEmpty ? defaultOrderWhatsappTemplate : template;
  final rendered = source
      .replaceAll('{order_number}', values.orderNumber)
      .replaceAll('{shop_name}', values.shopName)
      .replaceAll('{store_name}', values.storeName)
      .replaceAll('{business_name}', values.businessName)
      .replaceAll('{status}', values.status)
      .replaceAll('{items}', values.items)
      .replaceAll('{subtotal}', values.subtotal)
      .replaceAll('{discount_line}', values.discountLine)
      .replaceAll('{delivery_line}', values.deliveryLine)
      .replaceAll('{handling_line}', values.handlingLine)
      .replaceAll('{address_line}', values.addressLine)
      .replaceAll('{invoice_line}', values.invoiceLine)
      .replaceAll('{discount}', values.discount)
      .replaceAll('{delivery_fee}', values.deliveryFee)
      .replaceAll('{handling_fee}', values.handlingFee)
      .replaceAll('{total}', values.total)
      .replaceAll('{address}', values.address)
      .replaceAll('{customer_note}', values.customerNote)
      .replaceAll('{invoice_link}', values.invoiceLink)
      .replaceAll('{contact_person}', values.contactPerson)
      .replaceAll('{phone}', values.phone);

  return stripSecretsFromInviteUrls(
    rendered.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim(),
    '',
  );
}

String resolveOrderWhatsappMessage({
  required Order order,
  required String fallbackBusinessName,
  String shopName = '',
  String invoiceLink = '',
  String? template,
  String? overrideText,
}) {
  final override = overrideText?.trim() ?? '';
  if (override.isNotEmpty) {
    return stripSecretsFromInviteUrls(override, '');
  }
  return renderOrderWhatsappTemplate(
    template: template ?? defaultOrderWhatsappTemplate,
    order: order,
    fallbackBusinessName: fallbackBusinessName,
    shopName: shopName,
    invoiceLink: invoiceLink,
  );
}
