import 'dart:async';

import 'package:animal_supply_b2b/src/core/notifications/new_order_alert_sound.dart';
import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/core/utils/formatters.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
import 'package:animal_supply_b2b/src/data/models/app_notification.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
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

  testWidgets(
    'expanded order shows a wide invoice with snapshot product details',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(646, 838));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([_invoiceOrder()]);

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: _MutableNotificationsRepository(const []),
        sound: _FakeNewOrderAlertSound(),
        autoRefreshInterval: Duration.zero,
      );
      await tester.pumpAndSettle();

      final orderTitle = find.text('طلب INV-1001');
      await tester.ensureVisible(orderTitle);
      await tester.tap(orderTitle);
      await tester.pumpAndSettle();

      final invoice = find.byKey(
        const ValueKey('admin-order-invoice-invoice-order'),
      );
      final line = find.byKey(
        const ValueKey('admin-invoice-line-cat-001-0'),
      );

      expect(invoice, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('admin-order-items-wide-invoice-order'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('admin-order-items-compact-invoice-order'),
        ),
        findsNothing,
      );
      expect(find.descendant(of: invoice, matching: find.text('الصنف')),
          findsOneWidget);
      expect(find.descendant(of: invoice, matching: find.text('الكمية')),
          findsOneWidget);
      expect(
        find.descendant(of: invoice, matching: find.text('سعر الوحدة')),
        findsOneWidget,
      );
      expect(find.descendant(of: invoice, matching: find.text('الإجمالي')),
          findsOneWidget);
      expect(
        find.descendant(
          of: line,
          matching: find.text('اسم المنتج وقت الطلب'),
        ),
        findsOneWidget,
      );
      expect(find.text('الاسم الحالي في الكتالوج'), findsNothing);
      expect(
        find.descendant(
          of: line,
          matching: find.text('كيس 2 كجم'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text('SNAP-SKU')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text(lyd(12.5))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text(lyd(37.5))),
        findsOneWidget,
      );

      final imageFinder = find.descendant(
        of: line,
        matching: find.byType(ProductImagePlaceholder),
      );
      expect(imageFinder, findsOneWidget);
      final image = tester.widget<ProductImagePlaceholder>(imageFinder);
      expect(image.productId, 'cat-001');
      expect(image.semanticLabel, 'صورة اسم المنتج وقت الطلب');
      final productName = tester.widget<Text>(
        find.descendant(
          of: line,
          matching: find.text('اسم المنتج وقت الطلب'),
        ),
      );
      expect(productName.maxLines, isNull);
      expect(productName.overflow, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded order uses the compact invoice layout on mobile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([_invoiceOrder()]);

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: _MutableNotificationsRepository(const []),
        sound: _FakeNewOrderAlertSound(),
        autoRefreshInterval: Duration.zero,
      );
      await tester.pumpAndSettle();

      final orderTitle = find.text('طلب INV-1001');
      await tester.ensureVisible(orderTitle);
      await tester.tap(orderTitle);
      await tester.pumpAndSettle();

      final compact = find.byKey(
        const ValueKey('admin-order-items-compact-invoice-order'),
      );
      final line = find.byKey(
        const ValueKey('admin-invoice-line-cat-001-0'),
      );

      expect(compact, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('admin-order-items-wide-invoice-order'),
        ),
        findsNothing,
      );
      expect(Directionality.of(tester.element(compact)), TextDirection.rtl);
      expect(
        find.descendant(
          of: line,
          matching: find.text('اسم المنتج وقت الطلب'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text('الكمية')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text('سعر الوحدة')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text('الإجمالي')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text(lyd(12.5))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text(lyd(37.5))),
        findsOneWidget,
      );
      expect(tester.getRect(compact).width, lessThanOrEqualTo(390));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wide invoice handles long details and large values with scaled text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(646, 838));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([
        _invoiceOrder(
          productName:
              'اسم منتج عربي طويل جداً يجب أن يظهر كاملاً داخل تفاصيل الفاتورة',
          productSku: 'SNAP-SKU-VERY-LONG-1234567890',
          quantity: 1000000,
          unitPrice: 1234567.89,
          lineTotal: 1234567890000,
        ),
      ]);

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: _MutableNotificationsRepository(const []),
        sound: _FakeNewOrderAlertSound(),
        autoRefreshInterval: Duration.zero,
        textScaler: const TextScaler.linear(1.2),
      );
      await tester.pumpAndSettle();

      final orderTitle = find.text('طلب INV-1001');
      await tester.ensureVisible(orderTitle);
      await tester.tap(orderTitle);
      await tester.pumpAndSettle();

      final line = find.byKey(
        const ValueKey('admin-invoice-line-cat-001-0'),
      );
      expect(
        find.byKey(
          const ValueKey('admin-order-items-wide-invoice-order'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: line,
          matching: find.text(
            'اسم منتج عربي طويل جداً يجب أن يظهر كاملاً داخل تفاصيل الفاتورة',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: line,
          matching: find.text('SNAP-SKU-VERY-LONG-1234567890'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text('1000000')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text(lyd(1234567.89))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.text(lyd(1234567890000))),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpOrdersScreen(
  WidgetTester tester, {
  required _MutableOrdersRepository orders,
  required _MutableNotificationsRepository notifications,
  required _FakeNewOrderAlertSound sound,
  required Duration autoRefreshInterval,
  TextScaler textScaler = TextScaler.noScaling,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
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

Order _invoiceOrder({
  String productName = 'اسم المنتج وقت الطلب',
  String productSku = 'SNAP-SKU',
  int quantity = 3,
  double unitPrice = 12.5,
  double lineTotal = 37.5,
}) {
  const currentProduct = Product(
    id: 'cat-001',
    nameAr: 'الاسم الحالي في الكتالوج',
    sku: 'CURRENT-SKU',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'اختبار',
    unitSize: '2 كجم',
    packageSize: 'كيس 2 كجم',
    basePrice: 18,
    stockQuantity: 10,
    minOrderQty: 1,
  );
  final orderItem = OrderItem(
    id: 'invoice-item',
    productId: 'cat-001',
    productName: productName,
    productSku: productSku,
    unitSize: '2 كجم',
    packageLabel: 'كيس 2 كجم',
    quantity: quantity,
    unitPrice: unitPrice,
    lineTotal: lineTotal,
    product: currentProduct,
  );
  return Order(
    id: 'invoice-order',
    orderNumber: 'INV-1001',
    customerId: 'customer-test',
    businessName: 'متجر الاختبار',
    status: OrderStatus.pending,
    items: [orderItem],
    createdAt: DateTime.utc(2026, 8, 14, 12),
    subtotal: lineTotal,
    deliveryFee: 2,
    handlingFee: 4,
    total: lineTotal + 6,
  );
}
