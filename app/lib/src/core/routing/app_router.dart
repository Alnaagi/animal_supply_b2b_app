import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_user.dart';
import '../../features/admin_archive/admin_archive_screen.dart';
import '../../features/admin_banners/admin_banners_screen.dart';
import '../../features/admin_customers/admin_customers_screen.dart';
import '../../features/admin_dashboard/admin_dashboard_screen.dart';
import '../../features/admin_notifications/admin_notifications_screen.dart';
import '../../features/admin_orders/admin_orders_screen.dart';
import '../../features/admin_products/admin_products_screen.dart';
import '../../features/admin_reports/admin_reports_screen.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/auth_bootstrap_screen.dart';
import '../../features/auth/change_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/cart/cart_screen.dart';
import '../../features/cart/checkout_screen.dart';
import '../../features/catalog/catalog_screen.dart';
import '../../features/catalog/product_details_screen.dart';
import '../../features/customer_home/customer_home_screen.dart';
import '../../features/customer_home/customer_shell.dart';
import '../../features/download/app_download_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/settings/settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..onDispose(refresh.dispose)
    ..listen<AuthState>(authControllerProvider, (_, __) {
      refresh.value++;
    });

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final isInviteLocation = location == '/invite' ||
          (location == '/' &&
              (state.uri.host == 'invite' ||
                  state.uri.queryParameters['token']?.isNotEmpty == true));
      final isPublicContentLocation = location == '/download';
      final isPublicAuthLocation =
          location == '/' || location == '/login' || isInviteLocation;
      final isPublicLocation = isPublicAuthLocation || isPublicContentLocation;
      final nextLocation = _safeNextLocation(state.uri.queryParameters['next']);
      final requestedLocation = _safeNextLocation(state.uri.toString());

      if (auth.bootstrapping) {
        // Keep an incoming invite URI intact while the saved session is
        // checked. Protected deep links are preserved behind a neutral loading
        // screen so notification/order links survive session restoration.
        if (isPublicLocation || location == '/auth-loading') return null;
        return requestedLocation == null
            ? '/auth-loading'
            : _locationWithNext('/auth-loading', requestedLocation);
      }

      final user = auth.user;
      if (user == null) {
        if (isPublicLocation) return null;
        final safeDestination = nextLocation ?? requestedLocation;
        return safeDestination == null
            ? '/login'
            : _locationWithNext('/login', safeDestination);
      }

      if (user.mustChangePassword) {
        if (location == '/change-password') return null;
        final safeDestination = nextLocation ?? requestedLocation;
        return safeDestination == null
            ? '/change-password'
            : _locationWithNext('/change-password', safeDestination);
      }

      final landingLocation = user.isAdminLike ? '/admin' : '/home';
      if (isPublicContentLocation) return null;
      if (isPublicAuthLocation ||
          location == '/auth-loading' ||
          location == '/change-password') {
        return nextLocation == null
            ? landingLocation
            : _authorizedDestination(user, nextLocation);
      }

      if (user.isAdminLike && location == '/orders') {
        return _locationWithPath(state.uri, '/admin/orders');
      }
      if (user.isAdminLike && location.startsWith('/product/')) {
        return '/admin/products';
      }
      if (user.isAdminLike && _isCustomerLocation(location)) {
        return '/admin';
      }
      if (user.isCustomer && location.startsWith('/admin')) {
        return '/home';
      }
      if (!user.isAdmin && _isAdminOnlyLocation(location)) {
        return '/admin';
      }

      return null;
    },
    errorBuilder: (context, state) => _RouteNotFoundScreen(
      requestedLocation: state.uri.path,
    ),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => _loginScreenFromState(state),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => _loginScreenFromState(state),
      ),
      GoRoute(
        path: '/invite',
        builder: (context, state) => _loginScreenFromState(state),
      ),
      GoRoute(
        path: '/download',
        builder: (context, state) => const AppDownloadScreen(),
      ),
      GoRoute(
        path: '/auth-loading',
        builder: (context, state) => const AuthBootstrapScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => ProductDetailsScreen(
          productId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
      ),
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
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/cart', builder: (context, state) => const CartScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/orders',
                builder: (context, state) => OrdersScreen(
                    highlightedOrderId: state.uri.queryParameters['order'])),
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
          builder: (context, state) => AdminProductsScreen(
                openCreateForm: state.uri.queryParameters['action'] == 'create',
              )),
      GoRoute(
          path: '/admin/banners',
          builder: (context, state) => const AdminBannersScreen()),
      GoRoute(
        path: '/admin/pricing',
        redirect: (context, state) => '/admin/customers',
      ),
      GoRoute(
          path: '/admin/orders',
          builder: (context, state) => AdminOrdersScreen(
                highlightedOrderId: state.uri.queryParameters['order'],
                showTodayOnly: state.uri.queryParameters['period'] == 'today',
              )),
      GoRoute(
          path: '/admin/archive',
          builder: (context, state) => const AdminArchiveScreen()),
      GoRoute(
          path: '/admin/notifications',
          builder: (context, state) => const AdminNotificationsScreen()),
      GoRoute(
          path: '/admin/reports',
          builder: (context, state) => const AdminReportsScreen()),
      GoRoute(
          path: '/admin/settings',
          builder: (context, state) => const SettingsScreen()),
    ],
  );
});

LoginScreen _loginScreenFromState(GoRouterState state) {
  return LoginScreen(
    inviteToken: state.uri.queryParameters['token'],
    clientCode: state.uri.queryParameters['client'],
  );
}

bool _isCustomerLocation(String location) {
  return location == '/home' ||
      location == '/catalog' ||
      _isProductLocation(location) ||
      location == '/cart' ||
      location == '/checkout' ||
      location == '/orders' ||
      location == '/profile';
}

bool _isProductLocation(String location) {
  final uri = Uri.tryParse(location);
  final segments = uri?.pathSegments ?? const <String>[];
  return segments.length == 2 &&
      segments.first == 'product' &&
      segments.last.isNotEmpty;
}

bool _isAdminLocation(String location) => const {
      '/admin',
      '/admin/customers',
      '/admin/products',
      '/admin/banners',
      '/admin/orders',
      '/admin/archive',
      '/admin/notifications',
      '/admin/reports',
      '/admin/settings',
    }.contains(location);

bool _isAdminOnlyLocation(String location) =>
    location == '/admin/banners' ||
    location == '/admin/notifications' ||
    location == '/admin/reports' ||
    location == '/admin/settings';

String _locationWithNext(String path, String next) => Uri(
      path: path,
      queryParameters: {'next': next},
    ).toString();

String _locationWithPath(Uri source, String path) => Uri(
      path: path,
      queryParameters:
          source.queryParameters.isEmpty ? null : source.queryParameters,
      fragment: source.fragment.isEmpty ? null : source.fragment,
    ).toString();

String? _safeNextLocation(String? raw) {
  if (raw == null || raw.isEmpty || raw.length > 1000) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      const {
        '/',
        '/login',
        '/invite',
        '/auth-loading',
        '/change-password',
      }.contains(uri.path)) {
    return null;
  }
  if (uri.path == '/admin/pricing') return '/admin/customers';
  if (!_isCustomerLocation(uri.path) && !_isAdminLocation(uri.path)) {
    return null;
  }

  final query = <String, String>{};
  void copyNonEmpty(String key) {
    final value = uri.queryParameters[key]?.trim();
    if (value != null && value.isNotEmpty) query[key] = value;
  }

  if (uri.path == '/catalog') copyNonEmpty('category');
  if (uri.path == '/orders' || uri.path == '/admin/orders') {
    copyNonEmpty('order');
  }
  if (uri.path == '/admin/orders' && uri.queryParameters['period'] == 'today') {
    query['period'] = 'today';
  }

  return Uri(
    path: uri.path,
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

String _authorizedDestination(AppUser user, String requested) {
  final uri = Uri.parse(requested);
  final location = uri.path;
  if (user.isAdminLike) {
    if (location == '/orders') return _locationWithPath(uri, '/admin/orders');
    if (_isProductLocation(location)) return '/admin/products';
    if (_isCustomerLocation(location)) return '/admin';
    if (!user.isAdmin && _isAdminOnlyLocation(location)) return '/admin';
    return requested;
  }
  if (location.startsWith('/admin')) return '/home';
  return requested;
}

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen({required this.requestedLocation});

  final String requestedLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الصفحة غير موجودة')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_outlined, size: 72),
                const SizedBox(height: 16),
                Text(
                  'تعذر العثور على هذه الصفحة',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  requestedLocation.isEmpty
                      ? 'الرابط غير صالح أو لم يعد متاحاً.'
                      : 'الرابط $requestedLocation غير صالح أو لم يعد متاحاً.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('العودة للصفحة الرئيسية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
