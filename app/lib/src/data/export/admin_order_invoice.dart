import 'dart:convert';

import '../../core/utils/formatters.dart';
import '../models/order.dart';

class AdminOrderInvoiceHtml {
  const AdminOrderInvoiceHtml._();

  static const _escape = HtmlEscape();

  static String build({
    required Order order,
    required String shopName,
    bool demoData = false,
  }) {
    final title = _escape.convert(
      'فاتورة ${westernDigits(order.displayNumber)} — ${shopName.trim()}',
    );
    final address = order.effectiveDeliveryAddress;
    final rows = [
      for (var index = 0; index < order.items.length; index++)
        '''
        <tr>
          <td>${_num(index + 1)}</td>
          <td>${_escape.convert(order.items[index].productName)}</td>
          <td>${_num(order.items[index].quantity)}</td>
          <td>${_num(lydWestern(order.items[index].unitPrice))}</td>
          <td>${_num(lydWestern(order.items[index].lineTotal))}</td>
        </tr>
        ''',
    ].join();

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<title>$title</title>
<style>
  html { font-feature-settings: "locl" 0; }
  body { font-family: "Noto Naskh Arabic", "Tahoma", sans-serif; color: #173f32; margin: 24px; }
  h1 { font-size: 22px; margin: 0 0 6px; }
  .muted { color: #5b6e66; font-size: 13px; }
  table { width: 100%; border-collapse: collapse; margin-top: 16px; }
  th, td { border: 1px solid #d7e3dd; padding: 8px; text-align: right; }
  th { background: #e9f4ee; }
  .totals { margin-top: 16px; width: 320px; }
  .total { font-weight: 800; font-size: 18px; }
  .demo { background: #fff4e5; border: 1px solid #ffcc80; padding: 8px 10px; margin-bottom: 12px; }
  .num { font-variant-numeric: lining-nums; -webkit-locale: "en"; unicode-bidi: isolate; }
</style>
</head>
<body>
  ${demoData ? '<div class="demo">بيانات تجريبية — غير تشغيلية.</div>' : ''}
  <h1>${_escape.convert(shopName.trim().isEmpty ? 'فاتورة طلب' : shopName.trim())}</h1>
  <div class="muted">طلب ${_escape.convert(westernDigits(order.displayNumber))} — ${_num('${order.createdAt.year}/${order.createdAt.month}/${order.createdAt.day}')}</div>
  <p>العميل: ${_escape.convert(order.businessName.trim().isEmpty ? 'عميل B2B' : order.businessName.trim())}</p>
  ${order.contactPhone.trim().isEmpty ? '' : '<p>الهاتف: ${_num(order.contactPhone.trim())}</p>'}
  ${address.isEmpty ? '' : '<p>عنوان التسليم: ${_escape.convert(address)}</p>'}
  ${order.customerNote.trim().isEmpty ? '' : '<p>ملاحظة العميل: ${_escape.convert(order.customerNote.trim())}</p>'}
  <table>
    <thead>
      <tr><th>#</th><th>الصنف</th><th>الكمية</th><th>سعر الوحدة</th><th>الإجمالي</th></tr>
    </thead>
    <tbody>$rows</tbody>
  </table>
  <table class="totals">
    <tr><td>الإجمالي الفرعي</td><td>${_num(lydWestern(order.subtotal))}</td></tr>
    ${order.discountAmount > 0 ? '<tr><td>الخصم</td><td>${_num(lydWestern(order.discountAmount))}</td></tr>' : ''}
    ${order.deliveryFee > 0 ? '<tr><td>التوصيل</td><td>${_num(lydWestern(order.deliveryFee))}</td></tr>' : ''}
    ${order.handlingFee > 0 ? '<tr><td>المناولة</td><td>${_num(lydWestern(order.handlingFee))}</td></tr>' : ''}
    <tr class="total"><td>الإجمالي المعتمد</td><td>${_num(lydWestern(order.total))}</td></tr>
  </table>
  <script>window.addEventListener("load", function () { window.focus(); window.print(); });</script>
</body>
</html>
''';
  }

  static String _num(Object value) {
    final text = westernDigits('$value')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<span class="num" lang="en" dir="ltr">$text</span>';
  }
}
