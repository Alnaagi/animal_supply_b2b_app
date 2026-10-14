import 'dart:convert';

import 'package:animal_supply_b2b/src/core/routing/banner_destination.dart';
import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/category_icon_view.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/features/customer_home/offer_banner_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductImagePlaceholder', () {
    testWidgets('real photos use a neutral surface and contain fit',
        (tester) async {
      await tester.pumpWidget(
        _testApp(
          child: ProductImagePlaceholder(
            category: 'قطط',
            imageBytes: base64Decode(_transparentPng),
            size: 96,
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      final surface = tester.widget<ColoredBox>(
        find.byKey(const Key('product-image-photo-surface')),
      );

      expect(image.fit, BoxFit.contain);
      expect(surface.color, Colors.white);
      expect(
        find.byKey(const Key('product-image-placeholder-surface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing photos use the themed brand placeholder',
        (tester) async {
      const primary = Color(0xff7357c8);
      await tester.pumpWidget(
        _testApp(
          primary: primary,
          child: const ProductImagePlaceholder(
            category: 'قطط',
            size: 96,
          ),
        ),
      );

      expect(
        find.byKey(const Key('product-image-placeholder-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('product-image-photo-surface')),
        findsNothing,
      );
      expect(tester.widget<Icon>(find.byIcon(Icons.pets)).color, primary);
    });
  });

  group('CategoryIconView', () {
    testWidgets('expanded artwork uses the largest exact square constraint',
        (tester) async {
      await tester.pumpWidget(
        _testApp(
          child: const SizedBox(
            width: 120,
            height: 80,
            child: CategoryIconView(
              iconKey: 'pets',
              name: 'حيوانات',
              expand: true,
            ),
          ),
        ),
      );

      final frame = find.byKey(const Key('category-artwork-frame'));
      final glyph = tester.widget<Icon>(
        find.descendant(of: frame, matching: find.byType(Icon)),
      );
      expect(tester.getSize(frame), const Size.square(80));
      expect(glyph.size, closeTo(80 * .45, .01));
      expect(find.byType(ClipOval), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expanded network artwork stays contained and unclipped',
        (tester) async {
      await tester.pumpWidget(
        _testApp(
          child: const SizedBox.square(
            dimension: 96,
            child: CategoryIconView(
              iconUrl: 'https://example.com/category.png',
              name: 'قطط',
              expand: true,
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 96);
      expect(image.height, 96);
      expect(image.fit, BoxFit.contain);
      expect(find.byType(ClipOval), findsNothing);
    });
  });

  group('OfferBannerCarousel', () {
    testWidgets('square slide height follows the rendered peek-page width',
        (tester) async {
      await _pumpCarousel(
        tester,
        width: 400,
        banners: [
          _squareBanner(id: 'square-1'),
          _squareBanner(id: 'square-2'),
        ],
      );

      final frame = tester.getSize(
        find.byKey(const Key('offer-banner-carousel-frame')),
      );
      final pageView = tester.widget<PageView>(
        find.byKey(const Key('offer-banner-peek-page-view')),
      );

      expect(pageView.controller?.viewportFraction, closeTo(.90, .001));
      expect(frame.height, closeTo(400 * .90, .01));
      expect(frame.height, lessThan(frame.width));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mixed aspect slides keep one stable wide frame',
        (tester) async {
      await _pumpCarousel(
        tester,
        width: 400,
        banners: [
          _squareBanner(id: 'mixed-square'),
          _wideBanner(id: 'mixed-wide'),
        ],
      );

      final frameFinder = find.byKey(const Key('offer-banner-carousel-frame'));
      final before = tester.getSize(frameFinder);
      final pageView = tester.widget<PageView>(
        find.byKey(const Key('offer-banner-peek-page-view')),
      );
      pageView.controller!.jumpToPage(pageView.controller!.initialPage + 1);
      await tester.pump();
      final after = tester.getSize(frameFinder);

      expect(
        before.height,
        closeTo(HomeBannerBreakpoints.resolveHeight(400 * .90), .01),
      );
      expect(after.height, before.height);
      expect(tester.takeException(), isNull);
    });

    testWidgets('banner renders full clean image without dark scrim or CTA button',
        (tester) async {
      const primary = Color(0xff7357c8);
      await _pumpCarousel(
        tester,
        width: 420,
        primary: primary,
        banners: [_wideBanner(id: 'themed')],
      );

      final frameRect = tester.getRect(
        find.byKey(const Key('offer-banner-carousel-frame')),
      );
      final overlayRect = tester.getRect(
        find.byKey(const Key('offer-banner-overlay')),
      );
      final scrimFinder = find.byKey(const Key('offer-banner-copy-scrim'));

      expect(overlayRect.height, closeTo(frameRect.height, .01));
      expect(scrimFinder, findsNothing);
      expect(find.byKey(const Key('offer-banner-cta-themed')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion disables decorative carousel animations',
        (tester) async {
      await _pumpCarousel(
        tester,
        width: 400,
        reduceMotion: true,
        banners: [
          _wideBanner(id: 'motion-1'),
          _wideBanner(id: 'motion-2'),
        ],
      );

      final carousel = find.byType(OfferBannerCarousel);
      final indicators = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: carousel,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedContainer &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>)
                    .value
                    .startsWith('offer-banner-indicator-'),
          ),
        ),
      );

      expect(
        find.descendant(of: carousel, matching: find.byType(AnimatedSize)),
        findsNothing,
      );
      expect(indicators, isNotEmpty);
      expect(
        indicators.every((indicator) => indicator.duration == Duration.zero),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _testApp({
  required Widget child,
  Color primary = AppTheme.green,
  bool reduceMotion = false,
}) {
  final base = AppTheme.light;
  final theme = base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: primary,
      onPrimary: Colors.white,
    ),
  );
  return MaterialApp(
    theme: theme,
    builder: (context, appChild) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(disableAnimations: reduceMotion),
        child: appChild!,
      );
    },
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

Future<void> _pumpCarousel(
  WidgetTester tester, {
  required double width,
  required List<HomeBannerSlide> banners,
  Color primary = AppTheme.green,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    _testApp(
      primary: primary,
      reduceMotion: reduceMotion,
      child: SizedBox(
        width: width,
        child: OfferBannerCarousel(
          banners: banners,
          autoPlay: false,
          interactionEnabled: false,
        ),
      ),
    ),
  );
  await tester.pump();
}

const _transparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

HomeBannerSlide _squareBanner({required String id}) {
  return HomeBannerSlide(
    id: id,
    title: 'عرض مربع',
    subtitle: 'وصف العرض',
    cta: 'تصفح',
    imageUrl: 'https://example.com/$id.jpg',
    category: 'قطط',
    destination: const BannerDestination.internal('/catalog'),
    sourceUrl: '',
    isDemo: false,
    aspectMode: BannerAspectMode.square,
  );
}

HomeBannerSlide _wideBanner({required String id}) {
  return HomeBannerSlide(
    id: id,
    title: 'عرض واسع',
    subtitle: 'وصف العرض',
    cta: 'تصفح',
    imageUrl: 'https://example.com/$id.jpg',
    category: 'قطط',
    destination: const BannerDestination.internal('/catalog'),
    sourceUrl: '',
    isDemo: false,
  );
}
