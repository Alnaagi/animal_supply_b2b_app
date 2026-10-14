import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/admin_shell.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/admin_text_scale.dart';
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

  test('admin text scale clamps, persists, and reloads', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        adminTextScalePrefsProvider.overrideWithValue(
          AdminTextScalePrefs(prefs: prefs),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(adminTextScaleProvider.notifier);
    await controller.setScale(1.23);
    expect(container.read(adminTextScaleProvider), 1.23);
    await controller.setScale(2);
    expect(container.read(adminTextScaleProvider), adminTextScaleMax);
    await controller.setScale(.1);
    expect(container.read(adminTextScaleProvider), adminTextScaleMin);

    final reloaded = ProviderContainer(
      overrides: [
        adminTextScalePrefsProvider.overrideWithValue(
          AdminTextScalePrefs(prefs: prefs),
        ),
      ],
    );
    addTearDown(reloaded.dispose);
    await reloaded.read(adminTextScaleProvider.notifier).reload();
    expect(reloaded.read(adminTextScaleProvider), adminTextScaleMin);
  });

  testWidgets('admin toolbar controls scale the whole shell text',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/admin/orders',
      routes: [
        GoRoute(
          path: '/admin/orders',
          builder: (context, state) => const AdminShell(
            title: 'الطلبات',
            child: Center(
              child: Text(
                '1.0',
                key: Key('admin-text-scale-probe'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _AdminAuth()),
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

    expect(find.byKey(const Key('admin-text-scale-controls')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(
        MediaQuery.textScalerOf(tester.element(
          find.byKey(const Key('admin-text-scale-probe')),
        )).scale(1),
        1);

    await tester.tap(find.byKey(const Key('admin-text-scale-increase')));
    await tester.pump();
    expect(find.text('110%'), findsOneWidget);
    expect(
        MediaQuery.textScalerOf(tester.element(
          find.byKey(const Key('admin-text-scale-probe')),
        )).scale(1),
        1.1);

    await tester.tap(find.byKey(const Key('admin-text-scale-decrease')));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
  });
}

class _AdminAuth extends AuthController {
  _AdminAuth() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-text-scale-test',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
