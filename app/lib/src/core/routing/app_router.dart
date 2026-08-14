import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin_archive/admin_archive_screen.dart';
import '../../features/admin_customers/admin_customers_screen.dart';
import '../../features/admin_dashboard/admin_dashboard_screen.dart';
import '../../features/admin_orders/admin_orders_screen.dart';
import '../../features/admin_products/admin_products_screen.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/cart/cart_screen.dart';
import '../../features/cart/checkout_screen.dart';
import '../../features/catalog/catalog_screen.dart';
import '../../features/catalog/product_details_screen.dart';
import '../../features/customer_home/customer_home_screen.dart';
import '../../features/customer_home/customer_shell.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/settings/settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggedIn = auth.user != null;
      if (!loggedIn && state.matchedLocation != '/login') return '/login';
      if (loggedIn && state.matchedLocation == '/login') {
        return auth.user!.isAdminLike ? '/admin' : '/home';
      }
      if (loggedIn &&
          state.matchedLocation.startsWith('/admin') &&
          !auth.user!.isAdminLike) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/home',
                builder: (context, state) => const CustomerHomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/catalog',
                builder: (context, state) => CatalogScreen(
                    initialCategory: state.uri.queryParameters['category'])),
            GoRoute(
                path: '/product/:id',
                builder: (context, state) => ProductDetailsScreen(
                    productId: state.pathParameters['id']!)),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/cart', builder: (context, state) => const CartScreen()),
            GoRoute(
                path: '/checkout',
                builder: (context, state) => const CheckoutScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/orders',
                builder: (context, state) => const OrdersScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen()),
          ]),
        ],
      ),
      GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminDashboardScreen()),
      GoRoute(
          path: '/admin/customers',
          builder: (context, state) => const AdminCustomersScreen()),
      GoRoute(
          path: '/admin/products',
          builder: (context, state) => const AdminProductsScreen()),
      GoRoute(
          path: '/admin/archive',
          builder: (context, state) => const AdminArchiveScreen()),
      GoRoute(
          path: '/admin/orders',
          builder: (context, state) => const AdminOrdersScreen()),
      GoRoute(
          path: '/admin/settings',
          builder: (context, state) => const SettingsScreen()),
    ],
  );
});
