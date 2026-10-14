import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/shop_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapWithTheme(Widget child, {bool rtl = true}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(body: child),
      ),
    );
  }

  group('ShopSkeleton Components', () {
    testWidgets('renders ShopSkeleton with semantics and shimmer',
        (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const ShopSkeleton(
            semanticLabel: 'جارٍ تحميل البيانات',
            child: ShopSkeletonBox(width: 100, height: 20),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('shop-skeleton')), findsOneWidget);
      expect(find.byType(ShopSkeletonBox), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('shop-skeleton'))).label,
        'جارٍ تحميل البيانات',
      );
    });

    testWidgets('shimmer adapts to reduced motion', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              disableAnimations: true,
              accessibleNavigation: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: ShopSkeleton(
                  child: ShopSkeletonBox(width: 100, height: 20),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ShopSkeletonBox), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('renders ShopDashboardSkeleton without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        wrapWithTheme(
          const ShopSkeleton(child: ShopDashboardSkeleton()),
        ),
      );
      await tester.pump();

      expect(find.byType(ShopSkeletonCard), findsWidgets);
      expect(find.byType(ShopSkeletonBox), findsWidgets);
      expect(find.byType(ShopSkeletonCircle), findsWidgets);
    });

    testWidgets('renders ShopProductGridSkeleton and ShopProductListSkeleton',
        (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SingleChildScrollView(
            child: Column(
              children: [
                ShopSkeleton(child: ShopProductGridSkeleton(itemCount: 4)),
                ShopSkeleton(child: ShopProductListSkeleton(itemCount: 3)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShopSkeletonCard), findsWidgets);
    });

    testWidgets('renders ShopCategoryStripSkeleton, Banner and Details',
        (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SingleChildScrollView(
            child: Column(
              children: [
                ShopSkeleton(child: ShopBannerSkeleton()),
                ShopSkeleton(child: ShopCategoryStripSkeleton()),
                ShopSkeleton(child: ShopProductDetailsSkeleton()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShopSkeletonCircle), findsWidgets);
      expect(find.byType(ShopSkeletonBox), findsWidgets);
    });

    testWidgets('renders Order, Customer, Settings and Reports skeletons',
        (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SingleChildScrollView(
            child: Column(
              children: [
                ShopSkeleton(child: ShopOrderListSkeleton(itemCount: 2)),
                ShopSkeleton(child: ShopCustomerListSkeleton(itemCount: 2)),
                ShopSkeleton(child: ShopSettingsSkeleton()),
                ShopSkeleton(child: ShopReportsSkeleton()),
                ShopSkeleton(child: ShopBannersSkeleton()),
                ShopSkeleton(child: ShopArchiveSkeleton()),
                ShopSkeleton(child: ShopNotificationsSkeleton()),
                ShopSkeleton(child: ShopDownloadSkeleton()),
                ShopSkeleton(child: ShopStorefrontBuilderSkeleton()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShopSkeletonCard), findsWidgets);
      expect(find.byType(ShopSkeleton), findsWidgets);
    });
  });
}
