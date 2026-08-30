import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final details = <_ProfileInfoData>[
      _ProfileInfoData(
        keyName: 'business-name',
        icon: Icons.storefront_outlined,
        label: 'اسم المتجر',
        value: user.businessName ?? user.username,
      ),
      if (user.fullName?.trim().isNotEmpty == true)
        _ProfileInfoData(
          keyName: 'contact-name',
          icon: Icons.badge_outlined,
          label: 'الشخص المسؤول',
          value: user.fullName!,
        ),
      if (user.phone?.trim().isNotEmpty == true)
        _ProfileInfoData(
          keyName: 'phone',
          icon: Icons.phone_outlined,
          label: 'الهاتف',
          value: user.phone!,
        ),
      if (user.city?.trim().isNotEmpty == true ||
          user.area?.trim().isNotEmpty == true)
        _ProfileInfoData(
          keyName: 'location',
          icon: Icons.location_on_outlined,
          label: 'المدينة والمنطقة',
          value: [
            if (user.city?.trim().isNotEmpty == true) user.city!,
            if (user.area?.trim().isNotEmpty == true) user.area!,
          ].join(' - '),
        ),
      if (user.address?.trim().isNotEmpty == true)
        _ProfileInfoData(
          keyName: 'address',
          icon: Icons.map_outlined,
          label: 'العنوان',
          value: user.address!,
        ),
    ];
    final whatsappConfigured = WhatsAppSupport.isConfiguredFor(supportPhone);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('customer-profile-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _ProfileHeroCard(
          businessName: user.businessName ?? user.username,
          contactName: user.fullName,
          isDemo: user.isDemo,
        ),
        const SizedBox(height: 12),
        _ProfileDetailsCard(
          details: details,
          onRefresh: AppConfig.remoteBackendEnabled
              ? () =>
                  ref.read(authControllerProvider.notifier).retrySessionCheck()
              : null,
        ),
        const SizedBox(height: 12),
        const PushPermissionCard(),
        const SizedBox(height: 16),
        const _ProfileSectionTitle(
          title: 'المساعدة والخدمات',
          icon: Icons.grid_view_rounded,
        ),
        const SizedBox(height: 9),
        _ProfileServiceActions(
          onSupport: () => context.push('/support'),
          whatsappLabel: whatsappConfigured
              ? WhatsAppSupport.displayPhoneFor(supportPhone)
              : 'غير مهيأ',
          onWhatsApp: whatsappConfigured
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
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          key: const Key('customer-profile-sign-out'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: scheme.error,
            side: BorderSide(
              color: scheme.error.withValues(alpha: .5),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          onPressed: () => ref
              .read(pushNotificationsCoordinatorProvider)
              .signOut(ref.read(authControllerProvider.notifier)),
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'),
        ),
        const SizedBox(height: 10),
        Text(
          'باستخدام التطبيق أنت توافق على سياسة الخصوصية والأحكام المعتمدة لدى $shopName.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: .55),
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.businessName,
    required this.contactName,
    required this.isDemo,
  });

  final String businessName;
  final String? contactName;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('customer-profile-hero'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            scheme.primary,
            scheme.secondary,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .28),
              ),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                if (contactName?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    contactName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .78),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDemo
                          ? const Color(0xffffd88a).withValues(alpha: .2)
                          : Colors.white.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDemo
                              ? Icons.science_outlined
                              : Icons.verified_rounded,
                          color: isDemo
                              ? const Color(0xffffd88a)
                              : const Color(0xffb9f2d9),
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            isDemo
                                ? 'حساب تجريبي — بيانات غير حقيقية'
                                : 'حساب جملة نشط',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetailsCard extends StatelessWidget {
  const _ProfileDetailsCard({
    required this.details,
    required this.onRefresh,
  });

  final List<_ProfileInfoData> details;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('customer-profile-details'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: .08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ProfileSectionTitle(
            title: 'بيانات الحساب',
            icon: Icons.account_circle_outlined,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 360;
              final spacing = isCompact ? 8.0 : 9.0;
              final tileWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (var i = 0; i < details.length; i++)
                    SizedBox(
                      width: (details.length % 2 != 0 && i == details.length - 1)
                          ? constraints.maxWidth
                          : tileWidth,
                      child: _ProfileInfoTile(
                        detail: details[i],
                        isCompact: isCompact,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const Key('customer-profile-refresh'),
            onPressed: onRefresh,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'تحديث بيانات الحساب والأسعار',
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoTile extends StatelessWidget {
  const _ProfileInfoTile({
    required this.detail,
    this.isCompact = false,
  });

  final _ProfileInfoData detail;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('customer-profile-info-${detail.keyName}'),
      constraints: BoxConstraints(minHeight: isCompact ? 70 : 78),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 9 : 11,
        vertical: isCompact ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isCompact ? 30 : 34,
            height: isCompact ? 30 : 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              detail.icon,
              color: scheme.primary,
              size: isCompact ? 16 : 18,
            ),
          ),
          SizedBox(width: isCompact ? 7 : 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  detail.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: .58),
                    fontSize: isCompact ? 10.5 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: isCompact ? 12 : 13,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: scheme.primary, size: 20),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileServiceActions extends StatelessWidget {
  const _ProfileServiceActions({
    required this.onSupport,
    required this.whatsappLabel,
    required this.onWhatsApp,
  });

  final VoidCallback onSupport;
  final String whatsappLabel;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('customer-profile-services'),
      builder: (context, constraints) {
        final support = _ProfileActionCard(
          icon: Icons.support_agent_rounded,
          title: 'مركز المساعدة',
          subtitle: 'الأسئلة الشائعة والدعم',
          onTap: onSupport,
        );
        final whatsapp = _ProfileActionCard(
          icon: Icons.chat_rounded,
          title: 'واتساب الدعم',
          subtitle: whatsappLabel,
          onTap: onWhatsApp,
        );
        if (constraints.maxWidth < 340) {
          return Column(
            children: [
              support,
              const SizedBox(height: 10),
              whatsapp,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: support),
            const SizedBox(width: 10),
            Expanded(child: whatsapp),
          ],
        );
      },
    );
  }
}

class _ProfileActionCard extends StatelessWidget {
  const _ProfileActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? .55 : 1,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: .08),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: scheme.primary, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: .6),
                          fontSize: 10.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_left_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileInfoData {
  const _ProfileInfoData({
    required this.keyName,
    required this.icon,
    required this.label,
    required this.value,
  });

  final String keyName;
  final IconData icon;
  final String label;
  final String value;
}
