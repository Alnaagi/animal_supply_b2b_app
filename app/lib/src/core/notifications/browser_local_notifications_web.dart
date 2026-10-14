import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'browser_notification_permission.dart';

export 'browser_notification_permission.dart';

const _iconPath = 'icons/Icon-192.png';

bool get isBrowserLocalNotificationSupported {
  try {
    return web.window.has('Notification');
  } catch (_) {
    return false;
  }
}

BrowserNotificationPermission readBrowserLocalNotificationPermission() {
  if (!isBrowserLocalNotificationSupported) {
    return BrowserNotificationPermission.unsupported;
  }
  return _fromRaw(web.Notification.permission);
}

Future<BrowserNotificationPermission>
    requestBrowserLocalNotificationPermission() async {
  if (!isBrowserLocalNotificationSupported) {
    return BrowserNotificationPermission.unsupported;
  }
  try {
    final raw = await web.Notification.requestPermission().toDart;
    return _fromRaw(raw.toDart);
  } catch (_) {
    return readBrowserLocalNotificationPermission();
  }
}

Future<bool> showBrowserLocalNotification({
  required String title,
  required String body,
  String? tag,
  String? target,
}) async {
  if (readBrowserLocalNotificationPermission() !=
      BrowserNotificationPermission.granted) {
    return false;
  }
  final safeTag = (tag ?? '').trim();
  final safeTarget = _safeTarget(target);
  final options = web.NotificationOptions(
    body: body,
    lang: 'ar',
    dir: 'rtl',
    tag: safeTag,
    icon: _iconPath,
    badge: _iconPath,
    renotify: safeTag.isNotEmpty,
    data: _TrayNotificationData(target: safeTarget),
  );

  // Backgrounded tabs should raise the OS tray from the Service Worker.
  // `new Notification()` is often suppressed while the document is hidden.
  final hidden = _isDocumentHidden();
  if (hidden) {
    if (_postShowNotificationToWorker(
      title: title,
      body: body,
      tag: safeTag,
      target: safeTarget,
    )) {
      return true;
    }
    if (await _showViaServiceWorker(title, options)) {
      return true;
    }
    return false;
  }
  if (await _showViaServiceWorker(title, options)) {
    return true;
  }
  if (_postShowNotificationToWorker(
    title: title,
    body: body,
    tag: safeTag,
    target: safeTarget,
  )) {
    return true;
  }
  return _showViaNotificationConstructor(title, options);
}

bool _isDocumentHidden() {
  try {
    return web.document.hidden;
  } catch (_) {
    return false;
  }
}

Future<bool> _showViaServiceWorker(
  String title,
  web.NotificationOptions options,
) async {
  try {
    if (!web.window.navigator.has('serviceWorker')) return false;
    final registration =
        await web.window.navigator.serviceWorker.ready.toDart.timeout(
      const Duration(seconds: 4),
    );
    await registration.showNotification(title, options).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

bool _postShowNotificationToWorker({
  required String title,
  required String body,
  required String tag,
  required String target,
}) {
  try {
    if (!web.window.navigator.has('serviceWorker')) return false;
    final worker = web.window.navigator.serviceWorker.controller;
    if (worker == null) return false;
    final message = JSObject()
      ..setProperty('type'.toJS, 'SHOW_OS_NOTIFICATION'.toJS)
      ..setProperty('title'.toJS, title.toJS)
      ..setProperty('body'.toJS, body.toJS)
      ..setProperty('tag'.toJS, tag.toJS)
      ..setProperty('target'.toJS, target.toJS);
    worker.postMessage(message);
    return true;
  } catch (_) {
    return false;
  }
}

bool _showViaNotificationConstructor(
  String title,
  web.NotificationOptions options,
) {
  try {
    final notification = web.Notification(title, options);
    notification.onclick = ((web.Event _) {
      web.window.focus();
    }).toJS;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> scheduleBrowserCartReminder({
  required Duration delay,
  required String title,
  required String body,
  String? tag,
  String? target,
}) async {
  if (readBrowserLocalNotificationPermission() !=
      BrowserNotificationPermission.granted) {
    return;
  }
  final safeTag = (tag ?? '').trim();
  final safeTarget = _safeTarget(target);
  try {
    if (!web.window.navigator.has('serviceWorker')) return;
    final worker = web.window.navigator.serviceWorker.controller;
    if (worker == null) return;
    final message = JSObject()
      ..setProperty('type'.toJS, 'SCHEDULE_CART_REMINDER'.toJS)
      ..setProperty('delayMs'.toJS, delay.inMilliseconds.toJS)
      ..setProperty('title'.toJS, title.toJS)
      ..setProperty('body'.toJS, body.toJS)
      ..setProperty('tag'.toJS, safeTag.toJS)
      ..setProperty('target'.toJS, safeTarget.toJS);
    worker.postMessage(message);
  } catch (_) {}
}

Future<void> cancelBrowserCartReminders() async {
  try {
    if (!web.window.navigator.has('serviceWorker')) return;
    final worker = web.window.navigator.serviceWorker.controller;
    if (worker == null) return;
    final message = JSObject()
      ..setProperty('type'.toJS, 'CANCEL_CART_REMINDERS'.toJS);
    worker.postMessage(message);
  } catch (_) {}
}

String _safeTarget(String? value) {
  final target = (value ?? '').trim();
  if (target.isEmpty ||
      !target.startsWith('/') ||
      target.startsWith('//') ||
      target.contains('\\') ||
      target.length > 500) {
    return '/';
  }
  return target;
}

BrowserNotificationPermission _fromRaw(String value) {
  return switch (value) {
    'granted' => BrowserNotificationPermission.granted,
    'denied' => BrowserNotificationPermission.denied,
    _ => BrowserNotificationPermission.notDetermined,
  };
}

extension type _TrayNotificationData._(JSObject _) implements JSObject {
  external factory _TrayNotificationData({String target});
}
