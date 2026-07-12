import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/order_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models/order.dart';
import '../../data/repositories/orders_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  OrderStatus? filter;
  int refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'إدارة الطلبات',
      child: FutureBuilder<List<Order>>(
        key: ValueKey(refreshKey),
        future: ref.read(ordersRepositoryProvider).allOrders(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Order>[];
          final orders = filter == null
              ? all
              : all.where((order) => order.status == filter).toList();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                    label: const Text('الكل'),
                    selected: filter == null,
                    onSelected: (_) => setState(() => filter = null)),
                for (final status in OrderStatus.values)
                  ChoiceChip(
                      label: Text(status.label),
                      selected: filter == status,
                      onSelected: (_) => setState(() => filter = status)),
              ]),
              const SizedBox(height: 14),
              if (orders.isEmpty)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.receipt_long),
                        title: Text('لا توجد طلبات بهذا الفلتر')))
              else
                for (final order in orders)
                  Card(
                    child: ExpansionTile(
                      leading: const CircleAvatar(
                          backgroundColor: AppTheme.green,
                          child: Icon(Icons.receipt_long, color: Colors.white)),
                      title: Text('طلب ${order.id}',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(
                          '${order.items.length} منتجات • ${lyd(order.total)} • ${order.createdAt.year}/${order.createdAt.month}/${order.createdAt.day}'),
                      trailing: StatusChip.order(order.status),
                      children: [
                        for (final item in order.items)
                          ListTile(
                            title: Text(item.product.name),
                            subtitle: Text(item.product.sku),
                            trailing: Text(
                                '${item.quantity} × ${lyd(item.product.price)}'),
                          ),
                        ListTile(
                            title: const Text('ملاحظة العميل'),
                            subtitle: Text(order.customerNote.isEmpty
                                ? 'لا توجد'
                                : order.customerNote)),
                        ListTile(
                            title: const Text('ملاحظة الإدارة'),
                            subtitle: Text(order.adminNote.isEmpty
                                ? 'لا توجد'
                                : order.adminNote)),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.icon(
                                onPressed: () => _showStatusDialog(order),
                                icon: const Icon(Icons.edit_note),
                                label: const Text('تغيير الحالة')),
                            OutlinedButton.icon(
                                onPressed: () => _copySummary(order),
                                icon: const Icon(Icons.copy),
                                label: const Text('نسخ ملخص واتساب')),
                          ]),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showStatusDialog(Order order) async {
    var selected = order.status;
    final note = TextEditingController(text: order.adminNote);
    final saved = await showDialog<OrderStatus>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تغيير حالة الطلب'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<OrderStatus>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: [
                  for (final status in OrderStatus.values)
                    DropdownMenuItem(value: status, child: Text(status.label))
                ],
                onChanged: (value) => setDialogState(
                    () => selected = value ?? OrderStatus.pending),
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: note,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'ملاحظة الإدارة')),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final adminNote = note.text.trim();
    note.dispose();
    if (saved == null) return;
    await ref
        .read(ordersRepositoryProvider)
        .updateOrderStatus(order.id, saved.value, adminNote: adminNote);
    setState(() => refreshKey++);
  }

  Future<void> _copySummary(Order order) async {
    final summary =
        ref.read(ordersRepositoryProvider).whatsappSummary(order, 'عميل B2B');
    await Clipboard.setData(ClipboardData(text: summary));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم نسخ ملخص الطلب')));
    }
  }
}
