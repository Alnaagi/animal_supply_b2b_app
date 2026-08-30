import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_local_notifications_stub.dart'
    if (dart.library.js_interop) 'browser_local_notifications_web.dart'
    as platform;
import 'browser_notification_permission.dart';

export 'browser_notification_permission.dart';

final browserLocalNotificationsProvider =
    Provider<BrowserLocalNotifications>((ref) {
  return const BrowserLocalNotifications();
});

class BrowserLocalNotifications {
  const BrowserLocalNotifications();

  bool get isSupported => platform.isBrowserLocalNotificationSupported;

  BrowserNotificationPermission permission() =>
      platform.readBrowserLocalNotificationPermission();

  Future<BrowserNotificationPermission> requestPermission() {
    return platform.requestBrowserLocalNotificationPermission();
  }

  Future<bool> show({
    required String title,
    required String body,
    String? tag,
    String? target,
  }) {
    return platform.showBrowserLocalNotification(
      title: title,
      body: body,
      tag: tag,
      target: target,
    );
  }

  Future<void> scheduleCartReminder({
    required Duration delay,
    required String title,
    required String body,
    String? tag,
    String? target,
  }) {
    return platform.scheduleBrowserCartReminder(
      delay: delay,
      title: title,
      body: body,
      tag: tag,
      target: target,
    );
  }

  Future<void> cancelCartReminders() {
    return platform.cancelBrowserCartReminders();
  }
}

/// Deep-link used when the user taps an OS-tray notification.
String osTrayNotificationTarget({
  required bool adminLike,
  String? orderId,
  String? productId,
  String? type,
}) {
  if (type == 'cart_reminder') {
    return '/cart?from_push=1';
  }
  final order = orderId?.trim() ?? '';
  if (order.isNotEmpty) {
    final path = adminLike ? '/admin/orders' : '/orders';
    return '$path?order=${Uri.encodeComponent(order)}&from_push=1';
  }
  final product = productId?.trim() ?? '';
  if (product.isNotEmpty) {
    return adminLike
        ? '/admin/products'
        : '/product/${Uri.encodeComponent(product)}?from_push=1';
  }
  return '/';
}
