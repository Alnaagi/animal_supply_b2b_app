import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/added_to_cart_prompt.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_controller.dart';
import 'package:animal_supply_b2b/src/features/catalog/catalog_screen.dart';
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

  testWidgets('add to cart shows continue and checkout actions', (tester) async {
    await _pumpCatalogCard(tester, product: _orderableProduct);

    await tester.tap(find.byTooltip('إضافة ${_orderableProduct.name} إلى السلة'));
    await tester.pumpAndSettle();

    expect(find.text(AddedToCartPromptCopy.title), findsOneWidget);
    expect(find.text(AddedToCartPromptCopy.continueShopping), findsOneWidget);
    expect(find.text(AddedToCartPromptCopy.checkout), findsOneWidget);
    expect(find.byKey(const Key('added-to-cart-continue')), findsOneWidget);
    expect(find.byKey(const Key('added-to-cart-checkout')), findsOneWidget);
  });

  testWidgets('continue shopping dismisses the prompt and stays on catalog',
      (tester) async {
    final router = await _pumpCatalogCard(tester, product: _orderableProduct);

    await tester.tap(find.byTooltip('إضافة ${_orderableProduct.name} إلى السلة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('added-to-cart-continue')));
    await tester.pumpAndSettle();

    expect(find.text(AddedToCartPromptCopy.title), findsNothing);
    expect(find.byType(ProductListCard), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/catalog');
  });

  testWidgets('checkout from the prompt opens the cart route', (tester) async {
    final router = await _pumpCatalogCard(tester, product: _orderableProduct);

    await tester.tap(find.byTooltip(AddedToCartPromptCopy.orderActionTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('added-to-cart-checkout')));
    await tester.pumpAndSettle();

    expect(find.text('شاشة السلة'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/cart');
  });

  testWidgets('unavailable product does not show the added-to-cart prompt',
      (tester) async {
    await _pumpCatalogCard(tester, product: _unavailableProduct);

    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.add),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('غير متوفر حالياً'));
    await tester.pumpAndSettle();

    expect(find.text(AddedToCartPromptCopy.title), findsNothing);
  });
}

Future<GoRouter> _pumpCatalogCard(
  WidgetTester tester, {
  required Product product,
}) async {
  final router = GoRouter(
    initialLocation: '/catalog',
    routes: [
      GoRoute(
        path: '/catalog',
        builder: (context, state) => Scaffold(
          body: ProductListCard(product: product),
        ),
      ),
      GoRoute(
        path: '/cart',
        builder: (context, state) => const Scaffold(
          body: Text('شاشة السلة'),
        ),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => const Scaffold(
          body: Text('تفاصيل المنتج'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _CustomerAuthController(),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

class _CustomerAuthController extends AuthController {
  _CustomerAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'profile-1',
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: 'customer-1',
      ),
    );
  }
}

const _orderableProduct = Product(
  id: 'product-1',
  nameAr: 'علف أغنام',
  sku: 'FEED-1',
  category: 'أعلاف',
  animalType: 'أغنام',
  brand: 'المورد',
  unitSize: 'كيس',
  basePrice: 3,
  stockQuantity: 20,
  minOrderQty: 1,
);

const _unavailableProduct = Product(
  id: 'product-out',
  nameAr: 'علف نافد',
  sku: 'FEED-0',
  category: 'أعلاف',
  animalType: 'أغنام',
  brand: 'المورد',
  unitSize: 'كيس',
  basePrice: 3,
  stockQuantity: 0,
  availableQuantity: 0,
  minOrderQty: 1,
);
