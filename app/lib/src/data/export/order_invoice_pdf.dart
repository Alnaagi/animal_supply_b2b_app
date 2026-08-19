import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../models/order.dart';

class OrderInvoicePdf {
  const OrderInvoicePdf._();

  static Future<Uint8List> build({
    required Order order,
    required String shopName,
    bool demoData = false,
  }) async {
    final fontData =
        await rootBundle.load('assets/fonts/NotoSansArabic-Variable.ttf');
    final arabicFont = pw.Font.ttf(fontData);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: arabicFont,
        bold: arabicFont,
        italic: arabicFont,
        boldItalic: arabicFont,
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(width: .8, color: PdfColors.grey400),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  shopName.trim().isEmpty ? 'متجر B2B' : shopName.trim(),
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text('فاتورة طلب', style: const pw.TextStyle(fontSize: 14)),
                pw.SizedBox(height: 4),
                pw.Text(_line('رقم الطلب', westernDigits(order.displayNumber))),
                pw.Text(_line('التاريخ', _formatDate(order.createdAt))),
              ],
            ),
          ),
          if (demoData)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#fff4e5'),
                border: pw.Border.all(color: PdfColor.fromHex('#ffcc80')),
              ),
              child: pw.Text('بيانات تجريبية - غير تشغيلية.'),
            ),
          pw.SizedBox(height: 12),
          pw.Text('بيانات العميل',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(_line('اسم النشاط',
              order.businessName.isEmpty ? 'عميل B2B' : order.businessName)),
          if (order.contactPhone.trim().isNotEmpty)
            pw.Text(_line('الهاتف', westernDigits(order.contactPhone.trim()))),
          if (order.effectiveDeliveryAddress.isNotEmpty)
            pw.Text(_line('عنوان التسليم', order.effectiveDeliveryAddress)),
          if (order.customerNote.trim().isNotEmpty)
            pw.Text(_line('ملاحظة العميل', order.customerNote.trim())),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .7),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerRight,
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            headers: const [
              '#',
              'الصنف',
              'الكمية',
              'سعر الوحدة',
              'الإجمالي',
            ],
            data: [
              for (var i = 0; i < order.items.length; i++)
                [
                  westernDigits('${i + 1}'),
                  order.items[i].productName,
                  westernDigits('${order.items[i].quantity}'),
                  lydWestern(order.items[i].unitPrice),
                  lydWestern(order.items[i].lineTotal),
                ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: .8),
              ),
              child: pw.Column(
                children: [
                  _totalRow('الإجمالي الفرعي', order.subtotal),
                  if (order.discountAmount > 0)
                    _totalRow('الخصم', order.discountAmount),
                  if (order.deliveryFee > 0)
                    _totalRow('التوصيل', order.deliveryFee),
                  if (order.handlingFee > 0)
                    _totalRow('المناولة', order.handlingFee),
                  pw.Divider(),
                  _totalRow('الإجمالي المعتمد', order.total, bold: true),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'تم إنشاء الفاتورة من نسخة الطلب المعتمدة في النظام.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static String _line(String label, String value) => '$label: $value';

  static String _formatDate(DateTime date) {
    return westernDigits('${date.year}/${date.month}/${date.day}');
  }

  static pw.Widget _totalRow(String label, double value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontSize: bold ? 12 : 10,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(lydWestern(value),
              style: style, textDirection: pw.TextDirection.ltr),
        ],
      ),
    );
  }
}
