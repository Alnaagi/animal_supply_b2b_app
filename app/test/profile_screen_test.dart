import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('customer profile hides discount, credit, and balance cards',
      (tester) async {
    tester.view.physicalSize = const Size(416, 838);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _CustomerAuth()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: ProfileScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('متجر الاختبار'), findsWidgets);
    expect(find.text('حساب جملة نشط'), findsOneWidget);
    expect(find.byKey(const Key('customer-profile-hero')), findsOneWidget);
    expect(find.byKey(const Key('customer-profile-details')), findsOneWidget);
    expect(
      find.byKey(const Key('customer-profile-info-business-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customer-profile-info-contact-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customer-profile-info-phone')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customer-profile-info-location')),
      findsOneWidget,
    );
    expect(find.text('خصم جميع المنتجات'), findsNothing);
    expect(find.text('حد الائتمان'), findsNothing);
    expect(find.text('الرصيد المستحق'), findsNothing);
    expect(find.text('العروض'), findsNothing);
    expect(find.text('تصفح كل المنتجات المخفضة'), findsNothing);

    await tester.drag(
      find.byKey(const Key('customer-profile-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('customer-profile-services')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('customer-profile-sign-out')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets(
        'preserves 2x2 grid grouping for account details on small mobile (${width.toInt()}px)',
        (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((ref) => _CustomerAuth()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: ProfileScreen()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final businessTile = find.byKey(const Key('customer-profile-info-business-name'));
      final contactTile = find.byKey(const Key('customer-profile-info-contact-name'));
      final phoneTile = find.byKey(const Key('customer-profile-info-phone'));
      final locationTile = find.byKey(const Key('customer-profile-info-location'));

      expect(businessTile, findsOneWidget);
      expect(contactTile, findsOneWidget);
      expect(phoneTile, findsOneWidget);
      expect(locationTile, findsOneWidget);

      final businessTop = tester.getTopLeft(businessTile).dy;
      final contactTop = tester.getTopLeft(contactTile).dy;
      final phoneTop = tester.getTopLeft(phoneTile).dy;
      final locationTop = tester.getTopLeft(locationTile).dy;

      // Row 1 items are side-by-side (same top y-coordinate)
      expect(businessTop, equals(contactTop));
      // Row 2 items are side-by-side (same top y-coordinate)
      expect(phoneTop, equals(locationTop));
      // Row 2 is below Row 1
      expect(phoneTop, greaterThan(businessTop));

      expect(tester.takeException(), isNull);
    });
  }
}

class _CustomerAuth extends AuthController {
  _CustomerAuth() {
    state = const AuthState(
      user: AppUser(
        id: 'profile-1',
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: 'customer-1',
        fullName: 'محمد الاختبار',
        phone: '0912233444',
        city: 'طرابلس',
        area: 'صلاح الدين',
      ),
    );
  }
}
