import 'browser_notification_permission.dart';

export 'browser_notification_permission.dart';

bool get isBrowserLocalNotificationSupported => false;

BrowserNotificationPermission readBrowserLocalNotificationPermission() {
  return BrowserNotificationPermission.unsupported;
}

Future<BrowserNotificationPermission>
    requestBrowserLocalNotificationPermission() async {
  return BrowserNotificationPermission.unsupported;
}

Future<bool> showBrowserLocalNotification({
  required String title,
  required String body,
  String? tag,
  String? target,
}) async {
  return false;
}

Future<void> scheduleBrowserCartReminder({
  required Duration delay,
  required String title,
  required String body,
  String? tag,
  String? target,
}) async {}

Future<void> cancelBrowserCartReminders() async {}

