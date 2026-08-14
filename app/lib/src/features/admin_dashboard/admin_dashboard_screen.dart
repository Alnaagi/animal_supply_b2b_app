import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import 'admin_shell.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int refreshKey = 0;

  Future<AdminDashboardData> _loadDashboard() async {
    final repository = ref.read(adminRepositoryProvider);
    if (repository.hasRemoteBackend) {
      return repository.dashboardData();
    }
    final results = await Future.wait<Object>([
      ref.read(catalogRepositoryProvider).products(),
      ref.read(ordersRepositoryProvider).allOrders(),
    ]);
    return repository.dashboardData(
      products: results[0] as List<Product>,
      orders: results[1] as List<Order>,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(
      authControllerProvider.select((state) => state.user?.isAdmin == true),
    );
    return AdminShell(
      title: 'لوحة الإدارة',
      child: FutureBuilder<AdminDashboardData>(
        key: ValueKey(refreshKey),
        future: _loadDashboard(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _AdminDashboardLoadError(
              onRetry: () => setState(() => refreshKey++),
            );
          }
          final data = snapshot.data ??
              const AdminDashboardData(
                stats: AdminDashboardStats(
                  totalCustomers: 0,
                  activeCustomers: 0,
                  pendingOrders: 0,
                  todayOrders: 0,
                  lowStockCount: 0,
                  monthSales: 0,
                ),
                pendingOrders: [],
                lowStockProducts: [],
              );
          final stats = data.stats;
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  final columns = constraints.maxWidth >= 1200
                      ? 6
                      : constraints.maxWidth >= 720
                          ? 3
                          : 2;
                  final cardWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _StatCard(
                          width: cardWidth,
                          label: 'العملاء',
                          value: '${stats.totalCustomers}',
                          icon: Icons.groups,
                          color: AppTheme.green,
                          onTap: () => context.go('/admin/customers')),
                      _StatCard(
                          width: cardWidth,
                          label: 'نشطين',
                          value: '${stats.activeCustomers}',
                          icon: Icons.verified_user,
                          color: AppTheme.darkGreen,
                          onTap: () => context.go('/admin/customers')),
                      _StatCard(
                          width: cardWidth,
                          label: 'طلبات معلقة',
                          value: '${stats.pendingOrders}',
                          icon: Icons.pending_actions,
                          color: AppTheme.orange,
                          onTap: () => context.go('/admin/orders')),
                      _StatCard(
                          width: cardWidth,
                          label: 'طلبات اليوم',
                          value: '${stats.todayOrders}',
                          icon: Icons.today_outlined,
                          color: AppTheme.brown,
                          onTap: () =>
                              context.go('/admin/orders?period=today')),
                      _StatCard(
                          width: cardWidth,
                          label: 'مخزون منخفض',
                          value: '${stats.lowStockCount}',
                          icon: Icons.warning_amber,
                          color: AppTheme.red,
                          onTap: () => context.go('/admin/products')),
                      _StatCard(
                          width: cardWidth,
                          label: 'مبيعات الشهر',
                          value: lyd(stats.monthSales),
                          icon: Icons.payments_outlined,
                          color: AppTheme.brown,
                          onTap: isAdmin
                              ? () => context.go('/admin/reports')
                              : null),
                    ],
                  );
                },
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
                      onPressed: () =>
                          context.go('/admin/products?action=create'),
                      icon: const Icon(Icons.add_box),
                      label: const Text('إضافة منتج')),
                  OutlinedButton.icon(
                      onPressed: () => context.go('/admin/orders'),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('متابعة الطلبات')),
                  if (isAdmin)
                    OutlinedButton.icon(
                        onPressed: () => context.go('/admin/reports'),
                        icon: const Icon(Icons.analytics_outlined),
                        label: const Text('التقارير')),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 850;
                final children = [
                  _Panel(
                      title: 'طلبات تحتاج مراجعة',
                      icon: Icons.receipt_long,
                      child: _PendingOrders(orders: data.pendingOrders)),
                  _Panel(
                      title: 'مخزون منخفض',
                      icon: Icons.inventory,
                      child: _LowStock(products: data.lowStockProducts)),
                ];
                return wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            for (final child in children)
                              Expanded(
                                  child: Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                          end: 12),
                                      child: child))
                          ])
                    : Column(children: children);
              }),
              if (isAdmin) ...[
                const SizedBox(height: 18),
                FutureBuilder<AppVersionInfo>(
                  future: ref.read(adminRepositoryProvider).latestVersion(),
                  builder: (context, versionSnapshot) {
                    final version = versionSnapshot.data;
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.system_update_alt,
                            color: AppTheme.green),
                        title: const Text('تحديثات التطبيق'),
                        subtitle: Text(version == null
                            ? 'جاهز لربط إصدار Android وإصدار iOS.'
                            : 'آخر إصدار Android: ${version.versionName} '
                                '(${version.versionCode})\n'
                                '${version.releaseNotes}'),
                        trailing: FilledButton(
                            onPressed: () => context.go('/admin/settings'),
                            child: const Text('الإعدادات')),
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AdminDashboardLoadError extends StatelessWidget {
  const _AdminDashboardLoadError({required this.onRetry});

  final VoidCallback onRetry;

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
              'تعذر تحميل لوحة الإدارة',
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

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      required this.width,
      this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
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
  final List<AdminDashboardOrderRow> orders;
  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const ListTile(title: Text('لا توجد طلبات معلقة حالياً'));
    }
    return Column(children: [
      for (final order in orders)
        ListTile(
          title: Text('طلب ${order.displayNumber}'),
          subtitle: Text(
            '${order.businessName} • ${order.itemCount} منتجات • '
            '${lyd(order.total)}',
          ),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => context.go('/admin/orders?order=${order.id}'),
        ),
    ]);
  }
}

class _LowStock extends StatelessWidget {
  const _LowStock({required this.products});
  final List<AdminInventoryReportRow> products;
  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const ListTile(title: Text('المخزون جيد حالياً'));
    }
    return Column(children: [
      for (final product in products)
        ListTile(
          title: Text(product.productName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(product.sku),
          trailing: Text('${product.availableQuantity}'),
          onTap: () => context.go('/admin/products'),
        ),
    ]);
  }
}
