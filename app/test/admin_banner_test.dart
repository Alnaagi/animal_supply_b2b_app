import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
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

  testWidgets('admin banner screen renders its Arabic RTL workflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(934, 858));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('إدارة البانرات'), findsOneWidget);
    expect(
        find.byKey(const Key('admin-banner-client-preview')), findsOneWidget);
    expect(find.byType(OfferBannerCarousel), findsOneWidget);
    expect(
        find.byKey(const Key('admin-banner-client-carousel')), findsOneWidget);
    expect(
      find.byKey(const Key('admin-banner-client-preview-stage')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin-banner-preview-mode')), findsOneWidget);
    expect(find.text('حاسوب'), findsOneWidget);
    expect(find.text('جوال'), findsOneWidget);
    expect(
      find.byKey(const Key('admin-banner-client-preview-desktop')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin-banner-client-preview-phone')),
        findsNothing);
    expect(
      find.byKey(const Key('admin-banner-preview-home-indicator')),
      findsNothing,
    );
    expect(find.text('معاينة عرض العملاء'), findsOneWidget);
    expect(
      find.text('شريط العروض كما يظهر للعملاء على الحاسوب.'),
      findsOneWidget,
    );
    expect(
      find.text('شريط العروض كما يظهر للعملاء على الجوال.'),
      findsNothing,
    );
    expect(find.text('قائمة البانرات'), findsOneWidget);
    expect(
      find.textContaining('البانرات غير النشطة مستبعدة من هذا العرض'),
      findsNothing,
    );
    final desktopStageSize = tester.getSize(
      find.byKey(const Key('admin-banner-client-preview-stage')),
    );
    final previewCardWidth = tester
        .getSize(find.byKey(const Key('admin-banner-client-preview')))
        .width;
    expect(desktopStageSize.width, greaterThan(500));
    expect(desktopStageSize.width, closeTo(previewCardWidth - 28, 8));
    final desktopCarouselSize = tester.getSize(
      find.byKey(const Key('admin-banner-client-carousel')),
    );
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byKey(const Key('admin-banner-client-carousel')),
              matching: find.byType(PageView),
            ),
          )
          .height,
      250,
    );
    final previewStage = tester.widget<DecoratedBox>(
      find.byKey(const Key('admin-banner-client-preview-stage')),
    );
    final stageDecoration = previewStage.decoration as BoxDecoration;
    expect(stageDecoration.color, AppTheme.sand);
    expect(stageDecoration.borderRadius, BorderRadius.circular(18));
    expect(stageDecoration.border, isNotNull);
    expect((stageDecoration.border as Border).top.width, 1);
    expect(
      (stageDecoration.border as Border).top.color,
      isNot(const Color(0xff1c1c1e)),
    );

    await tester.tap(find.text('جوال'));
    await tester.pump();
    expect(
      find.byKey(const Key('admin-banner-client-preview-phone')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin-banner-client-preview-desktop')),
      findsNothing,
    );
    expect(
      find.text('شريط العروض كما يظهر للعملاء على الجوال.'),
      findsOneWidget,
    );
    expect(
      find.text('شريط العروض كما يظهر للعملاء على الحاسوب.'),
      findsNothing,
    );
    expect(find.text('معاينة عرض العملاء'), findsOneWidget);
    expect(
      find.byKey(const Key('admin-banner-preview-home-indicator')),
      findsOneWidget,
    );
    final mobileStageSize = tester.getSize(
      find.byKey(const Key('admin-banner-client-preview-stage')),
    );
    expect(mobileStageSize.width, lessThanOrEqualTo(360));
    expect(mobileStageSize.width, lessThan(desktopStageSize.width));
    final mobileCarouselSize = tester.getSize(
      find.byKey(const Key('admin-banner-client-carousel')),
    );
    expect(mobileCarouselSize.width, lessThan(desktopCarouselSize.width));
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byKey(const Key('admin-banner-client-carousel')),
              matching: find.byType(PageView),
            ),
          )
          .height,
      240,
    );
    final mobileStage = tester.widget<DecoratedBox>(
      find.byKey(const Key('admin-banner-client-preview-stage')),
    );
    final mobileDecoration = mobileStage.decoration as BoxDecoration;
    expect(mobileDecoration.borderRadius, BorderRadius.circular(20));
    expect((mobileDecoration.border as Border).top.width, 1);
    expect(
      (mobileDecoration.border as Border).top.color,
      isNot(const Color(0xff1c1c1e)),
    );
    expect(
      (mobileDecoration.border as Border).top.color,
      isNot(Colors.black),
    );

    await tester.tap(find.text('حاسوب'));
    await tester.pump();
    expect(
      find.byKey(const Key('admin-banner-client-preview-desktop')),
      findsOneWidget,
    );
    expect(
      find.text('شريط العروض كما يظهر للعملاء على الحاسوب.'),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(OfferBannerCarousel),
        matching: find.widgetWithText(FilledButton, 'تسوق الآن'),
      ),
    );
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/admin/banners');
    expect(find.text('إدارة البانرات'), findsOneWidget);
    expect(find.text('الكل'), findsOneWidget);
    expect(find.text('النشطة'), findsOneWidget);
    expect(find.text('غير النشطة'), findsOneWidget);
    expect(find.byKey(const Key('admin-demo-mode-notice')), findsOneWidget);
    expect(find.textContaining('وضع تجريبي'), findsWidgets);
    expect(find.text('عروض خاصة لتجار مستلزمات الحيوانات'), findsWidgets);
    expect(find.text('تسوق الآن'), findsWidgets);
    expect(find.text('الترتيب'), findsOneWidget);
    expect(find.text('الترتيب 1'), findsNothing);
    expect(find.byKey(const ValueKey('banner-sort-order-banner-1')),
        findsOneWidget);
    expect(find.byKey(const Key('banner-move-up-banner-1')), findsOneWidget);
    expect(find.text('تعديل'), findsOneWidget);
    expect(find.text('إيقاف'), findsOneWidget);

    await tester.ensureVisible(find.text('تعديل'));
    await tester.pump();
    expect(tester.getRect(find.text('تعديل')).bottom, lessThan(858));
    expect(tester.getRect(find.text('إيقاف')).bottom, lessThan(858));
    expect(
      tester.getRect(find.byKey(const ValueKey('banner-actions-banner-1'))).top,
      greaterThan(
        tester.getRect(find.text('زر الإجراء: تسوق الآن')).bottom,
      ),
    );

    await tester.binding.setSurfaceSize(const Size(650, 1100));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('تعديل'), findsOneWidget);
    expect(find.text('إيقاف'), findsOneWidget);
    expect(
      tester.getRect(find.text('إيقاف')).bottom,
      greaterThanOrEqualTo(tester.getRect(find.text('تعديل')).top),
    );

    await tester.enterText(
      find.byKey(const ValueKey('banner-sort-order-banner-1')),
      '9',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('banner-sort-order-banner-1')),
          )
          .controller
          ?.text,
      '9',
    );
    expect(
      Directionality.of(tester.element(find.text('إدارة البانرات'))),
      TextDirection.rtl,
    );

    await tester.tap(find.byTooltip('بانر جديد'));
    await tester.pumpAndSettle();

    expect(find.text('رابط الصورة HTTPS'), findsOneWidget);
    expect(find.text('أدخل رابطاً آمناً أو ارفع صورة'), findsOneWidget);
    expect(find.text('اختيار ورفع صورة'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('banner-image-upload-progress')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('banner-image-preview-empty')),
      findsOneWidget,
    );
    expect(
      find.textContaining('رفع الصور غير متاح في الوضع التجريبي'),
      findsOneWidget,
    );
    expect(find.text('وجهة البانر'), findsOneWidget);
    expect(find.text('مخصص'), findsOneWidget);
    expect(find.text('تسوق الآن'), findsWidgets);
    expect(find.text('رقم الترتيب'), findsNothing);
    expect(find.text('رابط HTTPS خارجي'), findsNothing);
    expect(find.textContaining('معرّف المنتج'), findsNothing);
    expect(find.text('نشط ويظهر للعملاء'), findsOneWidget);

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('أضف رابط صورة أو ارفع صورة'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('banner-image-url-field')),
      'https://cdn.example.com/new-banner.webp',
    );

    await tester.tap(find.byKey(const ValueKey('banner-target-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فئة محددة').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('اختر فئة'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('banner-target-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('منتج محدد').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('banner-product-search-field')),
      findsOneWidget,
    );
    expect(find.text('ابحث عن منتج'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('banner-cta-custom-chip')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('banner-cta-custom-field')),
      findsOneWidget,
    );
  });
}
