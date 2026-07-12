import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/order_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/orders_repository.dart';
import 'admin_shell.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminShell(
      title: 'لوحة الإدارة',
      child: FutureBuilder(
        future: Future.wait([
          ref.read(catalogRepositoryProvider).products(),
          ref.read(ordersRepositoryProvider).allOrders(),
        ]),
        builder: (context, snapshot) {
          final products = (snapshot.data?[0] ?? <Product>[]) as List<Product>;
          final orders = (snapshot.data?[1] ?? <Order>[]) as List<Order>;
          return FutureBuilder<AdminDashboardStats>(
            future: ref
                .read(adminRepositoryProvider)
                .dashboardStats(products, orders),
            builder: (context, statsSnapshot) {
              final stats = statsSnapshot.data ??
                  const AdminDashboardStats(
                      totalCustomers: 0,
                      activeCustomers: 0,
                      pendingOrders: 0,
                      todayOrders: 0,
                      lowStockCount: 0,
                      monthSales: 0);
              final lowStock = products
                  .where((product) => product.lowStock)
                  .take(5)
                  .toList();
              final pending = orders
                  .where((order) => order.status == OrderStatus.pending)
                  .take(5)
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StatCard(
                          label: 'العملاء',
                          value: '${stats.totalCustomers}',
                          icon: Icons.groups,
                          color: AppTheme.green,
                          onTap: () => context.go('/admin/customers')),
                      _StatCard(
                          label: 'نشطين',
                          value: '${stats.activeCustomers}',
                          icon: Icons.verified_user,
                          color: AppTheme.darkGreen,
                          onTap: () => context.go('/admin/customers')),
                      _StatCard(
                          label: 'طلبات معلقة',
                          value: '${stats.pendingOrders}',
                          icon: Icons.pending_actions,
                          color: AppTheme.orange,
                          onTap: () => context.go('/admin/orders')),
                      _StatCard(
                          label: 'مخزون منخفض',
                          value: '${stats.lowStockCount}',
                          icon: Icons.warning_amber,
                          color: AppTheme.red,
                          onTap: () => context.go('/admin/products')),
                      _StatCard(
                          label: 'مبيعات الشهر',
                          value: lyd(stats.monthSales),
                          icon: Icons.payments_outlined,
                          color: AppTheme.brown),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                          onPressed: () => context.go('/admin/customers'),
                          icon: const Icon(Icons.person_add),
                          label: const Text('إنشاء عميل ودعوة')),
                      FilledButton.tonalIcon(
                          onPressed: () => context.go('/admin/products'),
                          icon: const Icon(Icons.add_box),
                          label: const Text('إضافة منتج')),
                      OutlinedButton.icon(
                          onPressed: () => context.go('/admin/orders'),
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('متابعة الطلبات')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(builder: (context, constraints) {
                    final wide = constraints.maxWidth > 850;
                    final children = [
                      _Panel(
                          title: 'طلبات تحتاج مراجعة',
                          icon: Icons.receipt_long,
                          child: _PendingOrders(orders: pending)),
                      _Panel(
                          title: 'مخزون منخفض',
                          icon: Icons.inventory,
                          child: _LowStock(products: lowStock)),
                    ];
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                for (final child in children)
                                  Expanded(
                                      child: Padding(
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                  end: 12),
                                          child: child))
                              ])
                        : Column(children: children);
                  }),
                  const SizedBox(height: 18),
                  FutureBuilder<AppVersionInfo>(
                    future: ref.read(adminRepositoryProvider).latestVersion(),
                    builder: (context, versionSnapshot) {
                      final version = versionSnapshot.data;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.system_update_alt,
                              color: AppTheme.green),
                          title: const Text('تحديثات APK و Shorebird'),
                          subtitle: Text(version == null
                              ? 'جاهز لربط رابط APK وإشعارات التحديث.'
                              : 'آخر إصدار Android: ${version.versionName} (${version.versionCode})\n${version.releaseNotes}'),
                          trailing: FilledButton(
                              onPressed: () => context.go('/admin/settings'),
                              child: const Text('الإعدادات')),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                  backgroundColor: color.withValues(alpha: .12),
                  child: Icon(icon, color: color)),
              const SizedBox(height: 14),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              Text(label,
                  style: const TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: AppTheme.green),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18))
            ]),
            const SizedBox(height: 10),
            child,
          ]),
        ),
      );
}

class _PendingOrders extends StatelessWidget {
  const _PendingOrders({required this.orders});
  final List<Order> orders;
  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const ListTile(title: Text('لا توجد طلبات معلقة حالياً'));
    }
    return Column(children: [
      for (final order in orders)
        ListTile(
          title: Text(
              'طلب ${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length)}'),
          subtitle: Text('${order.items.length} منتجات • ${lyd(order.total)}'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => context.go('/admin/orders'),
        ),
    ]);
  }
}

class _LowStock extends StatelessWidget {
  const _LowStock({required this.products});
  final List<Product> products;
  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const ListTile(title: Text('المخزون جيد حالياً'));
    }
    return Column(children: [
      for (final product in products)
        ListTile(
          title:
              Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(product.sku),
          trailing: Text('${product.stockQuantity}'),
          onTap: () => context.go('/admin/products'),
        ),
    ]);
  }
}
