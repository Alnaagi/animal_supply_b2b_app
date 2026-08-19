import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/files/browser_file_download.dart';
import '../../core/files/browser_print.dart';
import '../../core/utils/formatters.dart';
import '../../data/export/order_invoice_pdf.dart';
import '../../data/models/order.dart';
import '../../data/repositories/orders_repository.dart';

class CustomerInvoiceActions extends StatelessWidget {
  const CustomerInvoiceActions({
    required this.order,
    required this.shopName,
    super.key,
  });

  final Order order;
  final String shopName;

  Future<void> _viewInvoice(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'فاتورة الطلب ${order.displayNumber}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                for (final item in order.items)
                  ListTile(
                    dense: true,
                    title: Text(item.productName),
                    subtitle: Text('${item.quantity} × ${lyd(item.unitPrice)}'),
                    trailing: Text(
                      lyd(item.lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                const Divider(height: 20),
                ListTile(
                  dense: true,
                  title: const Text('الإجمالي المعتمد'),
                  trailing: Text(
                    lyd(order.total),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareSummary(BuildContext context) async {
    final summary = OrdersRepository().whatsappSummary(order, shopName);
    await Clipboard.setData(ClipboardData(text: summary));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ ملخص الطلب للمشاركة')),
    );
  }

  static Future<void> downloadPdfForOrder(
    BuildContext context, {
    required Order order,
    required String shopName,
  }) async {
    final bytes = await OrderInvoicePdf.build(
      order: order,
      shopName: shopName,
    );
    final fileName = _safeInvoiceFilename(order.displayNumber);
    if (kIsWeb) {
      downloadBytesInBrowser(
        filename: fileName,
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('بدأ تنزيل الفاتورة PDF')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تنزيل PDF متاح حالياً على الويب فقط')),
    );
  }

  Future<void> _printInvoice(BuildContext context) async {
    final bytes = await OrderInvoicePdf.build(
      order: order,
      shopName: shopName,
    );
    final opened = printPdfDocument(
      bytes: bytes,
      title: 'invoice-${_safeIdentifier(order.displayNumber)}',
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الطباعة متاحة من نسخة الويب فقط حالياً')),
      );
    }
  }

  Future<void> _downloadPdf(BuildContext context) async {
    await downloadPdfForOrder(
      context,
      order: order,
      shopName: shopName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const Key('invoice-view-action'),
          onPressed: () => _viewInvoice(context),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('عرض الفاتورة'),
        ),
        if (kIsWeb)
          OutlinedButton.icon(
            key: const Key('invoice-print-action'),
            onPressed: () => _printInvoice(context),
            icon: const Icon(Icons.print_outlined),
            label: const Text('طباعة'),
          ),
        OutlinedButton.icon(
          key: const Key('invoice-download-action'),
          onPressed: () => _downloadPdf(context),
          icon: const Icon(Icons.download_outlined),
          label: const Text('تحميل PDF'),
        ),
        OutlinedButton.icon(
          key: const Key('invoice-share-action'),
          onPressed: () => _shareSummary(context),
          icon: const Icon(Icons.share_outlined),
          label: const Text('مشاركة'),
        ),
      ],
    );
  }
}

String _safeInvoiceFilename(String orderDisplayNumber) {
  final safe = _safeIdentifier(orderDisplayNumber);
  return 'invoice-$safe.pdf';
}

String _safeIdentifier(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  final collapsed = normalized.replaceAll(RegExp(r'-+'), '-');
  final cleaned = collapsed.replaceAll(RegExp(r'^-|-$'), '');
  if (cleaned.isEmpty) return 'order';
  return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
}
