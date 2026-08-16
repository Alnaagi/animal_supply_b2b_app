import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/app_runtime_mode.dart';
import '../../core/config/shop_branding.dart';
import '../../core/notifications/browser_notification_permission_banner.dart';
import '../../core/notifications/in_app_notification_poller.dart';
import '../../core/notifications/push_notifications.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/network_status.dart';
import '../../core/widgets/shop_brand_logo.dart';
import '../../data/repositories/notifications_repository.dart';
import '../auth/auth_controller.dart';
import '../notifications/notification_center_sheet.dart';
import 'pending_orders_kpi_alert.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell(
      {required this.title,
      required this.child,
      this.actions = const [],
      super.key});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final user = ref.watch(authControllerProvider).user;
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    final nav = _AdminNav(
      isAdmin: user?.isAdmin == true,
      onLogout: () => ref
          .read(pushNotificationsCoordinatorProvider)
          .signOut(ref.read(authControllerProvider.notifier)),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: wide
            ? null
            : Builder(
                builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: 'فتح قائمة الإدارة',
                    onPressed: () => Scaffold.of(context).openDrawer())),
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => showNotificationCenter(context, ref),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          ...actions,
        ],
      ),
      drawer: wide ? null : Drawer(child: nav),
      body: Row(
        children: [
          if (wide)
            SizedBox(
                width: 270, child: Material(color: Colors.white, child: nav)),
          Expanded(
            child: Column(
              children: [
                if (AppConfig.isDemoMode ||
                    ref.watch(appRuntimeModeProvider) ||
                    user?.isDemo == true)
                  const AdminDemoModeNotice(),
                const NetworkStatusHeader(),
                const BrowserNotificationPermissionBanner(),
                const InAppNotificationPoller(adminOrdersOnly: true),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminDemoModeNotice extends StatelessWidget {
  const AdminDemoModeNotice({super.key});

  static const message =
      'وضع تجريبي — بيانات الإدارة والطلبات والتغييرات محلية وغير تشغيلية.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('admin-demo-mode-notice'),
          width: double.infinity,
          color: Colors.blueGrey.shade800,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminNav extends ConsumerWidget {
  const _AdminNav({required this.isAdmin, required this.onLogout});
  final bool isAdmin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = GoRouterState.of(context).matchedLocation;
    final branding = ref.watch(shopBrandingProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              ShopBrandLogo(
                logoUrl: branding.logoUrl,
                size: 52,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${branding.shopName}\nلوحة العمليات',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _NavTile(
              path: '/admin',
              current: current,
              icon: Icons.dashboard_outlined,
              label: 'الرئيسية'),
          _NavTile(
              path: '/admin/customers',
              current: current,
              icon: Icons.groups_outlined,
              label: 'العملاء'),
          _NavTile(
              path: '/admin/products',
              current: current,
              icon: Icons.inventory_2_outlined,
              label: 'المنتجات'),
          if (isAdmin)
            _NavTile(
                path: '/admin/banners',
                current: current,
                icon: Icons.view_carousel_outlined,
                label: 'البانرات'),
          _NavTile(
              path: '/admin/orders',
              current: current,
              icon: Icons.receipt_long_outlined,
              label: 'الطلبات'),
          _NavTile(
              path: '/admin/archive',
              current: current,
              icon: Icons.archive_outlined,
              label: 'الأرشيف'),
          if (isAdmin)
            _NavTile(
                path: '/admin/notifications',
                current: current,
                icon: Icons.campaign_outlined,
                label: 'إرسال الإشعارات'),
          if (isAdmin)
            _NavTile(
                path: '/admin/reports',
                current: current,
                icon: Icons.analytics_outlined,
                label: 'التقارير التشغيلية'),
          if (isAdmin)
            _NavTile(
                path: '/admin/settings',
                current: current,
                icon: Icons.settings_outlined,
                label: 'الإعدادات والتحديثات'),
          const Divider(height: 28),
          ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('خروج'),
              onTap: onLogout),
        ],
      ),
    );
  }
}

class _NavTile extends ConsumerWidget {
  const _NavTile(
      {required this.path,
      required this.current,
      required this.icon,
      required this.label});
  final String path;
  final String current;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = current == path;
    return ListTile(
      selected: selected,
      selectedTileColor: AppTheme.green.withValues(alpha: .12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(icon, color: selected ? AppTheme.green : null),
      title: Text(label,
          style: TextStyle(
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
      onTap: () {
        if (path == '/admin/orders') {
          unawaited(
            openAdminOrders(ref, (next) => context.go(next), location: path),
          );
          return;
        }
        context.go(path);
      },
    );
  }
}
