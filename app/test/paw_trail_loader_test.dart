import 'package:animal_supply_b2b/src/core/config/shop_branding.dart';
import 'package:animal_supply_b2b/src/core/config/shop_branding_cache.dart';
import 'package:animal_supply_b2b/src/core/config/storefront_theme_cache.dart';
import 'package:animal_supply_b2b/src/core/widgets/paw_trail_loader.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/features/storefront/storefront_theme_scope.dart';
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

  Widget harness({
    bool enabled = true,
    bool disableAnimations = false,
    ThemeData? theme,
  }) {
    return ProviderScope(
      overrides: [
        shopBrandingProvider.overrideWithValue(
          const ShopBranding(shopName: 'مؤسسة النور للأعلاف'),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: AppLoadingIntro(
              enabled: enabled,
              child: const Scaffold(body: Text('محتوى التطبيق')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('intro shows paw trail and shop name, then reveals the app',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    final intro = find.byKey(const Key('app-loading-intro'));
    expect(intro, findsOneWidget);
    expect(find.byType(PawTrail), findsOneWidget);
    expect(find.text('مؤسسة النور للأعلاف'), findsOneWidget);
    expect(find.text('محتوى التطبيق'), findsOneWidget);
    expect(Directionality.of(tester.element(intro)), TextDirection.rtl);

    await tester.pumpAndSettle();
    expect(intro, findsNothing);
    expect(find.byType(PawTrail), findsNothing);
    expect(find.text('محتوى التطبيق'), findsOneWidget);
  });

  testWidgets('intro colors follow the published storefront theme',
      (tester) async {
    const custom = StorefrontConfig(
      theme: StorefrontThemeConfig(
        primaryColor: Color(0xff7b2cbf),
        backgroundColor: Color(0xfffff1e6),
        textColor: Color(0xff22223b),
      ),
    );
    final theme = storefrontThemeData(custom);
    await tester.pumpWidget(harness(theme: theme));
    await tester.pump();

    final trail = tester.widget<PawTrail>(find.byType(PawTrail));
    expect(trail.color, theme.colorScheme.primary);
    final box = tester.widget<ColoredBox>(
      find.byKey(const Key('app-loading-intro')),
    );
    expect(box.color, theme.scaffoldBackgroundColor);
    await tester.pumpAndSettle();
  });

  test('theme cache survives a cold start and feeds the fallback config',
      () async {
    const purple = Color(0xff7b2cbf);
    StorefrontThemeCache.resetForTest();
    expect(
      StorefrontThemeCache.fallbackConfig().theme.primaryColor,
      StorefrontDefaults.bundled.theme.primaryColor,
    );

    StorefrontThemeCache.remember(
      const StorefrontThemeConfig(primaryColor: purple),
    );
    await Future<void>.delayed(Duration.zero);
    StorefrontThemeCache.resetForTest();
    await StorefrontThemeCache.load();

    expect(StorefrontThemeCache.current?.primaryColor, purple);
    expect(StorefrontThemeCache.fallbackConfig().theme.primaryColor, purple);
    StorefrontThemeCache.resetForTest();
  });

  testWidgets('intro is skipped when disabled', (tester) async {
    await tester.pumpWidget(harness(enabled: false));
    await tester.pump();
    expect(find.byKey(const Key('app-loading-intro')), findsNothing);
    expect(find.text('محتوى التطبيق'), findsOneWidget);
  });

  testWidgets('intro is skipped when the device reduces motion',
      (tester) async {
    await tester.pumpWidget(harness(disableAnimations: true));
    await tester.pump();
    expect(find.byKey(const Key('app-loading-intro')), findsNothing);
    expect(find.text('محتوى التطبيق'), findsOneWidget);
  });
}
