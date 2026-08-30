import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/storefront_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/customer_home/customer_shell.dart';
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
    'phone shell uses bottom navigation and header WhatsApp action',
    (tester) async {
      final router = await _pumpShell(
        tester,
        size: const Size(390, 844),
        disableAnimations: true,
      );
      addTearDown(() => _disposeHarness(tester, router));

      expect(find.byKey(const Key('customer-bottom-navigation')), findsOne);
      expect(find.byKey(const Key('customer-navigation-rail')), findsNothing);
      expect(find.byKey(const Key('customer-mobile-app-bar')), findsOne);
      expect(find.byKey(const Key('customer-desktop-app-bar')), findsNothing);
      expect(find.byKey(const Key('customer-mobile-support-action')), findsOne);
      expect(find.byKey(const Key('customer-mobile-logout-action')), findsOne);
      expect(find.byKey(const Key('customer-support-nudge')), findsOne);
      expect(
        tester
            .getSize(find.byKey(const Key('customer-support-nudge-frame')))
            .width,
        48,
      );
      expect(
        tester
            .widget<Scaffold>(
              find.byKey(const Key('customer-shell-scaffold')),
            )
            .floatingActionButton,
        isNull,
      );
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('customer-shell-scaffold'))),
        ),
        TextDirection.rtl,
      );
      // RTL: leading (WhatsApp) is visual right; actions (logout) is visual left.
      final supportDx = tester
          .getCenter(find.byKey(const Key('customer-mobile-support-action')))
          .dx;
      final logoutDx = tester
          .getCenter(find.byKey(const Key('customer-mobile-logout-action')))
          .dx;
      expect(supportDx, greaterThan(logoutDx));

      final shellBox = tester.renderObject<RenderBox>(
        find.byKey(const Key('customer-shell-scaffold')),
      );
      final navBox = tester.renderObject<RenderBox>(
        find.byKey(const Key('customer-bottom-navigation')),
      );
      expect(navBox.size.width, shellBox.size.width);
      expect(navBox.localToGlobal(Offset.zero).dx, shellBox.localToGlobal(Offset.zero).dx);
      expect(
        navBox.localToGlobal(Offset.zero).dy + navBox.size.height,
        shellBox.localToGlobal(Offset.zero).dy + shellBox.size.height,
      );
      final decoratedBox = tester.widget<DecoratedBox>(
        find.ancestor(
          of: find.byKey(const Key('customer-bottom-navigation')),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.border?.top, isNotNull);
      expect(decoration.borderRadius, isNull);

      await tester.tap(find.text('المنتجات'));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/catalog');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone support prompt reveals inside the app bar and fades shop identity',
    (tester) async {
      final router = await _pumpShell(
        tester,
        size: const Size(338, 838),
        disableAnimations: false,
      );
      addTearDown(() => _disposeHarness(tester, router));

      expect(
        tester
            .getSize(find.byKey(const Key('customer-support-nudge-frame')))
            .width,
        48,
      );
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const Key('customer-shop-identity-opacity')),
            )
            .opacity,
        1,
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(AppMotion.emphasized);

      expect(
        tester
            .getSize(find.byKey(const Key('customer-support-nudge-frame')))
            .width,
        186,
      );
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const Key('customer-shop-identity-opacity')),
            )
            .opacity,
        0,
      );
      expect(find.text('تحتاج مساعدة؟ اضغط هنا'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet and desktop shell use an adaptive rail and capped content',
    (tester) async {
      final router = await _pumpShell(
        tester,
        size: const Size(768, 900),
        disableAnimations: true,
      );
      addTearDown(() => _disposeHarness(tester, router));

      expect(find.byKey(const Key('customer-bottom-navigation')), findsNothing);
      expect(find.byKey(const Key('customer-navigation-rail')), findsOne);
      expect(find.byKey(const Key('customer-desktop-app-bar')), findsOne);
      expect(
        find.byKey(const Key('customer-desktop-support-action')),
        findsOne,
      );
      expect(
        find.byKey(const Key('customer-desktop-logout-action')),
        findsOne,
      );
      expect(
        tester
            .widget<NavigationRail>(
              find.byKey(const Key('customer-navigation-rail')),
            )
            .extended,
        isFalse,
      );

      await tester.binding.setSurfaceSize(const Size(1024, 900));
      await tester.pump();
      expect(
        tester
            .widget<NavigationRail>(
              find.byKey(const Key('customer-navigation-rail')),
            )
            .extended,
        isTrue,
      );

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pump();
      expect(
        tester
            .widget<NavigationRail>(
              find.byKey(const Key('customer-navigation-rail')),
            )
            .extended,
        isTrue,
      );

      await tester.binding.setSurfaceSize(const Size(1700, 900));
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const Key('customer-centered-content')))
            .width,
        lessThanOrEqualTo(1320),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<GoRouter> _pumpShell(
  WidgetTester tester, {
  required Size size,
  required bool disableAnimations,
}) async {
  await tester.binding.setSurfaceSize(size);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => CustomerShell(
          shell: shell,
          currentLocation: state.uri.path,
        ),
        branches: [
          _branch('/home', 'home-branch'),
          _branch('/catalog', 'catalog-branch'),
          _branch('/cart', 'cart-branch'),
          _branch('/orders', 'orders-branch'),
          _branch('/profile', 'profile-branch'),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _SignedOutAuthController(),
        ),
        appSettingsProvider.overrideWith(
          (ref) async => const AppSettingsData(
            shopName: 'متجر الاختبار',
            supportWhatsapp: '+218 91 234 5678',
          ),
        ),
        publishedStorefrontConfigProvider.overrideWith(
          (ref) async => StorefrontDefaults.bundled,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              accessibleNavigation: disableAnimations,
              disableAnimations: disableAnimations,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return router;
}

StatefulShellBranch _branch(String path, String key) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        builder: (context, state) => ColoredBox(
          key: ValueKey(key),
          color: Colors.transparent,
        ),
      ),
    ],
  );
}

Future<void> _disposeHarness(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(const SizedBox.shrink());
  router.dispose();
  await tester.binding.setSurfaceSize(null);
}

class _SignedOutAuthController extends AuthController {
  _SignedOutAuthController() {
    state = const AuthState();
  }
}
