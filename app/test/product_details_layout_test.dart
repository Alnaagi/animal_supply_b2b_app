import 'dart:async';

import 'package:animal_supply_b2b/src/core/widgets/customer_product_summary.dart';
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

  testWidgets('product details uses a page-shaped skeleton while loading',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final productCompleter = Completer<Product?>();
    await _pumpDetails(
      tester,
      product: _dogFood,
      repository: _DelayedProductRepository(productCompleter.future),
      settle: false,
    );
    await tester.pump();

    expect(
      find.byKey(const Key('product-details-skeleton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-skeleton-image')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-skeleton-overview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-skeleton-info')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-skeleton-price')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-skeleton-actions')),
      findsOneWidget,
    );
    expect(find.byTooltip('رجوع'), findsOneWidget);
    expect(find.byKey(const Key('shop-loading-page')), findsNothing);
    expect(tester.takeException(), isNull);

    productCompleter.complete(_dogFood);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-details-skeleton')), findsNothing);
    expect(find.byKey(const Key('product-details-image')), findsOneWidget);
    expect(
      find.byKey(const Key('product-details-info-card')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stale product completion cannot replace related products after routing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _RacingProductRepository(
      relatedCatalogs: const [
        [_catFood, _relatedCatFood],
        [_dogFood, _relatedDogFood],
      ],
    );
    final router = GoRouter(
      initialLocation: '/product/${_dogFood.id}',
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
          catalogRepositoryProvider.overrideWithValue(repository),
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
    await tester.pump();
    expect(repository.requestedProductIds, [_dogFood.id]);

    router.go('/product/${_catFood.id}');
    await tester.pump();
    await tester.pump();
    expect(repository.requestedProductIds, [_dogFood.id, _catFood.id]);

    repository.completeProduct(_catFood.id, _catFood);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(_catFood.name), findsOneWidget);
    expect(repository.productsCallCount, 1);

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('related-product-card-cat-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('related-product-card-dog-2')),
      findsNothing,
    );

    repository.completeProduct(_dogFood.id, _dogFood);
    await tester.pump();
    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();

    expect(find.text(_catFood.name), findsOneWidget);
    expect(repository.productsCallCount, 1);
    expect(
      find.byKey(const Key('related-product-card-cat-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('related-product-card-dog-2')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('product details groups a clear overview and sticky actions',
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
    expect(placeholder.backgroundColor, Colors.white);

    final imageRect = tester.getRect(image);
    expect(imageRect.width, greaterThan(300));
    expect(imageRect.height, inInclusiveRange(180, 200));

    final overview = find.byKey(const Key('product-details-overview-card'));
    final info = find.byKey(const Key('product-details-info-card'));
    final price = find.byKey(const Key('product-details-price-card'));
    expect(overview, findsOneWidget);
    expect(find.descendant(of: overview, matching: image), findsOneWidget);
    expect(find.descendant(of: overview, matching: info), findsOneWidget);
    expect(find.descendant(of: overview, matching: price), findsOneWidget);

    expect(find.text(_dogFood.name), findsOneWidget);
    expect(
      find.text('الشركة: ${_dogFood.brand}'),
      findsOneWidget,
    );
    expect(find.text('التصنيف: ${_dogFood.category}'), findsOneWidget);
    expect(find.text('متوفر للطلب'), findsNothing);
    expect(find.text('تفاصيل الشراء والتعبئة'), findsOneWidget);
    expect(find.text('الحد الأدنى القابل للطلب'), findsOneWidget);
    expect(find.text('1 صندوق'), findsOneWidget);
    expect(find.text('يعادل 12 قطعة إجمالاً'), findsOneWidget);
    expect(find.text('محتوى كل صندوق'), findsOneWidget);
    expect(find.text('12 قطعة'), findsOneWidget);
    expect(find.text('وحدة الطلب: صندوق كامل'), findsOneWidget);
    expect(find.text('حجم العبوة'), findsOneWidget);
    expect(find.text(_dogFood.effectivePackageSize), findsOneWidget);
    expect(find.text('رمز المنتج'), findsOneWidget);
    expect(find.text(_dogFood.sku), findsOneWidget);
    expect(
      find.descendant(
        of: info,
        matching: find.byKey(const Key('product-details-purchase-facts')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: info, matching: find.byType(Card)),
      findsNothing,
      reason: 'The identity and purchasing facts should stay on one surface.',
    );

    final wholesaleLabel = tester.widget<Text>(
      find.byKey(const Key('product-details-wholesale-label')),
    );
    final wholesalePrice = tester.widget<Text>(
      find.byKey(const Key('product-details-wholesale-price')),
    );
    expect(wholesaleLabel.data, 'سعر الجملة');
    expect(wholesaleLabel.style?.color, AppTheme.green);
    expect(wholesalePrice.data, lyd(_dogFood.price));
    expect(wholesalePrice.style?.color, AppTheme.darkGreen);
    expect(
      find.byKey(const Key('product-details-retail-banner')),
      findsOneWidget,
    );
    expect(find.text(CustomerProductCardCopy.retail), findsOneWidget);
    expect(find.text(CustomerProductCardCopy.retailUnitHint), findsOneWidget);
    expect(find.text(lyd(_dogFood.retailUnitPrice!)), findsOneWidget);

    expect(find.byKey(const Key('product-details-actions')), findsOneWidget);
    expect(find.byKey(const Key('product-details-quantity')), findsOneWidget);
    expect(find.text('إضافة للسلة'), findsOneWidget);
    expect(find.text('استفسر عبر واتساب'), findsOneWidget);

    final actionsBottom =
        tester.getRect(find.byKey(const Key('product-details-actions'))).bottom;
    expect(actionsBottom, closeTo(844, 1));

    final actionsTop =
        tester.getRect(find.byKey(const Key('product-details-actions'))).top;
    expect(
      tester.getRect(overview).bottom,
      lessThanOrEqualTo(actionsTop),
      reason: 'The grouped product overview should fit above sticky actions.',
    );
  });

  testWidgets('grouped product overview remains clear at 338px width',
      (tester) async {
    tester.view.physicalSize = const Size(338, 838);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(tester, product: _dogFood);

    final overview = find.byKey(const Key('product-details-overview-card'));
    expect(overview, findsOneWidget);
    expect(
      find.descendant(
        of: overview,
        matching: find.byKey(const Key('product-details-image')),
      ),
      findsOneWidget,
    );
    expect(find.text('الشركة: ${_dogFood.brand}'), findsOneWidget);
    expect(find.text('الحد الأدنى القابل للطلب'), findsOneWidget);
    expect(find.text('محتوى كل صندوق'), findsOneWidget);
    expect(find.text('يعادل 12 قطعة إجمالاً'), findsOneWidget);
    expect(find.text(CustomerProductCardCopy.retail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile keeps a sticky purchase action with 44px controls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(tester, product: _dogFood);

    expect(
      find.byKey(const Key('product-details-desktop-layout')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('product-details-purchase-panel')),
      findsNothing,
    );
    final actions = find.byKey(const Key('product-details-actions'));
    expect(actions, findsOneWidget);
    expect(tester.getRect(actions).bottom, closeTo(844, 1));

    for (final target in [
      find.byTooltip('تقليل الكمية'),
      find.byTooltip('زيادة الكمية'),
      find.byKey(const Key('product-details-add-to-cart')),
      find.byKey(const Key('product-details-whatsapp')),
    ]) {
      final rect = tester.getRect(target);
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets(
      'desktop uses a capped two-column layout and in-page purchase panel',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(
      tester,
      product: _dogFood,
      relatedProducts: const [_relatedDogFood, _relatedDogTreats],
    );

    final layout = find.byKey(const Key('product-details-desktop-layout'));
    final purchasePanel =
        find.byKey(const Key('product-details-purchase-panel'));
    final mainColumn = find.byKey(const Key('product-details-main-column'));
    expect(layout, findsOneWidget);
    expect(purchasePanel, findsOneWidget);
    expect(mainColumn, findsOneWidget);
    expect(find.byKey(const Key('product-details-actions')), findsNothing);

    final layoutRect = tester.getRect(layout);
    final purchaseRect = tester.getRect(purchasePanel);
    final mainRect = tester.getRect(mainColumn);
    expect(layoutRect.width, lessThanOrEqualTo(1240));
    expect(purchaseRect.width, closeTo(352, 1));
    expect(
      purchaseRect.left,
      greaterThan(mainRect.left),
      reason: 'The purchase panel should occupy the RTL/right-side column.',
    );
    expect(
      find.descendant(
        of: purchasePanel,
        matching: find.byKey(const Key('product-details-price-card')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-related-grid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-related-list')),
      findsNothing,
    );

    for (final target in [
      find.byTooltip('تقليل الكمية'),
      find.byTooltip('زيادة الكمية'),
      find.byKey(const Key('product-details-add-to-cart')),
      find.byKey(const Key('product-details-whatsapp')),
    ]) {
      final rect = tester.getRect(target);
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop layout remains overflow-safe with enlarged Arabic text',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(
      tester,
      product: _dogFood,
      relatedProducts: const [_relatedDogFood, _relatedDogTreats],
      textScaler: const TextScaler.linear(1.3),
    );

    expect(
      find.byKey(const Key('product-details-desktop-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-purchase-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-related-grid')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '1280px desktop layout remains overflow-safe with enlarged Arabic text',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(
      tester,
      product: _dogFood,
      relatedProducts: const [_relatedDogFood, _relatedDogTreats],
      textScaler: const TextScaler.linear(1.3),
    );

    expect(
      find.byKey(const Key('product-details-desktop-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-purchase-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-related-grid')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('product details add-to-cart uses page quantity then prompt',
      (tester) async {
    tester.view.physicalSize = const Size(338, 838);
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

  testWidgets('related products keep same-category items before fallbacks',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(
      tester,
      product: _dogFood,
      relatedProducts: const [_relatedDogFood, _catFood],
    );

    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('product-details-related-products')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('product-details-related-icon')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.widgets_rounded), findsOneWidget);
    expect(find.byKey(const Key('related-product-card-dog-2')), findsOneWidget);
    expect(find.text(_relatedDogFood.name), findsOneWidget);
    expect(find.byKey(const Key('related-product-card-cat-1')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('related-product-card-dog-2'))).dx,
      greaterThan(
        tester
            .getCenter(find.byKey(const Key('related-product-card-cat-1')))
            .dx,
      ),
      reason:
          'The same-category product should be the first card in the RTL list.',
    );

    final addButton = find.byKey(const Key('related-product-add-dog-2'));
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    expect(addButton, findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'إضافة ${_relatedDogFood.name} إلى السلة',
      ),
      findsOneWidget,
    );
    final addButtonSize = tester.getSize(addButton);
    expect(addButtonSize.width, greaterThanOrEqualTo(44));
    expect(addButtonSize.height, greaterThanOrEqualTo(44));
    expect(tester.widget<IconButton>(addButton).onPressed, isNotNull);

    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(find.byType(AddedToCartPromptSheet), findsOneWidget);
    expect(find.text(AddedToCartPromptCopy.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('related products fall back when the category has no alternative',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(
      tester,
      product: _dogFood,
      relatedProducts: const [_catFood],
    );

    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('product-details-related-products')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('related-product-card-cat-1')), findsOneWidget);
    expect(find.text(_catFood.name), findsOneWidget);
    expect(
      find.byKey(Key('related-product-card-${_dogFood.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('related-product add button stays visible but disabled',
      (tester) async {
    tester.view.physicalSize = const Size(338, 838);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpDetails(
      tester,
      product: _dogFood,
      relatedProducts: const [_unavailableDogFood],
    );

    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    final addButton =
        find.byKey(const Key('related-product-add-dog-unavailable'));
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();

    expect(addButton, findsOneWidget);
    final addButtonSize = tester.getSize(addButton);
    expect(addButtonSize.width, greaterThanOrEqualTo(44));
    expect(addButtonSize.height, greaterThanOrEqualTo(44));
    expect(tester.widget<IconButton>(addButton).onPressed, isNull);
    expect(
      find.bySemanticsLabel(
        'إضافة ${_unavailableDogFood.name} إلى السلة',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDetails(
  WidgetTester tester, {
  required Product product,
  List<Product> relatedProducts = const [],
  CatalogRepository? repository,
  bool settle = true,
  TextScaler textScaler = TextScaler.noScaling,
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
          repository ??
              CatalogRepository.demo(seed: [product, ...relatedProducts]),
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
            data: media.copyWith(
              disableAnimations: true,
              textScaler: textScaler,
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
  if (settle) {
    await tester.pumpAndSettle();
  }
}

class _DelayedProductRepository extends CatalogRepository {
  _DelayedProductRepository(this.productFuture) : super.demo(seed: const []);

  final Future<Product?> productFuture;

  @override
  Future<Product?> productById(String id) => productFuture;

  @override
  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async =>
      const [];
}

class _RacingProductRepository extends CatalogRepository {
  _RacingProductRepository({
    required this.relatedCatalogs,
  }) : super.demo(seed: const []);

  final List<List<Product>> relatedCatalogs;
  final Map<String, Completer<Product?>> _productCompleters = {};
  final List<String> requestedProductIds = [];
  int productsCallCount = 0;

  @override
  Future<Product?> productById(String id) {
    requestedProductIds.add(id);
    return (_productCompleters[id] ??= Completer<Product?>()).future;
  }

  void completeProduct(String id, Product? product) {
    _productCompleters[id]!.complete(product);
  }

  @override
  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async {
    final catalog = relatedCatalogs[productsCallCount];
    productsCallCount += 1;
    return catalog;
  }
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
  unitsPerBox: 12,
  minOrderQty: 1,
);

const _relatedDogFood = Product(
  id: 'dog-2',
  nameAr: 'تاستي كلب لحم عبوة 15 كجم',
  sku: 'TASTY-BEEF-15',
  category: 'كلاب',
  animalType: 'كلاب',
  brand: 'نوفا',
  unitSize: '15 كجم',
  basePrice: 235,
  stockQuantity: 20,
  minOrderQty: 1,
);

const _relatedDogTreats = Product(
  id: 'dog-3',
  nameAr: 'مكافآت كلاب طرية بالدجاج',
  sku: 'DOG-TREAT-CHICKEN',
  category: 'كلاب',
  animalType: 'كلاب',
  brand: 'نوفا',
  unitSize: '500 جم',
  basePrice: 48,
  stockQuantity: 32,
  minOrderQty: 1,
);

const _unavailableDogFood = Product(
  id: 'dog-unavailable',
  nameAr: 'طعام كلاب غير متوفر',
  sku: 'DOG-OOS',
  category: 'كلاب',
  animalType: 'كلاب',
  brand: 'نوفا',
  unitSize: '10 كجم',
  basePrice: 190,
  stockQuantity: 0,
  minOrderQty: 1,
);

const _catFood = Product(
  id: 'cat-1',
  nameAr: 'طعام قطط سمك عبوة 10 كجم',
  sku: 'CAT-FISH-10',
  category: 'قطط',
  animalType: 'قطط',
  brand: 'نوفا',
  unitSize: '10 كجم',
  basePrice: 180,
  stockQuantity: 20,
  minOrderQty: 1,
);

const _relatedCatFood = Product(
  id: 'cat-2',
  nameAr: 'طعام قطط بالدجاج عبوة 8 كجم',
  sku: 'CAT-CHICKEN-8',
  category: 'قطط',
  animalType: 'قطط',
  brand: 'نوفا',
  unitSize: '8 كجم',
  basePrice: 165,
  stockQuantity: 18,
  minOrderQty: 1,
);
