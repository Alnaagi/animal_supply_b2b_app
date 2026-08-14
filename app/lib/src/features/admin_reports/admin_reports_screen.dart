import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  _ReportPeriod period = _ReportPeriod.thirtyDays;
  late Future<AdminReportData> reportFuture;

  @override
  void initState() {
    super.initState();
    reportFuture = _loadReport();
  }

  Future<AdminReportData> _loadReport() async {
    final repository = ref.read(adminRepositoryProvider);
    final now = DateTime.now();
    if (repository.hasRemoteBackend) {
      return repository.reports(
        const <Product>[],
        const <Order>[],
        from: period.startAt(now),
        to: now,
      );
    }
    final results = await Future.wait<Object>([
      ref.read(catalogRepositoryProvider).products(),
      ref.read(ordersRepositoryProvider).allOrders(),
    ]);
    final products = results[0] as List<Product>;
    final orders = results[1] as List<Order>;
    return repository.reports(
      products,
      orders,
      from: period.startAt(now),
      to: now,
    );
  }

  Future<void> _refresh() async {
    final next = _loadReport();
    setState(() => reportFuture = next);
    await next;
  }

  void _changePeriod(_ReportPeriod value) {
    setState(() {
      period = value;
      reportFuture = _loadReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'التقارير التشغيلية',
      child: FutureBuilder<AdminReportData>(
        future: reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _ReportsLoadError(onRetry: _refresh);
          }
          final report = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(18),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (AppConfig.isDemoMode) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.orange.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.science_outlined, color: AppTheme.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تقرير تجريبي مبني على بيانات محلية غير حقيقية. '
                            'الأرصدة المعروضة قيم مرجعية تُسجل يدوياً وليست دفتر حسابات.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<_ReportPeriod>(
                        initialValue: period,
                        decoration:
                            const InputDecoration(labelText: 'فترة التقرير'),
                        items: [
                          for (final value in _ReportPeriod.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _changePeriod(value);
                        },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copySummary(report),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('نسخ ملخص التقرير'),
                    ),
                    IconButton.filledTonal(
                      onPressed: _refresh,
                      tooltip: 'تحديث البيانات',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    final columns = constraints.maxWidth >= 1100
                        ? 4
                        : constraints.maxWidth >= 650
                            ? 2
                            : 1;
                    final width =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        _ReportMetricCard(
                          width: width,
                          title: 'مبيعات الفترة',
                          value: lyd(report.salesTotal),
                          subtitle:
                              '${report.deliveredOrderCount} طلبات مسلّمة',
                          icon: Icons.payments_outlined,
                          color: AppTheme.green,
                        ),
                        _ReportMetricCard(
                          width: width,
                          title: 'متوسط الطلب المسلّم',
                          value: lyd(report.averageOrderValue),
                          subtitle:
                              '${report.periodOrderCount} طلبات بكل الحالات',
                          icon: Icons.analytics_outlined,
                          color: AppTheme.darkGreen,
                        ),
                        _ReportMetricCard(
                          width: width,
                          title: 'طلبات ملغاة',
                          value: '${report.cancelledOrderCount}',
                          subtitle: period.label,
                          icon: Icons.cancel_outlined,
                          color: AppTheme.red,
                        ),
                        _ReportMetricCard(
                          width: width,
                          title: 'أرصدة مرجعية مسجلة',
                          value: lyd(report.outstandingBalance),
                          subtitle:
                              '${report.outstandingCustomers.length} عملاء — إدخال يدوي',
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppTheme.orange,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final panels = [
                      _ReportPanel(
                        title: 'أفضل العملاء حسب المبيعات',
                        icon: Icons.groups_outlined,
                        child: _TopCustomers(rows: report.topCustomers),
                      ),
                      _ReportPanel(
                        title: 'أفضل المنتجات حسب الكمية',
                        icon: Icons.inventory_2_outlined,
                        child: _TopProducts(rows: report.topProducts),
                      ),
                    ];
                    if (constraints.maxWidth < 900) {
                      return Column(
                        children: [
                          panels[0],
                          const SizedBox(height: 12),
                          panels[1],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: panels[0]),
                        const SizedBox(width: 12),
                        Expanded(child: panels[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final panels = [
                      _ReportPanel(
                        title: 'تنبيه المخزون',
                        icon: Icons.warning_amber_outlined,
                        child: _LowStock(rows: report.lowStockProducts),
                      ),
                      _ReportPanel(
                        title: 'الأرصدة المسجلة يدوياً',
                        icon: Icons.request_quote_outlined,
                        helper:
                            'مرجع تشغيلي فقط؛ لا توجد فواتير أو مدفوعات تلقائية ضمن هذا الإصدار.',
                        child: _OutstandingBalances(
                            rows: report.outstandingCustomers),
                      ),
                    ];
                    if (constraints.maxWidth < 900) {
                      return Column(
                        children: [
                          panels[0],
                          const SizedBox(height: 12),
                          panels[1],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: panels[0]),
                        const SizedBox(width: 12),
                        Expanded(child: panels[1]),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _copySummary(AdminReportData report) async {
    final lines = [
      'تقرير ${period.label}',
      'مبيعات الفترة: ${lyd(report.salesTotal)}',
      'الطلبات المسلمة: ${report.deliveredOrderCount}',
      'إجمالي الطلبات: ${report.periodOrderCount}',
      'متوسط الطلب المسلّم: ${lyd(report.averageOrderValue)}',
      'الطلبات الملغاة: ${report.cancelledOrderCount}',
      'الأرصدة المرجعية المسجلة يدوياً: ${lyd(report.outstandingBalance)}',
      '',
      'أفضل العملاء:',
      if (report.topCustomers.isEmpty)
        '- لا توجد مبيعات مسلمة في هذه الفترة'
      else
        for (final row in report.topCustomers.take(5))
          '- ${row.businessName}: ${lyd(row.salesTotal)} (${row.orderCount} طلب)',
      '',
      'أفضل المنتجات:',
      if (report.topProducts.isEmpty)
        '- لا توجد مبيعات مسلمة في هذه الفترة'
      else
        for (final row in report.topProducts.take(5))
          '- ${row.productName}: ${row.quantity} وحدة — ${lyd(row.salesTotal)}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ ملخص التقرير.')),
    );
  }
}

enum _ReportPeriod {
  today('اليوم'),
  sevenDays('آخر 7 أيام'),
  thirtyDays('آخر 30 يوماً'),
  ninetyDays('آخر 90 يوماً'),
  all('كل البيانات');

  const _ReportPeriod(this.label);

  final String label;

  DateTime? startAt(DateTime now) {
    DateTime startOfDay(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    return switch (this) {
      _ReportPeriod.today => startOfDay(now),
      _ReportPeriod.sevenDays =>
        startOfDay(now.subtract(const Duration(days: 6))),
      _ReportPeriod.thirtyDays =>
        startOfDay(now.subtract(const Duration(days: 29))),
      _ReportPeriod.ninetyDays =>
        startOfDay(now.subtract(const Duration(days: 89))),
      _ReportPeriod.all => null,
    };
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final double width;
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.title,
    required this.icon,
    required this.child,
    this.helper,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            if (helper != null) ...[
              const SizedBox(height: 6),
              Text(
                helper!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade700),
              ),
            ],
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}

class _TopCustomers extends StatelessWidget {
  const _TopCustomers({required this.rows});

  final List<AdminCustomerReportRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyReport(message: 'لا توجد طلبات مسلمة في هذه الفترة.');
    }
    return Column(
      children: [
        for (final indexed in rows.take(10).indexed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              child: Text('${indexed.$1 + 1}'),
            ),
            title: Text(indexed.$2.businessName),
            subtitle: Text('${indexed.$2.orderCount} طلب مسلّم'),
            trailing: Text(
              lyd(indexed.$2.salesTotal),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
      ],
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.rows});

  final List<AdminProductReportRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyReport(message: 'لا توجد منتجات مباعة في هذه الفترة.');
    }
    return Column(
      children: [
        for (final indexed in rows.take(10).indexed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              child: Text('${indexed.$1 + 1}'),
            ),
            title: Text(indexed.$2.productName),
            subtitle: Text(
              '${indexed.$2.sku} • ${indexed.$2.quantity} وحدة',
            ),
            trailing: Text(
              lyd(indexed.$2.salesTotal),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
      ],
    );
  }
}

class _LowStock extends StatelessWidget {
  const _LowStock({required this.rows});

  final List<AdminInventoryReportRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyReport(message: 'لا توجد تنبيهات مخزون حالياً.');
    }
    return Column(
      children: [
        for (final row in rows.take(20))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              row.availableQuantity == 0
                  ? Icons.error_outline
                  : Icons.warning_amber_outlined,
              color:
                  row.availableQuantity == 0 ? AppTheme.red : AppTheme.orange,
            ),
            title: Text(row.productName),
            subtitle: Text(row.sku),
            trailing: Text(
              row.availableQuantity == 0
                  ? 'غير متوفر'
                  : '${row.availableQuantity} متاح',
              style: TextStyle(
                color:
                    row.availableQuantity == 0 ? AppTheme.red : AppTheme.orange,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }
}

class _OutstandingBalances extends StatelessWidget {
  const _OutstandingBalances({required this.rows});

  final List<AdminBalanceReportRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyReport(message: 'لا توجد أرصدة يدوية مسجلة.');
    }
    return Column(
      children: [
        for (final row in rows.take(20))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront_outlined),
            title: Text(row.businessName),
            subtitle: Text('حد ائتمان مرجعي: ${lyd(row.creditLimit)}'),
            trailing: Text(
              lyd(row.outstandingBalance),
              style: const TextStyle(
                color: AppTheme.red,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      ),
    );
  }
}

class _ReportsLoadError extends StatelessWidget {
  const _ReportsLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 52),
            const SizedBox(height: 12),
            Text(
              'تعذر تحميل التقارير',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text('تحقق من الاتصال بالخادم ثم أعد المحاولة.'),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
