import 'package:animal_supply_b2b/src/core/config/app_config.dart';
import 'package:animal_supply_b2b/src/core/routing/app_router.dart';
import 'package:animal_supply_b2b/src/data/local/local_auth_session_store.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/repositories/demo_data.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.debugSetSupabaseInitialized(true);
  });

  tearDown(() {
    AppConfig.debugSetSupabaseInitialized(false);
  });

  group('Production Auth & Demo Hardening', () {
    test('AppConfig guards strictly prohibit demo mode when Supabase is active', () {
      expect(AppConfig.hasSupabase, isTrue);
      expect(AppConfig.isDemoMode, isFalse);
      expect(AppConfig.allowsDemoCredentials, isFalse);
    });

    testWidgets('LoginScreen completely hides quick demo login pills in production/backend mode',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _HardenedAuthController(),
            ),
          ],
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: LoginScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('دخول'), findsOneWidget);
      // In production / when allowsDemoCredentials is false, quick login pills must be completely absent.
      expect(find.textContaining('تجربة سريعة'), findsNothing);
      expect(find.text('مدير'), findsNothing);
      expect(find.text('موظف'), findsNothing);
      expect(find.text('عميل'), findsNothing);
    });

    test('AuthController rejects demo credentials when backend is active',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LocalAuthSessionStore(prefs: prefs);
      final controller = AuthController(sessionStore: store);
      await controller.restoreSession();

      // Attempting to use demo login when backend is active
      // must not grant admin or customer access.
      await controller.login('admin', demoAdminPassword);
      expect(controller.state.user, isNull);
    });

    test('LocalAuthSessionStore never loads demo user when demo is disallowed',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        LocalAuthSessionStore.userKey,
        '{"id":"admin-1"}',
      );

      final store = LocalAuthSessionStore(prefs: prefs);
      final user = await store.readDemoUser();
      expect(user, isNull);
      expect(prefs.getString(LocalAuthSessionStore.userKey), isNull);
    });

    testWidgets('GoRouter redirects unauthenticated users away from /admin',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _UnauthenticatedAuthController(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.go('/admin');
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/login');
    });

    testWidgets('GoRouter prevents customer role from accessing admin panel',
        (tester) async {
      const customerUser = AppUser(
        id: 'cust-1',
        username: 'customer1',
        role: 'customer',
        accountStatus: 'active',
        isDemo: false,
      );

      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _CustomerAuthController(customerUser),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.go('/admin');
      await tester.pumpAndSettle();

      // Must be redirected to /home
      expect(router.state.matchedLocation, '/home');

      router.go('/admin/orders');
      await tester.pumpAndSettle();

      // Admin sub-routes also redirect customer to /home
      expect(router.state.matchedLocation, '/home');
    });
  });
}

class _HardenedAuthController extends AuthController {
  _HardenedAuthController() {
    state = const AuthState();
  }
}

class _UnauthenticatedAuthController extends AuthController {
  _UnauthenticatedAuthController() {
    state = const AuthState();
  }
}

class _CustomerAuthController extends AuthController {
  _CustomerAuthController(AppUser user) {
    state = AuthState(user: user);
  }
}
