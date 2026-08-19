import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/utils/formatters.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/cart/added_to_cart_prompt.dart';
import 'package:animal_supply_b2b/src/features/catalog/product_details_screen.dart';
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

  testWidgets('product details groups hero, info, price, and sticky actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(tester, product: _dogFood);

    expect(Directionality.of(tester.element(find.text('تفاصيل المنتج'))),
        TextDirection.rtl);
    expect(find.byTooltip('رجوع'), findsOneWidget);
    expect(find.byTooltip('نسخ بيانات المنتج'), findsOneWidget);

    final image = find.byKey(const Key('product-details-image'));
    expect(image, findsOneWidget);
    final placeholder = tester.widget<ProductImagePlaceholder>(image);
    expect(placeholder.expand, isTrue);
    expect(placeholder.fit, BoxFit.contain);

    final imageRect = tester.getRect(image);
    expect(imageRect.width, greaterThan(300));
    expect(imageRect.height, inInclusiveRange(300, 380));

    expect(find.byKey(const Key('product-details-info-card')), findsOneWidget);
    expect(find.text(_dogFood.name), findsOneWidget);
    expect(find.text('الشركة: ${_dogFood.brand}'), findsOneWidget);
    expect(find.text('متوفر للطلب'), findsOneWidget);
    expect(find.text('الحد الأدنى للجملة: 1'), findsOneWidget);

    expect(find.byKey(const Key('product-details-price-card')), findsOneWidget);
    final wholesaleLabel = tester.widget<Text>(
      find.byKey(const Key('product-details-wholesale-label')),
    );
    final wholesalePrice = tester.widget<Text>(
      find.byKey(const Key('product-details-wholesale-price')),
    );
    expect(wholesaleLabel.data, 'سعر الجملة');
    expect(wholesaleLabel.style?.color, const Color(0xff111111));
    expect(wholesalePrice.data, lyd(_dogFood.price));
    expect(wholesalePrice.style?.color, const Color(0xff111111));
    expect(
      find.byKey(const Key('product-details-retail-banner')),
      findsOneWidget,
    );
    expect(find.text('سعر بيع الوحدة المقترح للتاجر'), findsOneWidget);
    expect(find.text(lyd(_dogFood.retailUnitPrice!)), findsOneWidget);

    expect(find.byKey(const Key('product-details-actions')), findsOneWidget);
    expect(find.byKey(const Key('product-details-quantity')), findsOneWidget);
    expect(find.text('إضافة للسلة'), findsOneWidget);
    expect(find.text('استفسر عبر واتساب'), findsOneWidget);

    final actionsBottom =
        tester.getRect(find.byKey(const Key('product-details-actions'))).bottom;
    expect(actionsBottom, closeTo(844, 1));
  });

  testWidgets('product details add-to-cart uses page quantity then prompt',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(tester, product: _dogFood);

    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('الكمية الحالية: 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('product-details-add-to-cart')));
    await tester.pumpAndSettle();

    expect(find.byType(AddedToCartPromptSheet), findsOneWidget);
    expect(find.text(AddedToCartPromptCopy.title), findsOneWidget);
    expect(find.bySemanticsLabel('الكمية الحالية: 2'), findsNWidgets(2));
  });
}

Future<void> _pumpDetails(
  WidgetTester tester, {
  required Product product,
}) async {
  final router = GoRouter(
    initialLocation: '/product/${product.id}',
    routes: [
      GoRoute(
        path: '/catalog',
        builder: (context, state) => const Scaffold(body: Text('الكتالوج')),
      ),
      GoRoute(
        path: '/cart',
        builder: (context, state) => const Scaffold(body: Text('شاشة السلة')),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => ProductDetailsScreen(
          productId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(
          CatalogRepository.demo(seed: [product]),
        ),
        appSettingsProvider.overrideWith(
          (ref) async => const AppSettingsData(
            supportWhatsapp: '218912345678',
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _dogFood = Product(
  id: 'tasty-dog-1',
  nameAr: 'تاستي كلب دجاج + بقر عبوة 15 كجم',
  sku: 'TASTY-15',
  category: 'كلاب',
  animalType: 'كلاب',
  brand: 'نوفا',
  unitSize: '15 كجم',
  basePrice: 240,
  retailUnitPrice: 300,
  stockQuantity: 40,
  minOrderQty: 1,
);
