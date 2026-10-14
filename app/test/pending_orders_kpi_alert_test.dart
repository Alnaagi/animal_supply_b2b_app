import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/admin_dashboard_screen.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/dashboard_widget_visibility.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/pending_orders_kpi_alert.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const logic = PendingOrdersKpiAlertLogic();

  test('new pending orders highlight until acknowledged', () {
    var state = const PendingOrdersKpiAlertState();
    state = logic.observe(state: state, pendingCount: 2);
    expect(state.shouldHighlight, isTrue);

    state = logic.acknowledge(state);
    expect(state.shouldHighlight, isFalse);

    state = logic.observe(state: state, pendingCount: 2);
    expect(state.shouldHighlight, isFalse);

    state = logic.observe(state: state, pendingCount: 3);
    expect(state.shouldHighlight, isTrue);
  });

  test('zero pending never flashes and a later increase flashes again', () {
    var state = logic.observe(
      state: const PendingOrdersKpiAlertState(),
      pendingCount: 4,
    );
    state = logic.acknowledge(state);
    state = logic.observe(state: state, pendingCount: 0);
    expect(state.shouldHighlight, isFalse);
    expect(state.acknowledgedCount, 0);

    state = logic.observe(state: state, pendingCount: 1);
    expect(state.shouldHighlight, isTrue);
  });

  test('opening orders before the first count still calms the next observe',
      () {
    var state = logic.acknowledge(const PendingOrdersKpiAlertState());
    expect(state.ackOnNextObserve, isTrue);
    expect(state.shouldHighlight, isFalse);

    state = logic.observe(state: state, pendingCount: 5);
    expect(state.ackOnNextObserve, isFalse);
    expect(state.shouldHighlight, isFalse);
    expect(state.acknowledgedCount, 5);
  });

  testWidgets('pending KPI pulses then calms after opening orders',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final router = GoRouter(
      initialLocation: '/admin',
      routes: [
        GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminDashboardScreen(),
        ),
        GoRoute(
          path: '/admin/orders',
          builder: (context, state) => const Scaffold(
            body: Text('إدارة الطلبات'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _AdminAuthController(),
          ),
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepository.demo(seed: [_product()]),
          ),
          ordersRepositoryProvider.overrideWithValue(
            OrdersRepository.demo(seed: [_pendingOrder()]),
          ),
          adminRepositoryProvider.overrideWithValue(AdminRepository()),
          dashboardWidgetPrefsProvider.overrideWithValue(
            DashboardWidgetPrefs(prefs: prefs),
          ),
          pendingOrdersKpiAlertStoreProvider.overrideWithValue(
            PendingOrdersKpiAlertStore(prefs: prefs),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('طلبات معلقة'), findsOneWidget);
    expect(
      find.byKey(const Key('admin-dashboard-pending-orders-alert')),
      findsOneWidget,
    );
    expect(
      Directionality.of(tester.element(find.text('طلبات معلقة'))),
      TextDirection.rtl,
    );

    await tester
        .tap(find.byKey(const Key('admin-dashboard-pending-orders-card')));
    await tester.pumpAndSettle();

    expect(find.text('إدارة الطلبات'), findsOneWidget);

    router.go('/admin');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('admin-dashboard-pending-orders-alert')),
      findsNothing,
    );
    expect(find.text('طلبات معلقة'), findsOneWidget);
  });
}

Product _product() {
  return const Product(
    id: 'dash-pending-product',
    nameAr: 'علف اختبار',
    sku: 'SKU-PENDING',
    category: 'كلاب',
    animalType: '',
    brand: 'شركة اختبار',
    unitSize: 'عبوة',
    basePrice: 20,
    stockQuantity: 4,
    minOrderQty: 1,
  );
}

Order _pendingOrder() {
  return Order(
    id: 'pending-kpi-order',
    customerId: 'customer-1',
    status: OrderStatus.pending,
    items: const [],
    createdAt: DateTime(2026, 8, 16),
    businessName: 'عميل تجريبي',
  );
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-pending-kpi-test',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
