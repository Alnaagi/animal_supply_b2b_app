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
        final scheme = Theme.of(context).colorScheme;
        final loading = snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final state =
            snapshot.data ?? PushNotificationPermissionState.unavailable;
        final presentation = _presentationFor(
          state,
          loading: loading,
          primary: scheme.primary,
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
        return Material(
          key: const Key('push-permission-card'),
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: presentation.color.withValues(alpha: .18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: presentation.color.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        presentation.icon,
                        color: presentation.color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            presentation.title,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            presentation.message,
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: .68),
                              fontSize: 12.25,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (canRequest || snapshot.hasError) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonalIcon(
                      key: const Key('enable-push-notifications-button'),
                      onPressed: _requesting
                          ? null
                          : snapshot.hasError
                              ? () => setState(_refresh)
                              : _requestPermission,
                      icon: _requesting
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              snapshot.hasError
                                  ? Icons.refresh
                                  : Icons.notifications_active_outlined,
                              size: 18,
                            ),
                      label: Text(
                        snapshot.hasError
                            ? 'إعادة المحاولة'
                            : 'تفعيل الإشعارات',
                      ),
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
    required Color primary,
    required BrowserNotificationPermission browserPermission,
  }) {
    if (loading) {
      return _PushPermissionPresentation(
        title: 'جاري فحص حالة الإشعارات',
        message: 'لحظة واحدة…',
        icon: Icons.notifications_outlined,
        color: primary,
      );
    }
    return switch (state) {
      PushNotificationPermissionState.authorized =>
        _PushPermissionPresentation(
          title: 'الإشعارات الفورية مفعلة',
          message:
              'سيصل هذا الجهاز تحديث حالة الطلب والإعلانات الموجهة المهمة.',
          icon: Icons.notifications_active,
          color: primary,
        ),
      PushNotificationPermissionState.provisional =>
        _PushPermissionPresentation(
          title: 'الإشعارات مفعلة بهدوء',
          message:
              'قد تظهر بدون صوت حسب إعدادات الجهاز. يمكنك تعديلها من إعدادات النظام.',
          icon: Icons.notifications_paused_outlined,
          color: primary,
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
              ? primary
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
