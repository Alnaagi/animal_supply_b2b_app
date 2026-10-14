import 'dart:convert';

import 'package:animal_supply_b2b/src/core/config/shop_branding.dart';
import 'package:animal_supply_b2b/src/core/config/shop_branding_cache.dart';
import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/shop_brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ShopBrandingCache.resetForTest();
  });

  group('ShopBrandLogo', () {
    test('corner radius scales within 8–12 band', () {
      expect(ShopBrandLogo.cornerRadiusFor(28), 8.0);
      expect(ShopBrandLogo.cornerRadiusFor(40), closeTo(8.8, 0.01));
      expect(ShopBrandLogo.cornerRadiusFor(56), 12.0);
      expect(ShopBrandLogo.cornerRadiusFor(120), 12.0);
    });

    testWidgets('custom logo bytes use rounded-rect clip, not circle',
        (tester) async {
      const size = 42.0;
      await tester.pumpWidget(
        _testApp(
          child: ShopBrandLogo(
            logoBytes: base64Decode(_transparentPng),
            size: size,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ClipOval), findsNothing);
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius,
          BorderRadius.circular(ShopBrandLogo.cornerRadiusFor(size)));
      expect(clip.clipBehavior, Clip.antiAlias);
    });

    testWidgets('reads logo from ShopBrandingCache when logoUrl is omitted',
        (tester) async {
      ShopBrandingCache.syncFromRemote(
        const ShopBranding(
          shopName: 'متجر الاختبار',
          logoUrl: 'https://cdn.example.com/logo.png',
        ),
      );

      await tester.pumpWidget(
        _testApp(
          child: const ShopBrandLogo(size: 48),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('missing logo keeps circular fallback badge', (tester) async {
      const primary = Color(0xff7357c8);
      await tester.pumpWidget(
        _testApp(
          primary: primary,
          child: const ShopBrandLogo(
            size: 42,
            backgroundColor: primary,
          ),
        ),
      );

      expect(find.byType(ClipOval), findsNothing);
      expect(find.byType(ClipRRect), findsNothing);
      expect(find.byIcon(Icons.pets), findsOneWidget);
      final badge = tester.widget<DecoratedBox>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(
        (badge.decoration as BoxDecoration).color,
        primary,
      );
    });
  });
}

Widget _testApp({
  required Widget child,
  Color primary = AppTheme.green,
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
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

const _transparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
