import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_banners/admin_banners_screen.dart';
import 'package:animal_supply_b2b/src/features/customer_home/offer_banner_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  AppBanner draft({
    String id = 'new',
    String title = 'عرض الأعلاف',
    String imageUrl = 'https://cdn.example.com/banner.webp',
    String targetType = 'catalog',
    String targetValue = '',
    int sortOrder = 3,
    bool active = true,
    String ctaText = 'تسوق الآن',
  }) {
    return AppBanner(
      id: id,
      title: title,
      body: 'خصم خاص لعملاء الجملة',
      ctaText: ctaText,
      imageUrl: imageUrl,
      targetType: targetType,
      targetValue: targetValue,
      sortOrder: sortOrder,
      active: active,
    );
  }

  test('demo banner writes are session-local and inactive banners stay hidden',
      () async {
    final repository = AdminRepository();

    final created = await repository.saveBanner(
      draft(
        title: '  بانر موسمي  ',
        active: false,
        sortOrder: 1,
      ),
    );

    expect(created.id, isNot('new'));
    expect(created.title, 'بانر موسمي');
    expect(
      await repository.banners(),
      isNot(contains(predicate<AppBanner>((item) => item.id == created.id))),
    );
    expect(
      await repository.allBanners(),
      contains(predicate<AppBanner>((item) => item.id == created.id)),
    );

    final reordered =
        await repository.saveBanner(created.copyWith(sortOrder: 9));
    expect(reordered.sortOrder, 9);

    final activated = await repository.setBannerActive(created, active: true);
    expect(activated.active, isTrue);
    expect(
      await repository.banners(),
      contains(predicate<AppBanner>((item) => item.id == created.id)),
    );

    final freshRepository = AdminRepository();
    expect(
      await freshRepository.allBanners(),
      isNot(contains(predicate<AppBanner>((item) => item.id == created.id))),
    );
  });

  test('banner list is sorted and returned as an immutable snapshot', () async {
    final repository = AdminRepository();
    await repository.saveBanner(draft(title: 'ثانٍ', sortOrder: 20));
    await repository.saveBanner(draft(title: 'أول', sortOrder: 0));

    final banners = await repository.allBanners();

    expect(
      banners.map((banner) => banner.sortOrder),
      orderedEquals([0, 1, 20]),
    );
    expect(
      () => banners.add(draft()),
      throwsUnsupportedError,
    );
  });

  test('parseBannerSortOrder accepts 0 to 100000', () {
    expect(parseBannerSortOrder(''), isNull);
    expect(parseBannerSortOrder('abc'), isNull);
    expect(parseBannerSortOrder('-1'), isNull);
    expect(parseBannerSortOrder('0'), 0);
    expect(parseBannerSortOrder(' 7 '), 7);
    expect(parseBannerSortOrder('100000'), 100000);
    expect(parseBannerSortOrder('100001'), isNull);
  });

  test('nextBannerSortOrder uses max existing order plus one', () {
    expect(nextBannerSortOrder(const []), 0);
    expect(
      nextBannerSortOrder([
        draft(sortOrder: 2),
        draft(sortOrder: 7),
        draft(sortOrder: 4),
      ]),
      8,
    );
  });

  test('showing order is top-to-bottom and move swaps adjacent banners', () {
    final first = draft(id: 'a', title: 'أول', sortOrder: 2);
    final second = draft(id: 'b', title: 'ثانٍ', sortOrder: 5);
    final third = draft(id: 'c', title: 'ثالث', sortOrder: 9);

    expect(
      bannersInShowingOrder([third, first, second]).map((banner) => banner.id),
      ['a', 'b', 'c'],
    );

    expect(
      activeBannersInShowingOrder([
        first.copyWith(active: false),
        second,
        third.copyWith(active: false),
      ]).map((banner) => banner.id),
      ['b'],
    );

    final movedUp = moveBannerInShowingOrder(
      [first, second, third],
      bannerId: 'c',
      direction: -1,
    );
    expect(movedUp.map((banner) => banner.id), ['a', 'c', 'b']);
    expect(movedUp.map((banner) => banner.sortOrder), [1, 2, 3]);
  });

  test('catalog target discards stale target values before saving', () async {
    final repository = AdminRepository();

    final created = await repository.saveBanner(
      draft(targetType: 'catalog', targetValue: 'stale-value'),
    );

    expect(created.targetType, 'catalog');
    expect(created.targetValue, isEmpty);
  });

  test('safe category and product targets are accepted', () async {
    final repository = AdminRepository();

    final category = await repository.saveBanner(
      draft(targetType: 'category', targetValue: ' قطط '),
    );
    final product = await repository.saveBanner(
      draft(targetType: 'product', targetValue: 'cat-001'),
    );

    expect(category.targetValue, 'قطط');
    expect(product.targetValue, 'cat-001');
  });

  test('external URL targets are rejected on save', () async {
    final repository = AdminRepository();

    await expectLater(
      repository.saveBanner(
        draft(
          targetType: 'url',
          targetValue: 'https://client.example.com/offers?source=banner',
        ),
      ),
      throwsArgumentError,
    );
    expect(AppBanner.supportedTargetTypes.contains('url'), isFalse);
  });

  test('unsafe banner values are rejected before any write', () async {
    final repository = AdminRepository();

    await expectLater(
      repository.saveBanner(draft(imageUrl: 'http://example.com/banner.jpg')),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveBanner(
        draft(targetType: 'product', targetValue: '../products/1'),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveBanner(
        draft(targetType: 'category', targetValue: '   '),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveBanner(draft(sortOrder: -1)),
      throwsArgumentError,
    );
  });

  test('Supabase payload never includes an id and clears optional values', () {
    final payload =
        draft().copyWith(body: '', targetValue: '').toSupabasePayload();

    expect(payload, isNot(contains('id')));
    expect(payload['body'], isNull);
    expect(payload['target_value'], isNull);
    expect(payload['image_path'], isNull);
    expect(payload['active'], isTrue);
  });

  Future<void> pumpAdminBanners(
    WidgetTester tester, {
    AdminRepository? repository,
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    final router = GoRouter(
      initialLocation: '/admin/banners',
      routes: [
        GoRoute(
          path: '/admin/banners',
          builder: (context, state) => const AdminBannersScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (repository != null)
            adminRepositoryProvider.overrideWithValue(repository),
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
  }

  testWidgets('toolbar filter and preview modal work in RTL', (tester) async {
    await pumpAdminBanners(tester);
    expect(find.text('1 بانرات'), findsOneWidget);
    expect(find.text('1 نشطة'), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-store-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preview-store-button')));
    await tester.pumpAndSettle();
    expect(find.text('معاينة المتجر'), findsWidgets);
    expect(find.byType(OfferBannerCarousel), findsOneWidget);
    expect(find.text('جوال'), findsWidgets);
    expect(find.text('حاسوب'), findsWidgets);
  });

  testWidgets('reorder disabled hint appears when filtered', (tester) async {
    await pumpAdminBanners(tester);
    await tester.tap(find.text('النشطة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('إعادة الترتيب متاحة فقط'), findsOneWidget);
  });

  testWidgets('card destination avoids raw product UUID display',
      (tester) async {
    final repository = AdminRepository();
    await repository.saveBanner(
      draft(
        title: 'بانر منتج',
        targetType: 'product',
        targetValue: 'product-very-long-uuid-like-value',
        sortOrder: 2,
      ),
    );
    await pumpAdminBanners(tester, repository: repository);
    expect(
        find.textContaining('product-very-long-uuid-like-value'), findsNothing);
    expect(find.textContaining('🎯 منتج'), findsOneWidget);
  });

  testWidgets('duplicate banner opens editor as inactive', (tester) async {
    await pumpAdminBanners(tester);
    await tester.ensureVisible(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('نسخ البانر').last);
    await tester.pumpAndSettle();
    expect(find.text('تعديل البانر'), findsOneWidget);
    final dialogSwitchFinder = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Switch),
    );
    expect(dialogSwitchFinder, findsOneWidget);
    expect(tester.widget<Switch>(dialogSwitchFinder).value, isFalse);
  });

  testWidgets('failed toggle rolls back banner visibility switch',
      (tester) async {
    final repository = _FailToggleRepository();
    await pumpAdminBanners(tester, repository: repository);
    final switchFinder = find.byType(Switch).first;
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(find.textContaining('تم التراجع عن التعديل'), findsOneWidget);
  });
}

class _FailToggleRepository extends AdminRepository {
  @override
  Future<AppBanner> setBannerActive(
    AppBanner banner, {
    required bool active,
  }) {
    throw StateError('toggle failed');
  }
}
