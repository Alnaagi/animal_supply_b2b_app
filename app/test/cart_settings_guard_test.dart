import 'dart:async';

import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_screen.dart';
import 'package:animal_supply_b2b/src/features/cart/checkout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const item = CartItem(
    product: Product(
      id: 'product-1',
      nameAr: 'علف اختبار',
      sku: 'FEED-1',
      category: 'أعلاف',
      animalType: 'مواشي',
      brand: 'المورد',
      unitSize: '25 كجم',
      basePrice: 100,
      stockQuantity: 50,
      minOrderQty: 1,
    ),
    quantity: 1,
  );

  testWidgets('cart blocks checkout while order settings are loading',
      (tester) async {
    final pending = Completer<AppSettingsData>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartControllerProvider.overrideWith(
            (ref) => CartController(
              ref,
              ownerProfileId: null,
              initialItems: const [item],
            ),
          ),
          appSettingsProvider.overrideWith((ref) => pending.future),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CartScreen()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('جارٍ تحميل رسوم وحد الطلب...'), findsOneWidget);
    final checkoutButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'متابعة تأكيد الطلب'),
    );
    expect(checkoutButton.onPressed, isNull);
  });

  testWidgets('cart shows a retryable Arabic settings error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartControllerProvider.overrideWith(
            (ref) => CartController(
              ref,
              ownerProfileId: null,
              initialItems: const [item],
            ),
          ),
          appSettingsProvider.overrideWith(
            (ref) => Future<AppSettingsData>.error(
              StateError('settings unavailable'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CartScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل رسوم وحد الطلب'), findsOneWidget);
    expect(find.byTooltip('إعادة تحميل إعدادات الطلب'), findsOneWidget);
  });

  testWidgets('maintenance mode blocks cart checkout with an Arabic notice',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartControllerProvider.overrideWith(
            (ref) => CartController(
              ref,
              ownerProfileId: null,
              initialItems: const [item],
            ),
          ),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(maintenanceMode: true),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: CartScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cart-maintenance-notice')), findsOneWidget);
    expect(find.text('الطلبات متوقفة مؤقتاً للصيانة'), findsOneWidget);
    final checkoutButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'متابعة تأكيد الطلب'),
    );
    expect(checkoutButton.onPressed, isNull);
  });

  testWidgets('maintenance mode blocks checkout submission locally',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _CustomerAuthController(),
          ),
          cartControllerProvider.overrideWith(
            (ref) => CartController(
              ref,
              ownerProfileId: 'profile-1',
              initialItems: const [item],
            ),
          ),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(maintenanceMode: true),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: CheckoutScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('checkout-maintenance-notice')),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('checkout-submit-button')),
    );
    expect(submitButton.onPressed, isNull);
  });

  testWidgets('checkout groups editable fields above order review',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _CustomerAuthController(),
          ),
          cartControllerProvider.overrideWith(
            (ref) => CartController(
              ref,
              ownerProfileId: 'profile-1',
              initialItems: const [item],
            ),
          ),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: CheckoutScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('بيانات التسليم'), findsOneWidget);
    expect(find.text('مراجعة الطلب'), findsOneWidget);
    expect(find.byKey(const Key('checkout-editable-fields')), findsOneWidget);
    expect(find.byKey(const Key('checkout-delivery-address')), findsOneWidget);
    expect(find.byKey(const Key('checkout-customer-note')), findsOneWidget);
    expect(find.text('علف اختبار'), findsOneWidget);

    final editableY =
        tester.getTopLeft(find.byKey(const Key('checkout-editable-fields'))).dy;
    final addressY = tester
        .getTopLeft(find.byKey(const Key('checkout-delivery-address')))
        .dy;
    final noteY =
        tester.getTopLeft(find.byKey(const Key('checkout-customer-note'))).dy;
    final productY = tester.getTopLeft(find.text('علف اختبار')).dy;

    expect(editableY, lessThan(productY));
    expect(addressY, lessThan(noteY));
    expect(noteY, lessThan(productY));

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkout-totals-card')), findsOneWidget);
    expect(find.text('الإجمالي التقديري'), findsOneWidget);
    expect(find.text('إرسال الطلب'), findsOneWidget);

    final totalsY =
        tester.getTopLeft(find.byKey(const Key('checkout-totals-card'))).dy;
    final submitY =
        tester.getTopLeft(find.byKey(const Key('checkout-submit-button'))).dy;
    expect(totalsY, lessThan(submitY));
  });
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
        accountStatus: 'active',
      ),
    );
  }
}
