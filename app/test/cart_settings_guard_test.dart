import 'dart:async';

import 'package:animal_supply_b2b/src/core/widgets/product_image_placeholder.dart';
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

  testWidgets('checkout uses compact address picker and product images',
      (tester) async {
    tester.view.physicalSize = const Size(338, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    expect(find.text('بيانات التسليم'), findsNothing);
    expect(find.text('مراجعة الطلب'), findsNothing);
    expect(find.byKey(const Key('checkout-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('checkout-desktop-layout')), findsNothing);
    expect(find.byKey(const Key('checkout-editable-fields')), findsOneWidget);
    expect(find.byKey(const Key('checkout-address-selector')), findsOneWidget);
    expect(find.byKey(const Key('checkout-delivery-address')), findsNothing);
    expect(find.byKey(const Key('checkout-customer-note')), findsOneWidget);
    expect(
      find.byKey(const Key('checkout-product-image-product-1')),
      findsOneWidget,
    );
    expect(find.text('طرابلس - حي الأندلس - شارع الاختبار'), findsOneWidget);
    expect(find.text('علف اختبار'), findsOneWidget);

    final editableY =
        tester.getTopLeft(find.byKey(const Key('checkout-editable-fields'))).dy;
    final addressY = tester
        .getTopLeft(find.byKey(const Key('checkout-address-selector')))
        .dy;
    final noteY =
        tester.getTopLeft(find.byKey(const Key('checkout-customer-note'))).dy;
    final productY = tester.getTopLeft(find.text('علف اختبار')).dy;

    expect(editableY, lessThan(productY));
    expect(addressY, lessThan(noteY));
    expect(noteY, lessThan(productY));

    final noteField = tester.widget<TextField>(
      find.byKey(const Key('checkout-customer-note')),
    );
    expect(noteField.decoration?.filled, isTrue);
    expect(
      noteField.decoration?.fillColor,
      Theme.of(
        tester.element(find.byKey(const Key('checkout-customer-note'))),
      ).colorScheme.secondaryContainer,
    );

    await tester.tap(find.byKey(const Key('checkout-address-selector')));
    await tester.pumpAndSettle();
    expect(find.text('اختر عنوان التسليم'), findsOneWidget);
    expect(
      find.byKey(const Key('checkout-address-registered-option')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('checkout-address-custom-option')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('checkout-delivery-address')),
      'مصراتة - شارع طرابلس',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('checkout-address-apply')));
    await tester.tap(find.byKey(const Key('checkout-address-apply')));
    await tester.pumpAndSettle();
    expect(find.text('مصراتة - شارع طرابلس'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkout-totals-card')), findsOneWidget);
    expect(find.text('الإجمالي التقديري'), findsOneWidget);
    expect(find.text('الإجمالي الفرعي التقديري'), findsNothing);
    expect(find.text('إرسال الطلب'), findsOneWidget);

    final totalsY =
        tester.getTopLeft(find.byKey(const Key('checkout-totals-card'))).dy;
    final submitY =
        tester.getTopLeft(find.byKey(const Key('checkout-submit-button'))).dy;
    expect(totalsY, lessThan(submitY));
  });

  testWidgets('cart uses capped desktop columns with a persistent summary',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
            (ref) async => const AppSettingsData(
              deliveryFee: 12,
              handlingFee: 3,
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

    expect(find.byKey(const Key('cart-desktop-layout')), findsOneWidget);
    expect(find.byKey(const Key('cart-mobile-layout')), findsNothing);
    expect(find.byKey(const Key('cart-desktop-items')), findsOneWidget);
    expect(find.byKey(const Key('cart-desktop-summary')), findsOneWidget);

    final layout = tester.getRect(find.byKey(const Key('cart-desktop-layout')));
    final itemsRect =
        tester.getRect(find.byKey(const Key('cart-desktop-items')));
    final summaryRect =
        tester.getRect(find.byKey(const Key('cart-desktop-summary')));
    expect(layout.width, lessThanOrEqualTo(1280));
    expect(summaryRect.right, lessThan(itemsRect.left));
    expect(summaryRect.width, closeTo(360, 1));
    expect(find.byKey(const Key('cart-summary-total')), findsOneWidget);
    expect(find.text('الإجمالي الفرعي'), findsOneWidget);

    final thumbnail = tester.widget<ProductImagePlaceholder>(
      find.byKey(const Key('cart-product-image-product-1')),
    );
    expect(thumbnail.expand, isTrue);
    expect(thumbnail.fit, BoxFit.contain);

    expect(
      tester.getSize(find.byKey(const Key('cart-remove-button'))),
      const Size.square(44),
    );
    expect(
      tester.getSize(find.byTooltip('تقليل الكمية')),
      const Size.square(44),
    );
    expect(
      tester.getSize(find.byTooltip('زيادة الكمية')),
      const Size.square(44),
    );
    expect(
      tester.getSize(find.byKey(const Key('cart-checkout-button'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkout uses capped desktop review and sticky summary columns',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
            (ref) async => const AppSettingsData(
              deliveryFee: 12,
              handlingFee: 3,
            ),
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

    expect(find.byKey(const Key('checkout-desktop-layout')), findsOneWidget);
    expect(find.byKey(const Key('checkout-mobile-layout')), findsNothing);
    expect(find.byKey(const Key('checkout-desktop-main')), findsOneWidget);
    expect(find.byKey(const Key('checkout-desktop-summary')), findsOneWidget);
    expect(find.byKey(const Key('checkout-address-selector')), findsOneWidget);
    expect(find.byKey(const Key('checkout-customer-note')), findsOneWidget);
    expect(find.byKey(const Key('checkout-products-card')), findsOneWidget);

    final layout =
        tester.getRect(find.byKey(const Key('checkout-desktop-layout')));
    final main = tester.getRect(find.byKey(const Key('checkout-desktop-main')));
    final summary =
        tester.getRect(find.byKey(const Key('checkout-desktop-summary')));
    expect(layout.width, lessThanOrEqualTo(1280));
    expect(summary.right, lessThan(main.left));
    expect(summary.width, closeTo(380, 1));
    expect(find.text('ملخص الطلب'), findsOneWidget);
    expect(find.text('الإجمالي الفرعي'), findsOneWidget);

    final thumbnail = tester.widget<ProductImagePlaceholder>(
      find.byKey(const Key('checkout-product-image-product-1')),
    );
    expect(thumbnail.expand, isTrue);
    expect(thumbnail.fit, BoxFit.contain);
    expect(
      tester.getSize(find.byKey(const Key('checkout-product-image-product-1'))),
      const Size.square(64),
    );
    expect(
      tester.getSize(find.byKey(const Key('checkout-submit-button'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
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
        city: 'طرابلس',
        area: 'حي الأندلس',
        address: 'شارع الاختبار',
        accountStatus: 'active',
      ),
    );
  }
}
