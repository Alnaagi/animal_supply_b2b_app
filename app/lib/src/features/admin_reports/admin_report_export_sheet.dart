import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/config/app_config.dart';
import '../../core/files/browser_file_download.dart';
import '../../core/theme/app_theme.dart';
import '../../data/export/admin_report_export.dart';
import '../../data/models/admin_models.dart';

typedef AdminReportFileSaver = void Function({
  required String filename,
  required List<int> bytes,
  required String mimeType,
});

Future<void> showAdminReportExportSheet({
  required BuildContext context,
  required AdminReportData report,
  required String periodLabel,
  String? shopName,
  AdminReportFileSaver? fileSaver,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: AdminReportExportSheet(
          report: report,
          periodLabel: periodLabel,
          shopName: shopName ?? AppConfig.shopName,
          fileSaver: fileSaver ??
              ({
                required filename,
                required bytes,
                required mimeType,
              }) {
                downloadBytesInBrowser(
                  filename: filename,
                  bytes: bytes,
                  mimeType: mimeType,
                );
              },
        ),
      );
    },
  );
}

class AdminReportExportSheet extends StatefulWidget {
  const AdminReportExportSheet({
    required this.report,
    required this.periodLabel,
    required this.fileSaver,
    this.shopName = AppConfig.shopName,
    super.key,
  });

  final AdminReportData report;
  final String periodLabel;
  final String shopName;
  final AdminReportFileSaver fileSaver;

  @override
  State<AdminReportExportSheet> createState() => _AdminReportExportSheetState();
}

class _AdminReportExportSheetState extends State<AdminReportExportSheet> {
  final Set<AdminReportExportDataset> selected = {
    ...AdminReportExportDataset.values,
  };
  bool exporting = false;

  @override
  Widget build(BuildContext context) {
    final demo = AppConfig.isDemoMode;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 8,
          bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const Key('admin-report-export-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تصدير التقرير',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'اختر المجموعات ثم نزّل PDF أو Excel. التصدير للإدارة فقط، '
              'ويعتمد على بيانات التقرير المعروضة.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey.shade700),
            ),
            if (demo) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.orange.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'الملف سيُوسَم كبيانات تجريبية غير تشغيلية.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final dataset in AdminReportExportDataset.values)
              CheckboxListTile(
                key: Key('admin-report-export-${dataset.id}'),
                value: selected.contains(dataset),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(dataset.labelAr),
                onChanged: exporting
                    ? null
                    : (value) {
                        setState(() {
                          if (value == true) {
                            selected.add(dataset);
                          } else {
                            selected.remove(dataset);
                          }
                        });
                      },
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const Key('admin-report-export-pdf'),
                  onPressed: exporting ? null : () => _export(pdf: true),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(exporting ? 'جارٍ التصدير...' : 'تنزيل PDF'),
                ),
                OutlinedButton.icon(
                  key: const Key('admin-report-export-excel'),
                  onPressed: exporting ? null : () => _export(pdf: false),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('تنزيل Excel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export({required bool pdf}) async {
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر مجموعة واحدة على الأقل قبل التصدير.')),
      );
      return;
    }
    setState(() => exporting = true);
    try {
      final request = AdminReportExportRequest(
        report: widget.report,
        periodLabel: widget.periodLabel,
        datasets: Set<AdminReportExportDataset>.from(selected),
        demoData: AppConfig.isDemoMode,
        shopName: widget.shopName,
      );
      final stem = adminReportExportFileStem(DateTime.now());
      if (pdf) {
        final fontData = await rootBundle.load(
          'assets/fonts/NotoSansArabic-Variable.ttf',
        );
        final bytes = await AdminReportPdfExport.build(
          request,
          arabicFont: pw.Font.ttf(fontData),
        );
        widget.fileSaver(
          filename: '$stem.pdf',
          bytes: bytes,
          mimeType: 'application/pdf',
        );
      } else {
        final bytes = AdminReportCsvExport.build(request);
        widget.fileSaver(
          filename: '$stem.csv',
          bytes: bytes,
          mimeType: 'text/csv;charset=utf-8',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pdf ? 'تم تجهيز ملف PDF.' : 'تم تجهيز ملف Excel.'),
        ),
      );
    } on UnsupportedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تنزيل الملفات متاح من نسخة الويب.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      debugPrint('Admin report export failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تجهيز ملف التصدير. أعد المحاولة.')),
      );
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }
}
