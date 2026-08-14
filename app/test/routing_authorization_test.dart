import 'package:animal_supply_b2b/src/core/routing/app_router.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
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
}

Future<_RouterHarness> _pumpRouter(
  WidgetTester tester,
  AuthState state,
) async {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => _FixedAuthController(state)),
    ],
  );
  final router = container.read(appRouterProvider);
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

Future<void> _pumpNavigation(WidgetTester tester) async {
  // Route redirects are synchronous, but the destination screens intentionally
  // contain continuous progress and carousel animations. Waiting for a fully
  // settled frame would therefore never be a valid authorization assertion.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

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

class _RouterHarness {
  const _RouterHarness(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  void dispose() {
    router.dispose();
    container.dispose();
  }
}
