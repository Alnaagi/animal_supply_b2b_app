import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_customers/admin_customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'admin edits a customer-wide discount with localized Arabic input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(646, 838));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = AdminRepository(
        demoCustomers: const [
          BusinessCustomer(
            id: 'customer-discount',
            businessName: 'متجر الاختبار',
            username: 'discount-shop',
            contactPerson: 'سالم علي',
            phone: '+218910000009',
            city: 'طرابلس',
            area: 'الأندلس',
            discountPercent: 5,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: AdminCustomersScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('خصم 5%'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('admin-customer-card-customer-discount')),
      );
      await tester.pumpAndSettle();

      final discountField =
          find.byKey(const ValueKey('admin-customer-discount-field'));
      expect(discountField, findsOneWidget);
      expect(find.text('مجموعة الأسعار'), findsNothing);
      expect(
        Directionality.of(tester.element(discountField)),
        TextDirection.rtl,
      );
      final fieldWidget = tester.widget<TextField>(discountField);
      expect(fieldWidget.textDirection, TextDirection.ltr);
      expect(fieldWidget.decoration?.suffixText, '%');

      await tester.enterText(discountField, '100');
      await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('admin-customer-form-validation')),
        findsOneWidget,
      );
      expect(find.textContaining('0 و99.99'), findsOneWidget);
      expect(find.text('تعديل عميل'), findsOneWidget);

      await tester.enterText(discountField, '١٢٫٥');
      await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
      await tester.pumpAndSettle();

      expect(find.textContaining('خصم 12.5%'), findsOneWidget);
      expect(find.text('تعديل عميل'), findsNothing);
      expect(
        (await repository.listCustomers()).single.discountPercent,
        12.5,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new customer discount defaults to zero without price groups',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(646, 838));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            AdminRepository(demoCustomers: const []),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AdminCustomersScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'إنشاء عميل'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('admin-customer-discount-field')),
    );
    expect(field.controller?.text, '0');
    expect(find.text('مجموعة الأسعار'), findsNothing);
    expect(find.text('إنشاء عميل'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
