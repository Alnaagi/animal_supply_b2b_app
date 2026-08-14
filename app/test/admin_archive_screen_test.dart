import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_archive/admin_archive_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'archive screen separates entity types and restores categories safely',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(646, 838));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final categoryProduct = _product(
        id: 'category-product',
        name: 'منتج قطط مؤرشف مع التصنيف',
        category: 'قطط',
      );
      final individualProduct = _product(
        id: 'individual-product',
        name: 'منتج طيور مؤرشف',
        category: 'طيور',
        active: false,
        archivedAt: DateTime.utc(2026, 8, 13),
      );
      final catalog = CatalogRepository.demo(
        seed: [categoryProduct, individualProduct],
      );
      final catCategory = (await catalog.productCategories())
          .singleWhere((category) => category.name == 'قطط');
      await catalog.archiveCategory(catCategory.id);

      final admin = AdminRepository();
      final archivedCustomer = (await admin.listCustomers()).first;
      await admin.saveCustomer(
        archivedCustomer.copyWith(accountStatus: 'archived'),
      );
      final router = GoRouter(
        initialLocation: '/admin/archive',
        routes: [
          GoRoute(
            path: '/admin/archive',
            builder: (context, state) => const AdminArchiveScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _FixedAuthController(),
            ),
            catalogRepositoryProvider.overrideWithValue(catalog),
            adminRepositoryProvider.overrideWithValue(admin),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الأرشيف'), findsOneWidget);
      expect(find.text('المنتجات (2)'), findsOneWidget);
      expect(find.text('التصنيفات (1)'), findsOneWidget);
      expect(find.text('العملاء (1)'), findsOneWidget);
      expect(find.textContaining('لا تُحذف نهائياً'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('الأرشيف'))),
        TextDirection.rtl,
      );
      final categoryProductRestore = find.byKey(
        const ValueKey('restore-product-category-product'),
      );
      expect(categoryProductRestore, findsOneWidget);
      expect(
        tester.widget<FilledButton>(categoryProductRestore).onPressed,
        isNull,
      );
      expect(find.text('استعد التصنيف أولاً'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('admin-archive-categories-tab')),
      );
      await tester.pumpAndSettle();

      expect(find.text('قطط'), findsOneWidget);
      expect(find.text('1 منتج مؤرشف مع التصنيف'), findsOneWidget);

      await tester.tap(find.byKey(
        ValueKey('restore-category-${catCategory.id}'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('استعادة التصنيف'), findsWidgets);
      await tester.tap(
        find.widgetWithText(FilledButton, 'استعادة التصنيف').last,
      );
      await tester.pumpAndSettle();

      expect(find.text('التصنيفات (0)'), findsOneWidget);
      expect(find.text('المنتجات (1)'), findsOneWidget);
      expect(find.text('لا توجد تصنيفات مؤرشفة'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('admin-archive-customers-tab')),
      );
      await tester.pumpAndSettle();
      expect(find.text(archivedCustomer.businessName), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('admin-archive-search')),
        'غير موجود',
      );
      await tester.pump();
      expect(find.text('لا توجد نتائج مطابقة في عملاء'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('admin-archive-search')),
        'طرابلس',
      );
      await tester.pump();
      expect(find.text(archivedCustomer.businessName), findsOneWidget);
    },
  );

  testWidgets(
    'successful restore stays successful when the archive refresh fails',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(646, 838));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final catalog = _RestoreThenFailReloadCatalogRepository();
      final router = GoRouter(
        initialLocation: '/admin/archive',
        routes: [
          GoRoute(
            path: '/admin/archive',
            builder: (context, state) => const AdminArchiveScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _FixedAuthController(),
            ),
            catalogRepositoryProvider.overrideWithValue(catalog),
            adminRepositoryProvider.overrideWithValue(AdminRepository()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey('restore-product-refresh-failure-product'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'استعادة ونشر').last,
      );
      await tester.pumpAndSettle();

      expect(catalog.restoreCalls, 1);
      expect(
        find.byKey(const ValueKey('admin-archive-refresh-error')),
        findsOneWidget,
      );
      expect(
        find.textContaining('تمت استعادة المنتج ونشره للعملاء.'),
        findsOneWidget,
      );
      expect(
        find.text('تعذر استعادة المنتج. تحقق من الاتصال وحاول مجدداً.'),
        findsNothing,
      );
    },
  );
}

Product _product({
  required String id,
  required String name,
  required String category,
  bool active = true,
  DateTime? archivedAt,
}) {
  return Product(
    id: id,
    nameAr: name,
    sku: 'SKU-$id',
    category: category,
    animalType: '',
    brand: 'شركة اختبار',
    unitSize: 'عبوة',
    basePrice: 20,
    stockQuantity: 10,
    minOrderQty: 1,
    isActive: active,
    archivedAt: archivedAt,
  );
}

class _FixedAuthController extends AuthController {
  _FixedAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-archive-test',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}

class _RestoreThenFailReloadCatalogRepository extends CatalogRepository {
  _RestoreThenFailReloadCatalogRepository()
      : super.demo(
          seed: [
            _product(
              id: 'refresh-failure-product',
              name: 'منتج مؤرشف يحتاج تحديثاً',
              category: 'طيور',
              active: false,
              archivedAt: DateTime.utc(2026, 8, 13),
            ),
          ],
        );

  bool _failArchiveLoads = false;
  int restoreCalls = 0;

  @override
  Future<List<Product>> archivedProducts() {
    if (_failArchiveLoads) {
      return Future.error(StateError('archive refresh failed'));
    }
    return super.archivedProducts();
  }

  @override
  Future<void> restoreProduct(String id) async {
    restoreCalls++;
    await super.restoreProduct(id);
    _failArchiveLoads = true;
  }
}
