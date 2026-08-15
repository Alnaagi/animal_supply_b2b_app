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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
      final todayFilter = find.byKey(
        const ValueKey('admin-orders-date-today'),
      );
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

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      orders.current = [_order('order-2'), _order('order-1')];
      notifications.current = [
        _notification('notification-2'),
        _notification('notification-1'),
      ];
      await tester.pump(const Duration(milliseconds: 250));
      expect(orders.pageCalls, callsBeforePause);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
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
    '646px order card exposes organized details, history, and actions',
    (tester) async {
      const surfaceSize = Size(646, 838);
      await tester.binding.setSurfaceSize(surfaceSize);
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

      final filterPanel = find.byKey(
        const ValueKey('admin-orders-filter-panel'),
      );
      final card = find.byKey(
        const ValueKey('admin-order-card-invoice-order'),
      );
      final summary = find.byKey(
        const ValueKey('admin-order-summary-invoice-order'),
      );
      final details = find.byKey(
        const ValueKey('admin-order-details-invoice-order'),
      );

      _expectHorizontallyWithinViewport(tester, filterPanel, surfaceSize);
      _expectHorizontallyWithinViewport(tester, card, surfaceSize);
      expect(details, findsNothing);

      await _tapVisible(tester, summary);
      await tester.pumpAndSettle();

      final invoice = find.byKey(
        const ValueKey('admin-order-invoice-invoice-order'),
      );
      final line = find.byKey(
        const ValueKey('admin-invoice-line-cat-001-0'),
      );

      expect(details, findsOneWidget);
      expect(invoice, findsOneWidget);
      _expectHorizontallyWithinViewport(tester, details, surfaceSize);
      _expectHorizontallyWithinViewport(tester, invoice, surfaceSize);
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

      final customerDelivery = find.byKey(
        const ValueKey('admin-order-customer-delivery-invoice-order'),
      );
      expect(customerDelivery, findsOneWidget);
      _expectHorizontallyWithinViewport(
        tester,
        customerDelivery,
        surfaceSize,
      );
      expect(find.text('أحمد الفيتوري'), findsOneWidget);
      expect(find.text('0912345678'), findsOneWidget);
      expect(find.text('طرابلس، طريق المطار'), findsOneWidget);
      expect(find.text('يرجى الاتصال قبل الوصول.'), findsOneWidget);
      final customerHeading = find.text('بيانات العميل');
      final deliveryHeading = find.text('بيانات التسليم');
      expect(
        tester.getTopLeft(customerHeading).dy,
        closeTo(tester.getTopLeft(deliveryHeading).dy, .5),
      );

      final notes = find.byKey(
        const ValueKey('admin-order-notes-invoice-order'),
      );
      expect(notes, findsOneWidget);
      expect(find.text('يفضل التسليم صباحاً.'), findsOneWidget);
      expect(find.text('تمت مراجعة بيانات التسليم.'), findsOneWidget);
      _expectHorizontallyWithinViewport(tester, notes, surfaceSize);

      final history = find.byKey(
        const ValueKey('admin-order-history-invoice-order'),
      );
      final historyToggle = find.byKey(
        const ValueKey('admin-order-history-toggle-invoice-order'),
      );
      final historyBody = find.byKey(
        const ValueKey('admin-order-history-body-invoice-order'),
      );
      expect(history, findsOneWidget);
      expect(historyBody, findsNothing);
      await _tapVisible(tester, historyToggle);
      await tester.pumpAndSettle();
      expect(historyBody, findsOneWidget);
      expect(find.text('بدأ الطلب بحالة قيد المراجعة'), findsOneWidget);
      expect(find.text('تم إنشاء الطلب للمراجعة.'), findsOneWidget);
      _expectHorizontallyWithinViewport(tester, history, surfaceSize);

      final actions = find.byKey(
        const ValueKey('admin-order-actions-invoice-order'),
      );
      final changeStatus = find.byKey(
        const ValueKey('admin-order-change-status-invoice-order'),
      );
      final copySummary = find.byKey(
        const ValueKey('admin-order-copy-summary-invoice-order'),
      );
      await tester.ensureVisible(actions);
      await tester.pumpAndSettle();
      final confirmedStatus = find.byKey(
        const ValueKey('admin-order-next-status-invoice-order-confirmed'),
      );
      expect(changeStatus, findsOneWidget);
      expect(copySummary.hitTestable(), findsOneWidget);
      expect(confirmedStatus.hitTestable(), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('admin-order-next-status-invoice-order-cancelled'),
        ),
        findsOneWidget,
      );
      expect(find.text('الخطوة التالية'), findsOneWidget);
      expect(find.text('تغيير حالة الطلب'), findsNothing);
      final changeRect = tester.getRect(changeStatus);
      final copyRect = tester.getRect(copySummary);
      expect(changeRect.height, greaterThanOrEqualTo(48));
      expect(copyRect.height, greaterThanOrEqualTo(48));
      expect(copyRect.top, greaterThan(changeRect.bottom - .5));
      _expectHorizontallyWithinViewport(tester, actions, surfaceSize);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '390px order card stacks details, omits empty notes, and reaches actions',
    (tester) async {
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([
        _invoiceOrder(customerNote: '', adminNote: ''),
      ]);

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: _MutableNotificationsRepository(const []),
        sound: _FakeNewOrderAlertSound(),
        autoRefreshInterval: Duration.zero,
      );
      await tester.pumpAndSettle();

      final filterPanel = find.byKey(
        const ValueKey('admin-orders-filter-panel'),
      );
      final card = find.byKey(
        const ValueKey('admin-order-card-invoice-order'),
      );
      final summary = find.byKey(
        const ValueKey('admin-order-summary-invoice-order'),
      );
      final details = find.byKey(
        const ValueKey('admin-order-details-invoice-order'),
      );

      _expectHorizontallyWithinViewport(tester, filterPanel, surfaceSize);
      _expectHorizontallyWithinViewport(tester, card, surfaceSize);
      expect(details, findsNothing);

      await _tapVisible(tester, summary);
      await tester.pumpAndSettle();

      final compact = find.byKey(
        const ValueKey('admin-order-items-compact-invoice-order'),
      );
      final line = find.byKey(
        const ValueKey('admin-invoice-line-cat-001-0'),
      );

      expect(details, findsOneWidget);
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
      _expectHorizontallyWithinViewport(tester, details, surfaceSize);
      _expectHorizontallyWithinViewport(tester, compact, surfaceSize);

      final customerDelivery = find.byKey(
        const ValueKey('admin-order-customer-delivery-invoice-order'),
      );
      expect(customerDelivery, findsOneWidget);
      expect(find.text('يرجى الاتصال قبل الوصول.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('بيانات التسليم')).dy,
        greaterThan(tester.getTopLeft(find.text('بيانات العميل')).dy),
      );
      _expectHorizontallyWithinViewport(
        tester,
        customerDelivery,
        surfaceSize,
      );
      expect(
        find.byKey(const ValueKey('admin-order-notes-invoice-order')),
        findsNothing,
      );
      expect(find.text('الملاحظات'), findsNothing);

      final historyToggle = find.byKey(
        const ValueKey('admin-order-history-toggle-invoice-order'),
      );
      final historyBody = find.byKey(
        const ValueKey('admin-order-history-body-invoice-order'),
      );
      expect(historyBody, findsNothing);
      await _tapVisible(tester, historyToggle);
      await tester.pumpAndSettle();
      expect(historyBody, findsOneWidget);

      final actions = find.byKey(
        const ValueKey('admin-order-actions-invoice-order'),
      );
      final changeStatus = find.byKey(
        const ValueKey('admin-order-change-status-invoice-order'),
      );
      final copySummary = find.byKey(
        const ValueKey('admin-order-copy-summary-invoice-order'),
      );
      await tester.ensureVisible(actions);
      await tester.pumpAndSettle();
      expect(changeStatus, findsOneWidget);
      expect(copySummary.hitTestable(), findsOneWidget);
      expect(
        find
            .byKey(
              const ValueKey('admin-order-next-status-invoice-order-confirmed'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      final changeRect = tester.getRect(changeStatus);
      final copyRect = tester.getRect(copySummary);
      expect(changeRect.height, greaterThanOrEqualTo(48));
      expect(copyRect.height, greaterThanOrEqualTo(48));
      expect(copyRect.top, greaterThan(changeRect.bottom));
      _expectHorizontallyWithinViewport(tester, actions, surfaceSize);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default filter hides delivered and settings wheel persists a custom set',
    (tester) async {
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([
        _order('order-1'),
        _invoiceOrder(),
      ]);

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: _MutableNotificationsRepository(const []),
        sound: _FakeNewOrderAlertSound(),
        autoRefreshInterval: Duration.zero,
      );
      await tester.pumpAndSettle();

      expect(find.text('كل الحالات ما عدا المُسلَّم'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('admin-orders-filter-settings')),
        findsOneWidget,
      );
      expect(orders.lastStatus, isNull);
      expect(
        orders.lastStatuses,
        [
          OrderStatus.pending,
          OrderStatus.confirmed,
          OrderStatus.preparing,
          OrderStatus.ready,
          OrderStatus.cancelled,
        ],
      );

      await tester.tap(
        find.byKey(const ValueKey('admin-orders-filter-settings')),
      );
      await tester.pumpAndSettle();
      expect(find.text('إعدادات التصفية'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('admin-orders-filter-pref-cancelled')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ الإعدادات'));
      await tester.pumpAndSettle();
      expect(find.textContaining('تم حفظ إعدادات التصفية'), findsOneWidget);
      expect(orders.lastStatuses, isNot(contains(OrderStatus.cancelled)));
      expect(orders.lastStatuses, isNot(contains(OrderStatus.delivered)));
    },
  );

  testWidgets(
    'inline next-status buttons update without a dialog',
    (tester) async {
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
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
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('admin-order-summary-invoice-order')),
      );
      await tester.pumpAndSettle();

      expect(find.text('تغيير حالة الطلب'), findsNothing);
      expect(find.text('الحالة التالية'), findsNothing);
      await _tapVisible(
        tester,
        find.byKey(
          const ValueKey('admin-order-next-status-invoice-order-confirmed'),
        ),
      );
      await tester.pumpAndSettle();

      expect(orders.lastTransition, OrderStatus.confirmed);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('تم تحديث الطلب إلى'), findsOneWidget);
    },
  );

  testWidgets(
    'expanding an order card scrolls that card back into view',
    (tester) async {
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final orders = _MutableOrdersRepository([
        _order('order-1'),
        _order('order-2'),
      ]);

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: _MutableNotificationsRepository(const []),
        sound: _FakeNewOrderAlertSound(),
        autoRefreshInterval: Duration.zero,
      );
      await tester.pumpAndSettle();
      expect(find.text('طلب ORD-order-1'), findsOneWidget);
      expect(find.text('طلب ORD-order-2'), findsOneWidget);

      final lastSummary = find.byKey(
        const ValueKey('admin-order-summary-order-2'),
      );
      final lastCard = find.byKey(
        const ValueKey('admin-order-card-order-2'),
      );
      expect(lastSummary, findsOneWidget);
      await _tapVisible(tester, lastSummary);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('admin-order-details-order-2')),
        findsOneWidget,
      );
      final rect = tester.getRect(lastCard);
      expect(rect.top, greaterThanOrEqualTo(-1));
      expect(rect.top, lessThan(surfaceSize.height));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded order stays attached when refresh prepends a new order',
    (tester) async {
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final original = _invoiceOrder(
        customerNote: '',
        adminNote: '',
        includeHistory: false,
      );
      final orders = _MutableOrdersRepository([original]);

      await _pumpOrdersScreen(
        tester,
        orders: orders,
        notifications: _MutableNotificationsRepository(const []),
        sound: _FakeNewOrderAlertSound(),
        autoRefreshInterval: Duration.zero,
      );
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.byKey(
          const ValueKey('admin-order-summary-invoice-order'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('admin-order-details-invoice-order')),
        findsOneWidget,
      );

      orders.current = [_order('new-order'), original];
      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-orders-live-status')),
      );
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('refresh-admin-orders-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('admin-order-card-new-order')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-order-details-new-order')),
        findsNothing,
      );
      final originalDetails = find.byKey(
        const ValueKey('admin-order-details-invoice-order'),
      );
      expect(originalDetails, findsOneWidget);
      _expectHorizontallyWithinViewport(
        tester,
        originalDetails,
        surfaceSize,
      );
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

      await _tapVisible(
        tester,
        find.byKey(
          const ValueKey('admin-order-summary-invoice-order'),
        ),
      );
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
  OrderStatus? lastStatus;
  List<OrderStatus>? lastStatuses;
  OrderStatus? lastTransition;

  @override
  Future<OrdersPage> ordersPage({
    String? customerId,
    OrderStatus? status,
    Iterable<OrderStatus>? statuses,
    DateTime? createdFrom,
    DateTime? createdUntil,
    DateTime? snapshotAt,
    int offset = 0,
    int pageSize = OrdersRepository.defaultPageSize,
  }) async {
    pageCalls++;
    lastStatuses = statuses?.toList();
    lastStatus = status;
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

  @override
  Future<Order> transitionOrderStatus(
    String orderId,
    OrderStatus status, {
    String adminNote = '',
  }) async {
    lastTransition = status;
    current = [
      for (final order in current)
        if (order.id == orderId)
          order.copyWith(status: status, adminNote: adminNote)
        else
          order,
    ];
    return current.firstWhere((order) => order.id == orderId);
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
  String customerNote = 'يفضل التسليم صباحاً.',
  String adminNote = 'تمت مراجعة بيانات التسليم.',
  bool includeHistory = true,
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
    contactPerson: 'أحمد الفيتوري',
    contactPhone: '0912345678',
    status: OrderStatus.pending,
    items: [orderItem],
    createdAt: DateTime.utc(2026, 8, 14, 12),
    deliveryAddress: 'طرابلس، طريق المطار',
    deliveryNote: 'يرجى الاتصال قبل الوصول.',
    customerNote: customerNote,
    adminNote: adminNote,
    statusHistory: includeHistory
        ? [
            OrderStatusHistoryEntry(
              toStatus: OrderStatus.pending,
              note: 'تم إنشاء الطلب للمراجعة.',
              changedAt: DateTime.utc(2026, 8, 14, 10),
            ),
          ]
        : const [],
    subtotal: lineTotal,
    deliveryFee: 2,
    handlingFee: 4,
    total: lineTotal + 6,
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final rect = tester.getRect(finder);
  await tester.tapAt(Offset(rect.center.dx, rect.top + 16));
}

void _expectHorizontallyWithinViewport(
  WidgetTester tester,
  Finder finder,
  Size surfaceSize,
) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(-.5));
  expect(rect.right, lessThanOrEqualTo(surfaceSize.width + .5));
}
