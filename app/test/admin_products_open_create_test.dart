import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_products_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
      'products?action=create opens the product form then clears the query',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/admin/products?action=create',
      routes: [
        GoRoute(
          path: '/admin/products',
          builder: (context, state) => AdminProductsScreen(
            openCreateForm: state.uri.queryParameters['action'] == 'create',
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
            CatalogRepository.demo(seed: const []),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('منتج جديد'), findsWidgets);
    expect(find.byKey(const ValueKey('product-name-field')), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/admin/products');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['action'],
      isNull,
    );
  });
}

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-product-create-test',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
