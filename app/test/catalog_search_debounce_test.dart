import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/catalog/catalog_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catalog search waits for the debounce and uses the latest query',
      (tester) async {
    final repository = _RecordingCatalogRepository();
    await tester.pumpWidget(_catalogApp(repository));
    await tester.pumpAndSettle();

    expect(repository.queries, ['']);

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'ع');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(searchField, 'علف');
    await tester.pump(const Duration(milliseconds: 349));

    expect(repository.queries, ['']);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(repository.queries, ['', 'علف']);
  });

  testWidgets('catalog cancels a pending search when disposed', (tester) async {
    final repository = _RecordingCatalogRepository();
    await tester.pumpWidget(_catalogApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'قطط');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.queries, ['']);
  });
}

Widget _catalogApp(CatalogRepository repository) {
  return ProviderScope(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: CatalogScreen()),
      ),
    ),
  );
}

class _RecordingCatalogRepository extends CatalogRepository {
  final List<String> queries = [];

  @override
  Future<CatalogPage> productsPage({
    String query = '',
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    String availability = 'all',
    bool includeInactive = false,
    DateTime? snapshotAt,
    int offset = 0,
    int pageSize = CatalogRepository.defaultPageSize,
  }) async {
    queries.add(query);
    return CatalogPage(
      products: const [_product],
      hasMore: false,
      nextOffset: offset + 1,
      snapshotAt: snapshotAt ?? DateTime.utc(2026, 7, 22),
      source: CatalogPageSource.demo,
      offlineSnapshotCount: 1,
    );
  }

  @override
  Future<List<String>> categories() async => const ['أعلاف'];
}

const _product = Product(
  id: 'product-1',
  nameAr: 'علف اختبار',
  sku: 'FEED-1',
  category: 'أعلاف',
  animalType: 'مواشي',
  brand: 'المورد',
  unitSize: '25 كجم',
  basePrice: 100,
  stockQuantity: 50,
  minOrderQty: 1,
);
