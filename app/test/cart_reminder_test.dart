import 'dart:math';

import 'package:animal_supply_b2b/src/core/notifications/browser_local_notifications.dart';
import 'package:animal_supply_b2b/src/core/notifications/cart_reminder_coordinator.dart';
import 'package:animal_supply_b2b/src/core/notifications/cart_reminder_poller.dart';
import 'package:animal_supply_b2b/src/core/notifications/push_notifications.dart';
import 'package:animal_supply_b2b/src/data/local/local_cache.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/sync/sync_outbox.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CartReminderCoordinator', () {
    test('schedules randomized reminders and dispatches OS notifications',
        () async {
      final browser = _FakeBrowserLocalNotifications()
        ..current = BrowserNotificationPermission.granted;
      final mobile = _FakePushNotificationsService();
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CartReminderCoordinator(
        notifications: browser,
        mobileAlerts: mobile,
        prefsLoader: () async => prefs,
        randomDelayGenerator: (step, random) =>
            Duration(milliseconds: 10 * (step + 1)),
        random: Random(42),
      );

      // 1. Cart has items: schedules next reminder
      await coordinator.syncCartState(hasItems: true);
      expect(prefs.getInt('cart_reminder.next_scheduled_epoch.v1'), isNotNull);
      expect(prefs.getInt('cart_reminder.step.v1'), 0);
      expect(browser.scheduledReminders, hasLength(1));
      expect(
        browser.scheduledReminders.single.target,
        '/cart?from_push=1',
      );

      // 2. Trigger reminder
      final shown = await coordinator.triggerReminder();
      expect(shown, isTrue);
      expect(browser.shownNotifications, hasLength(1));
      expect(browser.shownNotifications.single.tag, cartReminderTag);
      expect(browser.shownNotifications.single.target, cartReminderTarget);
      expect(
        CartReminderCoordinator.reminderCopies
            .any((c) => c.title == browser.shownNotifications.single.title),
        isTrue,
      );
      expect(prefs.getInt('cart_reminder.step.v1'), 1);

      // 3. Cart becomes empty: cancels all reminders
      await coordinator.syncCartState(hasItems: false);
      expect(prefs.getInt('cart_reminder.next_scheduled_epoch.v1'), isNull);
      expect(prefs.getInt('cart_reminder.step.v1'), isNull);
      expect(browser.cancelledCalls, 1);

      coordinator.dispose();
    });

    test('picks from Arabic wholesale copies tailored to B2B feed & supplies',
        () {
      final browser = _FakeBrowserLocalNotifications();
      final coordinator = CartReminderCoordinator(
        notifications: browser,
        random: Random(1),
      );

      final copy = coordinator.pickRandomCopy();
      expect(copy.title, isNotEmpty);
      expect(copy.body, isNotEmpty);
      expect(
        copy.title.contains('سلة') ||
            copy.title.contains('تذكير') ||
            copy.title.contains('أصنافك') ||
            copy.title.contains('طلبك'),
        isTrue,
      );
    });

    test('checkDueReminders triggers only when scheduled epoch has arrived',
        () async {
      final browser = _FakeBrowserLocalNotifications()
        ..current = BrowserNotificationPermission.granted;
      final prefs = await SharedPreferences.getInstance();

      final coordinator = CartReminderCoordinator(
        notifications: browser,
        prefsLoader: () async => prefs,
        randomDelayGenerator: (step, random) => const Duration(seconds: 100),
      );

      await coordinator.syncCartState(hasItems: true);
      expect(browser.shownNotifications, isEmpty);

      // Check while not due yet
      await coordinator.checkDueReminders(hasItems: true);
      expect(browser.shownNotifications, isEmpty);

      // Fast-forward stored epoch to the past
      await prefs.setInt(
        'cart_reminder.next_scheduled_epoch.v1',
        DateTime.now().millisecondsSinceEpoch - 1000,
      );

      await coordinator.syncCartState(hasItems: true);
      expect(browser.shownNotifications, hasLength(1));

      coordinator.dispose();
    });
  });

  group('CartReminderPoller widget integration', () {
    testWidgets('syncs state on cart item changes and visibility checks',
        (tester) async {
      final browser = _FakeBrowserLocalNotifications()
        ..current = BrowserNotificationPermission.granted;
      final prefs = await SharedPreferences.getInstance();
      final cache = LocalCache(prefs: prefs);
      final outbox = SyncOutbox(prefs: prefs);

      final coordinator = CartReminderCoordinator(
        notifications: browser,
        prefsLoader: () async => prefs,
        randomDelayGenerator: (step, random) => const Duration(seconds: 60),
      );

      final container = ProviderContainer(
        overrides: [
          localCacheProvider.overrideWithValue(cache),
          syncOutboxProvider.overrideWithValue(outbox),
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(_customer()),
          ),
          cartReminderCoordinatorProvider.overrideWithValue(coordinator),
          browserLocalNotificationsProvider.overrideWithValue(browser),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CartReminderPoller(
                checkInterval: Duration(milliseconds: 50),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cartController = container.read(cartControllerProvider.notifier);
      await cartController.hydrate();

      // Initially empty: no scheduled reminder
      expect(prefs.getInt('cart_reminder.next_scheduled_epoch.v1'), isNull);

      // Add item to cart
      cartController.add(_sampleProduct());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      // Scheduled reminder should now be persisted
      expect(prefs.getInt('cart_reminder.next_scheduled_epoch.v1'), isNotNull);
      expect(browser.scheduledReminders, isNotEmpty);

      // Clear cart
      cartController.clear();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      // Should be cleared
      expect(prefs.getInt('cart_reminder.next_scheduled_epoch.v1'), isNull);
      expect(browser.cancelledCalls, greaterThanOrEqualTo(1));
    });
  });

  group('PushNotificationNavigation for cart reminders', () {
    test('routes cart_reminder notifications directly to /cart', () {
      final nav = PushNotificationNavigation.fromData({
        'type': 'cart_reminder',
      });
      expect(nav.hasDestination, isTrue);
      expect(nav.locationFor(_customer()), '/cart');
    });
  });
}

class _FakeBrowserLocalNotifications extends BrowserLocalNotifications {
  BrowserNotificationPermission current =
      BrowserNotificationPermission.notDetermined;
  final List<({String title, String body, String? tag, String? target})>
      shownNotifications = [];
  final List<({Duration delay, String title, String body, String? tag, String? target})>
      scheduledReminders = [];
  int cancelledCalls = 0;

  @override
  bool get isSupported => true;

  @override
  BrowserNotificationPermission permission() => current;

  @override
  Future<bool> show({
    required String title,
    required String body,
    String? tag,
    String? target,
  }) async {
    shownNotifications.add((
      title: title,
      body: body,
      tag: tag,
      target: target,
    ));
    return true;
  }

  @override
  Future<void> scheduleCartReminder({
    required Duration delay,
    required String title,
    required String body,
    String? tag,
    String? target,
  }) async {
    scheduledReminders.add((
      delay: delay,
      title: title,
      body: body,
      tag: tag,
      target: target,
    ));
  }

  @override
  Future<void> cancelCartReminders() async {
    cancelledCalls++;
  }
}

class _FakePushNotificationsService extends PushNotificationsService {
  final List<({String id, String title, String body})> shownInbox = [];

  @override
  Future<bool> showInboxNotification({
    required String id,
    required String title,
    required String body,
  }) async {
    shownInbox.add((id: id, title: title, body: body));
    return true;
  }
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(AppUser user) {
    state = AuthState(user: user);
  }
}

AppUser _customer() {
  return const AppUser(
    id: 'customer-1',
    username: 'customer-1',
    role: 'customer',
    customerId: 'biz-1',
    accountStatus: 'active',
  );
}

Product _sampleProduct() {
  return const Product(
    id: 'product-feed-1',
    nameAr: 'علف دواجن تسمين',
    sku: 'FEED-POULTRY-1',
    category: 'أعلاف',
    animalType: 'دواجن',
    brand: 'الباشق',
    unitSize: '50 كجم',
    basePrice: 85,
    stockQuantity: 100,
    minOrderQty: 1,
  );
}
