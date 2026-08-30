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
import '../../core/widgets/network_status.dart';
import '../../core/widgets/shop_brand_logo.dart';
import '../../data/repositories/notifications_repository.dart';
import '../auth/auth_controller.dart';
import '../admin_storefront/apply_storefront_theme_to_admin.dart';
import '../notifications/notification_center_sheet.dart';
import 'pending_orders_kpi_alert.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({
    required this.title,
    required this.child,
    this.actions = const [],
    this.compactForStorefrontBuilder = false,
    super.key,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final bool compactForStorefrontBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storefrontTheme = ref.watch(adminShellStorefrontThemeProvider);
    final shell = Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final user = ref.watch(authControllerProvider).user;
        final unread =
            ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
        final current = _matchedLocation(context);
        final storefrontBuilder = compactForStorefrontBuilder ||
            current.startsWith('/admin/storefront');
        final nav = _AdminNav(
          isAdmin: user?.isAdmin == true,
          compact: storefrontBuilder && wide,
          onLogout: () => ref
              .read(pushNotificationsCoordinatorProvider)
              .signOut(ref.read(authControllerProvider.notifier)),
        );
        // Storefront builder owns its chrome (toolbar / mobile header). An empty
        // sand AppBar above the demo notice created a large dead beige strip.
        return Scaffold(
          appBar: storefrontBuilder
              ? null
              : AppBar(
                  title: Text(title),
                  leading: wide
                      ? null
                      : Builder(
                          builder: (context) => IconButton(
                              icon: const Icon(Icons.menu),
                              tooltip: 'فتح قائمة الإدارة',
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer())),
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
                  width: storefrontBuilder ? 72 : 270,
                  child: Material(color: scheme.surface, child: nav),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (AppConfig.isDemoMode ||
                        ref.watch(appRuntimeModeProvider) ||
                        user?.isDemo == true)
                      const AdminDemoModeNotice(),
                    if (!storefrontBuilder) ...[
                      const NetworkStatusHeader(),
                      const BrowserNotificationPermissionBanner(),
                      const InAppNotificationPoller(adminOrdersOnly: true),
                    ],
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (storefrontTheme == null) return shell;
    return Theme(data: storefrontTheme, child: shell);
  }
}

String _matchedLocation(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return '';
  return GoRouterState.of(context).matchedLocation;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science_outlined, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.25,
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
  const _AdminNav({
    required this.isAdmin,
    required this.onLogout,
    this.compact = false,
  });
  final bool isAdmin;
  final VoidCallback onLogout;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = _matchedLocation(context);
    final branding = ref.watch(shopBrandingProvider);
    if (compact) {
      return SafeArea(
        key: const Key('admin-compact-nav-rail'),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: ShopBrandLogo(
                  logoUrl: branding.logoUrl,
                  size: 36,
                ),
              ),
            ),
            const Divider(height: 1),
            _CompactNavTile(
              path: '/admin',
              current: current,
              icon: Icons.dashboard_outlined,
              label: 'الرئيسية',
            ),
            _CompactNavTile(
              path: '/admin/customers',
              current: current,
              icon: Icons.groups_outlined,
              label: 'العملاء',
            ),
            _CompactNavTile(
              path: '/admin/products',
              current: current,
              icon: Icons.inventory_2_outlined,
              label: 'المنتجات',
            ),
            if (isAdmin)
              _CompactNavTile(
                path: '/admin/banners',
                current: current,
                icon: Icons.view_carousel_outlined,
                label: 'البانرات',
              ),
            if (isAdmin)
              _CompactNavTile(
                path: '/admin/storefront',
                current: current,
                icon: Icons.palette_outlined,
                label: 'تصميم المتجر',
              ),
            _CompactNavTile(
              path: '/admin/orders',
              current: current,
              icon: Icons.receipt_long_outlined,
              label: 'الطلبات',
            ),
            _CompactNavTile(
              path: '/admin/archive',
              current: current,
              icon: Icons.archive_outlined,
              label: 'الأرشيف',
            ),
            if (isAdmin)
              _CompactNavTile(
                path: '/admin/notifications',
                current: current,
                icon: Icons.campaign_outlined,
                label: 'الإشعارات',
              ),
            if (isAdmin)
              _CompactNavTile(
                path: '/admin/reports',
                current: current,
                icon: Icons.analytics_outlined,
                label: 'التقارير',
              ),
            if (isAdmin)
              _CompactNavTile(
                path: '/admin/settings',
                current: current,
                icon: Icons.settings_outlined,
                label: 'الإعدادات',
              ),
            const Divider(height: 16),
            IconButton(
              tooltip: 'خروج',
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
      );
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .10),
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
          if (isAdmin)
            _NavTile(
                path: '/admin/storefront',
                current: current,
                icon: Icons.palette_outlined,
                label: 'تصميم المتجر'),
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
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      selected: selected,
      selectedTileColor: primary.withValues(alpha: .12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(icon, color: selected ? primary : null),
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

class _CompactNavTile extends ConsumerWidget {
  const _CompactNavTile({
    required this.path,
    required this.current,
    required this.icon,
    required this.label,
  });

  final String path;
  final String current;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = current == path || current.startsWith('$path/');
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: () {
          if (path == '/admin/orders') {
            unawaited(
              openAdminOrders(ref, (next) => context.go(next), location: path),
            );
            return;
          }
          context.go(path);
        },
        icon: Icon(icon, color: selected ? primary : null),
        style: IconButton.styleFrom(
          backgroundColor: selected ? primary.withValues(alpha: .12) : null,
        ),
      ),
    );
  }
}
