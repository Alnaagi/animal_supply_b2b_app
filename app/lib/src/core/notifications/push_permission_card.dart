import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/app_config_validation.dart';
import '../theme/app_theme.dart';
import 'browser_local_notifications.dart';
import 'new_order_alert_sound.dart';
import 'push_notifications.dart';

class PushPermissionCard extends ConsumerStatefulWidget {
  const PushPermissionCard({super.key});

  @override
  ConsumerState<PushPermissionCard> createState() => _PushPermissionCardState();
}

class _PushPermissionCardState extends ConsumerState<PushPermissionCard> {
  late Future<PushNotificationPermissionState> _statusFuture;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _statusFuture =
        ref.read(pushNotificationsCoordinatorProvider).permissionState();
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    await ref.read(newOrderAlertSoundProvider).prime();
    final fcmEnabled = await ref
        .read(pushNotificationsCoordinatorProvider)
        .requestPermissionAndRegister();
    final browser = ref.read(browserLocalNotificationsProvider);
    var browserGranted = false;
    if (browser.isSupported) {
      browserGranted = await browser.requestPermission() ==
          BrowserNotificationPermission.granted;
    }
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _refresh();
    });
    final enabled = fcmEnabled || browserGranted;
    if (browserGranted) {
      await ref.read(browserLocalNotificationsProvider).show(
            title: 'تم تفعيل الإشعارات',
            body: 'ستظهر التنبيهات في شريط إشعارات الجهاز.',
            tag: 'browser-permission-granted',
          );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? (fcmEnabled
                  ? 'تم تفعيل الإشعارات الفورية لهذا الجهاز.'
                  : 'تم تفعيل تنبيهات شريط النظام. ${firebaseClosedAppRequirementAr(
                      configured:
                          AppConfig.hasFirebaseConfigurationForCurrentPlatform,
                    )}')
              : 'لم يتم منح الإذن. يمكنك تغييره من إعدادات الهاتف أو المتصفح.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PushNotificationPermissionState>(
      future: _statusFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final state =
            snapshot.data ?? PushNotificationPermissionState.unavailable;
        final presentation = _presentationFor(
          state,
          loading: loading,
          browserPermission:
              ref.read(browserLocalNotificationsProvider).permission(),
        );
        final browser = ref.read(browserLocalNotificationsProvider);
        final browserPermission = browser.permission();
        final browserCanRequest = browser.isSupported &&
            browserPermission != BrowserNotificationPermission.granted &&
            browserPermission != BrowserNotificationPermission.denied;
        final canRequest = !loading &&
            ((state != PushNotificationPermissionState.unavailable &&
                    state != PushNotificationPermissionState.authorized &&
                    state != PushNotificationPermissionState.provisional) ||
                browserCanRequest);
        return Card(
          key: const Key('push-permission-card'),
          color: presentation.color.withValues(alpha: .08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(presentation.icon, color: presentation.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        presentation.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(presentation.message),
                if (canRequest || snapshot.hasError) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('enable-push-notifications-button'),
                    onPressed: _requesting
                        ? null
                        : snapshot.hasError
                            ? () => setState(_refresh)
                            : _requestPermission,
                    icon: _requesting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            snapshot.hasError
                                ? Icons.refresh
                                : Icons.notifications_active_outlined,
                          ),
                    label: Text(
                      snapshot.hasError ? 'إعادة المحاولة' : 'تفعيل الإشعارات',
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  _PushPermissionPresentation _presentationFor(
    PushNotificationPermissionState state, {
    required bool loading,
    required BrowserNotificationPermission browserPermission,
  }) {
    if (loading) {
      return const _PushPermissionPresentation(
        title: 'جاري فحص حالة الإشعارات',
        message: 'لحظة واحدة…',
        icon: Icons.notifications_outlined,
        color: AppTheme.green,
      );
    }
    return switch (state) {
      PushNotificationPermissionState.authorized =>
        const _PushPermissionPresentation(
          title: 'الإشعارات الفورية مفعلة',
          message:
              'سيصل هذا الجهاز تحديث حالة الطلب والإعلانات الموجهة المهمة.',
          icon: Icons.notifications_active,
          color: AppTheme.green,
        ),
      PushNotificationPermissionState.provisional =>
        const _PushPermissionPresentation(
          title: 'الإشعارات مفعلة بهدوء',
          message:
              'قد تظهر بدون صوت حسب إعدادات الجهاز. يمكنك تعديلها من إعدادات النظام.',
          icon: Icons.notifications_paused_outlined,
          color: AppTheme.green,
        ),
      PushNotificationPermissionState.notDetermined =>
        const _PushPermissionPresentation(
          title: 'فعّل تنبيهات الطلب',
          message: 'اسمح بالإشعارات لتصلك كل مرحلة من تأكيد الطلب حتى التسليم.',
          icon: Icons.notifications_none,
          color: AppTheme.orange,
        ),
      PushNotificationPermissionState.denied =>
        const _PushPermissionPresentation(
          title: 'إذن الإشعارات غير مسموح',
          message:
              'فعّله من إعدادات الهاتف أو المتصفح حتى لا تفوتك تحديثات الطلب.',
          icon: Icons.notifications_off_outlined,
          color: AppTheme.red,
        ),
      PushNotificationPermissionState.unavailable =>
        _PushPermissionPresentation(
          title: browserPermission == BrowserNotificationPermission.granted
              ? 'تنبيهات شريط النظام مفعلة'
              : AppConfig.hasFirebaseConfigurationForCurrentPlatform
                  ? 'فعّل تنبيهات الطلب'
                  : 'فعّل تنبيهات شريط النظام',
          message: browserPermission == BrowserNotificationPermission.granted
              ? firebaseClosedAppRequirementAr(
                  configured:
                      AppConfig.hasFirebaseConfigurationForCurrentPlatform,
                )
              : AppConfig.hasFirebaseConfigurationForCurrentPlatform
                  ? 'الإشعارات داخل التطبيق متاحة. فعّل إذن المتصفح ليظهر التنبيه في شريط النظام.'
                  : firebaseClosedAppRequirementAr(configured: false),
          icon: browserPermission == BrowserNotificationPermission.granted
              ? Icons.notifications_active
              : Icons.notifications_none,
          color: browserPermission == BrowserNotificationPermission.granted
              ? AppTheme.green
              : AppTheme.orange,
        ),
    };
  }
}

class _PushPermissionPresentation {
  const _PushPermissionPresentation({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
}
