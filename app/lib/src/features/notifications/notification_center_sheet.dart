import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/push_notifications.dart';
import '../../core/theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(notificationsRepositoryProvider).list();
  }

  Future<void> _enablePushNotifications() async {
    final enabled = await ref
        .read(pushNotificationsCoordinatorProvider)
        .requestPermissionAndRegister();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'تم تفعيل الإشعارات الفورية لهذا الجهاز.'
              : 'تعذر تفعيل الإشعارات الفورية. تحقق من إذن المتصفح أو إعدادات الإنتاج.',
        ),
      ),
    );
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
                Text(
                  'الإشعارات',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'تفعيل الإشعارات الفورية',
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
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
                return ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
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
        'new_order' || 'order_status' => Icons.receipt_long_outlined,
        'product_campaign' || 'promotion' => Icons.local_offer_outlined,
        'account' => Icons.manage_accounts_outlined,
        _ => Icons.notifications_outlined,
      };

  Color _colorFor(String type) => switch (type) {
        'new_order' || 'order_status' => AppTheme.green,
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
