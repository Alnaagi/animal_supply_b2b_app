import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/browser_notification_prompt_store.dart';
import '../../data/models/app_user.dart';
import '../../features/auth/auth_controller.dart';
import '../config/app_config.dart';
import '../config/app_config_validation.dart';
import '../theme/app_theme.dart';
import 'browser_local_notifications.dart';
import 'new_order_alert_sound.dart';

class BrowserNotificationPermissionBanner extends ConsumerStatefulWidget {
  const BrowserNotificationPermissionBanner({super.key});

  @override
  ConsumerState<BrowserNotificationPermissionBanner> createState() =>
      _BrowserNotificationPermissionBannerState();
}

class _BrowserNotificationPermissionBannerState
    extends ConsumerState<BrowserNotificationPermissionBanner> {
  bool _visible = false;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_evaluate());
    });
  }

  Future<void> _evaluate() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null || user.isDemo) {
      if (mounted) setState(() => _visible = false);
      return;
    }
    final notifications = ref.read(browserLocalNotificationsProvider);
    if (!notifications.isSupported) {
      if (mounted) setState(() => _visible = false);
      return;
    }
    final permission = notifications.permission();
    if (permission == BrowserNotificationPermission.granted ||
        permission == BrowserNotificationPermission.unsupported) {
      if (mounted) setState(() => _visible = false);
      return;
    }
    if (permission == BrowserNotificationPermission.denied) {
      final dismissed =
          await ref.read(browserNotificationPromptStoreProvider).isDismissed();
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _visible = !dismissed;
      });
      return;
    }
    final dismissed =
        await ref.read(browserNotificationPromptStoreProvider).isDismissed();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _visible = !dismissed;
    });
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(newOrderAlertSoundProvider).prime();
      final permission = await ref
          .read(browserLocalNotificationsProvider)
          .requestPermission();
      if (permission == BrowserNotificationPermission.denied) {
        await ref.read(browserNotificationPromptStoreProvider).dismiss();
      }
      if (permission == BrowserNotificationPermission.granted) {
        await ref.read(browserLocalNotificationsProvider).show(
              title: 'تم تفعيل الإشعارات',
              body: 'ستظهر التنبيهات في شريط إشعارات الجهاز.',
              tag: 'browser-permission-granted',
            );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _visible = permission == BrowserNotificationPermission.notDetermined;
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            permission == BrowserNotificationPermission.granted
                ? 'تم تفعيل تنبيهات شريط النظام. ستظهر حتى والتاب في الخلفية.'
                : permission == BrowserNotificationPermission.denied
                    ? 'تم رفض الإذن. يمكنك تفعيله لاحقاً من إعدادات المتصفح.'
                    : 'لم يُمنح الإذن بعد.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _later() async {
    await ref.read(browserNotificationPromptStoreProvider).dismiss();
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.user?.id != next.user?.id) {
        unawaited(_evaluate());
      }
    });
    if (!_visible) return const SizedBox.shrink();
    final user = ref.watch(authControllerProvider).user;
    final copy = _copyFor(user);
    final denied = ref.read(browserLocalNotificationsProvider).permission() ==
        BrowserNotificationPermission.denied;
    return Material(
      color: AppTheme.orange.withValues(alpha: .10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined,
                    color: AppTheme.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    copy.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(copy.body),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!denied)
                  FilledButton.icon(
                    key: const Key('allow-browser-notifications-button'),
                    onPressed: _busy ? null : _allow,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_active_outlined),
                    label: Text(_loaded ? 'السماح بالإشعارات' : 'السماح بالإشعارات'),
                  ),
                TextButton(
                  onPressed: _busy ? null : _later,
                  child: Text(denied ? 'إخفاء' : 'لاحقاً'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  _BannerCopy _copyFor(AppUser? user) {
    if (user?.isAdminLike == true) {
      return _BannerCopy(
        title: 'تنبيهات الطلبات الجديدة',
        body:
            'اسمح بالإشعارات ليظهر الطلب الجديد في شريط نظام الهاتف مع صوت. ${firebaseClosedAppRequirementAr(configured: AppConfig.hasFirebaseConfigurationForCurrentPlatform)}',
      );
    }
    return _BannerCopy(
      title: 'تفعيل إشعارات المتجر',
      body:
          'اسمح بالإشعارات ليصلك تنبيه في شريط النظام لصوت وتحديثات الطلب والعروض. ${firebaseClosedAppRequirementAr(configured: AppConfig.hasFirebaseConfigurationForCurrentPlatform)}',
    );
  }
}

class _BannerCopy {
  const _BannerCopy({required this.title, required this.body});

  final String title;
  final String body;
}
