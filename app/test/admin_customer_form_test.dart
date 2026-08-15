import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_customers/admin_customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'edit customer form emphasizes WhatsApp phone and keeps empty password unchanged',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var passwordCalls = 0;
      final repository = AdminRepository(
        demoCustomers: const [
          BusinessCustomer(
            id: 'customer-form',
            businessName: 'متجر النموذج',
            username: 'form-shop',
            contactPerson: 'أحمد سالم',
            phone: '+218910000010',
            city: 'طرابلس',
            area: 'الاندلس',
            discountPercent: 5,
          ),
        ],
        edgeFunctionInvoker: (functionName, body) async {
          if (functionName == 'admin-reset-customer-password') {
            passwordCalls += 1;
          }
          return {
            'ok': true,
            'data': {'password_updated': true},
          };
        },
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

      await tester.tap(
        find.byKey(const ValueKey('admin-customer-card-customer-form')),
      );
      await tester.pumpAndSettle();

      expect(find.text('تعديل عميل'), findsOneWidget);
      expect(find.text('الشخص المسؤول'), findsWidgets);
      expect(find.text('اسم النشاط التجاري'), findsWidgets);
      expect(find.text('هذا الرقم لواتساب (مفضّل)'), findsOneWidget);
      expect(find.text('خصم العميل'), findsWidgets);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('admin-customer-whatsapp-preferred')),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('تعديل عميل'), findsNothing);
      expect(passwordCalls, 0);
      expect(
        (await repository.listCustomers()).single.phoneIsWhatsapp,
        isTrue,
      );
    },
  );

  testWidgets('weak password on edit stays in the dialog with Arabic guidance',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            AdminRepository(
              demoCustomers: const [
                BusinessCustomer(
                  id: 'customer-form',
                  businessName: 'متجر النموذج',
                  username: 'form-shop',
                  contactPerson: 'أحمد سالم',
                  phone: '+218910000010',
                  city: 'طرابلس',
                  area: 'الاندلس',
                ),
              ],
            ),
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

    await tester.tap(
      find.byKey(const ValueKey('admin-customer-card-customer-form')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('admin-customer-password-field')),
      'weak',
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-customer-password-confirm-field')),
      'weak',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pump();

    expect(find.text('تعديل عميل'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-customer-form-validation')),
      findsOneWidget,
    );
    expect(find.textContaining('10 أحرف'), findsOneWidget);
  });
}
