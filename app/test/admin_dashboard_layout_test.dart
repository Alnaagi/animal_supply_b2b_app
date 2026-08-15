import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/admin_dashboard_screen.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/dashboard_widget_visibility.dart';
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

  testWidgets('gear hides a summary card and persists the preference',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/admin',
      routes: [
        GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminDashboardScreen(),
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
            OrdersRepository.demo(seed: const []),
          ),
          adminRepositoryProvider.overrideWithValue(AdminRepository()),
          dashboardWidgetPrefsProvider.overrideWithValue(
            DashboardWidgetPrefs(prefs: prefs),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لوحة الإدارة'), findsWidgets);
    expect(find.text('العملاء'), findsOneWidget);
    expect(find.text('طلبات تحتاج مراجعة'), findsOneWidget);
    expect(find.byKey(const Key('admin-dashboard-fullness-card')), findsOneWidget);
    expect(find.text('امتلاء البيانات'), findsOneWidget);
    expect(find.text('تجريبي'), findsWidgets);
    expect(
      find.text('تقدير تجريبي من الكتالوج والطلبات المحلية — غير تشغيلي'),
      findsOneWidget,
    );
    expect(
      Directionality.of(tester.element(find.text('لوحة الإدارة').first)),
      TextDirection.rtl,
    );

    await tester.tap(find.byKey(const Key('admin-dashboard-layout-settings')));
    await tester.pumpAndSettle();

    expect(find.text('تخصيص عناصر اللوحة'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('admin-dashboard-widget-toggle-customers')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('admin-dashboard-widget-toggle-pending_orders_panel'),
      ),
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('تخصيص عناصر اللوحة'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('العملاء'), findsNothing);
    expect(find.text('طلبات تحتاج مراجعة'), findsNothing);
    expect(find.text('نشطين'), findsOneWidget);

    final stored = DashboardWidgetVisibility.decode(
      prefs.getString(DashboardWidgetPrefs.storageKey),
    );
    expect(stored.isVisible(DashboardWidgetId.customers), isFalse);
    expect(stored.isVisible(DashboardWidgetId.pendingOrdersPanel), isFalse);
    expect(stored.isVisible(DashboardWidgetId.dataFullness), isTrue);
  });
}

Product _product() {
  return const Product(
    id: 'dash-product',
    nameAr: 'علف اختبار',
    sku: 'SKU-DASH',
    category: 'كلاب',
    animalType: '',
    brand: 'شركة اختبار',
    unitSize: 'عبوة',
    basePrice: 20,
    stockQuantity: 4,
    minOrderQty: 1,
  );
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-dashboard-layout-test',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
