import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
import 'package:animal_supply_b2b/src/core/widgets/quantity_selector.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
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

  testWidgets('add to cart asks for quantity before adding', (tester) async {
    await _pumpCatalogCard(tester, product: _orderableProduct);

    await tester
        .tap(find.byTooltip('إضافة ${_orderableProduct.name} إلى السلة'));
    await tester.pumpAndSettle();

    expect(find.byType(AddedToCartPromptSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AddedToCartPromptSheet),
        matching: find.text(_orderableProduct.name),
      ),
      findsOneWidget,
    );
    expect(find.text(AddedToCartPromptCopy.title), findsOneWidget);
    expect(find.text(AddedToCartPromptCopy.body), findsOneWidget);
    expect(find.text(AddedToCartPromptCopy.quantityLabel), findsOneWidget);
    expect(
      find.text(AddedToCartPromptCopy.minOrderHint(1)),
      findsWidgets,
    );
    expect(find.byKey(const Key('add-to-cart-quantity')), findsOneWidget);
    expect(
        find.byKey(const Key('added-to-cart-product-image')), findsOneWidget);
    final sheetImage = tester.widget<ProductImagePlaceholder>(
      find.byKey(const Key('added-to-cart-product-image')),
    );
    expect(sheetImage.fit, BoxFit.contain);
    expect(sheetImage.category, _orderableProduct.category);
    final imageRect = tester.getRect(
      find.byKey(const Key('added-to-cart-product-image')),
    );
    final nameRect = tester.getRect(
      find.descendant(
        of: find.byType(AddedToCartPromptSheet),
        matching: find.text(_orderableProduct.name),
      ),
    );
    expect(imageRect.left, greaterThan(nameRect.left));
    expect(find.bySemanticsLabel('الكمية الحالية: 1'), findsOneWidget);
    expect(find.text(AddedToCartPromptCopy.continueShopping), findsOneWidget);
    expect(find.text(AddedToCartPromptCopy.checkout), findsOneWidget);
    expect(find.byKey(const Key('added-to-cart-continue')), findsOneWidget);
    expect(find.byKey(const Key('added-to-cart-checkout')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('added-to-cart-continue')),
        matching: find.byIcon(Icons.add_shopping_cart_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('added-to-cart-checkout')),
        matching: find.byIcon(Icons.shopping_cart_checkout_rounded),
      ),
      findsOneWidget,
    );
    expect(_cartOf(tester), isEmpty);
  });

  testWidgets('quantity stepper starts at min order and respects stock',
      (tester) async {
    const product = Product(
      id: 'product-bulk',
      nameAr: 'رمل قطط',
      sku: 'LITTER-1',
      category: 'رمل',
      animalType: 'قطط',
      brand: 'كييف',
      unitSize: 'كيس',
      basePrice: 75,
      stockQuantity: 5,
      minOrderQty: 2,
    );
    await _pumpCatalogCard(tester, product: product);

    await tester.tap(find.byTooltip('إضافة ${product.name} إلى السلة'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('الكمية الحالية: 2'), findsOneWidget);
    expect(_sheetQtyButton(tester, Icons.remove).onPressed, isNull);

    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('الكمية الحالية: 3'), findsOneWidget);

    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('الكمية الحالية: 5'), findsOneWidget);
    expect(_sheetQtyButton(tester, Icons.add).onPressed, isNull);
    expect(_cartOf(tester), isEmpty);
  });

  testWidgets('continue shopping adds the chosen quantity and stays on catalog',
      (tester) async {
    final router = await _pumpCatalogCard(tester, product: _orderableProduct);

    await tester
        .tap(find.byTooltip('إضافة ${_orderableProduct.name} إلى السلة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('added-to-cart-continue')));
    await tester.pumpAndSettle();

    expect(find.text(AddedToCartPromptCopy.title), findsNothing);
    expect(find.byType(ProductListCard), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/catalog');
    final items = _cartOf(tester);
    expect(items, hasLength(1));
    expect(items.single.product.id, _orderableProduct.id);
    expect(items.single.quantity, 3);
  });

  testWidgets('checkout adds the chosen quantity and opens the cart route',
      (tester) async {
    final router = await _pumpCatalogCard(tester, product: _orderableProduct);

    await tester
        .tap(find.byTooltip('إضافة ${_orderableProduct.name} إلى السلة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('added-to-cart-checkout')));
    await tester.pumpAndSettle();

    expect(find.text('شاشة السلة'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/cart');
    final items = _cartOf(tester);
    expect(items, hasLength(1));
    expect(items.single.quantity, 2);
  });

  testWidgets('dismissing the sheet does not add to the cart', (tester) async {
    await _pumpCatalogCard(tester, product: _orderableProduct);

    await tester
        .tap(find.byTooltip('إضافة ${_orderableProduct.name} إلى السلة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(AddedToCartPromptSheet), findsNothing);
    expect(_cartOf(tester), isEmpty);
  });

  testWidgets('unavailable product does not show the added-to-cart prompt',
      (tester) async {
    await _pumpCatalogCard(tester, product: _unavailableProduct);

    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byTooltip('المنتج غير متوفر'),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
    );
    expect(find.text(AddedToCartPromptCopy.title), findsNothing);
    expect(find.byType(QuantitySelector), findsNothing);
    expect(_cartOf(tester), isEmpty);
  });
}

List<CartItem> _cartOf(WidgetTester tester) {
  final element = tester.element(find.byType(MaterialApp));
  return ProviderScope.containerOf(element).read(cartControllerProvider);
}

IconButton _sheetQtyButton(WidgetTester tester, IconData icon) {
  return tester.widget<IconButton>(
    find.descendant(
      of: find.byKey(const Key('add-to-cart-quantity')),
      matching: find.widgetWithIcon(IconButton, icon),
    ),
  );
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
