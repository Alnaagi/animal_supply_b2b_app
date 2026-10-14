import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_user.dart';
import '../../data/repositories/storefront_repository.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_screen.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/product_details_screen.dart';
import '../customer_home/customer_home_screen.dart';
import '../customer_home/customer_shell.dart';
import '../offers/offers_screen.dart';
import '../storefront/storefront_theme_scope.dart';
import '../support/support_screen.dart';
import 'admin_storefront_controller.dart';

/// A read-only guest storefront for admins to browse the complete customer
/// journey without changing the active admin session.
class GuestStorefrontPreviewScreen extends ConsumerStatefulWidget {
  const GuestStorefrontPreviewScreen({
    this.embedded = false,
    super.key,
  });

  final bool embedded;

  @override
  ConsumerState<GuestStorefrontPreviewScreen> createState() =>
      _GuestStorefrontPreviewScreenState();
}

class _GuestStorefrontPreviewScreenState
    extends ConsumerState<GuestStorefrontPreviewScreen> {
  late final GoRouter _router = _createRouter();
  late final _EmbeddedRouteInformationProvider
      _embeddedRouteInformationProvider =
      _EmbeddedRouteInformationProvider(_router.routeInformationProvider);

  @override
  void dispose() {
    _embeddedRouteInformationProvider.dispose();
    _router.dispose();
    super.dispose();
  }

  GoRouter _createRouter() {
    return GoRouter(
      initialLocation: '/home',
      overridePlatformDefaultLocation: true,
      routerNeglect: true,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => CustomerPreviewShell(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (index) => shell.goBranch(
              index,
              initialLocation: index == shell.currentIndex,
            ),
            child: shell,
          ),
          branches: [
            StatefulShellBranch(
              initialLocation: '/home',
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) => const CustomerHomeScreen(),
                ),
                GoRoute(
                  path: '/offers',
                  builder: (context, state) => const OffersScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              initialLocation: '/catalog',
              routes: [
                GoRoute(
                  path: '/catalog',
                  builder: (context, state) => CatalogScreen(
                    initialCategory: state.uri.queryParameters['category'],
                  ),
                ),
                GoRoute(
                  path: '/product/:id',
                  builder: (context, state) => ProductDetailsScreen(
                    productId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              initialLocation: '/cart',
              routes: [
                GoRoute(
                  path: '/cart',
                  builder: (context, state) => const CartScreen(),
                ),
                GoRoute(
                  path: '/checkout',
                  builder: (context, state) => const _GuestAccessScreen(
                    title: 'إتمام الطلب',
                    message: 'يمكنك تصفح المنتجات وإضافة ما تريد للسلة كزائر. '
                        'لتأكيد الطلب، سجّل الدخول بحساب العميل.',
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/orders',
                  builder: (context, state) => const _GuestAccessScreen(
                    title: 'طلباتي',
                    message:
                        'سجّل الدخول بحساب العميل لمتابعة الطلبات وحالاتها.',
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              initialLocation: '/profile',
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (context, state) => const _GuestAccessScreen(
                    title: 'الحساب',
                    message: 'هذه معاينة زائر. سجّل الدخول لعرض بيانات الحساب '
                        'والعناوين والطلبات.',
                  ),
                ),
                GoRoute(
                  path: '/support',
                  builder: (context, state) => const SupportScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(adminStorefrontControllerProvider).activeConfig;
    return ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _GuestAuthController()),
        publishedStorefrontConfigProvider.overrideWith((ref) async => config),
      ],
      child: Theme(
        data: storefrontThemeData(config),
        child: Localizations(
          locale: const Locale('ar'),
          delegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Router<RouteMatchList>(
              key: widget.embedded
                  ? const Key('embedded-guest-storefront-preview')
                  : null,
              routeInformationProvider: _embeddedRouteInformationProvider,
              routeInformationParser: _router.routeInformationParser,
              routerDelegate: _router.routerDelegate,
              backButtonDispatcher: _router.backButtonDispatcher,
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the embedded router fully functional without allowing it to publish
/// its internal `/home`, `/catalog`, or `/cart` locations to the browser URL.
class _EmbeddedRouteInformationProvider extends RouteInformationProvider
    with ChangeNotifier {
  _EmbeddedRouteInformationProvider(this._source) {
    _source.addListener(_handleSourceChanged);
  }

  final RouteInformationProvider _source;

  @override
  RouteInformation get value => _source.value;

  void _handleSourceChanged() {
    notifyListeners();
  }

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    // Intentionally do not call SystemNavigator.routeInformationUpdated().
    // The guest router is scoped to the admin preview frame.
  }

  @override
  void dispose() {
    _source.removeListener(_handleSourceChanged);
    super.dispose();
  }
}

class _GuestAuthController extends AuthController {
  _GuestAuthController() : super() {
    state = const AuthState(user: _guestUser);
  }

  @override
  Future<void> logout() async {
    state = const AuthState();
  }
}

const _guestUser = AppUser(
  id: 'guest-preview',
  username: 'guest-preview',
  role: 'customer',
  customerId: 'guest-preview',
  businessName: 'زائر المتجر',
  accountStatus: 'active',
  isDemo: true,
);

class _GuestAccessScreen extends StatelessWidget {
  const _GuestAccessScreen({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 42,
                  color: scheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('متابعة التصفح'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
