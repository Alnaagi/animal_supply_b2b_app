import 'package:animal_supply_b2b/src/data/local/local_cache.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_products_screen.dart';
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

  group('CatalogRepository bounded paging', () {
    test('passes complete server filters and stable paging parameters',
        () async {
      final gateway = _RecordingGateway(
        rows: [
          _row('product-2', DateTime.utc(2026, 7, 22, 11)),
          _row('product-1', DateTime.utc(2026, 7, 22, 10)),
        ],
        hasMore: true,
        nextOffset: 52,
      );
      final repository = CatalogRepository(
        pagedRemote: gateway,
        demoSeed: const [],
      );
      final snapshot = DateTime.utc(2026, 7, 22, 12);

      final page = await repository.productsPage(
        query: 'علف',
        category: 'أعلاف',
        brand: 'المورد',
        animalType: 'أغنام',
        unitSize: '25 كجم',
        minimumPrice: 20,
        maximumPrice: 80,
        availability: 'low_stock',
        includeInactive: true,
        snapshotAt: snapshot,
        offset: 50,
        pageSize: 2,
      );

      final call = gateway.pageCalls.single;
      expect(call.query, 'علف');
      expect(call.category, 'أعلاف');
      expect(call.brand, 'المورد');
      expect(call.animalType, 'أغنام');
      expect(call.unitSize, '25 كجم');
      expect(call.minimumPrice, 20);
      expect(call.maximumPrice, 80);
      expect(call.availability, 'low_stock');
      expect(call.includeInactive, isTrue);
      expect(call.snapshotAt, snapshot);
      expect(call.offset, 50);
      expect(call.limit, 2);
      expect(page.products.map((product) => product.id), [
        'product-2',
        'product-1',
      ]);
      expect(page.hasMore, isTrue);
      expect(page.nextOffset, 52);
      expect(page.snapshotAt, snapshot);
    });

    test('demo paging preserves supported filter parity', () async {
      final repository = CatalogRepository.demo(
        seed: [
          _product(
            id: 'target',
            createdAt: DateTime.utc(2026, 7, 22, 11),
            category: 'أعلاف',
            brand: 'ألف',
            animalType: 'أغنام',
            packageSize: '25 كجم',
            price: 55,
            stock: 8,
            tags: const ['مميز'],
          ),
          _product(
            id: 'wrong-brand',
            createdAt: DateTime.utc(2026, 7, 22, 10),
            category: 'أعلاف',
            brand: 'باء',
            animalType: 'أغنام',
            packageSize: '25 كجم',
            price: 55,
            stock: 8,
            tags: const ['مميز'],
          ),
          _product(
            id: 'inactive',
            createdAt: DateTime.utc(2026, 7, 22, 9),
            category: 'أعلاف',
            brand: 'ألف',
            animalType: 'أغنام',
            packageSize: '25 كجم',
            price: 55,
            stock: 8,
            tags: const ['مميز'],
            active: false,
          ),
        ],
      );

      final page = await repository.productsPage(
        query: 'target',
        category: 'أعلاف',
        brand: 'ألف',
        animalType: 'أغنام',
        unitSize: '25 كجم',
        minimumPrice: 50,
        maximumPrice: 60,
        availability: 'low_stock',
      );

      expect(page.products.map((product) => product.id), ['target']);
      expect(page.source, CatalogPageSource.demo);
    });

    test('offline fallback is owner-scoped and capped at 200 products',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = LocalCache(prefs: prefs);
      final seed = [
        for (var index = 0; index < 205; index++)
          _product(
            id: 'cached-$index',
            createdAt: DateTime.utc(2026, 7, 22, 12)
                .subtract(Duration(minutes: index)),
          ),
      ];
      await cache.saveProducts(seed, ownerProfileId: 'profile-a');
      final repository = CatalogRepository(
        cache: cache,
        pagedRemote: const _FailingGateway('profile-a'),
        demoSeed: const [],
      );

      final first = await repository.productsPage(pageSize: 100);
      final second = await repository.productsPage(
        pageSize: 100,
        offset: first.nextOffset,
        snapshotAt: first.snapshotAt,
      );
      final ids = [...first.products, ...second.products]
          .map((product) => product.id)
          .toList();

      expect(first.source, CatalogPageSource.offlineSnapshot);
      expect(first.offlineSnapshotCount, 200);
      expect(first.hasMore, isTrue);
      expect(second.hasMore, isFalse);
      expect(ids, hasLength(200));
      expect(ids.first, 'cached-0');
      expect(ids.last, 'cached-199');
      expect(ids, isNot(contains('cached-200')));
    });
  });

  testWidgets('customer catalog loads more in Arabic with one snapshot',
      (tester) async {
    final repository = _ScreenCatalogRepository(
      firstPage: [
        _product(
          id: 'customer-new',
          name: 'منتج العميل الجديد',
          createdAt: DateTime.utc(2026, 7, 22, 11),
        ),
      ],
      secondPage: [
        _product(
          id: 'customer-old',
          name: 'منتج العميل الأقدم',
          createdAt: DateTime.utc(2026, 7, 21, 11),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CatalogScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('منتج العميل الجديد'), findsOneWidget);
    expect(find.text('تحميل المزيد'), findsOneWidget);

    final loadMore = find.byKey(const ValueKey('catalog-load-more'));
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('منتج العميل الأقدم'), findsOneWidget);
    expect(repository.pageCalls, hasLength(2));
    expect(repository.pageCalls.last.offset, 1);
    expect(repository.pageCalls.last.snapshotAt, _ScreenCatalogRepository.time);
  });

  testWidgets('customer catalog shows wholesale and retail reference only',
      (tester) async {
    final repository = _ScreenCatalogRepository(
      firstPage: [
        _product(
          id: 'two-prices',
          name: 'منتج بسعرين',
          price: 40,
          oldPrice: 50,
          retailUnitPrice: 60,
        ),
      ],
      secondPage: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CatalogScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('بيع الوحدة المقترح'), findsOneWidget);
    expect(find.textContaining('50.00'), findsNothing);
  });

  testWidgets('admin product list pages inactive-capable results safely',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ScreenCatalogRepository(
      firstPage: [
        _product(
          id: 'admin-new',
          name: 'منتج إداري جديد',
          createdAt: DateTime.utc(2026, 7, 22, 11),
        ),
      ],
      secondPage: [
        _product(
          id: 'admin-archived',
          name: 'منتج إداري مؤرشف',
          createdAt: DateTime.utc(2026, 7, 21, 11),
          active: false,
          archivedAt: DateTime.utc(2026, 7, 21, 12),
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/admin/products',
      routes: [
        GoRoute(
          path: '/admin/products',
          builder: (context, state) => const AdminProductsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(
              const AppUser(
                id: 'admin-a',
                username: 'admin',
                role: 'admin',
              ),
            ),
          ),
          catalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final loadMore = find.byKey(const ValueKey('admin-products-load-more'));
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('منتج إداري مؤرشف'), findsOneWidget);
    expect(repository.pageCalls.first.includeInactive, isTrue);
    expect(repository.pageCalls.last.snapshotAt, _ScreenCatalogRepository.time);
  });
}

class _RecordingGateway implements CatalogPagedRemoteGateway {
  _RecordingGateway({
    required this.rows,
    required this.hasMore,
    required this.nextOffset,
  });

  final List<Map<String, dynamic>> rows;
  final bool hasMore;
  final int nextOffset;
  final List<_PageCall> pageCalls = [];

  @override
  String? get ownerProfileId => 'profile-a';

  @override
  Future<CatalogRemotePage> productsPage({
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    DateTime? snapshotAt,
    required int offset,
    required int limit,
  }) async {
    pageCalls.add(
      _PageCall(
        query: query,
        category: category,
        brand: brand,
        animalType: animalType,
        unitSize: unitSize,
        minimumPrice: minimumPrice,
        maximumPrice: maximumPrice,
        availability: availability,
        includeInactive: includeInactive,
        snapshotAt: snapshotAt,
        offset: offset,
        limit: limit,
      ),
    );
    return CatalogRemotePage(
      rows: rows,
      hasMore: hasMore,
      nextOffset: nextOffset,
      snapshotAt: snapshotAt ?? DateTime.utc(2026, 7, 22, 12),
    );
  }

  @override
  Future<CatalogFilterOptions> filterOptions({
    required bool includeInactive,
  }) async {
    return const CatalogFilterOptions(
      categories: ['أعلاف'],
      brands: ['المورد'],
      animalTypes: ['أغنام'],
      unitSizes: ['25 كجم'],
    );
  }
}

class _FailingGateway implements CatalogPagedRemoteGateway {
  const _FailingGateway(this.ownerProfileId);

  @override
  final String? ownerProfileId;

  @override
  Future<CatalogRemotePage> productsPage({
    required String query,
    String? category,
    String? brand,
    String? animalType,
    String? unitSize,
    double? minimumPrice,
    double? maximumPrice,
    required String availability,
    required bool includeInactive,
    DateTime? snapshotAt,
    required int offset,
    required int limit,
  }) {
    throw StateError('offline');
  }

  @override
  Future<CatalogFilterOptions> filterOptions({
    required bool includeInactive,
  }) {
    throw StateError('offline');
  }
}

class _ScreenCatalogRepository extends CatalogRepository {
  _ScreenCatalogRepository({
    required this.firstPage,
    required this.secondPage,
  }) : super.demo(seed: const []);

  static final time = DateTime.utc(2026, 7, 22, 12);

  final List<Product> firstPage;
  final List<Product> secondPage;
  final List<_PageCall> pageCalls = [];

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
    pageCalls.add(
      _PageCall(
        query: query,
        category: category,
        brand: brand,
        animalType: animalType,
        unitSize: unitSize,
        minimumPrice: minimumPrice,
        maximumPrice: maximumPrice,
        availability: availability,
        includeInactive: includeInactive,
        snapshotAt: snapshotAt,
        offset: offset,
        limit: pageSize,
      ),
    );
    final selected = offset == 0 ? firstPage : secondPage;
    return CatalogPage(
      products: selected,
      hasMore: offset == 0 && secondPage.isNotEmpty,
      nextOffset: offset + selected.length,
      snapshotAt: snapshotAt ?? time,
      source: CatalogPageSource.remote,
      offlineSnapshotCount: 0,
    );
  }

  @override
  Future<List<String>> categories() async => const ['أعلاف'];

  @override
  Future<CatalogFilterOptions> filterOptions({
    bool includeInactive = false,
  }) async {
    return const CatalogFilterOptions(
      categories: ['أعلاف'],
      brands: ['المورد'],
      animalTypes: ['أغنام'],
      unitSizes: ['25 كجم'],
    );
  }
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(AppUser user) {
    state = AuthState(user: user);
  }
}

class _PageCall {
  const _PageCall({
    required this.query,
    required this.category,
    required this.brand,
    required this.animalType,
    required this.unitSize,
    required this.minimumPrice,
    required this.maximumPrice,
    required this.availability,
    required this.includeInactive,
    required this.snapshotAt,
    required this.offset,
    required this.limit,
  });

  final String query;
  final String? category;
  final String? brand;
  final String? animalType;
  final String? unitSize;
  final double? minimumPrice;
  final double? maximumPrice;
  final String availability;
  final bool includeInactive;
  final DateTime? snapshotAt;
  final int offset;
  final int limit;
}

Product _product({
  required String id,
  DateTime? createdAt,
  String? name,
  String category = 'أعلاف',
  String brand = 'المورد',
  String animalType = 'أغنام',
  String packageSize = '25 كجم',
  double price = 40,
  double? oldPrice,
  double? retailUnitPrice,
  int stock = 20,
  List<String> tags = const [],
  bool active = true,
  DateTime? archivedAt,
}) {
  return Product(
    id: id,
    nameAr: name ?? id,
    sku: 'SKU-$id',
    category: category,
    animalType: animalType,
    brand: brand,
    unitSize: packageSize,
    packageSize: packageSize,
    basePrice: price,
    oldPrice: oldPrice,
    retailUnitPrice: retailUnitPrice,
    stockQuantity: stock,
    minOrderQty: 1,
    tags: tags,
    isActive: active,
    archivedAt: archivedAt,
    createdAt: createdAt,
  );
}

Map<String, dynamic> _row(String id, DateTime createdAt) {
  return {
    'id': id,
    'name': id,
    'sku': 'SKU-$id',
    'category_name': 'أعلاف',
    'animal_type': 'أغنام',
    'brand': 'المورد',
    'unit_size': '25 كجم',
    'package_size': '25 كجم',
    'base_price': 40,
    'effective_price': 40,
    'stock_quantity': 20,
    'available_quantity': 20,
    'min_order_quantity': 1,
    'active': true,
    'created_at': createdAt.toIso8601String(),
    'updated_at': createdAt.toIso8601String(),
  };
}
