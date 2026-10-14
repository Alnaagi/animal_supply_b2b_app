import 'package:animal_supply_b2b/src/core/notifications/cart_reminder_coordinator.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/storefront_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_controller.dart';
import 'package:animal_supply_b2b/src/features/customer_home/cart_attention_nudge_icon.dart';
import 'package:animal_supply_b2b/src/features/customer_home/customer_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mockCustomerUser = AppUser(
  id: 'cust-1',
  username: 'customer1',
  role: 'customer',
  businessName: 'مزرعة الأمل',
  phone: '0912345678',
);

const _sampleProduct = Product(
  id: 'prod-1',
  nameAr: 'علف دواجن ممتاز',
  sku: 'FEED-001',
  category: 'أعلاف',
  animalType: 'دواجن',
  brand: 'البركة',
  unitSize: 'كيس 50 كجم',
  basePrice: 65,
  minOrderQty: 5,
  stockQuantity: 100,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CartAttentionNudgeIcon Unit Tests', () {
    testWidgets('renders badge and icon at rest', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CartAttentionNudgeIcon(
                count: 3,
                icon: Icons.shopping_cart_outlined,
                isNudging: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('customer-cart-nav-badge')), findsOneWidget);
      expect(find.byKey(const Key('customer-cart-nav-icon')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(
        find.byKey(const Key('customer-cart-nudge-transform')),
        findsOneWidget,
      );
    });

    testWidgets('animates wiggle and bounce when isNudging is true',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CartAttentionNudgeIcon(
                count: 5,
                icon: Icons.shopping_cart_outlined,
                isNudging: true,
              ),
            ),
          ),
        ),
      );

      // Advance animation slightly
      await tester.pump(const Duration(milliseconds: 200));

      final transformFinder =
          find.byKey(const Key('customer-cart-nudge-transform'));
      expect(transformFinder, findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      // Advance animation through peak wiggle
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('5'), findsOneWidget);

      // Complete full cycle (1800ms)
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
    });

    testWidgets('suppresses animation when reduceMotion is enabled',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CartAttentionNudgeIcon(
                count: 4,
                icon: Icons.shopping_cart_outlined,
                isNudging: true,
                reduceMotion: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('4'), findsOneWidget);
      expect(
        find.byKey(const Key('customer-cart-nudge-transform')),
        findsNothing,
      );
    });

    testWidgets('restarts animation when count increases while isNudging is true',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CartAttentionNudgeIcon(
                count: 2,
                icon: Icons.shopping_cart_outlined,
                isNudging: true,
              ),
            ),
          ),
        ),
      );

      // Advance animation halfway
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('2'), findsOneWidget);

      // Update widget with increased count
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CartAttentionNudgeIcon(
                count: 5,
                icon: Icons.shopping_cart_outlined,
                isNudging: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('5'), findsOneWidget);
      expect(
        find.byKey(const Key('customer-cart-nudge-transform')),
        findsOneWidget,
      );
    });
  });

  group('CustomerShell Add To Cart & Scrolling Nudge Integration Tests', () {
    testWidgets(
        'adding item to cart immediately triggers cart nudge on mobile bottom nav',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(user: _mockCustomerUser),
          ),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(
              shopName: 'متجر الأعلاف',
              supportWhatsapp: '+218 91 000 0000',
            ),
          ),
          publishedStorefrontConfigProvider.overrideWith(
            (ref) async => StorefrontDefaults.bundled,
          ),
          cartReminderCoordinatorProvider.overrideWithValue(
            _NoopCartReminderCoordinator(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => CustomerShell(
              shell: shell,
              currentLocation: state.uri.path,
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (context, state) => const Scaffold(
                      body: Text('الرئيسية'),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/catalog',
                    builder: (context, state) => const Text('المنتجات'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/cart',
                    builder: (context, state) => const Text('شاشة السلة'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/orders',
                    builder: (context, state) => const Text('الطلبات'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/profile',
                    builder: (context, state) => const Text('الحساب'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initially cart is empty
      expect(find.text('الرئيسية'), findsWidgets);

      // Add item to cart
      container
          .read(cartControllerProvider.notifier)
          .addQuantity(_sampleProduct, 6);

      // Re-pump to let Riverpod listener react immediately
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Cart badge shows count 6 and nudge animation is running
      expect(find.text('6'), findsOneWidget);
      final transformFinder =
          find.byKey(const Key('customer-cart-nudge-transform'));
      expect(transformFinder, findsOneWidget);

      // After animation finishes
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pump();
    });

    testWidgets(
        'adding item to cart immediately triggers cart nudge on desktop navigation rail',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(user: _mockCustomerUser),
          ),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(
              shopName: 'متجر الأعلاف',
              supportWhatsapp: '+218 91 000 0000',
            ),
          ),
          publishedStorefrontConfigProvider.overrideWith(
            (ref) async => StorefrontDefaults.bundled,
          ),
          cartReminderCoordinatorProvider.overrideWithValue(
            _NoopCartReminderCoordinator(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => CustomerShell(
              shell: shell,
              currentLocation: state.uri.path,
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (context, state) => const Scaffold(
                      body: Text('الرئيسية'),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/catalog',
                    builder: (context, state) => const Text('المنتجات'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/cart',
                    builder: (context, state) => const Text('شاشة السلة'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/orders',
                    builder: (context, state) => const Text('الطلبات'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/profile',
                    builder: (context, state) => const Text('الحساب'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      // Desktop width
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('customer-navigation-rail')), findsOneWidget);

      // Add item to cart
      container
          .read(cartControllerProvider.notifier)
          .addQuantity(_sampleProduct, 10);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('10'), findsOneWidget);
      final transformFinder =
          find.byKey(const Key('customer-cart-nudge-transform'));
      expect(transformFinder, findsOneWidget);
    });
    testWidgets(
        'scrolling with items in cart triggers cart nudge after prolonged browsing',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(user: _mockCustomerUser),
          ),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(
              shopName: 'متجر الأعلاف',
              supportWhatsapp: '+218 91 000 0000',
            ),
          ),
          publishedStorefrontConfigProvider.overrideWith(
            (ref) async => StorefrontDefaults.bundled,
          ),
          cartReminderCoordinatorProvider.overrideWithValue(
            _NoopCartReminderCoordinator(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Add item to cart
      container
          .read(cartControllerProvider.notifier)
          .addQuantity(_sampleProduct, 5);

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => CustomerShell(
              shell: shell,
              currentLocation: state.uri.path,
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (context, state) => Scaffold(
                      body: ListView.builder(
                        itemCount: 50,
                        itemBuilder: (context, index) => ListTile(
                          title: Text('عنصر $index'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/catalog',
                    builder: (context, state) => const Text('المنتجات'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/cart',
                    builder: (context, state) => const Text('شاشة السلة'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/orders',
                    builder: (context, state) => const Text('الطلبات'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/profile',
                    builder: (context, state) => const Text('الحساب'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Cart count is visible in bottom nav
      expect(find.text('5'), findsOneWidget);

      // User scrolls in the listview
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();

      // Advance time by 23 seconds of browsing activity
      await tester.pump(const Duration(seconds: 23));

      // Nudge animation transform is running!
      final transformFinder =
          find.byKey(const Key('customer-cart-nudge-transform'));
      expect(transformFinder, findsOneWidget);

      // Navigating to cart immediately switches to cart
      await tester.tap(find.text('السلة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(router.routeInformationProvider.value.uri.path, '/cart');
      expect(find.text('شاشة السلة'), findsOneWidget);
    });
  });
}

class _FakeAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _FakeAuthController({AppUser? user})
      : super(AuthState(bootstrapping: false, user: user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopCartReminderCoordinator implements CartReminderCoordinator {
  @override
  void dispose() {}

  @override
  Future<void> checkDueReminders({required bool hasItems}) async {}

  @override
  Future<void> syncCartState({required bool hasItems}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
