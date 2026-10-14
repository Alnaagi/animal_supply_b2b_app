import 'package:animal_supply_b2b/src/core/notifications/browser_local_notifications.dart';
import 'package:animal_supply_b2b/src/core/notifications/browser_notification_permission_banner.dart';
import 'package:animal_supply_b2b/src/core/notifications/in_app_notification_poller.dart';
import 'package:animal_supply_b2b/src/core/notifications/local_alert_coordinator.dart';
import 'package:animal_supply_b2b/src/core/notifications/new_order_alert_sound.dart';
import 'package:animal_supply_b2b/src/core/notifications/new_order_alert_tone.dart';
import 'package:animal_supply_b2b/src/data/models/app_notification.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/repositories/notifications_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('customer banner requests browser permission once',
      (tester) async {
    final browser = _FakeBrowserLocalNotifications();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(_customer()),
          ),
          browserLocalNotificationsProvider.overrideWithValue(browser),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BrowserNotificationPermissionBanner()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تفعيل إشعارات المتجر'), findsOneWidget);
    await tester
        .tap(find.byKey(const Key('allow-browser-notifications-button')));
    await tester.pumpAndSettle();

    expect(browser.requests, 1);
    expect(browser.shownTags, contains('browser-permission-granted'));
    expect(find.text('تفعيل إشعارات المتجر'), findsNothing);
    expect(find.textContaining('تم تفعيل تنبيهات شريط النظام'), findsOneWidget);
  });

  testWidgets('denied browser permission is not requested again after hide',
      (tester) async {
    final browser = _FakeBrowserLocalNotifications()
      ..current = BrowserNotificationPermission.denied;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(_admin()),
          ),
          browserLocalNotificationsProvider.overrideWithValue(browser),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BrowserNotificationPermissionBanner()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تنبيهات الطلبات الجديدة'), findsOneWidget);
    expect(find.byKey(const Key('allow-browser-notifications-button')),
        findsNothing);
    await tester.tap(find.text('إخفاء'));
    await tester.pumpAndSettle();
    expect(find.text('تنبيهات الطلبات الجديدة'), findsNothing);
    expect(browser.requests, 0);
  });

  test('local alerts announce each notification id once', () async {
    final browser = _FakeBrowserLocalNotifications()
      ..current = BrowserNotificationPermission.granted;
    final sound = _FakeSound();
    final coordinator = LocalAlertCoordinator(
      notifications: browser,
      sound: sound,
    );

    final first = await coordinator.announce(
      id: 'n1',
      title: 'طلب جديد',
      body: 'وصل طلب.',
    );
    final second = await coordinator.announce(
      id: 'n1',
      title: 'طلب جديد',
      body: 'وصل طلب.',
    );

    expect(first.shown, isTrue);
    expect(first.playedSound, isTrue);
    expect(second.shown, isFalse);
    expect(browser.shownTags, ['n1']);
    expect(sound.playCalls, 1);
  });

  test('os tray targets stay on role-safe in-app routes', () {
    expect(
      osTrayNotificationTarget(
        adminLike: false,
        orderId: 'order-1',
      ),
      '/orders?order=order-1&from_push=1',
    );
    expect(
      osTrayNotificationTarget(
        adminLike: true,
        orderId: 'order-1',
      ),
      '/admin/orders?order=order-1&from_push=1',
    );
  });

  testWidgets('customer inbox poll announces a new row once', (tester) async {
    final browser = _FakeBrowserLocalNotifications()
      ..current = BrowserNotificationPermission.granted;
    final sound = _FakeSound();
    final repository = _FakeInboxRepository([
      AppNotification(
        id: 'existing',
        type: 'product_campaign',
        title: 'عرض سابق',
        body: 'سابق',
        createdAt: DateTime(2026, 8, 16, 8),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(_customer()),
          ),
          browserLocalNotificationsProvider.overrideWithValue(browser),
          newOrderAlertSoundProvider.overrideWithValue(sound),
          notificationsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: InAppNotificationPoller(
              interval: Duration(milliseconds: 40),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(browser.shownTags, isEmpty);

    repository.rows = [
      AppNotification(
        id: 'campaign-new',
        type: 'product_campaign',
        title: 'عرض جديد',
        body: 'وصل عرض.',
        createdAt: DateTime(2026, 8, 16, 9),
      ),
      ...repository.rows,
    ];
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 10));

    expect(browser.shownTags, ['campaign-new']);
    expect(sound.playCalls, 1);
  });
}

AppUser _customer() {
  return const AppUser(
    id: 'customer-a',
    username: 'customer-a',
    role: 'customer',
    customerId: 'biz-a',
    accountStatus: 'active',
  );
}

AppUser _admin() {
  return const AppUser(id: 'admin-a', username: 'admin', role: 'admin');
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(AppUser user) {
    state = AuthState(user: user);
  }
}

class _FakeBrowserLocalNotifications extends BrowserLocalNotifications {
  BrowserNotificationPermission current =
      BrowserNotificationPermission.notDetermined;
  int requests = 0;
  final List<String> shownTags = [];

  @override
  bool get isSupported => true;

  @override
  BrowserNotificationPermission permission() => current;

  @override
  Future<BrowserNotificationPermission> requestPermission() async {
    requests++;
    current = BrowserNotificationPermission.granted;
    return current;
  }

  @override
  Future<bool> show({
    required String title,
    required String body,
    String? tag,
    String? target,
  }) async {
    if (current != BrowserNotificationPermission.granted) return false;
    shownTags.add(tag ?? title);
    return true;
  }
}

class _FakeInboxRepository extends NotificationsRepository {
  _FakeInboxRepository(this.rows);

  List<AppNotification> rows;

  @override
  Future<List<AppNotification>> list({int limit = 50}) async => rows;

  @override
  Future<int> unreadCount() async =>
      rows.where((notification) => !notification.isRead).length;
}

class _FakeSound extends NewOrderAlertSound {
  int playCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> play({
    NewOrderAlertTone? tone,
    double? volume,
  }) async {
    playCalls++;
    return true;
  }
}
