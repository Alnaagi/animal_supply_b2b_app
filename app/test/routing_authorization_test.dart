import 'package:animal_supply_b2b/src/core/routing/app_router.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/storefront_repository.dart';
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
  testWidgets('unauthenticated protected links preserve a safe next route',
      (tester) async {
    final harness = await _pumpRouter(tester, const AuthState());
    addTearDown(harness.dispose);

    harness.router.go('/admin/orders?order=order-1');
    await _pumpNavigation(tester);

    final uri = harness.router.routeInformationProvider.value.uri;
    expect(uri.path, '/login');
    expect(uri.queryParameters['next'], '/admin/orders?order=order-1');
  });

  testWidgets('forced password change blocks all application routes',
      (tester) async {
    final harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'customer', mustChangePassword: true)),
    );
    addTearDown(harness.dispose);

    harness.router.go('/orders?order=order-1');
    await _pumpNavigation(tester);

    final uri = harness.router.routeInformationProvider.value.uri;
    expect(uri.path, '/change-password');
    expect(uri.queryParameters['next'], '/orders?order=order-1');
  });

  testWidgets('customer, staff, and admin routes remain role-scoped',
      (tester) async {
    var harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'customer')),
    );
    harness.router.go('/admin/settings');
    await _pumpNavigation(tester);
    expect(
      harness.router.routeInformationProvider.value.uri.path,
      '/home',
    );
    harness.dispose();

    harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'staff')),
    );
    harness.router.go('/admin/reports');
    await _pumpNavigation(tester);
    expect(
      harness.router.routeInformationProvider.value.uri.path,
      '/admin',
    );
    harness.router.go('/admin/storefront');
    await _pumpNavigation(tester);
    expect(
      harness.router.routeInformationProvider.value.uri.path,
      '/admin',
    );
    harness.dispose();

    harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'admin')),
    );
    harness.router.go('/orders?order=order-1');
    await _pumpNavigation(tester);
    final uri = harness.router.routeInformationProvider.value.uri;
    expect(uri.path, '/admin/orders');
    expect(uri.queryParameters['order'], 'order-1');
    harness.dispose();
  });

  testWidgets('unknown admin paths render the Arabic not-found page',
      (tester) async {
    final harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'admin')),
    );
    addTearDown(harness.dispose);

    harness.router.go('/admin/not-a-real-page');
    await _pumpNavigation(tester);

    expect(find.text('تعذر العثور على هذه الصفحة'), findsOneWidget);
    expect(find.textContaining('/admin/not-a-real-page'), findsOneWidget);
  });

  testWidgets('legacy order success routes redirect to orders safely',
      (tester) async {
    final harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'customer')),
    );
    addTearDown(harness.dispose);

    harness.router.go('/order-success');
    await _pumpNavigation(tester);
    expect(harness.router.routeInformationProvider.value.uri.path, '/orders');

    harness.router.go('/order-success/');
    await _pumpNavigation(tester);
    expect(harness.router.routeInformationProvider.value.uri.path, '/orders');
  });

  testWidgets('orders success query remains in customer shell with bottom nav',
      (tester) async {
    final harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'customer')),
    );
    addTearDown(harness.dispose);

    harness.router.go('/orders?order=ord_1&success=1');
    await _pumpNavigation(tester);

    expect(harness.router.routeInformationProvider.value.uri.path, '/orders');
    expect(find.text('الطلبات'), findsOneWidget);
  });

  testWidgets(
    'customer detail paths keep one app bar and bottom navigation on mobile',
    (tester) async {
      await _expectCustomerDetailRoutesInShell(
        tester,
        size: const Size(390, 844),
        desktop: false,
      );
    },
  );

  testWidgets(
    'customer detail paths keep branded top bar and rail on desktop',
    (tester) async {
      await _expectCustomerDetailRoutesInShell(
        tester,
        size: const Size(1280, 1000),
        desktop: true,
      );
    },
  );

  testWidgets('customer detail paths remain protected and role scoped',
      (tester) async {
    var harness = await _pumpRouter(tester, const AuthState());
    for (final route in _customerDetailRoutes) {
      harness.router.go(route.path);
      await _pumpNavigation(tester);
      final uri = harness.router.routeInformationProvider.value.uri;
      expect(uri.path, '/login', reason: route.path);
      expect(uri.queryParameters['next'], route.path, reason: route.path);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();

    harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'admin')),
    );
    for (final route in _customerDetailRoutes) {
      harness.router.go(route.path);
      await _pumpNavigation(tester);
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        route.path.startsWith('/product/') ? '/admin/products' : '/admin',
        reason: route.path,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('preserved destinations remove unsupported query parameters',
      (tester) async {
    final harness = await _pumpRouter(tester, const AuthState());
    addTearDown(harness.dispose);

    harness.router.go(
      '/admin/orders?order=order-1&period=today&redirect=https://example.com',
    );
    await _pumpNavigation(tester);

    final uri = harness.router.routeInformationProvider.value.uri;
    expect(uri.path, '/login');
    expect(
      uri.queryParameters['next'],
      '/admin/orders?order=order-1&period=today',
    );
  });
  testWidgets('bootstrap keeps a protected screen instead of the landing page',
      (tester) async {
    final auth = _MutableAuthController(
      const AuthState(loading: true, bootstrapping: true),
    );
    final harness = await _pumpRouterWithController(tester, auth);
    addTearDown(harness.dispose);

    harness.router.go('/admin/reports');
    await _pumpNavigation(tester);

    var uri = harness.router.routeInformationProvider.value.uri;
    expect(uri.path, '/auth-loading');
    expect(uri.queryParameters['next'], '/admin/reports');

    auth.emit(AuthState(user: _user(role: 'admin')));
    await _pumpNavigation(tester);

    uri = harness.router.routeInformationProvider.value.uri;
    expect(uri.path, '/admin/reports');
  });

  testWidgets('restored route resumes after a login-style public location',
      (tester) async {
    final harness = await _pumpRouter(
      tester,
      AuthState(
        user: _user(role: 'admin'),
        restoredRoute: '/admin/reports',
      ),
    );
    addTearDown(harness.dispose);

    harness.router.go('/login');
    await _pumpNavigation(tester);

    expect(
      harness.router.routeInformationProvider.value.uri.path,
      '/admin/reports',
    );
  });
}

Future<_RouterHarness> _pumpRouter(
  WidgetTester tester,
  AuthState state, {
  Size size = const Size(1280, 1800),
}) {
  return _pumpRouterWithController(
    tester,
    _FixedAuthController(state),
    size: size,
  );
}

Future<_RouterHarness> _pumpRouterWithController(
  WidgetTester tester,
  AuthController controller, {
  Size size = const Size(1280, 1800),
}) async {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => controller),
      appSettingsProvider.overrideWith(
        (ref) async => const AppSettingsData(shopName: 'متجر الاختبار'),
      ),
      catalogRepositoryProvider.overrideWithValue(
        CatalogRepository.demo(seed: const [_shellRouteProduct]),
      ),
      publishedStorefrontConfigProvider.overrideWith(
        (ref) async => StorefrontDefaults.bundled,
      ),
    ],
  );
  final router = container.read(appRouterProvider);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            accessibleNavigation: true,
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await _pumpNavigation(tester);
  return _RouterHarness(container, router);
}

Future<void> _expectCustomerDetailRoutesInShell(
  WidgetTester tester, {
  required Size size,
  required bool desktop,
}) async {
  for (final route in _customerDetailRoutes) {
    final harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'customer')),
      size: size,
    );
    try {
      expect(
        tester.takeException(),
        isNull,
        reason: 'Initial customer shell before ${route.path}',
      );
      harness.router.go(route.path);
      await _pumpNavigation(tester);
      expect(tester.takeException(), isNull, reason: route.path);

      expect(
        harness.router.routeInformationProvider.value.uri.path,
        route.path,
        reason: route.path,
      );
      expect(
        find.byKey(const Key('customer-shell-scaffold')),
        findsOneWidget,
        reason: route.path,
      );
      expect(
        find.widgetWithText(AppBar, route.title),
        findsOneWidget,
        reason: route.path,
      );

      if (desktop) {
        expect(
          find.byKey(const Key('customer-desktop-app-bar')),
          findsOneWidget,
          reason: route.path,
        );
        expect(
          find.byKey(const Key('customer-mobile-app-bar')),
          findsNothing,
          reason: route.path,
        );
        final railFinder = find.byKey(const Key('customer-navigation-rail'));
        expect(railFinder, findsOneWidget, reason: route.path);
        expect(
          tester.widget<NavigationRail>(railFinder).selectedIndex,
          route.branchIndex,
          reason: route.path,
        );
        expect(
          find.byKey(const Key('customer-bottom-navigation')),
          findsNothing,
          reason: route.path,
        );
        expect(find.byType(AppBar), findsNWidgets(2), reason: route.path);
        await tester.tap(
          find.descendant(
            of: railFinder,
            matching: find.text(route.navigationLabel),
          ),
        );
      } else {
        expect(
          find.byKey(const Key('customer-mobile-app-bar')),
          findsNothing,
          reason: 'The route app bar should replace the shell app bar.',
        );
        expect(
          find.byKey(const Key('customer-desktop-app-bar')),
          findsNothing,
          reason: route.path,
        );
        final navigationFinder =
            find.byKey(const Key('customer-bottom-navigation'));
        expect(navigationFinder, findsOneWidget, reason: route.path);
        expect(
          tester.widget<NavigationBar>(navigationFinder).selectedIndex,
          route.branchIndex,
          reason: route.path,
        );
        expect(
          find.byKey(const Key('customer-navigation-rail')),
          findsNothing,
          reason: route.path,
        );
        expect(find.byType(AppBar), findsOneWidget, reason: route.path);
        await tester.tap(
          find.descendant(
            of: navigationFinder,
            matching: find.text(route.navigationLabel),
          ),
        );
      }

      await _pumpNavigation(tester);
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        route.rootPath,
        reason: 'Selecting ${route.navigationLabel} should return to its root.',
      );
      expect(
        find.byKey(const Key('customer-shell-scaffold')),
        findsOneWidget,
        reason: route.path,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    }
  }
}

Future<void> _pumpNavigation(WidgetTester tester) async {
  // Route redirects are synchronous, but the destination screens intentionally
  // contain continuous progress and carousel animations. Waiting for a fully
  // settled frame would therefore never be a valid authorization assertion.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

const _customerDetailRoutes = <({
  String path,
  String title,
  int branchIndex,
  String rootPath,
  String navigationLabel,
})>[
  (
    path: '/product/route-product',
    title: 'تفاصيل المنتج',
    branchIndex: 1,
    rootPath: '/catalog',
    navigationLabel: 'المنتجات',
  ),
  (
    path: '/checkout',
    title: 'تأكيد الطلب',
    branchIndex: 2,
    rootPath: '/cart',
    navigationLabel: 'السلة',
  ),
  (
    path: '/offers',
    title: 'العروض',
    branchIndex: 0,
    rootPath: '/home',
    navigationLabel: 'الرئيسية',
  ),
  (
    path: '/support',
    title: 'المساعدة والدعم',
    branchIndex: 4,
    rootPath: '/profile',
    navigationLabel: 'الحساب',
  ),
];

const _shellRouteProduct = Product(
  id: 'route-product',
  nameAr: 'منتج اختبار المسار',
  sku: 'ROUTE-1',
  category: 'اختبار',
  animalType: 'عام',
  brand: 'المتجر',
  unitSize: '1 صندوق',
  basePrice: 10,
  discountPercent: 10,
  stockQuantity: 20,
  minOrderQty: 1,
);

AppUser _user({
  required String role,
  bool mustChangePassword = false,
}) {
  return AppUser(
    id: '$role-profile',
    username: role,
    role: role,
    customerId: role == 'customer' ? 'customer-1' : null,
    accountStatus: 'active',
    mustChangePassword: mustChangePassword,
  );
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(AuthState initial) {
    state = initial;
  }
}

class _MutableAuthController extends AuthController {
  _MutableAuthController(AuthState initial) {
    state = initial;
  }

  void emit(AuthState next) => state = next;
}

class _RouterHarness {
  const _RouterHarness(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  void dispose() {
    router.dispose();
    container.dispose();
  }
}
