import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/local/local_cache.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import 'admin_shell.dart';
import 'dashboard_fullness.dart';
import 'dashboard_widget_visibility.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int refreshKey = 0;

  Future<_LoadedDashboard> _loadDashboard() async {
    final repository = ref.read(adminRepositoryProvider);
    if (repository.hasRemoteBackend) {
      final results = await Future.wait<Object>([
        repository.dashboardData(),
        ref.read(localCacheProvider).cachedProducts(),
      ]);
      final cached = results[1] as List<Product>;
      return _LoadedDashboard(
        data: results[0] as AdminDashboardData,
        fullness: estimateDashboardFullness(
          demoOrOffline: false,
          productCount: cached.length,
        ),
      );
    }
    final results = await Future.wait<Object>([
      ref.read(catalogRepositoryProvider).products(),
      ref.read(ordersRepositoryProvider).allOrders(),
    ]);
    final products = results[0] as List<Product>;
    final orders = results[1] as List<Order>;
    return _LoadedDashboard(
      data: await repository.dashboardData(
        products: products,
        orders: orders,
      ),
      fullness: estimateDashboardFullness(
        demoOrOffline: true,
        productCount: products.length,
        orderCount: orders.length,
      ),
    );
  }

  Future<void> _openLayoutSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return const _DashboardLayoutSheet();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(
      authControllerProvider.select((state) => state.user?.isAdmin == true),
    );
    final visibility = ref.watch(dashboardWidgetVisibilityProvider);
    return AdminShell(
      title: 'لوحة الإدارة',
      actions: [
        IconButton(
          key: const Key('admin-dashboard-layout-settings'),
          tooltip: 'تخصيص عناصر اللوحة',
          icon: const Icon(Icons.settings),
          onPressed: _openLayoutSettings,
        ),
      ],
      child: FutureBuilder<_LoadedDashboard>(
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
          final loaded = snapshot.data ??
              const _LoadedDashboard(
                data: AdminDashboardData(
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
                ),
                fullness: DashboardFullnessEstimate(
                  percent: 0,
                  kind: DashboardFullnessKind.demoCatalog,
                  titleAr: 'امتلاء البيانات',
                  captionAr:
                      'تقدير تجريبي من الكتالوج والطلبات المحلية — غير تشغيلي',
                ),
              );
          final data = loaded.data;
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
                  final cards = <Widget>[
                    if (visibility.isVisible(DashboardWidgetId.customers))
                      _StatCard(
                          width: cardWidth,
                          label: 'العملاء',
                          value: '${stats.totalCustomers}',
                          icon: Icons.groups,
                          color: AppTheme.green,
                          onTap: () => context.go('/admin/customers')),
                    if (visibility.isVisible(DashboardWidgetId.activeCustomers))
                      _StatCard(
                          width: cardWidth,
                          label: 'نشطين',
                          value: '${stats.activeCustomers}',
                          icon: Icons.verified_user,
                          color: AppTheme.darkGreen,
                          onTap: () => context.go('/admin/customers')),
                    if (visibility
                        .isVisible(DashboardWidgetId.pendingOrdersStat))
                      _StatCard(
                          width: cardWidth,
                          label: 'طلبات معلقة',
                          value: '${stats.pendingOrders}',
                          icon: Icons.pending_actions,
                          color: AppTheme.orange,
                          onTap: () => context.go('/admin/orders')),
                    if (visibility.isVisible(DashboardWidgetId.todayOrders))
                      _StatCard(
                          width: cardWidth,
                          label: 'طلبات اليوم',
                          value: '${stats.todayOrders}',
                          icon: Icons.today_outlined,
                          color: AppTheme.brown,
                          onTap: () =>
                              context.go('/admin/orders?period=today')),
                    if (visibility.isVisible(DashboardWidgetId.lowStockStat))
                      _StatCard(
                          width: cardWidth,
                          label: 'مخزون منخفض',
                          value: '${stats.lowStockCount}',
                          icon: Icons.warning_amber,
                          color: AppTheme.red,
                          onTap: () => context.go('/admin/products')),
                    if (visibility.isVisible(DashboardWidgetId.monthSales))
                      _StatCard(
                          width: cardWidth,
                          label: 'مبيعات الشهر',
                          value: lyd(stats.monthSales),
                          icon: Icons.payments_outlined,
                          color: AppTheme.brown,
                          onTap: isAdmin
                              ? () => context.go('/admin/reports')
                              : null),
                    if (visibility.isVisible(DashboardWidgetId.dataFullness))
                      _FullnessCard(
                        width: cardWidth,
                        estimate: loaded.fullness,
                      ),
                  ];
                  if (cards.isEmpty) return const SizedBox.shrink();
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: cards,
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
                final children = <Widget>[
                  if (visibility
                      .isVisible(DashboardWidgetId.pendingOrdersPanel))
                    _Panel(
                        title: 'طلبات تحتاج مراجعة',
                        icon: Icons.receipt_long,
                        child: _PendingOrders(orders: data.pendingOrders)),
                  if (visibility.isVisible(DashboardWidgetId.lowStockPanel))
                    _Panel(
                        title: 'مخزون منخفض',
                        icon: Icons.inventory,
                        child: _LowStock(products: data.lowStockProducts)),
                ];
                if (children.isEmpty) return const SizedBox.shrink();
                return wide && children.length > 1
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
              if (isAdmin &&
                  visibility.isVisible(DashboardWidgetId.appUpdates)) ...[
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

class _LoadedDashboard {
  const _LoadedDashboard({required this.data, required this.fullness});

  final AdminDashboardData data;
  final DashboardFullnessEstimate fullness;
}

class _DashboardLayoutSheet extends ConsumerWidget {
  const _DashboardLayoutSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(dashboardWidgetVisibilityProvider);
    final isAdmin = ref.watch(
      authControllerProvider.select((state) => state.user?.isAdmin == true),
    );
    final statIds = [
      DashboardWidgetId.customers,
      DashboardWidgetId.activeCustomers,
      DashboardWidgetId.pendingOrdersStat,
      DashboardWidgetId.todayOrders,
      DashboardWidgetId.lowStockStat,
      DashboardWidgetId.monthSales,
      DashboardWidgetId.dataFullness,
    ];
    final panelIds = [
      DashboardWidgetId.pendingOrdersPanel,
      DashboardWidgetId.lowStockPanel,
      if (isAdmin) DashboardWidgetId.appUpdates,
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تخصيص عناصر اللوحة',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'أخفِ البطاقات غير المطلوبة. يُحفظ الاختيار على هذا الجهاز.',
                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                const Text(
                  'بطاقات الملخص',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                for (final id in statIds)
                  SwitchListTile(
                    key: Key('admin-dashboard-widget-toggle-${id.storageKey}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(id.labelAr),
                    value: visibility.isVisible(id),
                    onChanged: (value) => ref
                        .read(dashboardWidgetVisibilityProvider.notifier)
                        .setVisible(id, value),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'اللوحات السفلية',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                for (final id in panelIds)
                  SwitchListTile(
                    key: Key('admin-dashboard-widget-toggle-${id.storageKey}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(id.labelAr),
                    value: visibility.isVisible(id),
                    onChanged: (value) => ref
                        .read(dashboardWidgetVisibilityProvider.notifier)
                        .setVisible(id, value),
                  ),
              ],
            ),
          ),
        ),
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

class _FullnessCard extends StatelessWidget {
  const _FullnessCard({required this.width, required this.estimate});

  final double width;
  final DashboardFullnessEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final progress = estimate.percent.clamp(0, 100) / 100;
    return SizedBox(
      width: width,
      child: Card(
        key: const Key('admin-dashboard-fullness-card'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                estimate.titleAr,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        color: AppTheme.green,
                        backgroundColor:
                            AppTheme.green.withValues(alpha: 0.14),
                      ),
                    ),
                    Text(
                      '${estimate.percent}%',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (estimate.isDemoEstimate)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'تجريبي',
                    style: TextStyle(
                      color: AppTheme.darkGreen,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                estimate.captionAr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
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
