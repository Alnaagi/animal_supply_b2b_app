import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/notifications/push_notifications.dart';
import '../../core/notifications/push_permission_card.dart';
import '../../core/support/whatsapp_support.dart';
import '../../data/repositories/admin_repository.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final settings = ref.watch(appSettingsProvider).asData?.value;
    final shopName = ref.watch(shopBrandingProvider).shopName;
    final supportPhone = settings?.supportWhatsapp.trim().isNotEmpty == true
        ? settings!.supportWhatsapp
        : AppConfig.supportWhatsapp;
    final rows = {
      'اسم المتجر': user.businessName ?? user.username,
      if (user.fullName?.trim().isNotEmpty == true)
        'الشخص المسؤول': user.fullName!,
      if (user.phone?.trim().isNotEmpty == true) 'الهاتف': user.phone!,
      if (user.city?.trim().isNotEmpty == true ||
          user.area?.trim().isNotEmpty == true)
        'المدينة/المنطقة': [
          if (user.city?.trim().isNotEmpty == true) user.city!,
          if (user.area?.trim().isNotEmpty == true) user.area!,
        ].join(' - '),
      if (user.address?.trim().isNotEmpty == true) 'العنوان': user.address!,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              const CircleAvatar(
                  radius: 34, child: Icon(Icons.storefront, size: 34)),
              const SizedBox(height: 10),
              Text(user.businessName ?? user.username,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center),
              Text(
                user.isDemo
                    ? 'حساب عميل تجريبي — البيانات غير حقيقية'
                    : 'حساب عميل جملة نشط',
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        ...rows.entries.map((e) =>
            Card(child: ListTile(title: Text(e.key), subtitle: Text(e.value)))),
        OutlinedButton.icon(
          onPressed: AppConfig.remoteBackendEnabled
              ? () => ref
                  .read(authControllerProvider.notifier)
                  .retrySessionCheck()
              : null,
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث بيانات الحساب والأسعار'),
        ),
        const PushPermissionCard(),
        OutlinedButton.icon(
            onPressed: WhatsAppSupport.isConfiguredFor(supportPhone)
                ? () async {
                    final opened = await WhatsAppSupport.openMessage(
                      'مرحباً، أحتاج مساعدة بخصوص حسابي في '
                      '$shopName.',
                      phone: supportPhone,
                    );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تعذر فتح واتساب حالياً'),
                        ),
                      );
                    }
                  }
                : null,
            icon: const Icon(Icons.chat),
            label: Text(WhatsAppSupport.isConfiguredFor(supportPhone)
                ? 'الدعم عبر واتساب ${WhatsAppSupport.displayPhoneFor(supportPhone)}'
                : 'واتساب الدعم غير مهيأ')),
        FilledButton.icon(
            onPressed: () => ref
                .read(pushNotificationsCoordinatorProvider)
                .signOut(ref.read(authControllerProvider.notifier)),
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل خروج')),
      ],
    );
  }
}
