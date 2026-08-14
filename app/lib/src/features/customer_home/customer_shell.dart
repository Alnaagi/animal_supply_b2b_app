import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/connectivity/connectivity_provider.dart';
import '../../core/notifications/push_notifications.dart';
import '../../core/support/whatsapp_support.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/sync/outbox_retry_coordinator.dart';
import '../../data/sync/sync_outbox.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_controller.dart';

class CustomerShell extends ConsumerWidget {
  const CustomerShell({required this.shell, super.key});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep connectivity-triggered place-order outbox flush alive for customers.
    ref.watch(outboxRetryCoordinatorProvider);
    final user = ref.watch(authControllerProvider).user;
    final settings = ref.watch(appSettingsProvider).asData?.value;
    final shopName = settings?.shopName.trim().isNotEmpty == true
        ? settings!.shopName.trim()
        : AppConfig.shopName;
    final supportPhone = settings?.supportWhatsapp.trim().isNotEmpty == true
        ? settings!.supportWhatsapp
        : AppConfig.supportWhatsapp;
    ref.listen<OutboxSyncNotice?>(outboxSyncNoticeProvider, (previous, next) {
      if (next == null ||
          next.ownerProfileId != user?.id ||
          identical(previous, next)) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إرسال الطلب المحفوظ ${next.orderNumber} واعتماده بنجاح.',
          ),
        ),
      );
    });
    final online = ref.watch(
      connectivityProvider.select((async) => async.value ?? true),
    );
    final cartCount = ref.watch(
      cartControllerProvider.select(
        (items) => items.fold<int>(0, (sum, item) => sum + item.quantity),
      ),
    );
    final queuedOrderCount = user == null
        ? 0
        : ref
                .watch(customerOrderOutboxProvider(user.id))
                .asData
                ?.value
                .totalCount ??
            0;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: WhatsAppSupport.isConfiguredFor(supportPhone)
            ? IconButton(
                tooltip: 'الدعم عبر واتساب',
                icon: const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  color: Color(0xff25d366),
                ),
                onPressed: () async {
                  final opened = await WhatsAppSupport.openMessage(
                    'مرحباً، أحتاج مساعدة في تطبيق $shopName.',
                    phone: supportPhone,
                  );
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تعذر فتح واتساب حالياً'),
                      ),
                    );
                  }
                },
              )
            : null,
        title: Text(shopName),
        actions: [
          IconButton(
              onPressed: () => ref
                  .read(pushNotificationsCoordinatorProvider)
                  .signOut(ref.read(authControllerProvider.notifier)),
              icon: const Icon(Icons.logout),
              tooltip: 'خروج'),
        ],
      ),
      body: Column(
        children: [
          if (AppConfig.isDemoMode || user?.isDemo == true)
            const DemoModeNotice(),
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
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: queuedOrderCount > 0,
                  label: Text('$queuedOrderCount'),
                  child: const Icon(Icons.receipt_long_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: queuedOrderCount > 0,
                  label: Text('$queuedOrderCount'),
                  child: const Icon(
                    Icons.receipt_long,
                    color: AppTheme.green,
                  ),
                ),
                label: 'الطلبات',
              ),
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

class DemoModeNotice extends StatelessWidget {
  const DemoModeNotice({super.key});

  static const message =
      'وضع تجريبي — البيانات والأسعار والطلبات للعرض فقط وغير حقيقية.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('customer-demo-mode-notice'),
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
