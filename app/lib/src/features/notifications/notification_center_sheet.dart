import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/app_config_validation.dart';
import '../../core/notifications/browser_local_notifications.dart';
import '../../core/notifications/notification_day_groups.dart';
import '../../core/notifications/push_notifications.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/app_notification.dart';
import '../../data/repositories/notifications_repository.dart';
import '../auth/auth_controller.dart';

Future<void> showNotificationCenter(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: .82,
      child: NotificationCenterSheet(),
    ),
  );
}

class NotificationCenterSheet extends ConsumerStatefulWidget {
  const NotificationCenterSheet({super.key});

  @override
  ConsumerState<NotificationCenterSheet> createState() =>
      _NotificationCenterSheetState();
}

class _NotificationCenterSheetState
    extends ConsumerState<NotificationCenterSheet> {
  late Future<List<AppNotification>> _future;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _reload();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(_reload);
      ref.invalidate(unreadNotificationsCountProvider);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _reload() {
    _future = ref.read(notificationsRepositoryProvider).list();
  }

  Future<void> _enablePushNotifications() async {
    final fcmEnabled = await ref
        .read(pushNotificationsCoordinatorProvider)
        .requestPermissionAndRegister();
    final browser = ref.read(browserLocalNotificationsProvider);
    var browserGranted = false;
    if (browser.isSupported) {
      browserGranted = await browser.requestPermission() ==
          BrowserNotificationPermission.granted;
    }
    if (browserGranted) {
      await browser.show(
        title: 'تم تفعيل الإشعارات',
        body: 'ستظهر التنبيهات في شريط إشعارات الجهاز.',
        tag: 'browser-permission-granted',
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fcmEnabled
              ? 'تم تفعيل الإشعارات الفورية لهذا الجهاز.'
              : browserGranted
                  ? 'تم تفعيل تنبيهات شريط النظام. ${firebaseClosedAppRequirementAr(
                      configured:
                          AppConfig.hasFirebaseConfigurationForCurrentPlatform,
                    )}'
                  : 'تعذر تفعيل الإشعارات الفورية. يمكنك السماح بتنبيه المتصفح أو فتح الإشعارات من الإعدادات.',
        ),
      ),
    );
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
      ref.invalidate(unreadNotificationsCountProvider);
    } catch (_) {}
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) {
      try {
        await ref
            .read(notificationsRepositoryProvider)
            .markRead(notification.id);
        ref.invalidate(unreadNotificationsCountProvider);
      } catch (_) {
        // Opening the relevant screen is more important than a best-effort
        // read receipt when connectivity is interrupted.
      }
    }
    if (!mounted) return;

    final user = ref.read(authControllerProvider).user;
    final orderId = notification.orderId;
    final productId = notification.productId;
    Navigator.pop(context);
    if (orderId != null && orderId.isNotEmpty) {
      context.go(
        Uri(
          path: user?.isAdminLike == true ? '/admin/orders' : '/orders',
          queryParameters: {'order': orderId},
        ).toString(),
      );
    } else if (productId != null && productId.isNotEmpty) {
      context.go(
        user?.isAdminLike == true ? '/admin/products' : '/product/$productId',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(notificationInboxEpochProvider, (previous, next) {
      if (previous == next) return;
      setState(_reload);
    });
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_outlined,
                    color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الإشعارات',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  key: const Key('mark-all-notifications-read-button'),
                  onPressed: _markAllRead,
                  child: const Text('قراءة الكل'),
                ),
                IconButton(
                  tooltip: 'تفعيل تنبيهات شريط النظام',
                  onPressed: _enablePushNotifications,
                  icon: const Icon(Icons.notifications_active_outlined),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: () {
                    ref.invalidate(unreadNotificationsCountProvider);
                    setState(_reload);
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<AppNotification>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData &&
                    !snapshot.hasError) {
                  return const ShopLoading.section();
                }
                if (snapshot.hasError && snapshot.data == null) {
                  return _NotificationMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'تعذر تحميل الإشعارات',
                    message: 'تحقق من الاتصال ثم أعد المحاولة.',
                    action: FilledButton(
                      onPressed: () => setState(_reload),
                      child: const Text('إعادة المحاولة'),
                    ),
                  );
                }
                final notifications =
                    snapshot.data ?? const <AppNotification>[];
                if (notifications.isEmpty) {
                  return const _NotificationMessage(
                    icon: Icons.notifications_none,
                    title: 'لا توجد إشعارات',
                    message: 'ستظهر تحديثات الطلبات والعروض هنا.',
                  );
                }
                final groups = groupNotificationsByDay(notifications);
                final entries = <Object>[
                  for (final group in groups) ...[
                    group.label,
                    ...group.items,
                  ],
                ];
                return ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: entries.length,
                  separatorBuilder: (context, index) {
                    if (entries[index] is String) {
                      return const SizedBox(height: 4);
                    }
                    return const SizedBox(height: 8);
                  },
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    if (entry is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                        child: Text(
                          entry,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppTheme.darkGreen,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      );
                    }
                    final notification = entry as AppNotification;
                    return Card(
                      color: notification.isRead
                          ? Colors.white
                          : AppTheme.green.withValues(alpha: .08),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _colorFor(notification.type)
                              .withValues(alpha: .12),
                          child: Icon(
                            _iconFor(notification.type),
                            color: _colorFor(notification.type),
                          ),
                        ),
                        title: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: notification.isRead
                                ? FontWeight.w700
                                : FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(notification.body),
                        trailing: notification.isRead
                            ? null
                            : const CircleAvatar(
                                radius: 5,
                                backgroundColor: AppTheme.orange,
                              ),
                        onTap: () => _open(notification),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
        'new_order' ||
        'order_status' ||
        'order_status_changed' =>
          Icons.receipt_long_outlined,
        'product_campaign' || 'promotion' => Icons.local_offer_outlined,
        'account' => Icons.manage_accounts_outlined,
        _ => Icons.notifications_outlined,
      };

  Color _colorFor(String type) => switch (type) {
        'new_order' ||
        'order_status' ||
        'order_status_changed' =>
          AppTheme.green,
        'product_campaign' || 'promotion' => AppTheme.orange,
        'account' => AppTheme.brown,
        _ => AppTheme.darkGreen,
      };
}

class _NotificationMessage extends StatelessWidget {
  const _NotificationMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.green),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
