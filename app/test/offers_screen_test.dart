import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/offers/offers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('offers screen shows only discounted products', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider
              .overrideWithValue(_OffersCatalogRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: OffersScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('العروض المتاحة'), findsOneWidget);
    expect(find.text('منتج عليه خصم'), findsOneWidget);
    expect(find.text('منتج عادي'), findsNothing);
  });
}

class _OffersCatalogRepository extends CatalogRepository {
  @override
  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async {
    return const [
      Product(
        id: 'discount-1',
        nameAr: 'منتج عليه خصم',
        sku: 'D1',
        category: 'عام',
        animalType: 'كلاب',
        brand: 'براند',
        unitSize: '10 كجم',
        basePrice: 50,
        discountPercent: 10,
        stockQuantity: 20,
        minOrderQty: 1,
      ),
      Product(
        id: 'regular-1',
        nameAr: 'منتج عادي',
        sku: 'R1',
        category: 'عام',
        animalType: 'كلاب',
        brand: 'براند',
        unitSize: '10 كجم',
        basePrice: 60,
        stockQuantity: 20,
        minOrderQty: 1,
      ),
    ];
  }
}
