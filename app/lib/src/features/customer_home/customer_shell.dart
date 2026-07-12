import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_controller.dart';

class CustomerShell extends ConsumerWidget {
  const CustomerShell({required this.shell, super.key});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider).value ?? true;
    final cartCount = ref
        .watch(cartControllerProvider)
        .fold<int>(0, (sum, item) => sum + item.quantity);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'واتساب',
          icon:
              const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xff25d366)),
          onPressed: () async {
            final phone =
                AppConfig.supportWhatsapp.replaceAll(RegExp(r'[^0-9]'), '');
            final message = Uri.encodeComponent(
                'مرحباً، أحتاج مساعدة في تطبيق ${AppConfig.shopName}.');
            final url = Uri.parse('https://wa.me/$phone?text=$message');
            final opened =
                await launchUrl(url, mode: LaunchMode.externalApplication);
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تعذر فتح واتساب حالياً')),
              );
            }
          },
        ),
        title: const Text('Animal Supply B2B'),
        actions: [
          IconButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout),
              tooltip: 'خروج'),
        ],
      ),
      body: Column(
        children: [
          if (!online)
            Container(
              width: double.infinity,
              color: Colors.amber.shade200,
              padding: const EdgeInsets.all(8),
              child: const Text('لا يوجد اتصال — سيتم حفظ التغييرات مؤقتاً',
                  textAlign: TextAlign.center),
            ),
          Expanded(child: shell),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: NavigationBar(
            backgroundColor: Colors.white,
            indicatorColor: AppTheme.green.withValues(alpha: .14),
            selectedIndex: shell.currentIndex,
            onDestinationSelected: shell.goBranch,
            destinations: [
              const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home, color: AppTheme.green),
                  label: 'الرئيسية'),
              const NavigationDestination(
                  icon: Icon(Icons.storefront_outlined),
                  selectedIcon: Icon(Icons.storefront, color: AppTheme.green),
                  label: 'المنتجات'),
              NavigationDestination(
                icon: Badge(
                    isLabelVisible: cartCount > 0,
                    label: Text('$cartCount'),
                    child: const Icon(Icons.shopping_cart_outlined)),
                selectedIcon: Badge(
                    isLabelVisible: cartCount > 0,
                    label: Text('$cartCount'),
                    child:
                        const Icon(Icons.shopping_cart, color: AppTheme.green)),
                label: 'السلة',
              ),
              const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long, color: AppTheme.green),
                  label: 'الطلبات'),
              const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person, color: AppTheme.green),
                  label: 'الحساب'),
            ],
          ),
        ),
      ),
    );
  }
}
