import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_local_notifications.dart';
import 'push_notifications.dart';

typedef RandomDelayGenerator = Duration Function(int step, Random random);

const String cartReminderTag = 'cart-abandoned-reminder';
const String cartReminderTarget = '/cart?from_push=1';

const String _prefScheduledEpochKey = 'cart_reminder.next_scheduled_epoch.v1';
const String _prefStepKey = 'cart_reminder.step.v1';

final cartReminderCoordinatorProvider =
    Provider<CartReminderCoordinator>((ref) {
  final coordinator = CartReminderCoordinator(
    notifications: ref.watch(browserLocalNotificationsProvider),
    mobileAlerts: ref.watch(pushNotificationsServiceProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class CartReminderCoordinator {
  CartReminderCoordinator({
    required BrowserLocalNotifications notifications,
    PushNotificationsService? mobileAlerts,
    Future<SharedPreferences> Function()? prefsLoader,
    RandomDelayGenerator? randomDelayGenerator,
    Random? random,
  })  : _notifications = notifications,
        _mobileAlerts = mobileAlerts,
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
        _randomDelayGenerator =
            randomDelayGenerator ?? _defaultRandomDelayGenerator,
        _random = random ?? Random();

  final BrowserLocalNotifications _notifications;
  final PushNotificationsService? _mobileAlerts;
  final Future<SharedPreferences> Function() _prefsLoader;
  final RandomDelayGenerator _randomDelayGenerator;
  final Random _random;

  Timer? _activeTimer;
  bool _isDisposed = false;
  int? _nextScheduledEpoch;
  int _step = 0;

  static const List<({String title, String body})> reminderCopies = [
    (
      title: 'لديك منتجات في سلة المشتريات 🛒',
      body:
          'تذكير: لم تكتمل عملية طلبك لدى شركة الباشق. اضغط هنا لمراجعة السلة وإتمام الطلب.',
    ),
    (
      title: 'سلة مشترياتك في انتظارك 📦',
      body:
          'لا تنسَ إتمام طلب الأعلاف والمستلزمات قبل نفاد الكميات المتاحة.',
    ),
    (
      title: 'هل نسيت إتمام طلبك؟ 🌾',
      body:
          'منتجاتك ما زالت محفوظة في السلة. اضغط لتأكيد الطلب وتحديد موقع التوصيل.',
    ),
    (
      title: 'تنبيه: سلة طلبات غير مكتملة 🚜',
      body:
          'لديك أصناف مضافة في السلة بانتظار التأكيد. تابع طلبك الآن بسهولة.',
    ),
  ];

  static Duration _defaultRandomDelayGenerator(int step, Random random) {
    if (step <= 0) {
      // 1st reminder: 15 to 45 minutes
      final minutes = 15 + random.nextInt(31);
      return Duration(minutes: minutes);
    } else if (step == 1) {
      // 2nd reminder: 2 to 5 hours (120 to 300 minutes)
      final minutes = 120 + random.nextInt(181);
      return Duration(minutes: minutes);
    } else if (step == 2) {
      // 3rd reminder: 12 to 24 hours (720 to 1440 minutes)
      final minutes = 720 + random.nextInt(721);
      return Duration(minutes: minutes);
    } else {
      // Subsequent reminders: 24 to 48 hours (1440 to 2880 minutes)
      final minutes = 1440 + random.nextInt(1441);
      return Duration(minutes: minutes);
    }
  }

  ({String title, String body}) pickRandomCopy() {
    final index = _random.nextInt(reminderCopies.length);
    return reminderCopies[index];
  }

  Future<void> syncCartState({required bool hasItems}) async {
    if (_isDisposed) return;
    if (!hasItems) {
      await cancelAllReminders();
      return;
    }

    final prefs = await _prefsLoader();
    final savedEpoch = prefs.getInt(_prefScheduledEpochKey);
    final savedStep = prefs.getInt(_prefStepKey) ?? 0;
    _step = savedStep;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (savedEpoch != null && savedEpoch > now) {
      _nextScheduledEpoch = savedEpoch;
      _scheduleTimer(Duration(milliseconds: savedEpoch - now));
      return;
    }

    if (savedEpoch != null && savedEpoch <= now) {
      // Reminder is already due
      await triggerReminder();
      return;
    }

    // No reminder currently scheduled: schedule a new randomized one
    await _scheduleNextReminder(step: _step);
  }

  Future<void> cancelAllReminders() async {
    _activeTimer?.cancel();
    _activeTimer = null;
    _nextScheduledEpoch = null;
    _step = 0;

    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_prefScheduledEpochKey);
      await prefs.remove(_prefStepKey);
    } catch (_) {}

    try {
      await _notifications.cancelCartReminders();
    } catch (_) {}
  }

  Future<bool> triggerReminder() async {
    if (_isDisposed) return false;
    final copy = pickRandomCopy();

    // 1. Show browser notification to OS tray
    final browserShown = await _notifications.show(
      title: copy.title,
      body: copy.body,
      tag: cartReminderTag,
      target: cartReminderTarget,
    );

    // 2. Show mobile local notification to OS tray
    final mobileShown = await _mobileAlerts?.showInboxNotification(
          id: 'cart-reminder-${DateTime.now().day}',
          title: copy.title,
          body: copy.body,
        ) ??
        false;

    // Advance step and schedule next random reminder
    _step++;
    await _scheduleNextReminder(step: _step);

    return browserShown || mobileShown;
  }

  Future<void> _scheduleNextReminder({required int step}) async {
    if (_isDisposed) return;
    final delay = _randomDelayGenerator(step, _random);
    final now = DateTime.now();
    final nextEpoch = now.add(delay).millisecondsSinceEpoch;
    _nextScheduledEpoch = nextEpoch;

    try {
      final prefs = await _prefsLoader();
      await prefs.setInt(_prefScheduledEpochKey, nextEpoch);
      await prefs.setInt(_prefStepKey, step);
    } catch (_) {}

    // On Web, instruct Service Worker to also schedule this delay
    final copy = pickRandomCopy();
    try {
      await _notifications.scheduleCartReminder(
        delay: delay,
        title: copy.title,
        body: copy.body,
        tag: cartReminderTag,
        target: cartReminderTarget,
      );
    } catch (_) {}

    _scheduleTimer(delay);
  }

  void _scheduleTimer(Duration delay) {
    _activeTimer?.cancel();
    if (_isDisposed) return;
    _activeTimer = Timer(delay, () {
      unawaited(triggerReminder());
    });
  }

  Future<void> checkDueReminders({required bool hasItems}) async {
    if (_isDisposed || !hasItems) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_nextScheduledEpoch != null && _nextScheduledEpoch! <= now) {
      await triggerReminder();
    }
  }

  void dispose() {
    _isDisposed = true;
    _activeTimer?.cancel();
    _activeTimer = null;
  }
}
