import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/order_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/order.dart';
import '../../data/repositories/orders_repository.dart';

enum AdminReportDetailKind {
  sales,
  averageOrder,
  cancelled,
  customers,
  products,
  inventory;

  String get titleAr => switch (this) {
        sales => 'مبيعات الفترة',
        averageOrder => 'متوسط الطلب المسلّم',
        cancelled => 'طلبات ملغاة',
        customers => 'أفضل العملاء',
        products => 'أفضل المنتجات',
        inventory => 'تنبيه المخزون',
      };

  bool get loadsOrders =>
      this == sales || this == averageOrder || this == cancelled;
}

Future<void> showAdminReportDetailSheet({
  required BuildContext context,
  required AdminReportDetailKind kind,
  required AdminReportData report,
  required String periodLabel,
  DateTime? from,
  DateTime? to,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: AdminReportDetailSheet(
          kind: kind,
          report: report,
          periodLabel: periodLabel,
          from: from,
          to: to,
        ),
      );
    },
  );
}

class AdminReportDetailSheet extends ConsumerStatefulWidget {
  const AdminReportDetailSheet({
    required this.kind,
    required this.report,
    required this.periodLabel,
    this.from,
    this.to,
    super.key,
  });

  final AdminReportDetailKind kind;
  final AdminReportData report;
  final String periodLabel;
  final DateTime? from;
  final DateTime? to;

  @override
  ConsumerState<AdminReportDetailSheet> createState() =>
      _AdminReportDetailSheetState();
}

class _AdminReportDetailSheetState
    extends ConsumerState<AdminReportDetailSheet> {
  late final Future<List<Order>>? ordersFuture;

  @override
  void initState() {
    super.initState();
    ordersFuture = widget.kind.loadsOrders ? _loadOrders() : null;
  }

  Future<List<Order>> _loadOrders() {
    final until = (widget.to ?? DateTime.now()).add(const Duration(seconds: 1));
    return ref
        .read(ordersRepositoryProvider)
        .ordersPage(
          statuses: widget.kind == AdminReportDetailKind.cancelled
              ? const [OrderStatus.cancelled]
              : const [OrderStatus.delivered],
          createdFrom: widget.from,
          createdUntil: until,
          pageSize: 100,
        )
        .then((page) => page.orders);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            key: const Key('admin-report-detail-sheet'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.kind.titleAr,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                _subtitle(),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              _SummaryBanner(kind: widget.kind, report: widget.report),
              const SizedBox(height: 12),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    return switch (widget.kind) {
      AdminReportDetailKind.sales =>
        'الطلبات المسلّمة في ${widget.periodLabel} — الإجمالي ${lyd(widget.report.salesTotal)}',
      AdminReportDetailKind.averageOrder =>
        'متوسط الطلب محسوب من الطلبات المسلّمة في ${widget.periodLabel}',
      AdminReportDetailKind.cancelled =>
        'الطلبات الملغاة في ${widget.periodLabel}',
      AdminReportDetailKind.customers =>
        'العملاء حسب المبيعات المسلّمة في ${widget.periodLabel}',
      AdminReportDetailKind.products =>
        'المنتجات حسب الكمية المباعة في ${widget.periodLabel}',
      AdminReportDetailKind.inventory =>
        'منتجات بكمية منخفضة أو غير متوفرة حالياً',
    };
  }

  Widget _body() {
    if (widget.kind.loadsOrders) {
      return FutureBuilder<List<Order>>(
        future: ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const _DetailEmpty(
              message: 'تعذر تحميل تفاصيل الطلبات. أعد المحاولة.',
            );
          }
          return _OrdersList(orders: snapshot.data ?? const []);
        },
      );
    }
    return switch (widget.kind) {
      AdminReportDetailKind.customers =>
        _CustomersList(rows: widget.report.topCustomers),
      AdminReportDetailKind.products =>
        _ProductsList(rows: widget.report.topProducts),
      AdminReportDetailKind.inventory =>
        _InventoryList(rows: widget.report.lowStockProducts),
      _ => const _DetailEmpty(message: 'لا توجد تفاصيل إضافية.'),
    };
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.kind, required this.report});

  final AdminReportDetailKind kind;
  final AdminReportData report;

  @override
  Widget build(BuildContext context) {
    final chips = switch (kind) {
      AdminReportDetailKind.sales => [
          _chip('المبيعات', lyd(report.salesTotal)),
          _chip('مسلّم', '${report.deliveredOrderCount} طلب'),
          _chip('متوسط الطلب', lyd(report.averageOrderValue)),
        ],
      AdminReportDetailKind.averageOrder => [
          _chip('متوسط الطلب', lyd(report.averageOrderValue)),
          _chip('المبيعات', lyd(report.salesTotal)),
          _chip('مسلّم', '${report.deliveredOrderCount} طلب'),
        ],
      AdminReportDetailKind.cancelled => [
          _chip('ملغى', '${report.cancelledOrderCount} طلب'),
          _chip('كل الحالات', '${report.periodOrderCount} طلب'),
        ],
      AdminReportDetailKind.customers => [
          _chip('عملاء', '${report.topCustomers.length}'),
          _chip('مبيعات مسلّمة', lyd(report.salesTotal)),
        ],
      AdminReportDetailKind.products => [
          _chip('منتجات', '${report.topProducts.length}'),
          _chip('مبيعات مسلّمة', lyd(report.salesTotal)),
        ],
      AdminReportDetailKind.inventory => [
          _chip('تنبيهات', '${report.lowStockProducts.length}'),
          _chip(
            'غير متوفر',
            '${report.lowStockProducts.where((row) => row.availableQuantity == 0).length}',
          ),
        ],
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.green.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.green.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kind == AdminReportDetailKind.averageOrder)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'يحسب المتوسط من المبيعات المسلّمة ÷ عدد الطلبات المسلّمة.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const _DetailEmpty(message: 'لا توجد طلبات ضمن هذا المؤشر.');
    }
    return ListView.separated(
      itemCount: orders.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final order = orders[index];
        final created =
            '${order.createdAt.year}/${order.createdAt.month}/${order.createdAt.day}';
        final phone = order.contactPhone.trim();
        final address = order.effectiveDeliveryAddress;
        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  order.businessName.trim().isEmpty
                      ? 'عميل B2B'
                      : order.businessName.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                lyd(order.total),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          subtitle: Text(
            '${order.displayNumber} • ${order.status.label} • $created',
          ),
          children: [
            if (phone.isNotEmpty)
              _metaRow(Icons.call_outlined, 'الهاتف', phone),
            if (address.isNotEmpty)
              _metaRow(Icons.place_outlined, 'التسليم', address),
            if (order.customerNote.trim().isNotEmpty)
              _metaRow(
                  Icons.notes_outlined, 'ملاحظة', order.customerNote.trim()),
            for (final item in order.items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.productName),
                subtitle: Text(
                  '${item.productSku} • ${item.quantity} × ${lyd(item.unitPrice)}',
                ),
                trailing: Text(lyd(item.lineTotal)),
              ),
            if (order.items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('لا توجد بنود محفوظة لهذا الطلب.'),
              ),
          ],
        );
      },
    );
  }

  Widget _metaRow(IconData icon, String label, String value) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: AppTheme.green),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(value),
    );
  }
}

class _CustomersList extends StatelessWidget {
  const _CustomersList({required this.rows});

  final List<AdminCustomerReportRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _DetailEmpty(
        message: 'لا توجد طلبات مسلمة في هذه الفترة.',
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = rows[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 16, child: Text('${index + 1}')),
          title: Text(
            row.businessName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${row.orderCount} طلب مسلّم${_salesShare(row.salesTotal, rows)}',
          ),
          trailing: Text(
            lyd(row.salesTotal),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );
      },
    );
  }
}

class _ProductsList extends StatelessWidget {
  const _ProductsList({required this.rows});

  final List<AdminProductReportRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _DetailEmpty(
        message: 'لا توجد منتجات مباعة في هذه الفترة.',
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = rows[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 16, child: Text('${index + 1}')),
          title: Text(
            row.productName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${row.sku} • ${row.quantity} وحدة${_productShare(row.salesTotal, rows)}',
          ),
          trailing: Text(
            lyd(row.salesTotal),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );
      },
    );
  }
}

class _InventoryList extends StatelessWidget {
  const _InventoryList({required this.rows});

  final List<AdminInventoryReportRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _DetailEmpty(message: 'لا توجد تنبيهات مخزون حالياً.');
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = rows[index];
        final empty = row.availableQuantity == 0;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            empty ? Icons.error_outline : Icons.warning_amber_outlined,
            color: empty ? AppTheme.red : AppTheme.orange,
          ),
          title: Text(
            row.productName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(row.sku),
          trailing: Text(
            empty ? 'غير متوفر' : '${row.availableQuantity} متاح',
            style: TextStyle(
              color: empty ? AppTheme.red : AppTheme.orange,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    );
  }
}

class _DetailEmpty extends StatelessWidget {
  const _DetailEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}

String _salesShare(double salesTotal, List<AdminCustomerReportRow> rows) {
  final total = rows.fold<double>(0, (sum, row) => sum + row.salesTotal);
  return _percentLabel(salesTotal, total);
}

String _productShare(double salesTotal, List<AdminProductReportRow> rows) {
  final total = rows.fold<double>(0, (sum, row) => sum + row.salesTotal);
  return _percentLabel(salesTotal, total);
}

String _percentLabel(double salesTotal, double total) {
  if (total <= 0) return '';
  final percent = ((salesTotal / total) * 100).round();
  return ' • $percent٪ من القائمة';
}
