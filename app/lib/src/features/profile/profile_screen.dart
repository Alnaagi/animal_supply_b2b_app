import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final rows = {
      'اسم النشاط': user.businessName ?? 'عميل تجريبي',
      'الشخص المسؤول': 'محمد علي',
      'الهاتف': '+218910000001',
      'المدينة/المنطقة': 'طرابلس - حي الأندلس',
      'العنوان': 'عنوان العميل التجاري',
      'مجموعة الأسعار': 'جملة',
      'حد الائتمان': 'سيضاف لاحقاً',
      'الرصيد المستحق': 'سيضاف لاحقاً',
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
              const Text('حساب عميل جملة نشط'),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        ...rows.entries.map((e) =>
            Card(child: ListTile(title: Text(e.key), subtitle: Text(e.value)))),
        OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.chat),
            label: const Text('الدعم عبر واتساب ${AppConfig.supportWhatsapp}')),
        FilledButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل خروج')),
      ],
    );
  }
}
