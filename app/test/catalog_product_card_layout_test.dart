import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/customer_product_summary.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
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

  testWidgets('catalog list card image stretches to the full card height',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpCatalogCard(tester, product: _litterProduct);

    final card = find.byKey(const Key('catalog-product-card-litter-1'));
    final image = find.byKey(const Key('catalog-product-image-litter-1'));
    expect(card, findsOneWidget);
    expect(image, findsOneWidget);
    expect(
      Directionality.of(tester.element(card)),
      TextDirection.rtl,
    );

    final material = find.descendant(of: card, matching: find.byType(Material));
    final cardBody = tester.getRect(material.first);
    final imageRect = tester.getRect(image);

    expect(imageRect.width, inInclusiveRange(96, 120));
    expect(imageRect.height, closeTo(cardBody.height, 0.5));
    expect(imageRect.top, closeTo(cardBody.top, 0.5));
    expect(imageRect.bottom, closeTo(cardBody.bottom, 0.5));
    expect(imageRect.right, closeTo(cardBody.right, 0.5));
    expect(imageRect.left, greaterThan(cardBody.left + 80));

    final placeholder = tester.widget<ProductImagePlaceholder>(image);
    expect(placeholder.expand, isTrue);
    expect(placeholder.borderRadius, BorderRadius.zero);

    expect(find.text('كييف'), findsOneWidget);
    expect(find.text('10 كجم'), findsOneWidget);
    expect(find.text('سعر الجملة'), findsOneWidget);
    final wholesaleLabel = tester.widget<Text>(find.text('سعر الجملة'));
    expect(wholesaleLabel.style?.color, AppTheme.darkGreen);
    expect(find.textContaining('بيع الوحدة المقترح'), findsOneWidget);
    expect(find.text(CustomerProductCardCopy.addToCart), findsOneWidget);

    final iconSize = tester.getSize(find.byIcon(Icons.inventory_2));
    expect(iconSize.shortestSide, greaterThanOrEqualTo(56));
    expect(iconSize.shortestSide, lessThan(imageRect.shortestSide));
  });
}

Future<void> _pumpCatalogCard(
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

const _litterProduct = Product(
  id: 'litter-1',
  nameAr: 'رمل قطط',
  sku: 'LIT-1',
  category: 'عام',
  animalType: 'قطط',
  brand: 'كييف',
  unitSize: '10 كجم',
  basePrice: 75,
  retailUnitPrice: 9.5,
  stockQuantity: 18,
  minOrderQty: 2,
  unitsPerBox: 4,
);
