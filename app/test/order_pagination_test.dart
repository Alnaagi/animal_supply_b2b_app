import 'dart:async';

import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/data/sync/sync_outbox.dart';
import 'package:animal_supply_b2b/src/features/admin_orders/admin_orders_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/orders/orders_screen.dart';
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

  group('OrdersRepository bounded paging', () {
    test('demo pages are stable, newest-first, scoped, and snapshot bounded',
        () async {
      final snapshot = DateTime.utc(2026, 7, 22, 12);
      final repository = OrdersRepository.demo(
        seed: [
          _order(
            id: 'future',
            customerId: 'customer-a',
            createdAt: snapshot.add(const Duration(minutes: 1)),
          ),
          _order(
            id: 'order-a',
            customerId: 'customer-a',
            createdAt: DateTime.utc(2026, 7, 22, 10),
          ),
          _order(
            id: 'order-b',
            customerId: 'customer-a',
            createdAt: DateTime.utc(2026, 7, 22, 10),
          ),
          _order(
            id: 'order-c',
            customerId: 'customer-a',
            createdAt: DateTime.utc(2026, 7, 22, 11),
          ),
          _order(
            id: 'other-customer',
            customerId: 'customer-b',
            createdAt: DateTime.utc(2026, 7, 22, 11, 30),
          ),
        ],
      );

      final first = await repository.ordersPage(
        customerId: 'customer-a',
        snapshotAt: snapshot,
        pageSize: 2,
      );
      final second = await repository.ordersPage(
        customerId: 'customer-a',
        snapshotAt: first.snapshotAt,
        offset: first.nextOffset,
        pageSize: 2,
      );

      expect(first.orders.map((order) => order.id), ['order-c', 'order-b']);
      expect(first.hasMore, isTrue);
      expect(first.nextOffset, 2);
      expect(second.orders.map((order) => order.id), ['order-a']);
      expect(second.hasMore, isFalse);
      expect(
        [...first.orders, ...second.orders].map((order) => order.id).toSet(),
        {'order-a', 'order-b', 'order-c'},
      );
    });

    test('demo status and date filters match the remote query contract',
        () async {
      final repository = OrdersRepository.demo(
        seed: [
          _order(
            id: 'pending-today',
            customerId: 'customer-a',
            createdAt: DateTime.utc(2026, 7, 22, 9),
          ),
          _order(
            id: 'confirmed-today',
            customerId: 'customer-a',
            status: OrderStatus.confirmed,
            createdAt: DateTime.utc(2026, 7, 22, 10),
          ),
          _order(
            id: 'confirmed-yesterday',
            customerId: 'customer-a',
            status: OrderStatus.confirmed,
            createdAt: DateTime.utc(2026, 7, 21, 10),
          ),
        ],
      );

      final page = await repository.ordersPage(
        customerId: 'customer-a',
        status: OrderStatus.confirmed,
        createdFrom: DateTime.utc(2026, 7, 22),
        createdUntil: DateTime.utc(2026, 7, 23),
        snapshotAt: DateTime.utc(2026, 7, 22, 12),
      );

      expect(page.orders.map((order) => order.id), ['confirmed-today']);
    });

    test('demo mixed status filter keeps active work and hides delivered',
        () async {
      final repository = OrdersRepository.demo(
        seed: [
          _order(
            id: 'open',
            customerId: 'customer-a',
            createdAt: DateTime.utc(2026, 7, 22, 11),
          ),
          _order(
            id: 'done',
            customerId: 'customer-a',
            status: OrderStatus.delivered,
            createdAt: DateTime.utc(2026, 7, 22, 10),
          ),
          _order(
            id: 'cancelled',
            customerId: 'customer-a',
            status: OrderStatus.cancelled,
            createdAt: DateTime.utc(2026, 7, 22, 9),
          ),
        ],
      );

      final page = await repository.ordersPage(
        customerId: 'customer-a',
        statuses: {
          OrderStatus.pending,
          OrderStatus.confirmed,
          OrderStatus.preparing,
          OrderStatus.ready,
          OrderStatus.cancelled,
        },
        snapshotAt: DateTime.utc(2026, 7, 22, 12),
      );

      expect(page.orders.map((order) => order.id), ['open', 'cancelled']);
    });

    test('paged gateways receive server filters and a page-size lookahead',
        () async {
      final gateway = _PagedGateway(
        pageRows: [
          _row('order-3', DateTime.utc(2026, 7, 22, 11)),
          _row('order-2', DateTime.utc(2026, 7, 22, 10)),
          _row('order-1', DateTime.utc(2026, 7, 22, 9)),
        ],
      );
      final repository = OrdersRepository(remote: gateway, demoSeed: const []);
      final from = DateTime.utc(2026, 7, 22);
      final until = DateTime.utc(2026, 7, 23);
      final snapshot = DateTime.utc(2026, 7, 22, 12);

      final page = await repository.ordersPage(
        customerId: 'customer-a',
        status: OrderStatus.confirmed,
        createdFrom: from,
        createdUntil: until,
        snapshotAt: snapshot,
        offset: 50,
        pageSize: 2,
      );
      final highlighted = await repository.orderById(
        'highlighted',
        customerId: 'customer-a',
      );

      expect(gateway.pageCalls, hasLength(1));
      final call = gateway.pageCalls.single;
      expect(call.customerId, 'customer-a');
      expect(call.statusValue, 'confirmed');
      expect(call.createdFrom, from);
      expect(call.createdUntil, until);
      expect(call.snapshotAt, snapshot);
      expect(call.offset, 50);
      expect(call.limit, 3);
      expect(page.orders.map((order) => order.id), ['order-3', 'order-2']);
      expect(page.hasMore, isTrue);
      expect(page.nextOffset, 52);
      expect(gateway.lookupCustomerId, 'customer-a');
      expect(highlighted?.id, 'highlighted');
    });

    test('rejects a paged customer response that crosses account scope',
        () async {
      final gateway = _PagedGateway(
        pageRows: [
          _row(
            'wrong-customer-order',
            DateTime.utc(2026, 7, 22, 11),
            customerId: 'customer-b',
          ),
        ],
      );
      final repository = OrdersRepository(remote: gateway, demoSeed: const []);

      expect(
        () => repository.ordersPage(customerId: 'customer-a'),
        throwsA(
          isA<OrdersRepositoryException>().having(
            (error) => error.code,
            'code',
            'INVALID_SERVER_RESPONSE',
          ),
        ),
      );
    });
  });

  testWidgets('orders initial loading uses an RTL skeleton at 338px',
      (tester) async {
    tester.view.physicalSize = const Size(338, 838);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    addTearDown(outbox.dispose);
    final repository = _PendingOrdersRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncOutboxProvider.overrideWithValue(outbox),
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(
              const AppUser(
                id: 'profile-a',
                username: 'customer',
                role: 'customer',
                businessName: 'متجر الاختبار',
                customerId: 'customer-a',
              ),
            ),
          ),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: OrdersScreen()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final skeleton = find.byKey(const ValueKey('orders-initial-skeleton'));
    expect(skeleton, findsOneWidget);
    expect(find.byKey(const Key('shop-skeleton')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('orders-skeleton-card-0')),
      findsOneWidget,
    );
    expect(
      Directionality.of(tester.element(skeleton)),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);

    repository.complete();
    await tester.pump();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'customer deep-link lookup is scoped and load more reuses the snapshot',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    addTearDown(outbox.dispose);
    final repository = _ScreenOrdersRepository(
      firstPage: [
        _order(
          id: 'new-order',
          orderNumber: 'ORD-NEW',
          customerId: 'customer-a',
          createdAt: DateTime.utc(2026, 7, 22, 11),
        ),
      ],
      secondPage: [
        _order(
          id: 'older-order',
          orderNumber: 'ORD-OLDER',
          customerId: 'customer-a',
          createdAt: DateTime.utc(2026, 7, 21, 11),
        ),
      ],
      highlighted: _order(
        id: 'highlighted-order',
        orderNumber: 'ORD-HIGHLIGHTED',
        customerId: 'customer-a',
        createdAt: DateTime.utc(2026, 6, 1),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncOutboxProvider.overrideWithValue(outbox),
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(
              const AppUser(
                id: 'profile-a',
                username: 'customer',
                role: 'customer',
                businessName: 'متجر الاختبار',
                customerId: 'customer-a',
              ),
            ),
          ),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: OrdersScreen(
                highlightedOrderId: 'highlighted-order',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('طلب ORD-NEW'), findsOneWidget);
    expect(find.text('طلب ORD-HIGHLIGHTED'), findsOneWidget);
    expect(repository.lookupCustomerId, 'customer-a');

    final loadMore = find.byKey(const ValueKey('customer-orders-load-more'));
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('طلب ORD-OLDER'), findsOneWidget);
    expect(repository.pageCalls, hasLength(2));
    expect(repository.pageCalls.last.offset, 1);
    expect(repository.pageCalls.last.snapshotAt, _ScreenOrdersRepository.time);
  });

  testWidgets('orders success panel renders and can clear success state',
      (tester) async {
    tester.view.physicalSize = const Size(338, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    addTearDown(outbox.dispose);
    final order = _order(
      id: 'success-order',
      orderNumber: 'ORD-SUCCESS',
      customerId: 'customer-a',
      createdAt: DateTime.utc(2026, 7, 22, 11),
      items: const [
        OrderItem(
          id: 'item-1',
          productId: 'product-1',
          productName: 'علف اختبار',
          productSku: 'FEED-1',
          unitSize: '25 كجم',
          packageLabel: '25 كجم',
          unitsPerBox: 10,
          quantity: 1,
          unitPrice: 100,
          lineTotal: 100,
          product: Product(
            id: 'product-1',
            nameAr: 'علف اختبار',
            sku: 'FEED-1',
            category: 'أعلاف',
            animalType: 'مواشي',
            brand: 'المورد',
            unitSize: '25 كجم',
            basePrice: 100,
            imageUrl: 'https://example.com/order-product.png',
            stockQuantity: 50,
            minOrderQty: 1,
          ),
        ),
      ],
    );
    final repository = _ScreenOrdersRepository(
      firstPage: [order],
      secondPage: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncOutboxProvider.overrideWithValue(outbox),
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(
              const AppUser(
                id: 'profile-a',
                username: 'customer',
                role: 'customer',
                businessName: 'متجر الاختبار',
                customerId: 'customer-a',
              ),
            ),
          ),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: OrdersScreen(
                  highlightedOrderId: 'success-order',
                  showSuccessState: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('orders-success-panel')), findsOneWidget);
    expect(find.text('تم استلام طلبك بنجاح!'), findsOneWidget);
    expect(find.text('طلب ORD-SUCCESS'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('customer-order-preview-image-success-order'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'customer-order-item-image-success-order-product-1',
        ),
      ),
      findsOneWidget,
    );
    final orderImage = tester.widget<ProductImagePlaceholder>(
      find.byKey(
        const ValueKey(
          'customer-order-item-image-success-order-product-1',
        ),
      ),
    );
    expect(orderImage.imageUrl, 'https://example.com/order-product.png');
    expect(orderImage.fit, BoxFit.contain);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('orders-success-view-order')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('orders-success-panel')), findsNothing);
  });

  testWidgets('admin combined filters and pagination stay server-side and RTL',
      (tester) async {
    const viewport = Size(646, 838);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ScreenOrdersRepository(
      firstPage: [
        _order(
          id: 'admin-new',
          orderNumber: 'ADMIN-NEW',
          customerId: 'customer-a',
          createdAt: DateTime.utc(2026, 7, 22, 11),
        ),
      ],
      secondPage: [
        _order(
          id: 'admin-old',
          orderNumber: 'ADMIN-OLD',
          customerId: 'customer-a',
          status: OrderStatus.confirmed,
          createdAt: DateTime.utc(2026, 7, 21, 11),
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/admin/orders',
      routes: [
        GoRoute(
          path: '/admin/orders',
          builder: (context, state) => const AdminOrdersScreen(),
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
                id: 'admin-a',
                username: 'admin',
                role: 'admin',
              ),
            ),
          ),
          ordersRepositoryProvider.overrideWithValue(repository),
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
    await tester.pumpAndSettle();

    final filterPanel = find.byKey(const ValueKey('admin-orders-filter-panel'));
    expect(filterPanel, findsOneWidget);
    expect(
      Directionality.of(tester.element(filterPanel)),
      TextDirection.rtl,
    );
    _expectWithinViewport(tester, filterPanel, viewport);

    final todayFilter = find.byKey(const ValueKey('admin-orders-date-today'));
    expect(todayFilter, findsOneWidget);
    await tester.tap(todayFilter);
    await tester.pumpAndSettle();
    final dateCall = repository.pageCalls.last;
    expect(dateCall.offset, 0);
    expect(dateCall.status, isNull);
    expect(
      dateCall.statuses,
      [
        'pending',
        'confirmed',
        'preparing',
        'ready',
        'cancelled',
      ],
    );
    expect(dateCall.createdFrom, isNotNull);
    expect(dateCall.createdUntil, isNotNull);

    final statusFilter =
        find.byKey(const ValueKey('admin-orders-status-filter'));
    await tester.tap(statusFilter);
    await tester.pumpAndSettle();
    final confirmedStatus =
        find.byKey(const ValueKey('admin-orders-status-confirmed'));
    expect(confirmedStatus, findsOneWidget);
    expect(
      Directionality.of(tester.element(confirmedStatus)),
      TextDirection.rtl,
    );
    await tester.tap(
      find.descendant(
        of: confirmedStatus,
        matching: find.text(OrderStatus.confirmed.label),
      ),
    );
    await tester.pumpAndSettle();
    final combinedFilterCall = repository.pageCalls.last;
    expect(combinedFilterCall.offset, 0);
    expect(combinedFilterCall.status, OrderStatus.confirmed);
    expect(combinedFilterCall.statuses, isNull);
    expect(combinedFilterCall.createdFrom, dateCall.createdFrom);
    expect(combinedFilterCall.createdUntil, dateCall.createdUntil);
    expect(combinedFilterCall.snapshotAt, isNull);

    final loadMore = find.byKey(const ValueKey('admin-orders-load-more'));
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('admin-order-summary-admin-old')),
      findsOneWidget,
    );
    expect(find.text('تحميل المزيد'), findsNothing);
    final paginationCall = repository.pageCalls.last;
    expect(paginationCall.offset, 1);
    expect(paginationCall.status, OrderStatus.confirmed);
    expect(paginationCall.statuses, isNull);
    expect(paginationCall.createdFrom, combinedFilterCall.createdFrom);
    expect(paginationCall.createdUntil, combinedFilterCall.createdUntil);
    expect(paginationCall.snapshotAt, _ScreenOrdersRepository.time);

    final allStatuses = find.byKey(const ValueKey('admin-orders-status-all'));
    await tester.ensureVisible(allStatuses);
    await tester.tap(allStatuses);
    await tester.pumpAndSettle();
    final clearedStatusCall = repository.pageCalls.last;
    expect(clearedStatusCall.offset, 0);
    expect(clearedStatusCall.status, isNull);
    expect(
      clearedStatusCall.statuses,
      [
        'pending',
        'confirmed',
        'preparing',
        'ready',
        'cancelled',
      ],
    );
    expect(clearedStatusCall.createdFrom, combinedFilterCall.createdFrom);
    expect(clearedStatusCall.createdUntil, combinedFilterCall.createdUntil);
    expect(clearedStatusCall.snapshotAt, isNull);

    final currentOrderSummary =
        find.byKey(const ValueKey('admin-order-summary-admin-new'));
    await tester.ensureVisible(currentOrderSummary);
    expect(
      Directionality.of(tester.element(currentOrderSummary)),
      TextDirection.rtl,
    );
    _expectWithinViewport(tester, currentOrderSummary, viewport);
    await tester.tap(currentOrderSummary);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('admin-order-details-admin-new')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

void _expectWithinViewport(
  WidgetTester tester,
  Finder finder,
  Size viewport,
) {
  final rect = tester.getRect(finder);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

class _PagedGateway implements OrdersRemoteGateway, OrdersPagedRemoteGateway {
  _PagedGateway({required this.pageRows});

  final List<Map<String, dynamic>> pageRows;
  final List<_PageCall> pageCalls = [];
  String? lookupCustomerId;

  @override
  Future<List<Map<String, dynamic>>> queryOrdersPage({
    String? customerId,
    String? status,
    List<String>? statuses,
    DateTime? createdFrom,
    DateTime? createdUntil,
    required DateTime snapshotAt,
    required int offset,
    required int limit,
  }) async {
    pageCalls.add(
      _PageCall(
        customerId: customerId,
        status: status == null ? null : OrderStatus.values.byName(status),
        statusValue: status,
        statuses: statuses,
        createdFrom: createdFrom,
        createdUntil: createdUntil,
        snapshotAt: snapshotAt,
        offset: offset,
        limit: limit,
      ),
    );
    return pageRows;
  }

  @override
  Future<Map<String, dynamic>?> queryOrderById(
    String orderId, {
    String? customerId,
  }) async {
    lookupCustomerId = customerId;
    return _row(orderId, DateTime.utc(2026, 6, 1));
  }

  @override
  Future<List<Map<String, dynamic>>> allOrders() {
    throw StateError('Unbounded gateway read must not be used.');
  }

  @override
  Future<List<Map<String, dynamic>>> ordersForCustomer(String customerId) {
    throw StateError('Unbounded gateway read must not be used.');
  }

  @override
  Future<OrdersFunctionResponse> placeOrder(Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  @override
  Future<OrdersFunctionResponse> transitionOrderStatus(
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<OrdersFunctionResponse> updateOrderPricing(
    Map<String, dynamic> body,
  ) {
    throw UnimplementedError();
  }
}

class _ScreenOrdersRepository extends OrdersRepository {
  _ScreenOrdersRepository({
    required this.firstPage,
    required this.secondPage,
    this.highlighted,
  }) : super.demo(seed: const []);

  static final time = DateTime.utc(2026, 7, 22, 12);

  final List<Order> firstPage;
  final List<Order> secondPage;
  final Order? highlighted;
  final List<_PageCall> pageCalls = [];
  String? lookupCustomerId;

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
    pageCalls.add(
      _PageCall(
        customerId: customerId,
        status: status,
        statusValue: status?.value,
        statuses: statuses == null
            ? null
            : [for (final value in statuses) value.value],
        createdFrom: createdFrom,
        createdUntil: createdUntil,
        snapshotAt: snapshotAt,
        offset: offset,
        limit: pageSize,
      ),
    );
    final selected = offset == 0 ? firstPage : secondPage;
    return OrdersPage(
      orders: selected,
      hasMore: offset == 0 && secondPage.isNotEmpty,
      nextOffset: offset + selected.length,
      snapshotAt: snapshotAt ?? time,
    );
  }

  @override
  Future<Order?> orderById(
    String orderId, {
    String? customerId,
  }) async {
    lookupCustomerId = customerId;
    return highlighted?.id == orderId ? highlighted : null;
  }
}

class _PendingOrdersRepository extends OrdersRepository {
  _PendingOrdersRepository() : super.demo(seed: const []);

  final Completer<OrdersPage> _page = Completer<OrdersPage>();

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
  }) {
    return _page.future;
  }

  void complete() {
    if (_page.isCompleted) return;
    _page.complete(
      OrdersPage(
        orders: const [],
        hasMore: false,
        nextOffset: 0,
        snapshotAt: DateTime.utc(2026, 8, 25),
      ),
    );
  }
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(AppUser user) {
    state = AuthState(user: user);
  }
}

class _PageCall {
  const _PageCall({
    required this.customerId,
    required this.status,
    required this.statusValue,
    required this.statuses,
    required this.createdFrom,
    required this.createdUntil,
    required this.snapshotAt,
    required this.offset,
    required this.limit,
  });

  final String? customerId;
  final OrderStatus? status;
  final String? statusValue;
  final List<String>? statuses;
  final DateTime? createdFrom;
  final DateTime? createdUntil;
  final DateTime? snapshotAt;
  final int offset;
  final int limit;
}

Order _order({
  required String id,
  required String customerId,
  required DateTime createdAt,
  String? orderNumber,
  OrderStatus status = OrderStatus.pending,
  List<OrderLine> items = const [],
}) {
  return Order(
    id: id,
    orderNumber: orderNumber ?? id,
    customerId: customerId,
    businessName: 'متجر الاختبار',
    status: status,
    items: items,
    createdAt: createdAt,
  );
}

Map<String, dynamic> _row(
  String id,
  DateTime createdAt, {
  String customerId = 'customer-a',
}) {
  return {
    'id': id,
    'order_number': id,
    'customer_id': customerId,
    'status': 'pending',
    'created_at': createdAt.toIso8601String(),
    'order_items': const <Map<String, dynamic>>[],
    'status_history': const <Map<String, dynamic>>[],
  };
}
