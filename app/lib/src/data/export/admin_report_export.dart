import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/config/app_config.dart';
import '../../core/utils/formatters.dart';
import '../models/admin_models.dart';

enum AdminReportExportDataset {
  sales('sales', 'ملخص المبيعات'),
  customers('customers', 'أفضل العملاء'),
  products('products', 'أفضل المنتجات'),
  inventory('inventory', 'تنبيه المخزون');

  const AdminReportExportDataset(this.id, this.labelAr);

  final String id;
  final String labelAr;
}

class AdminReportExportRequest {
  const AdminReportExportRequest({
    required this.report,
    required this.periodLabel,
    required this.datasets,
    required this.demoData,
    this.shopName = AppConfig.shopName,
  });

  final AdminReportData report;
  final String periodLabel;
  final Set<AdminReportExportDataset> datasets;
  final bool demoData;
  final String shopName;

  String get brandedShopName {
    final trimmed = shopName.trim();
    return trimmed.isEmpty ? AppConfig.shopName : trimmed;
  }
}

class AdminReportCsvExport {
  static const utf8Bom = [0xEF, 0xBB, 0xBF];

  static Uint8List build(AdminReportExportRequest request) {
    final lines = <String>[
      _csvRow([request.brandedShopName]),
          _csvRow(['تقرير تشغيلي', westernDigits(request.periodLabel)]),
      if (request.demoData)
        _csvRow(['بيانات تجريبية', 'غير تشغيلية - للاطلاع المحلي فقط']),
      '',
    ];

    for (final dataset in AdminReportExportDataset.values) {
      if (!request.datasets.contains(dataset)) continue;
      lines.addAll(_section(dataset, request.report));
      lines.add('');
    }

    final encoded = utf8.encode(lines.join('\r\n'));
    return Uint8List.fromList([...utf8Bom, ...encoded]);
  }

  static List<String> _section(
    AdminReportExportDataset dataset,
    AdminReportData report,
  ) {
    switch (dataset) {
      case AdminReportExportDataset.sales:
        return [
          _csvRow([dataset.labelAr]),
          _csvRow(['المؤشر', 'القيمة']),
          _csvRow(['مبيعات الفترة', reportMoney(report.salesTotal)]),
          _csvRow(['طلبات مسلّمة', reportCount(report.deliveredOrderCount)]),
          _csvRow(['متوسط الطلب المسلّم', reportMoney(report.averageOrderValue)]),
          _csvRow(['طلبات بكل الحالات', reportCount(report.periodOrderCount)]),
          _csvRow(['طلبات ملغاة', reportCount(report.cancelledOrderCount)]),
        ];
      case AdminReportExportDataset.customers:
        return [
          _csvRow([dataset.labelAr]),
          _csvRow(['العميل', 'طلبات مسلّمة', 'المبيعات']),
          if (report.topCustomers.isEmpty)
            _csvRow(['لا توجد طلبات مسلمة في هذه الفترة'])
          else
            for (final row in report.topCustomers)
              _csvRow([
                row.businessName,
                reportCount(row.orderCount),
                reportMoney(row.salesTotal),
              ]),
        ];
      case AdminReportExportDataset.products:
        return [
          _csvRow([dataset.labelAr]),
          _csvRow(['المنتج', 'الرمز', 'الكمية', 'المبيعات']),
          if (report.topProducts.isEmpty)
            _csvRow(['لا توجد منتجات مباعة في هذه الفترة'])
          else
            for (final row in report.topProducts)
              _csvRow([
                row.productName,
                row.sku,
                reportCount(row.quantity),
                reportMoney(row.salesTotal),
              ]),
        ];
      case AdminReportExportDataset.inventory:
        return [
          _csvRow([dataset.labelAr]),
          _csvRow(['المنتج', 'الرمز', 'الكمية المتاحة']),
          if (report.lowStockProducts.isEmpty)
            _csvRow(['لا توجد تنبيهات مخزون حالياً'])
          else
            for (final row in report.lowStockProducts)
              _csvRow([
                row.productName,
                row.sku,
                row.availableQuantity == 0
                    ? 'غير متوفر'
                    : reportCount(row.availableQuantity),
              ]),
        ];
    }
  }

  static String _csvRow(List<String> cells) =>
      cells.map(_csvCell).join(',');

  static String _csvCell(String value) {
    final escaped = westernDigits(value).replaceAll('"', '""');
    return '"$escaped"';
  }
}

class AdminReportHtmlExport {
  const AdminReportHtmlExport._();

  static const _escape = HtmlEscape();

  static String build(AdminReportExportRequest request) {
    final shop = _escape.convert(request.brandedShopName);
    final period = _escape.convert(westernDigits(request.periodLabel));
    final sections = [
      for (final dataset in AdminReportExportDataset.values)
        if (request.datasets.contains(dataset))
          _htmlSection(dataset, request.report),
    ].join();
    final demo = request.demoData
        ? '<div class="demo">بيانات تجريبية غير تشغيلية - للتصدير المحلي فقط.</div>'
        : '';

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<title>${_escape.convert('التقارير التشغيلية - ${request.brandedShopName}')}</title>
<style>
  html { font-feature-settings: "locl" 0; }
  body {
    font-family: "Noto Naskh Arabic", "Noto Sans Arabic", "Tahoma", sans-serif;
    color: #173f32;
    margin: 0;
    background: #f7f2ea;
  }
  .num {
    font-variant-numeric: lining-nums;
    -webkit-locale: "en";
    unicode-bidi: isolate;
    font-feature-settings: "locl" 0;
  }
  .page { max-width: 920px; margin: 0 auto; padding: 24px; }
  .hero {
    background: #173f32;
    color: #fff;
    border-radius: 18px;
    padding: 22px 24px;
  }
  .hero .shop { font-size: 13px; opacity: .85; margin: 0 0 6px; }
  h1 { font-size: 24px; margin: 0 0 6px; }
  .period { font-size: 14px; opacity: .9; }
  .demo {
    background: #fff4e5;
    border: 1px solid #ffcc80;
    color: #173f32;
    padding: 10px 12px;
    border-radius: 12px;
    margin: 16px 0 0;
    font-weight: 700;
  }
  section {
    background: #fff;
    border: 1px solid #d7e3dd;
    border-radius: 16px;
    margin-top: 18px;
    overflow: hidden;
  }
  h2 {
    margin: 0;
    padding: 12px 16px;
    background: #168a63;
    color: #fff;
    font-size: 16px;
    border-right: 8px solid #0f5c42;
  }
  table { width: 100%; border-collapse: collapse; }
  th, td { border-bottom: 1px solid #d7e3dd; padding: 10px 12px; text-align: right; }
  th { background: #e9f4ee; font-weight: 800; }
  .empty { padding: 16px; color: #5b6e66; }
  .kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 10px; padding: 14px; }
  .kpi { background: #f3f5f3; border-radius: 12px; padding: 12px; }
  .kpi .label { color: #5b6e66; font-size: 12px; }
  .kpi .value { font-size: 18px; font-weight: 800; margin-top: 4px; }
</style>
</head>
<body>
  <div class="page">
    <header class="hero">
      <p class="shop">$shop</p>
      <h1>التقارير التشغيلية</h1>
      <div class="period"><span class="num" lang="en" dir="ltr">$period</span></div>
    </header>
    $demo
    $sections
  </div>
</body>
</html>
''';
  }

  static String _htmlSection(
    AdminReportExportDataset dataset,
    AdminReportData report,
  ) {
    final title = _escape.convert(dataset.labelAr);
    if (dataset == AdminReportExportDataset.sales) {
      final kpis = [
        for (final row in _salesRows(report))
          '''
          <div class="kpi">
            <div class="label">${_escape.convert(row[0])}</div>
            <div class="value">${_htmlNum(row[1])}</div>
          </div>
          ''',
      ].join();
      return '<section><h2>$title</h2><div class="kpis">$kpis</div></section>';
    }
    final headers = _headers(dataset);
    final rows = _logicalRows(dataset, report);
    if (rows.isEmpty) {
      return '<section><h2>$title</h2><div class="empty">${_escape.convert(_emptyMessage(dataset))}</div></section>';
    }
    final head = headers.map((cell) => '<th>${_escape.convert(cell)}</th>').join();
    final body = [
      for (final row in rows)
        '<tr>${row.map(_htmlCell).join()}</tr>',
    ].join();
    return '<section><h2>$title</h2><table><thead><tr>$head</tr></thead><tbody>$body</tbody></table></section>';
  }

  static String _htmlCell(String cell) => '<td>${_htmlNum(cell)}</td>';

  static String _htmlNum(String value) {
    final text = _escape.convert(westernDigits(value));
    if (!RegExp(r'[0-9]').hasMatch(text)) return text;
    return '<span class="num" lang="en" dir="ltr">$text</span>';
  }
}

class AdminReportPdfExport {
  static const _teal = PdfColor.fromInt(0xff168a63);
  static const _tealDeep = PdfColor.fromInt(0xff0f5c42);
  static const _darkGreen = PdfColor.fromInt(0xff173f32);
  static const _sand = PdfColor.fromInt(0xfff7f2ea);
  static const _headerRow = PdfColor.fromInt(0xffd7efe6);
  static const _border = PdfColor.fromInt(0xffc5ddd3);
  static const _muted = PdfColor.fromInt(0xff5b6e66);
  static const _white = PdfColor.fromInt(0xffffffff);
  static const _demo = PdfColor.fromInt(0xfffff4e5);

  static Future<Uint8List> build(
    AdminReportExportRequest request, {
    required pw.Font arabicFont,
  }) async {
    final theme = pw.ThemeData.withFont(
      base: arabicFont,
      bold: arabicFont,
      fontFallback: [pw.Font.helvetica()],
    );
    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(32, 24, 32, 36),
        header: (context) => _header(request, arabicFont, context),
        footer: (context) => _footer(request, arabicFont, context),
        build: (context) => [
          if (request.demoData) ...[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: _demo,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: const PdfColor.fromInt(0xffffcc80)),
              ),
              child: pw.Text(
                'بيانات تجريبية غير تشغيلية - للتصدير المحلي فقط.',
                style: pw.TextStyle(font: arabicFont, fontSize: 10),
                textAlign: pw.TextAlign.right,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
            pw.SizedBox(height: 14),
          ],
          for (final dataset in AdminReportExportDataset.values)
            if (request.datasets.contains(dataset)) ...[
              _pdfSection(dataset, request.report, arabicFont),
              pw.SizedBox(height: 16),
            ],
        ],
      ),
    );
    return Uint8List.fromList(await doc.save());
  }

  static pw.Widget _header(
    AdminReportExportRequest request,
    pw.Font font,
    pw.Context context,
  ) {
    final compact = context.pageNumber > 1;
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: pw.EdgeInsets.fromLTRB(16, compact ? 8 : 12, 16, compact ? 8 : 12),
      decoration: const pw.BoxDecoration(
        color: _darkGreen,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
            pw.Text(
              request.brandedShopName,
              style: pw.TextStyle(
                font: font,
                fontSize: compact ? 13 : 16,
                color: _white,
                fontFallback: [pw.Font.helvetica()],
              ),
              textAlign: pw.TextAlign.right,
              textDirection: pw.TextDirection.rtl,
            ),
          if (!compact) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'التقارير التشغيلية',
              style: pw.TextStyle(font: font, fontSize: 11, color: _sand),
              textAlign: pw.TextAlign.right,
              textDirection: pw.TextDirection.rtl,
            ),
          ],
          pw.SizedBox(height: 3),
          _pdfMixedText(
            font,
            request.periodLabel,
            fontSize: 10,
            color: _sand,
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(
    AdminReportExportRequest request,
    pw.Font font,
    pw.Context context,
  ) {
    final page = '${context.pageNumber}';
    final pages = '${context.pagesCount}';
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _teal, width: 1.4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _pdfMixedText(
            font,
            'صفحة $page من $pages',
            fontSize: 9,
            color: _muted,
          ),
          pw.Text(
            request.brandedShopName,
            style: pw.TextStyle(font: font, fontSize: 9, color: _tealDeep),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfSection(
    AdminReportExportDataset dataset,
    AdminReportData report,
    pw.Font font,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: const pw.BoxDecoration(
              color: _teal,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(11),
                topRight: pw.Radius.circular(11),
              ),
            ),
            child: pw.Text(
              dataset.labelAr,
              style: pw.TextStyle(font: font, fontSize: 13, color: _white),
              textAlign: pw.TextAlign.right,
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          dataset == AdminReportExportDataset.sales
              ? _salesCards(report, font)
              : _rtlTable(
                  font: font,
                  headers: _headers(dataset),
                  rows: _logicalRows(dataset, report),
                  emptyMessage: _emptyMessage(dataset),
                ),
        ],
      ),
    );
  }

  static pw.Widget _salesCards(AdminReportData report, pw.Font font) {
    final rows = _salesRows(report);
    return pw.Padding(
      padding: const pw.EdgeInsets.all(10),
      child: pw.Table(
        columnWidths: {
          0: const pw.FlexColumnWidth(),
          1: const pw.FlexColumnWidth(),
        },
        children: [
          for (var index = 0; index < rows.length; index += 2)
            pw.TableRow(
              children: [
                _kpiCell(font, rows[index]),
                if (index + 1 < rows.length)
                  _kpiCell(font, rows[index + 1])
                else
                  pw.SizedBox(),
              ].reversed.toList(growable: false),
            ),
        ],
      ),
    );
  }

  static pw.Widget _kpiCell(pw.Font font, List<String> row) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _sand,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _teal, width: 1.2),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              row[0],
              style: pw.TextStyle(font: font, fontSize: 9, color: _muted),
              textAlign: pw.TextAlign.right,
              textDirection: pw.TextDirection.rtl,
            ),
            pw.SizedBox(height: 4),
            _pdfMixedText(
              font,
              row[1],
              fontSize: 12,
              color: _darkGreen,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _rtlTable({
    required pw.Font font,
    required List<String> headers,
    required List<List<String>> rows,
    required String emptyMessage,
  }) {
    if (rows.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(12),
        child: pw.Text(
          emptyMessage,
          style: pw.TextStyle(font: font, fontSize: 10, color: _muted),
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }
    final visualHeaders = rtlVisualRow(headers);
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _border, width: 0.4),
        verticalInside: pw.BorderSide(color: _border, width: 0.25),
      ),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerRow),
          children: [
            for (final header in visualHeaders)
              _tableCell(font, header, header: true),
          ],
        ),
        for (final indexed in rows.indexed)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: indexed.$1.isOdd ? _sand : _white,
            ),
            children: [
              for (final cell in rtlVisualRow(indexed.$2))
                _tableCell(font, cell, header: false),
            ],
          ),
      ],
    );
  }

  static pw.Widget _tableCell(pw.Font font, String value, {required bool header}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: _pdfMixedText(
        font,
        value,
        fontSize: header ? 10 : 9,
        color: _darkGreen,
      ),
    );
  }

  /// Paint ASCII 0-9 with Helvetica so Noto Arabic `locl` cannot restyle them.
  static pw.Widget _pdfMixedText(
    pw.Font arabicFont,
    String value, {
    required double fontSize,
    required PdfColor color,
  }) {
    final western = westernDigits(value);
    final latin = pw.Font.helvetica();
    if (!RegExp(r'[0-9]').hasMatch(western)) {
      return pw.Text(
        western,
        style: pw.TextStyle(font: arabicFont, fontSize: fontSize, color: color),
        textAlign: pw.TextAlign.right,
        textDirection: pw.TextDirection.rtl,
      );
    }
    final spans = <pw.InlineSpan>[];
    final buffer = StringBuffer();
    var inDigits = false;

    void flush() {
      if (buffer.isEmpty) return;
      final chunk = buffer.toString();
      buffer.clear();
      spans.add(
        pw.TextSpan(
          text: chunk,
          style: pw.TextStyle(
            font: inDigits ? latin : arabicFont,
            fontSize: fontSize,
            color: color,
          ),
        ),
      );
    }

    for (final character in western.split('')) {
      final digit = RegExp(r'[0-9.,]').hasMatch(character);
      if (digit != inDigits && buffer.isNotEmpty) {
        flush();
        inDigits = digit;
      } else {
        inDigits = digit;
      }
      buffer.write(character);
    }
    flush();

    return pw.RichText(
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
      text: pw.TextSpan(children: spans),
    );
  }
}

/// PDF tables paint left-to-right, so reverse logical Arabic columns to put
/// the first column on the visual right.
List<String> rtlVisualRow(List<String> logical) =>
    logical.reversed.toList(growable: false);

List<String> _headers(AdminReportExportDataset dataset) {
  return switch (dataset) {
    AdminReportExportDataset.sales => ['المؤشر', 'القيمة'],
    AdminReportExportDataset.customers => ['العميل', 'طلبات مسلّمة', 'المبيعات'],
    AdminReportExportDataset.products => ['المنتج', 'الرمز', 'الكمية', 'المبيعات'],
    AdminReportExportDataset.inventory => ['المنتج', 'الرمز', 'الكمية المتاحة'],
  };
}

List<List<String>> _salesRows(AdminReportData report) => [
      ['مبيعات الفترة', reportMoney(report.salesTotal)],
      ['طلبات مسلّمة', reportCount(report.deliveredOrderCount)],
      ['متوسط الطلب المسلّم', reportMoney(report.averageOrderValue)],
      ['طلبات بكل الحالات', reportCount(report.periodOrderCount)],
      ['طلبات ملغاة', reportCount(report.cancelledOrderCount)],
    ];

List<List<String>> _logicalRows(
  AdminReportExportDataset dataset,
  AdminReportData report,
) {
  switch (dataset) {
    case AdminReportExportDataset.sales:
      return _salesRows(report);
    case AdminReportExportDataset.customers:
      return [
        for (final row in report.topCustomers)
          [
            row.businessName,
            reportCount(row.orderCount),
            reportMoney(row.salesTotal),
          ],
      ];
    case AdminReportExportDataset.products:
      return [
        for (final row in report.topProducts)
          [
            row.productName,
            row.sku,
            reportCount(row.quantity),
            reportMoney(row.salesTotal),
          ],
      ];
    case AdminReportExportDataset.inventory:
      return [
        for (final row in report.lowStockProducts)
          [
            row.productName,
            row.sku,
            row.availableQuantity == 0
                ? 'غير متوفر'
                : reportCount(row.availableQuantity),
          ],
      ];
  }
}

String _emptyMessage(AdminReportExportDataset dataset) {
  return switch (dataset) {
    AdminReportExportDataset.sales => 'لا توجد مؤشرات مبيعات في هذه الفترة',
    AdminReportExportDataset.customers => 'لا توجد طلبات مسلمة في هذه الفترة',
    AdminReportExportDataset.products => 'لا توجد منتجات مباعة في هذه الفترة',
    AdminReportExportDataset.inventory => 'لا توجد تنبيهات مخزون حالياً',
  };
}

String reportCount(num value) => '${value.round()}';

String reportMoney(num value) => lydWestern(value);

String adminReportExportFileStem(DateTime now) {
  final stamp =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  return 'taqreer-tashgheeli-$stamp';
}
