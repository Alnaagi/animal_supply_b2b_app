import 'package:animal_supply_b2b/src/core/config/app_config.dart';
import 'package:animal_supply_b2b/src/core/config/shop_branding.dart';
import 'package:animal_supply_b2b/src/core/config/shop_branding_cache.dart';
import 'package:animal_supply_b2b/src/core/localization/arabic_copy.dart';
import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/shop_loading.dart';
import 'package:animal_supply_b2b/src/core/widgets/shop_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ShopBrandingCache.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('page loader shows shop name, paw motion, and Arabic copy',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopBrandingProvider.overrideWithValue(
            const ShopBranding(shopName: 'مؤسسة النور للأعلاف'),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: ShopLoading.page()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('shop-loading-page')), findsOneWidget);
    expect(find.text('مؤسسة النور للأعلاف'), findsOneWidget);
    expect(find.text(ArabicCopy.screenLoading), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      Directionality.of(tester.element(find.byKey(const Key('shop-loading-page')))),
      TextDirection.rtl,
    );
  });

  testWidgets('page loader falls back to default shop name', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: ShopLoading.page()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(AppConfig.shopName), findsOneWidget);
  });

  testWidgets('compact loader is paw-based without a generic spinner',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: ShopLoading.compact()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('shop-loading-compact')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('pull-to-refresh copy follows drag, release, then refresh', () {
    expect(
      ShopRefreshIndicator.messageFor(RefreshIndicatorStatus.drag),
      ArabicCopy.pullToRefresh,
    );
    expect(
      ShopRefreshIndicator.messageFor(RefreshIndicatorStatus.armed),
      ArabicCopy.releaseToRefresh,
    );
    expect(
      ShopRefreshIndicator.messageFor(RefreshIndicatorStatus.refresh),
      ArabicCopy.refreshing,
    );
  });

  test('overscroll visual pull eases without overshooting the cap', () {
    expect(ShopRefreshIndicator.visualPullForOffset(0), 0);
    expect(
      ShopRefreshIndicator.visualPullForOffset(
        ShopRefreshIndicator.dragThreshold,
      ),
      closeTo(1, 0.001),
    );
    final mid = ShopRefreshIndicator.visualPullForOffset(
      ShopRefreshIndicator.dragThreshold * 0.5,
    );
    expect(mid, greaterThan(0.5));
    expect(mid, lessThan(1));
    final extra = ShopRefreshIndicator.visualPullForOffset(
      ShopRefreshIndicator.dragThreshold * 2,
    );
    expect(extra, greaterThan(1));
    expect(extra, lessThanOrEqualTo(ShopRefreshIndicator.maxPull));
  });

  testWidgets('refresh overlay uses branded Arabic banner', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ShopRefreshIndicator(
              onRefresh: () async {
                await Future<void>.delayed(const Duration(milliseconds: 50));
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 800, child: Text('محتوى')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.fling(find.text('محتوى'), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('shop-refresh-indicator')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text(ArabicCopy.refreshing),
      findsOneWidget,
    );
    expect(find.text(ArabicCopy.pullToRefresh), findsNothing);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
  });

  testWidgets('drag shows stretching indicator before release', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ShopRefreshIndicator(
                onRefresh: _noopRefresh,
                child: CustomScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(height: 800, child: Text('محتوى')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final gesture = await tester.startGesture(tester.getCenter(find.text('محتوى')));
    await gesture.moveBy(const Offset(0, 90));
    await tester.pump();
    expect(find.byKey(const Key('shop-refresh-indicator')), findsOneWidget);
    expect(
      find.text(ArabicCopy.pullToRefresh).evaluate().isNotEmpty ||
          find.text(ArabicCopy.releaseToRefresh).evaluate().isNotEmpty,
      isTrue,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}

Future<void> _noopRefresh() async {}
