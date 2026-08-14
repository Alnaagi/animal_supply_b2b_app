import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/models/product_category.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_products/admin_products_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'admin creates a category and safely archives a category with its products',
    (tester) async {
      final repository = _RefreshingCatalogRepository();

      await _pumpProducts(tester, repository);

      expect(repository.productsPageCalls, 1);
      final refresh =
          find.byKey(const ValueKey('refresh-admin-products-button'));
      expect(refresh, findsOneWidget);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(repository.productsPageCalls, 2);

      expect(
        find.byKey(const ValueKey('create-category-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('manage-categories-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('create-category-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-category-name-field')),
        'طيور',
      );
      await tester.tap(find.byKey(const ValueKey('save-category-button')));
      await tester.pumpAndSettle();

      expect(find.text('طيور'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('manage-categories-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('managed-category-cats')),
        findsOneWidget,
      );
      expect(find.text('2 منتج مرتبط'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('archive-category-cats')),
      );
      await tester.pumpAndSettle();

      expect(find.text('تأكيد أرشفة التصنيف'), findsOneWidget);
      expect(
        find.textContaining('كل المنتجات التابعة له (2)'),
        findsOneWidget,
      );
      expect(find.textContaining('قسم «الأرشيف»'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('confirm-archive-category-button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('تعذر أرشفة التصنيف'), findsNothing);
      expect(
        find.byKey(const ValueKey('managed-category-cats')),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(TextButton, 'إغلاق'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('admin-product-card-cat-active-product')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('admin-product-card-cat-hidden-product')),
        findsNothing,
      );

      final archived = await repository.archivedProducts();
      expect(archived, hasLength(2));
      expect(
        archived.every((product) => product.archivedByCategoryId == 'cats'),
        isTrue,
      );

      final archivedCategory = (await repository.productCategories(
        includeArchived: true,
      ))
          .singleWhere((item) => item.id == 'cats');
      expect(archivedCategory.isArchived, isTrue);
      expect(archivedCategory.archivedProductCount, 2);

      await repository.restoreCategory('cats');
      final restored = await repository.products(includeInactive: true);
      expect(
        restored.singleWhere((item) => item.id == 'cat-active-product').active,
        isTrue,
      );
      expect(
        restored.singleWhere((item) => item.id == 'cat-hidden-product').active,
        isFalse,
      );
      expect(restored.every((product) => !product.isArchived), isTrue);
    },
  );

  testWidgets(
    'authoritative refresh clears a category removed by another admin',
    (tester) async {
      final repository = _AuthoritativeRefreshCatalogRepository();
      await _pumpProducts(tester, repository);

      await tester.tap(find.widgetWithText(ChoiceChip, 'قطط'));
      await tester.pumpAndSettle();
      expect(repository.requestedCategories.last, 'قطط');

      repository.catsAvailable = false;
      await tester.tap(
        find.byKey(const ValueKey('refresh-admin-products-button')),
      );
      await tester.pumpAndSettle();

      expect(repository.requestedCategories.last, isNull);
      expect(find.widgetWithText(ChoiceChip, 'قطط'), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'الكل'),
            )
            .selected,
        isTrue,
      );
    },
  );

  testWidgets(
    'category creation remains successful when the manager refresh fails',
    (tester) async {
      final repository = _CreateRefreshFailureRepository();
      await _pumpProducts(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey('manage-categories-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('manager-create-category-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-category-name-field')),
        'طيور',
      );
      await tester.tap(
        find.byKey(const ValueKey('save-category-button')),
      );
      await tester.pumpAndSettle();

      expect(repository.createdCategory, isNotNull);
      expect(
        find.byKey(
          ValueKey(
            'managed-category-${repository.createdCategory!.id}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('تم إنشاء تصنيف «طيور»'), findsOneWidget);
      expect(find.textContaining('تعذر إنشاء التصنيف'), findsNothing);
    },
  );
}

Future<void> _pumpProducts(
  WidgetTester tester,
  CatalogRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(646, 838));
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
          (ref) => _AdminAuthController(),
        ),
        catalogRepositoryProvider.overrideWithValue(repository),
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

class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'category-management-admin',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}

class _RefreshingCatalogRepository extends CatalogRepository {
  _RefreshingCatalogRepository()
      : super.demo(
          seed: const [
            Product(
              id: 'cat-active-product',
              nameAr: 'منتج قطط ظاهر',
              sku: 'CAT-ACTIVE',
              category: 'قطط',
              categoryId: 'cats',
              animalType: 'قطط',
              brand: 'المورد',
              unitSize: 'عبوة',
              basePrice: 20,
              stockQuantity: 10,
              minOrderQty: 1,
            ),
            Product(
              id: 'cat-hidden-product',
              nameAr: 'منتج قطط مخفي',
              sku: 'CAT-HIDDEN',
              category: 'قطط',
              categoryId: 'cats',
              animalType: 'قطط',
              brand: 'المورد',
              unitSize: 'عبوة',
              basePrice: 25,
              stockQuantity: 8,
              minOrderQty: 1,
              isActive: false,
            ),
          ],
        );

  int productsPageCalls = 0;
  bool _failNextCategoryList = false;

  @override
  Future<void> archiveCategory(String id) async {
    await super.archiveCategory(id);
    _failNextCategoryList = true;
  }

  @override
  Future<List<ProductCategory>> productCategories({
    bool includeArchived = false,
  }) {
    if (_failNextCategoryList && !includeArchived) {
      _failNextCategoryList = false;
      return Future.error(StateError('category refresh failed'));
    }
    return super.productCategories(includeArchived: includeArchived);
  }

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
  }) {
    productsPageCalls++;
    return super.productsPage(
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
      pageSize: pageSize,
    );
  }
}

class _AuthoritativeRefreshCatalogRepository extends CatalogRepository {
  _AuthoritativeRefreshCatalogRepository()
      : super.demo(
          seed: const [
            Product(
              id: 'cats-product',
              nameAr: 'منتج قطط',
              sku: 'CATS-1',
              category: 'قطط',
              categoryId: 'cats',
              animalType: 'قطط',
              brand: 'المورد',
              unitSize: 'عبوة',
              basePrice: 20,
              stockQuantity: 10,
              minOrderQty: 1,
            ),
            Product(
              id: 'dogs-product',
              nameAr: 'منتج كلاب',
              sku: 'DOGS-1',
              category: 'كلاب',
              categoryId: 'dogs',
              animalType: 'كلاب',
              brand: 'المورد',
              unitSize: 'عبوة',
              basePrice: 25,
              stockQuantity: 8,
              minOrderQty: 1,
            ),
          ],
        );

  bool catsAvailable = true;
  final List<String?> requestedCategories = [];

  @override
  Future<CatalogFilterOptions> filterOptions({
    bool includeInactive = false,
  }) async {
    return CatalogFilterOptions(
      categories: catsAvailable ? const ['قطط', 'كلاب'] : const ['كلاب'],
    );
  }

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
  }) {
    requestedCategories.add(category);
    return super.productsPage(
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
      pageSize: pageSize,
    );
  }
}

class _CreateRefreshFailureRepository extends CatalogRepository {
  _CreateRefreshFailureRepository()
      : super.demo(
          seed: const [
            Product(
              id: 'existing-product',
              nameAr: 'منتج قطط',
              sku: 'EXISTING-1',
              category: 'قطط',
              categoryId: 'cats',
              animalType: 'قطط',
              brand: 'المورد',
              unitSize: 'عبوة',
              basePrice: 20,
              stockQuantity: 10,
              minOrderQty: 1,
            ),
          ],
        );

  ProductCategory? createdCategory;
  bool _failNextCategoryList = false;

  @override
  Future<ProductCategory> createCategory(String rawName) async {
    createdCategory = await super.createCategory(rawName);
    _failNextCategoryList = true;
    return createdCategory!;
  }

  @override
  Future<List<ProductCategory>> productCategories({
    bool includeArchived = false,
  }) {
    if (_failNextCategoryList) {
      _failNextCategoryList = false;
      return Future.error(StateError('category refresh failed'));
    }
    return super.productCategories(includeArchived: includeArchived);
  }
}
