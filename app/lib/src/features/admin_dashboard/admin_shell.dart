import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';

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
    final nav = _AdminNav(
        onLogout: () => ref.read(authControllerProvider.notifier).logout());
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: wide
            ? null
            : Builder(
                builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer())),
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => _showNotificationsPlaceholder(context),
            icon: const Badge(
                label: Text('1'), child: Icon(Icons.notifications_outlined)),
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
          Expanded(child: child),
        ],
      ),
    );
  }

  void _showNotificationsPlaceholder(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => const Padding(
        padding: EdgeInsets.all(18),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الإشعارات',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              SizedBox(height: 12),
              ListTile(
                  leading: Icon(Icons.receipt_long),
                  title: Text('طلب جديد'),
                  subtitle:
                      Text('سيتم ربط تنبيهات FCM هنا عند إضافة Firebase.')),
            ]),
      ),
    );
  }
}

class _AdminNav extends StatelessWidget {
  const _AdminNav({required this.onLogout});
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final current = GoRouterState.of(context).matchedLocation;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(22)),
            child: const Row(children: [
              CircleAvatar(
                  backgroundColor: AppTheme.green,
                  child: Icon(Icons.pets, color: Colors.white)),
              SizedBox(width: 10),
              Expanded(
                  child: Text('Animal Supply B2B\nلوحة العمليات',
                      style: TextStyle(fontWeight: FontWeight.w900))),
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
          _NavTile(
              path: '/admin/settings',
              current: current,
              icon: Icons.settings_outlined,
              label: 'الإعدادات والتحديثات'),
          const Divider(height: 28),
          ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('واجهة العميل'),
              onTap: () => context.go('/home')),
          ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('خروج'),
              onTap: onLogout),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final selected = current == path;
    return ListTile(
      selected: selected,
      selectedTileColor: AppTheme.green.withValues(alpha: .12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(icon, color: selected ? AppTheme.green : null),
      title: Text(label,
          style: TextStyle(
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
      onTap: () => context.go(path),
    );
  }
}
