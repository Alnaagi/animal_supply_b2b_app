import 'dart:async';

import 'package:animal_supply_b2b/src/core/notifications/new_order_alert_sound.dart';
import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/models/app_notification.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/repositories/notifications_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_orders/admin_orders_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'visible refresh establishes a silent baseline and sounds once per new batch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([_order('order-1')]);
      final notifications = _MutableNotificationsRepository([
        _notification('notification-1'),
      ]);
      final sound = _FakeNewOrderAlertSound();

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: notifications,
        sound: sound,
        autoRefreshInterval: Duration.zero,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('refresh-admin-orders-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-orders-live-status')),
        findsOneWidget,
      );
      expect(find.text('التحديث التلقائي متوقف'), findsOneWidget);
      expect(find.text('طلب ORD-order-1'), findsOneWidget);
      expect(sound.playCalls, 0);

      notifications.current = [
        _notification('notification-2'),
        _notification('notification-1'),
      ];
      await tester.tap(
        find.byKey(const ValueKey('refresh-admin-orders-button')),
      );
      await tester.pumpAndSettle();

      expect(sound.primeCalls, 1);
      expect(sound.playCalls, 1);
      expect(find.text('وصل طلب جديد وتم تحديث القائمة.'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('refresh-admin-orders-button')),
      );
      await tester.pumpAndSettle();

      expect(sound.primeCalls, 2);
      expect(sound.playCalls, 1);
    },
  );

  testWidgets(
    'auto refresh preserves orders on failure, detects new demo orders, and stops',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([_order('order-1')]);
      final notifications = _MutableNotificationsRepository(const []);
      final sound = _FakeNewOrderAlertSound();

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: notifications,
        sound: sound,
        autoRefreshInterval: const Duration(milliseconds: 100),
      );
      await _flushImmediateWork(tester);

      expect(find.text('طلب ORD-order-1'), findsOneWidget);
      expect(sound.playCalls, 0);

      orders.failNext = true;
      await tester.pump(const Duration(milliseconds: 101));
      await _flushImmediateWork(tester);

      expect(find.text('طلب ORD-order-1'), findsOneWidget);
      expect(
        find.text('تعذر آخر تحديث — ستتم المحاولة تلقائياً'),
        findsOneWidget,
      );
      expect(sound.playCalls, 0);

      orders.current = [_order('order-2'), _order('order-1')];
      await tester.pump(const Duration(milliseconds: 101));
      await _flushImmediateWork(tester);

      expect(find.text('طلب ORD-order-2'), findsOneWidget);
      expect(sound.playCalls, 1);

      await tester.pump(const Duration(milliseconds: 101));
      await _flushImmediateWork(tester);
      expect(sound.playCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final callsAfterDispose = orders.pageCalls;
      await tester.pump(const Duration(milliseconds: 350));
      expect(orders.pageCalls, callsAfterDispose);
    },
  );

  testWidgets(
    'changing filters does not consume an unseen new-order notification',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([_order('order-1')]);
      final notifications = _MutableNotificationsRepository([
        _notification('notification-1'),
      ]);
      final sound = _FakeNewOrderAlertSound();

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: notifications,
        sound: sound,
        autoRefreshInterval: Duration.zero,
      );
      await tester.pumpAndSettle();

      notifications.current = [
        _notification('notification-2'),
        _notification('notification-1'),
      ];
      final todayFilter = find.widgetWithText(ChoiceChip, 'اليوم');
      await tester.ensureVisible(todayFilter);
      await tester.tap(todayFilter);
      await tester.pumpAndSettle();

      expect(sound.playCalls, 0);

      await tester.tap(
        find.byKey(const ValueKey('refresh-admin-orders-button')),
      );
      await tester.pumpAndSettle();

      expect(sound.playCalls, 1);
      expect(
        find.text('وصل طلب جديد. قد لا يظهر مع الفلتر الحالي.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'resume refresh consumes background notifications without replaying sound',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([_order('order-1')]);
      final notifications = _MutableNotificationsRepository([
        _notification('notification-1'),
      ]);
      final sound = _FakeNewOrderAlertSound();

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: notifications,
        sound: sound,
        autoRefreshInterval: const Duration(milliseconds: 100),
      );
      await _flushImmediateWork(tester);
      final callsBeforePause = orders.pageCalls;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      orders.current = [_order('order-2'), _order('order-1')];
      notifications.current = [
        _notification('notification-2'),
        _notification('notification-1'),
      ];
      await tester.pump(const Duration(milliseconds: 250));
      expect(orders.pageCalls, callsBeforePause);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flushImmediateWork(tester);

      expect(find.text('طلب ORD-order-2'), findsOneWidget);
      expect(sound.playCalls, 0);

      orders.current = [
        _order('order-3'),
        _order('order-2'),
        _order('order-1'),
      ];
      notifications.current = [
        _notification('notification-3'),
        _notification('notification-2'),
        _notification('notification-1'),
      ];
      await tester.pump(const Duration(milliseconds: 101));
      await _flushImmediateWork(tester);

      expect(sound.playCalls, 1);
    },
  );

  testWidgets('manual sound priming serializes refresh against the timer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final orders = _MutableOrdersRepository([_order('order-1')]);
    final notifications = _MutableNotificationsRepository(const []);
    final sound = _FakeNewOrderAlertSound();

    await _pumpOrdersScreen(
      tester,
      orders: orders,
      notifications: notifications,
      sound: sound,
      autoRefreshInterval: const Duration(milliseconds: 100),
    );
    await _flushImmediateWork(tester);
    final callsBeforeRefresh = orders.pageCalls;

    final delayedPrime = Completer<bool>();
    sound.primeCompleter = delayedPrime;
    await tester.tap(
      find.byKey(const ValueKey('refresh-admin-orders-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(orders.pageCalls, callsBeforeRefresh);

    delayedPrime.complete(true);
    await _flushImmediateWork(tester);
    expect(orders.pageCalls, callsBeforeRefresh + 1);
  });
}

Future<void> _pumpOrdersScreen(
  WidgetTester tester, {
  required _MutableOrdersRepository orders,
  required _MutableNotificationsRepository notifications,
  required _FakeNewOrderAlertSound sound,
  required Duration autoRefreshInterval,
}) async {
  final router = GoRouter(
    initialLocation: '/admin/orders',
    routes: [
      GoRoute(
        path: '/admin/orders',
        builder: (context, state) => AdminOrdersScreen(
          autoRefreshInterval: autoRefreshInterval,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _FixedAuthController(
            const AppUser(
              id: 'admin-test',
              username: 'admin',
              role: 'admin',
            ),
          ),
        ),
        ordersRepositoryProvider.overrideWithValue(orders),
        notificationsRepositoryProvider.overrideWithValue(notifications),
        newOrderAlertSoundProvider.overrideWithValue(sound),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    ),
  );
}

Future<void> _flushImmediateWork(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

class _MutableOrdersRepository extends OrdersRepository {
  _MutableOrdersRepository(this.current) : super.demo(seed: const []);

  static final DateTime snapshot = DateTime.utc(2026, 8, 14, 12);

  List<Order> current;
  bool failNext = false;
  int pageCalls = 0;

  @override
  Future<OrdersPage> ordersPage({
    String? customerId,
    OrderStatus? status,
    DateTime? createdFrom,
    DateTime? createdUntil,
    DateTime? snapshotAt,
    int offset = 0,
    int pageSize = OrdersRepository.defaultPageSize,
  }) async {
    pageCalls++;
    if (failNext) {
      failNext = false;
      throw StateError('temporary refresh failure');
    }
    return OrdersPage(
      orders: List<Order>.of(current),
      hasMore: false,
      nextOffset: current.length,
      snapshotAt: snapshotAt ?? snapshot,
    );
  }
}

class _MutableNotificationsRepository extends NotificationsRepository {
  _MutableNotificationsRepository(this.current);

  List<AppNotification> current;

  @override
  Future<List<AppNotification>> list({int limit = 50}) async =>
      current.take(limit).toList();

  @override
  Future<int> unreadCount() async =>
      current.where((notification) => !notification.isRead).length;
}

class _FakeNewOrderAlertSound extends NewOrderAlertSound {
  int primeCalls = 0;
  int playCalls = 0;
  Completer<bool>? primeCompleter;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> prime() async {
    primeCalls++;
    return primeCompleter?.future ?? true;
  }

  @override
  Future<bool> play() async {
    playCalls++;
    return true;
  }
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(AppUser user) {
    state = AuthState(user: user);
  }
}

AppNotification _notification(String id) => AppNotification(
      id: id,
      type: 'new_order',
      title: 'طلب جديد',
      body: 'وصل طلب جديد.',
      payload: {'order_id': id},
      createdAt: DateTime.utc(2026, 8, 14, 12),
    );

Order _order(String id) => Order(
      id: id,
      orderNumber: 'ORD-$id',
      customerId: 'customer-test',
      businessName: 'متجر الاختبار',
      status: OrderStatus.pending,
      items: const [],
      createdAt: DateTime.utc(2026, 8, 14, 12),
    );
