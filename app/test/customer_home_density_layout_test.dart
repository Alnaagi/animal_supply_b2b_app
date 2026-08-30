import 'package:animal_supply_b2b/src/core/widgets/customer_product_summary.dart';
import 'package:animal_supply_b2b/src/core/routing/banner_destination.dart';
import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/models/product_category.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/catalog_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/customer_home/customer_home_screen.dart';
import 'package:animal_supply_b2b/src/features/customer_home/offer_banner_carousel.dart';
import 'package:animal_supply_b2b/src/features/storefront/storefront_home_data.dart';
import 'package:animal_supply_b2b/src/features/storefront/storefront_home_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeBannerBreakpoints', () {
    test('resolves responsive heights and treats legacy 88 as auto', () {
      // Mobile wide follows crop strip aspect (1600/620), clamped for CTA readability.
      expect(HomeBannerBreakpoints.resolveHeight(320), closeTo(152, 1));
      expect(
        HomeBannerBreakpoints.resolveHeight(390),
        closeTo(390 / (1600 / 620), 1),
      );
      expect(HomeBannerBreakpoints.resolveHeight(768), 228);
      expect(HomeBannerBreakpoints.resolveHeight(1024), 280);
      expect(HomeBannerBreakpoints.resolveHeight(1440), 320);
      expect(
        HomeBannerBreakpoints.resolveHeight(1024, configuredHeight: 88),
        280,
      );
      expect(
        HomeBannerBreakpoints.resolveHeight(1024, configuredHeight: 300),
        closeTo(300, 0.1),
      );
    });

    test('square aspect uses 1:1 height on mobile and caps on desktop', () {
      expect(
        HomeBannerBreakpoints.resolveHeight(
          390,
          aspectMode: BannerAspectMode.square,
        ),
        closeTo(390, 1),
      );
      expect(
        HomeBannerBreakpoints.resolveHeight(
          1200,
          aspectMode: BannerAspectMode.square,
        ),
        closeTo(420, 1),
      );
      expect(BannerAspectMode.parse(null), BannerAspectMode.wide);
      expect(BannerAspectMode.parse('square'), BannerAspectMode.square);
    });
  });

  group('OfferBannerCarousel layouts', () {
    testWidgets('mobile carousel reveals scaled banners on both sides',
        (tester) async {
      const size = Size(416, 838);
      await _pumpBanner(
        tester,
        size: size,
        banners: [
          const HomeBannerSlide(
            id: 'peek-1',
            title: 'العرض الأول',
            subtitle: 'وصف العرض الأول',
            cta: 'اطلب الآن',
            imageUrl: 'https://example.com/peek-1.jpg',
            category: 'قطط',
            destination: BannerDestination.internal('/catalog'),
            sourceUrl: '',
            isDemo: false,
          ),
          const HomeBannerSlide(
            id: 'peek-2',
            title: 'العرض الثاني',
            subtitle: 'وصف العرض الثاني',
            cta: 'تصفح',
            imageUrl: 'https://example.com/peek-2.jpg',
            category: 'كلاب',
            destination: BannerDestination.internal('/catalog'),
            sourceUrl: '',
            isDemo: false,
          ),
          const HomeBannerSlide(
            id: 'peek-3',
            title: 'العرض الثالث',
            subtitle: 'وصف العرض الثالث',
            cta: 'شاهد العرض',
            imageUrl: 'https://example.com/peek-3.jpg',
            category: 'طيور',
            destination: BannerDestination.internal('/catalog'),
            sourceUrl: '',
            isDemo: false,
          ),
        ],
      );

      final pageViewFinder =
          find.byKey(const Key('offer-banner-peek-page-view'));
      expect(pageViewFinder, findsOneWidget);
      final pageView = tester.widget<PageView>(pageViewFinder);
      expect(pageView.controller?.viewportFraction, closeTo(.90, .001));

      final initialPage = pageView.controller!.initialPage;
      final active = find.byKey(ValueKey('offer-banner-page-$initialPage'));
      final previous =
          find.byKey(ValueKey('offer-banner-page-${initialPage - 1}'));
      final next = find.byKey(ValueKey('offer-banner-page-${initialPage + 1}'));
      expect(active, findsOneWidget);
      expect(previous, findsOneWidget);
      expect(next, findsOneWidget);

      final frameRect = tester.getRect(
        find.byKey(const Key('offer-banner-carousel-frame')),
      );
      final activeRect = tester.getRect(active);
      expect(activeRect.width, lessThan(frameRect.width));
      expect(activeRect.left, greaterThan(frameRect.left));
      expect(activeRect.right, lessThan(frameRect.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'mobile uses full-bleed cover banner without dark scrim or overlay button',
        (tester) async {
      const size = Size(390, 844);
      await _pumpBanner(
        tester,
        size: size,
        banners: [
          const HomeBannerSlide(
            id: 'b1',
            title: 'عنوان طويل جداً لبانر العروض الخاصة بالجملة للتجار',
            subtitle: 'وصف فرعي واضح',
            cta: 'تسوق الآن',
            imageUrl: 'https://example.com/a.jpg',
            category: 'أعلاف',
            destination: BannerDestination.internal('/catalog'),
            sourceUrl: '',
            isDemo: false,
          ),
        ],
      );

      expect(
          find.byKey(const Key('offer-banner-carousel-frame')), findsOneWidget);
      expect(find.byKey(const Key('offer-banner-overlay')), findsOneWidget);
      expect(find.byKey(const Key('offer-banner-cta-b1')), findsNothing);
      expect(find.byKey(const Key('offer-banner-copy-scrim')), findsNothing);
      expect(tester.takeException(), isNull);

      final frame = tester.getSize(
        find.byKey(const Key('offer-banner-carousel-frame')),
      );
      // Viewport 390 minus scaffold padding (16*2) → content width ~358.
      final expectedHeight =
          HomeBannerBreakpoints.resolveHeight(size.width - 32);
      expect(frame.height, closeTo(expectedHeight, 1));
      // Must stay near crop aspect — not the old tall stacked ~292 slab.
      expect(frame.height, lessThan(210));

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, isNotEmpty);
      expect(
        images.every((image) => image.fit == BoxFit.fill),
        isTrue,
      );
    });

    testWidgets('square banner at 390 fills frame with cover fit',
        (tester) async {
      const size = Size(390, 844);
      await _pumpBanner(
        tester,
        size: size,
        banners: [
          const HomeBannerSlide(
            id: 'sq',
            title: 'بانر مربع',
            subtitle: 'اختبار 1:1',
            cta: 'اطلب الآن',
            imageUrl: 'https://example.com/square.jpg',
            category: 'أعلاف',
            destination: BannerDestination.internal('/catalog'),
            sourceUrl: '',
            isDemo: false,
            aspectMode: BannerAspectMode.square,
          ),
        ],
      );

      final frame = tester.getSize(
        find.byKey(const Key('offer-banner-carousel-frame')),
      );
      final expected = HomeBannerBreakpoints.resolveHeight(
        size.width - 32,
        aspectMode: BannerAspectMode.square,
      );
      expect(frame.height, closeTo(expected, 2));
      expect(frame.height, greaterThan(300));
      expect(find.byKey(const Key('offer-banner-overlay')), findsOneWidget);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, isNotEmpty);
      expect(images.every((image) => image.fit == BoxFit.fill), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile preview width 390 fills frame without stacked slab',
        (tester) async {
      const size = Size(390, 844);
      await _pumpBanner(
        tester,
        size: size,
        compact: true,
        banners: [
          const HomeBannerSlide(
            id: 'preview',
            title: 'عرض تجريبي',
            subtitle: 'معاينة المتجر',
            cta: 'اطلب الآن',
            imageUrl: 'https://example.com/preview.jpg',
            category: 'قطط',
            destination: BannerDestination.internal('/catalog'),
            sourceUrl: '',
            isDemo: false,
          ),
        ],
      );

      final frameRect = tester.getRect(
        find.byKey(const Key('offer-banner-carousel-frame')),
      );
      final overlayRect = tester.getRect(
        find.byKey(const Key('offer-banner-overlay')),
      );
      // Overlay (and cover image stack) spans the full carousel frame.
      expect(overlayRect.height, closeTo(frameRect.height, 2));
      expect(find.byKey(const Key('offer-banner-overlay')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet and desktop keep full-bleed banner cover layout',
        (tester) async {
      for (final size in const [
        Size(768, 1024),
        Size(1280, 800),
      ]) {
        await _pumpBanner(
          tester,
          size: size,
          banners: [
            const HomeBannerSlide(
              id: 'desk',
              title: 'عروض الجملة',
              subtitle: 'أسعار تجريبية',
              cta: 'اطلب الآن',
              imageUrl: 'https://example.com/b.jpg',
              category: 'قطط',
              destination: BannerDestination.internal('/catalog'),
              sourceUrl: '',
              isDemo: false,
            ),
          ],
        );
        expect(find.byKey(const Key('offer-banner-overlay')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('banner renders cleanly without overlay button or dark scrim across widths',
        (tester) async {
      const longTitle =
          'عروض خاصة جداً لتجار مستلزمات الحيوانات والأعلاف بالجملة في طرابلس ومصراتة وبنغازي';
      for (final width in const [
        320.0,
        360.0,
        390.0,
        430.0,
        768.0,
        1024.0,
        1440.0
      ]) {
        await _pumpBanner(
          tester,
          size: Size(width, 900),
          banners: [
            const HomeBannerSlide(
              id: 'long',
              title: longTitle,
              subtitle:
                  'نص فرعي طويل أيضاً للتحقق من الالتفاف العربي دون قص حاد للمحتوى',
              cta: 'ابدأ التسوق',
              imageUrl: 'https://example.com/d.jpg',
              category: 'مستلزمات',
              destination: BannerDestination.internal('/catalog'),
              sourceUrl: '',
              isDemo: false,
            ),
          ],
        );
        expect(find.byKey(const Key('offer-banner-overlay')), findsOneWidget);
        expect(find.byKey(const Key('offer-banner-copy-scrim')), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('customer home denser product layout', () {
    testWidgets('mobile product sections use a horizontal peek rail',
        (tester) async {
      await _pumpHome(tester, size: const Size(390, 844));
      expect(find.byKey(const Key('customer-home-products')), findsOneWidget);
      expect(
        find.byKey(const Key('customer-home-products-peek-rail')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('customer-home-product-feed-1')),
        findsWidgets,
      );
      expect(find.text('التصنيفات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'phone peeks the next product card on the trailing RTL edge',
        (tester) async {
      await _pumpMixedProductGrid(tester, size: const Size(390, 844));

      final rail = find.byKey(const Key('customer-home-products-peek-rail'));
      expect(rail, findsOneWidget);
      final first = find.byKey(const Key('customer-home-product-cat-001'));
      final second = find.byKey(const Key('customer-home-product-cat-002'));
      final third = find.byKey(const Key('customer-home-product-cat-003'));
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(third, findsOneWidget);

      final railRect = tester.getRect(rail);
      final firstRect = tester.getRect(first);
      final secondRect = tester.getRect(second);
      final thirdRect = tester.getRect(third);

      // Two full cards stay inside the rail.
      expect(firstRect.left, greaterThanOrEqualTo(railRect.left - .5));
      expect(firstRect.right, lessThanOrEqualTo(railRect.right + .5));
      expect(secondRect.left, greaterThanOrEqualTo(railRect.left - .5));
      expect(secondRect.right, lessThanOrEqualTo(railRect.right + .5));

      // Third card peeks from the trailing (left) edge in RTL.
      expect(
        firstRect.right,
        greaterThan(secondRect.right),
        reason: 'First product anchors at the RTL start edge.',
      );
      expect(
        thirdRect.right,
        lessThan(secondRect.left),
        reason: 'The third card continues past the second toward the left.',
      );
      expect(
        thirdRect.right,
        greaterThan(railRect.left + 8),
        reason: 'At least ~12–24px of the next card should be visible.',
      );
      expect(
        thirdRect.left,
        lessThan(railRect.left - 4),
        reason: 'Most of the third card stays clipped outside the rail.',
      );
      final peekVisible = thirdRect.right - railRect.left;
      expect(peekVisible, inInclusiveRange(12, 28));

      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop shows more products in section grid than before',
        (tester) async {
      await _pumpHome(tester, size: const Size(1280, 900));

      final section = find.byKey(const Key('customer-home-products'));
      expect(section, findsOneWidget);
      final cards = find.descendant(
        of: section,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>)
                  .value
                  .startsWith('customer-home-product-'),
        ),
      );
      // 5 columns × 2 rows = up to 10; catalog has 10 products.
      expect(cards.evaluate().length, greaterThanOrEqualTo(8));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'sparse desktop section uses equal wide RTL cards across the row',
        (tester) async {
      var productTaps = 0;
      var addToCartTaps = 0;
      await _pumpSparseProductGrid(
        tester,
        size: const Size(1440, 900),
        onProductTap: (_) => productTaps++,
        onAddToCart: (_) => addToCartTaps++,
      );

      final layout = find.byKey(
        const Key('customer-home-products-wide-product-layout'),
      );
      final firstCard = find.byKey(const Key('customer-home-product-sparse-1'));
      final secondCard =
          find.byKey(const Key('customer-home-product-sparse-2'));
      expect(layout, findsOneWidget);
      expect(firstCard, findsOneWidget);
      expect(secondCard, findsOneWidget);

      final sectionRect = tester.getRect(
        find.byKey(const Key('customer-home-products-section')),
      );
      final firstRect = tester.getRect(firstCard);
      final secondRect = tester.getRect(secondCard);
      expect(firstRect.size, secondRect.size);
      expect(firstRect.width, greaterThan(500));
      expect(firstRect.height, lessThan(260));
      expect(firstRect.width, greaterThan(firstRect.height * 2));
      expect(
        firstRect.right - secondRect.left,
        greaterThan(sectionRect.width * .9),
        reason: 'Two products should intentionally occupy the desktop row.',
      );
      expect(
        firstRect.right,
        greaterThan(secondRect.right),
        reason: 'The first product should start at the RTL edge.',
      );

      for (final card in [firstCard, secondCard]) {
        final imageFinder = find.descendant(
          of: card,
          matching: find.byType(ProductImagePlaceholder),
        );
        expect(imageFinder, findsOneWidget);
        expect(
          tester.widget<ProductImagePlaceholder>(imageFinder).fit,
          BoxFit.contain,
        );
        expect(
          tester.getSize(imageFinder).width,
          lessThan(tester.getSize(card).width * .45),
          reason: 'Desktop cards should use a horizontal media treatment.',
        );
      }

      await tester.tapAt(firstRect.topLeft + const Offset(24, 24));
      await tester.pump();
      expect(productTaps, 1);

      await tester.tap(
        find.byKey(const Key('customer-home-add-to-cart-sparse-1')),
      );
      await tester.pump();
      expect(addToCartTaps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'three sparse products keep roomy wide cards near 980 to 1100 pixels',
        (tester) async {
      var productTaps = 0;
      var addToCartTaps = 0;

      for (final viewportWidth in [1080.0, 1196.0]) {
        await _pumpSparseProductGrid(
          tester,
          size: Size(viewportWidth, 900),
          products: _threeSparseProducts,
          onProductTap: (_) => productTaps++,
          onAddToCart: (_) => addToCartTaps++,
        );

        final layout = find.byKey(
          const Key('customer-home-products-wide-product-layout'),
        );
        final firstCard =
            find.byKey(const Key('customer-home-product-sparse-1'));
        final secondCard =
            find.byKey(const Key('customer-home-product-sparse-2'));
        final thirdCard =
            find.byKey(const Key('customer-home-product-sparse-3'));
        expect(layout, findsOneWidget);
        expect(firstCard, findsOneWidget);
        expect(secondCard, findsOneWidget);
        expect(thirdCard, findsOneWidget);

        final layoutRect = tester.getRect(layout);
        final firstRect = tester.getRect(firstCard);
        final secondRect = tester.getRect(secondCard);
        final thirdRect = tester.getRect(thirdCard);
        expect(layoutRect.width, inInclusiveRange(980, 1100));
        expect(firstRect.width, closeTo(secondRect.width, .01));
        expect(secondRect.width, closeTo(thirdRect.width, .01));
        expect(firstRect.height, closeTo(secondRect.height, .01));
        expect(secondRect.height, closeTo(thirdRect.height, .01));
        expect(firstRect.width, greaterThanOrEqualTo(390));
        expect(firstRect.top, closeTo(secondRect.top, 1));
        expect(thirdRect.top, greaterThan(firstRect.bottom));
        expect(thirdRect.center.dx, closeTo(layoutRect.center.dx, 1));
        expect(
          firstRect.right,
          greaterThan(secondRect.right),
          reason: 'The first product should remain at the RTL edge.',
        );

        for (final card in [firstCard, secondCard, thirdCard]) {
          final imageFinder = find.descendant(
            of: card,
            matching: find.byType(ProductImagePlaceholder),
          );
          expect(imageFinder, findsOneWidget);
          expect(
            tester.widget<ProductImagePlaceholder>(imageFinder).fit,
            BoxFit.contain,
          );
        }

        await tester.tapAt(thirdRect.topLeft + const Offset(24, 24));
        await tester.pump();
        expect(productTaps, viewportWidth == 1080 ? 1 : 2);

        await tester.tap(
          find.byKey(const Key('customer-home-add-to-cart-sparse-3')),
        );
        await tester.pump();
        expect(addToCartTaps, viewportWidth == 1080 ? 1 : 2);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('product cards stay compact without large blank under image',
        (tester) async {
      await _pumpHome(tester, size: const Size(390, 844));
      final card = find.byKey(const Key('customer-home-product-feed-1')).first;
      expect(card, findsOneWidget);
      final size = tester.getSize(card);
      // Minimal phone cards: shorter image + flatter pricing chrome.
      expect(size.height, lessThan(240));
      expect(size.height, greaterThan(180));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'minimal product section peeks next section and rounds images',
        (tester) async {
      const size = Size(390, 844);
      await _pumpHome(tester, size: size);

      // Demo catalog marks top-selling items; featured may hide when empty.
      final productsSection =
          find.byKey(const Key('customer-home-products-section'));
      expect(productsSection, findsOneWidget);
      final productsRect = tester.getRect(productsSection);
      expect(
        productsRect.height,
        lessThan(320),
        reason: 'Phone product sections should use one compact row.',
      );
      expect(
        productsRect.bottom,
        lessThan(size.height - 48),
        reason: 'Product section should leave room below in the first viewport.',
      );

      final image = tester.widget<ProductImagePlaceholder>(
        find
            .descendant(
              of: find.byKey(const Key('customer-home-product-feed-1')).first,
              matching: find.byType(ProductImagePlaceholder),
            )
            .first,
      );
      expect(image.borderRadius, isNotNull);
      expect(image.borderRadius, isNot(BorderRadius.zero));
      expect(find.text('الأكثر طلباً'), findsOneWidget);
      expect(find.text('عرض الكل'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'mixed product content keeps equal cards and uncropped images at mobile widths',
        (tester) async {
      for (final width in const [338.0, 416.0]) {
        await _pumpMixedProductGrid(tester, size: Size(width, 838));

        final shortCard =
            find.byKey(const Key('customer-home-product-cat-001'));
        final longCard = find.byKey(const Key('customer-home-product-cat-002'));
        expect(shortCard, findsOneWidget);
        expect(longCard, findsOneWidget);

        final shortSize = tester.getSize(shortCard);
        final longSize = tester.getSize(longCard);
        expect(
          shortSize.height,
          closeTo(longSize.height, .01),
          reason:
              'Mixed product names must not change card height at $width px.',
        );

        for (final card in [shortCard, longCard]) {
          final imageFinder = find.descendant(
            of: card,
            matching: find.byType(ProductImagePlaceholder),
          );
          expect(imageFinder, findsOneWidget);
          final image = tester.widget<ProductImagePlaceholder>(imageFinder);
          expect(
            image.fit,
            BoxFit.contain,
            reason: 'Product images must remain fully visible at $width px.',
          );
          expect(
            tester.getSize(imageFinder).height,
            greaterThanOrEqualTo(100),
            reason: 'The allocated product image panel must stay substantial.',
          );
        }

        expect(
          find.text(CustomerProductCardCopy.retail).evaluate().length,
          greaterThanOrEqualTo(2),
        );
        final addAction = tester.getSize(
          find.byKey(
            const Key('customer-home-add-to-cart-cat-002'),
          ),
        );
        expect(addAction.width, greaterThanOrEqualTo(44));
        expect(addAction.height, greaterThanOrEqualTo(44));
        // Phone peek rail keeps the next product in the horizontal list.
        expect(
          find.byKey(const Key('customer-home-products-peek-rail')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('customer-home-product-cat-003')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('tablet uses multi-column section without overflow',
        (tester) async {
      await _pumpHome(tester, size: const Size(768, 1024));
      final section = find.byKey(const Key('customer-home-products'));
      final cards = find.descendant(
        of: section,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>)
                  .value
                  .startsWith('customer-home-product-'),
        ),
      );
      expect(cards.evaluate().length, greaterThanOrEqualTo(6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('categories remain readable across widths', (tester) async {
      for (final width in const [320.0, 338.0, 402.0, 430.0, 768.0, 1280.0]) {
        await _pumpHome(tester, size: Size(width, 900));
        expect(
            find.byKey(const Key('customer-home-categories')), findsOneWidget);
        expect(find.text('أعلاف'), findsWidgets);
        final tileWidth = tester
            .getSize(find.byKey(const Key('customer-home-category-أعلاف')))
            .width;
        final usesAutoRail = find
            .byKey(const Key('customer-home-categories-auto-rail'))
            .evaluate()
            .isNotEmpty;
        if (usesAutoRail) {
          expect(tileWidth, greaterThanOrEqualTo(68));
          expect(tileWidth, lessThanOrEqualTo(86));
        } else {
          expect(tileWidth, greaterThanOrEqualTo(80));
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'compact category strip shows whole RTL cards with inset artwork',
        (tester) async {
      for (final width in const [338.0, 402.0]) {
        await _pumpHome(tester, size: Size(width, 900));

        final strip = find.byKey(const Key('customer-home-categories'));
        final stripRect = tester.getRect(strip);
        var fullyVisibleCards = 0;
        for (final name in const [
          'أعلاف',
          'قطط',
          'أدوية',
          'كلاب',
          'طيور',
          'مستلزمات',
        ]) {
          final tile = find.byKey(Key('customer-home-category-$name'));
          if (tile.evaluate().isEmpty) continue;
          final tileRect = tester.getRect(tile);
          final fullyInside = tileRect.left >= stripRect.left - .5 &&
              tileRect.right <= stripRect.right + .5;
          if (!fullyInside) continue;
          fullyVisibleCards++;
        }
        expect(fullyVisibleCards, greaterThanOrEqualTo(3));

        final outerFrame = find.byKey(
          const Key('customer-home-category-frame-c-feed'),
        );
        final artworkFrame = find.descendant(
          of: outerFrame,
          matching: find.byKey(const Key('category-artwork-frame')),
        );
        final outerSize = tester.getSize(outerFrame);
        final artworkSize = tester.getSize(artworkFrame);
        expect(artworkSize.width, lessThan(outerSize.width - 8));
        expect(artworkSize.height, lessThan(outerSize.height - 8));
        expect(outerSize.width, closeTo(outerSize.height, .01));
        expect(
          Directionality.of(
            tester.element(
              find.byKey(const Key('customer-home-category-أعلاف')),
            ),
          ),
          TextDirection.rtl,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'compact categories leave room for featured products on phone',
        (tester) async {
      const size = Size(390, 844);
      await _pumpHome(tester, size: size);

      final categoriesSection =
          find.byKey(const Key('customer-home-categories-section'));
      final productsSection =
          find.byKey(const Key('customer-home-products-section'));
      expect(categoriesSection, findsOneWidget);
      expect(productsSection, findsOneWidget);

      final categoriesRect = tester.getRect(categoriesSection);
      expect(
        categoriesRect.height,
        lessThan(168),
        reason: 'Categories section should stay compact on phone.',
      );

      final productsRect = tester.getRect(productsSection);
      // Featured products header should enter the first phone viewport.
      expect(productsRect.top, lessThan(size.height - 120));
      expect(
        find.byKey(const Key('customer-home-categories-auto-rail')),
        findsOneWidget,
      );
      expect(find.text('عرض الكل'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'desktop groups detailed sections with square media and large actions',
        (tester) async {
      await _pumpHome(tester, size: const Size(1600, 1000));

      final frame = find.byKey(const Key('customer-home-content-frame'));
      expect(frame, findsOneWidget);
      final frameRect = tester.getRect(frame);
      expect(frameRect.width, lessThanOrEqualTo(1440));
      expect(frameRect.center.dx, closeTo(800, 1));

      final categoriesSection =
          find.byKey(const Key('customer-home-categories-section'));
      final productsSection =
          find.byKey(const Key('customer-home-products-section'));
      expect(categoriesSection, findsOneWidget);
      expect(productsSection, findsOneWidget);
      expect(
        find.descendant(
          of: categoriesSection,
          matching: find.byKey(const Key('customer-home-categories')),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'اختر التصنيف للوصول بسرعة إلى المنتجات المناسبة لمتجرك.',
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.category_outlined), findsOneWidget);
      expect(find.text('🔥 العروض'), findsNothing);
      expect(find.text('العروض'), findsOneWidget);

      final categoryFrame = tester.getSize(
        find.byKey(const Key('customer-home-category-frame-c-feed')),
      );
      expect(categoryFrame.width, closeTo(categoryFrame.height, .01));

      final addAction = tester.getSize(
        find.byKey(const Key('customer-home-add-to-cart-feed-1')).first,
      );
      expect(addAction.width, greaterThanOrEqualTo(44));
      expect(addAction.height, greaterThanOrEqualTo(44));

      final cards = find.descendant(
        of: find.byKey(const Key('customer-home-products')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>)
                  .value
                  .startsWith('customer-home-product-'),
        ),
      );
      expect(cards.evaluate().length, 10);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('renderer preserves banner CTA and product density in preview',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StorefrontHomeRenderer(
                config: StorefrontDefaults.bundled,
                data: StorefrontHomeData(
                  products: _manyProducts(),
                  categories: const [
                    ProductCategory(
                        id: 'c-feed', name: 'أعلاف', iconKey: 'feed'),
                  ],
                  banners: const [
                    AppBanner(
                      id: 'banner-1',
                      title: 'بانر المعاينة',
                      body: 'نص',
                      ctaText: 'اطلب',
                      imageUrl: 'https://example.com/banner.jpg',
                    ),
                  ],
                  userName: 'متجر الاختبار',
                  userLocation: 'طرابلس',
                ),
                interactionMode: StorefrontInteractionMode.preview,
                renderMode: StorefrontRenderMode.adminPreview,
                actions: const StorefrontHomeActions(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offer-banner-overlay')), findsOneWidget);
    expect(find.byKey(const Key('customer-home-products')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required Size size,
  required List<HomeBannerSlide> banners,
  bool? compact,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: OfferBannerCarousel(
              banners: banners,
              height: 88,
              compact: compact,
              autoPlay: false,
              interactionEnabled: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpHome(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => _CustomerAuthController(),
        ),
        catalogRepositoryProvider.overrideWithValue(_DenseCatalogRepository()),
        ordersRepositoryProvider.overrideWithValue(
          OrdersRepository.demo(seed: const []),
        ),
        adminRepositoryProvider.overrideWithValue(_HomeBannersRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: true),
            child: child!,
          );
        },
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CustomerHomeScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpMixedProductGrid(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const config = StorefrontConfig(
    sections: [
      StorefrontSectionConfig(
        type: StorefrontSectionType.bestSelling,
        settings: {
          'title': 'الأكثر طلباً',
          'maxItems': 4,
          'showAddToCart': true,
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StorefrontHomeRenderer(
              config: config,
              data: StorefrontHomeData(
                products: _mixedLengthProducts(),
                userName: 'متجر الاختبار',
                userLocation: 'طرابلس',
              ),
              actions: StorefrontHomeActions(
                onProductTap: (_) {},
                onAddToCart: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSparseProductGrid(
  WidgetTester tester, {
  required Size size,
  required ValueChanged<Product> onProductTap,
  required ValueChanged<Product> onAddToCart,
  List<Product> products = _sparseProducts,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const config = StorefrontConfig(
    sections: [
      StorefrontSectionConfig(
        type: StorefrontSectionType.bestSelling,
        settings: {
          'title': 'الأكثر طلباً',
          'maxItems': 3,
          'showAddToCart': true,
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StorefrontHomeRenderer(
              config: config,
              data: StorefrontHomeData(
                products: products,
                userName: 'متجر الاختبار',
                userLocation: 'طرابلس',
              ),
              actions: StorefrontHomeActions(
                onProductTap: onProductTap,
                onAddToCart: onAddToCart,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Product> _manyProducts() {
  return [
    for (var i = 1; i <= 10; i++)
      Product(
        id: 'feed-$i',
        nameAr: 'علف رقم $i للجملة',
        sku: 'FEED-$i',
        category: 'أعلاف',
        animalType: 'دواجن',
        brand: 'الواحة',
        unitSize: '25 كجم',
        basePrice: 40 + i.toDouble(),
        stockQuantity: 40,
        minOrderQty: 1,
        isTopSelling: true,
        discountPercent: i == 2 ? 10 : null,
      ),
  ];
}

const _sparseProducts = [
  Product(
    id: 'sparse-1',
    nameAr: 'طعام قطط بريميوم للتجار',
    sku: 'SPARSE-1',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'الواحة',
    unitSize: '15 كجم',
    basePrice: 150,
    retailUnitPrice: 180,
    stockQuantity: 40,
    minOrderQty: 1,
    isTopSelling: true,
  ),
  Product(
    id: 'sparse-2',
    nameAr: 'رمل قطط عالي الامتصاص',
    sku: 'SPARSE-2',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'بيتي',
    unitSize: '10 لتر',
    basePrice: 35,
    retailUnitPrice: 48,
    stockQuantity: 40,
    minOrderQty: 1,
    isTopSelling: true,
  ),
];

const _threeSparseProducts = [
  ..._sparseProducts,
  Product(
    id: 'sparse-3',
    nameAr: 'مكافآت قطط للتجار',
    sku: 'SPARSE-3',
    category: 'قطط',
    animalType: 'قطط',
    brand: 'بيتي',
    unitSize: '24 عبوة',
    basePrice: 72,
    retailUnitPrice: 90,
    stockQuantity: 40,
    minOrderQty: 1,
    isTopSelling: true,
  ),
];

List<Product> _mixedLengthProducts() {
  return const [
    Product(
      id: 'cat-001',
      nameAr: 'طعام قطط',
      sku: 'CAT-001',
      category: 'قطط',
      animalType: 'قطط',
      brand: 'كينج',
      unitSize: '15 كجم',
      basePrice: 150,
      retailUnitPrice: 180,
      stockQuantity: 40,
      minOrderQty: 1,
      isTopSelling: true,
    ),
    Product(
      id: 'cat-002',
      nameAr: 'طعام قطط متكامل فاخر جداً للقطط البالغة بنكهة الدجاج والخضروات',
      sku: 'CAT-002-LONG',
      category: 'قطط',
      animalType: 'قطط',
      brand: 'علامة تجارية طويلة جداً لاختبار المساحة',
      unitSize: 'صندوق كبير يحتوي على عبوات متعددة',
      basePrice: 9999999.99,
      retailUnitPrice: 12999999.99,
      stockQuantity: 40,
      minOrderQty: 1,
      isTopSelling: true,
    ),
    Product(
      id: 'cat-003',
      nameAr: 'رمل قطط',
      sku: 'CAT-003',
      category: 'قطط',
      animalType: 'قطط',
      brand: '',
      unitSize: '',
      basePrice: 35,
      retailUnitPrice: 42,
      stockQuantity: 40,
      minOrderQty: 1,
      isTopSelling: true,
    ),
    Product(
      id: 'cat-004',
      nameAr: 'مكافآت قطط بطعم السلمون للاستخدام اليومي',
      sku: 'CAT-004',
      category: 'قطط',
      animalType: 'قطط',
      brand: 'بيتي',
      unitSize: '12 عبوة × 85 جم',
      basePrice: 72,
      retailUnitPrice: 90,
      stockQuantity: 40,
      minOrderQty: 1,
      isTopSelling: true,
    ),
  ];
}

class _CustomerAuthController extends AuthController {
  _CustomerAuthController() {
    state = const AuthState(
      user: AppUser(
        id: 'profile-1',
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: 'customer-1',
        city: 'طرابلس',
        area: 'حي الأندلس',
      ),
    );
  }
}

class _DenseCatalogRepository extends CatalogRepository {
  @override
  Future<List<Product>> products({
    String query = '',
    String? category,
    bool includeInactive = false,
  }) async {
    return _manyProducts();
  }

  @override
  Future<List<ProductCategory>> productCategories({
    bool includeArchived = false,
  }) async {
    return const [
      ProductCategory(id: 'c-feed', name: 'أعلاف', iconKey: 'feed'),
      ProductCategory(id: 'c-cat', name: 'قطط', iconKey: 'cat'),
      ProductCategory(id: 'c-med', name: 'أدوية', iconKey: 'medicine'),
      ProductCategory(id: 'c-dog', name: 'كلاب', iconKey: 'dog'),
      ProductCategory(id: 'c-bird', name: 'طيور', iconKey: 'bird'),
      ProductCategory(id: 'c-supply', name: 'مستلزمات', iconKey: 'supplies'),
    ];
  }
}

class _HomeBannersRepository extends AdminRepository {
  @override
  Future<List<AppBanner>> banners({bool includeInactive = false}) async {
    return const [
      AppBanner(
        id: 'banner-1',
        title: 'عرض جملة لتجار الأعلاف',
        body: 'أسعار تجريبية للعرض',
        ctaText: 'اطلب الآن',
        imageUrl: 'https://example.com/banner.jpg',
      ),
    ];
  }
}
