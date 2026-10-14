import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/shop_skeleton.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/features/storefront/storefront_home_data.dart';
import 'package:animal_supply_b2b/src/features/storefront/storefront_home_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleProducts = [
    const Product(
      id: 'p1',
      nameAr: 'علف دواجن',
      sku: 'SKU-1',
      category: 'أعلاف',
      animalType: 'دواجن',
      brand: 'Brand',
      unitSize: '25kg',
      basePrice: 120,
      stockQuantity: 10,
      minOrderQty: 1,
      isTopSelling: true,
    ),
    const Product(
      id: 'p2',
      nameAr: 'طعام قطط',
      sku: 'SKU-2',
      category: 'قطط',
      animalType: 'قطط',
      brand: 'Brand',
      unitSize: '1kg',
      basePrice: 35,
      stockQuantity: 10,
      minOrderQty: 1,
      discountPercent: 10,
    ),
  ];

  Widget pumpRenderer({
    required StorefrontInteractionMode mode,
    required Key key,
  }) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StorefrontHomeRenderer(
              key: key,
              config: StorefrontDefaults.bundled,
              data: StorefrontHomeData(
                products: sampleProducts,
                categories: const [],
                userName: 'متجر الاختبار',
                userLocation: 'طرابلس',
              ),
              interactionMode: mode,
              renderMode: mode == StorefrontInteractionMode.preview
                  ? StorefrontRenderMode.adminPreview
                  : StorefrontRenderMode.customer,
              actions: const StorefrontHomeActions(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('customer and admin preview use the same renderer widget',
      (tester) async {
    const customerKey = Key('renderer-customer');
    const previewKey = Key('renderer-preview');

    await tester.pumpWidget(
      pumpRenderer(mode: StorefrontInteractionMode.live, key: customerKey),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(customerKey), findsOneWidget);
    expect(find.text('التصنيفات'), findsOneWidget);
    expect(find.text('الأكثر طلباً'), findsOneWidget);

    await tester.pumpWidget(
      pumpRenderer(mode: StorefrontInteractionMode.preview, key: previewKey),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StorefrontHomeRenderer), findsOneWidget);
    expect(find.text('التصنيفات'), findsOneWidget);
    expect(find.text('الأكثر طلباً'), findsOneWidget);
  });

  testWidgets('home loading state uses section-shaped ghost placeholders',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StorefrontHomeRenderer(
                config: StorefrontDefaults.bundled,
                data: const StorefrontHomeData(
                  userName: 'متجر الاختبار',
                  userLocation: 'طرابلس',
                  productsLoading: true,
                  categoriesLoading: true,
                  bannersLoading: true,
                  ordersLoading: true,
                ),
                actions: const StorefrontHomeActions(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('customer-home-banner-skeleton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customer-home-categories-skeleton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customer-home-products-skeleton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customer-home-recent-order-skeleton')),
      findsOneWidget,
    );
    expect(find.byType(ShopSkeleton), findsNWidgets(6));
    expect(find.byKey(const Key('shop-loading-compact')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
