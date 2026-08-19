import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_customers/admin_customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
            phoneIsWhatsapp: false,
            city: 'طرابلس',
            area: 'الاندلس',
            address: 'شارع السوق',
            discountPercent: 5,
            creditLimit: 2500,
            outstandingBalance: 420,
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
      expect(find.text('اسم المتجر'), findsWidgets);
      expect(find.text('رقم الهاتف (واتساب)'), findsWidgets);
      expect(find.text('هذا الرقم لواتساب (مفضّل)'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('خصم العميل'), findsWidgets);
      expect(find.text('الحالة'), findsWidgets);
      expect(find.text('نشط'), findsWidgets);
      expect(find.text('عنوان وائتمان مرجعي'), findsNothing);
      expect(find.text('العنوان'), findsNothing);
      expect(find.text('حد الائتمان المرجعي'), findsNothing);
      expect(find.text('الرصيد المستحق المسجل يدوياً'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('admin-customer-form-save')));
      await tester.pumpAndSettle();

      expect(find.text('تعديل عميل'), findsNothing);
      expect(passwordCalls, 0);
      final saved = (await repository.listCustomers()).single;
      expect(saved.phoneIsWhatsapp, isTrue);
      expect(saved.address, 'شارع السوق');
      expect(saved.creditLimit, 2500);
      expect(saved.outstandingBalance, 420);
    },
  );

  testWidgets('mismatched passwords stay in the dialog with Arabic guidance',
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
      'test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-customer-password-confirm-field')),
      'other',
    );
    await tester.tap(find.byKey(const ValueKey('admin-customer-form-save')));
    await tester.pump();

    expect(find.text('تعديل عميل'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(
              const ValueKey('admin-customer-password-confirm-field'),
            ),
          )
          .decoration
          ?.errorText,
      contains('غير متطابقتين'),
    );
  });

  testWidgets(
    'invalid username shows error on the field and keeps the create dialog open',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 900));
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

      await tester.enterText(
        find.byKey(const ValueKey('admin-customer-business-field')),
        'متجر محمد',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-customer-contact-field')),
        'محمد علي',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-customer-phone-field')),
        '+218910000088',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-customer-username-field')),
        'محمد',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-customer-form-save')),
      );
      await tester.tap(find.byKey(const ValueKey('admin-customer-form-save')));
      await tester.pumpAndSettle();

      expect(find.text('إنشاء عميل'), findsWidgets);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('admin-customer-username-field')),
            )
            .decoration
            ?.errorText,
        contains('لاتينياً'),
      );
      expect(
        find.byKey(const ValueKey('admin-customer-form-validation')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'empty required fields show errors under each box',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 900));
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

      await tester.enterText(
        find.byKey(const ValueKey('admin-customer-city-field')),
        '',
      );
      await tester.tap(find.byKey(const ValueKey('admin-customer-form-save')));
      await tester.pumpAndSettle();

      expect(find.text('إنشاء عميل'), findsWidgets);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('admin-customer-business-field')),
            )
            .decoration
            ?.errorText,
        'أدخل اسم المتجر.',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('admin-customer-contact-field')),
            )
            .decoration
            ?.errorText,
        'أدخل اسم الشخص المسؤول.',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('admin-customer-phone-field')),
            )
            .decoration
            ?.errorText,
        'أدخل رقم الهاتف (واتساب).',
      );
    },
  );

  testWidgets('short matching password test is accepted on edit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var passwordCalls = 0;
    String? sentPassword;
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
        ),
      ],
      edgeFunctionInvoker: (functionName, body) async {
        if (functionName == 'admin-reset-customer-password') {
          passwordCalls += 1;
          sentPassword = body['password']?.toString();
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

    await tester.enterText(
      find.byKey(const ValueKey('admin-customer-password-field')),
      'test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-customer-password-confirm-field')),
      'test',
    );
    await tester.tap(find.byKey(const ValueKey('admin-customer-form-save')));
    await tester.pumpAndSettle();

    expect(find.text('تعديل عميل'), findsNothing);
    expect(passwordCalls, 1);
    expect(sentPassword, 'test');
    expect(find.text('حساب تجريبي محلي'), findsOneWidget);
    expect(find.byKey(const Key('admin-invite-preview')), findsOneWidget);
    expect(find.textContaining('كلمة المرور: test'), findsWidgets);
  });

  testWidgets(
    'create customer form groups fields and uses phone digits as username',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = AdminRepository(demoCustomers: const []);

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

      await tester.tap(find.widgetWithText(FilledButton, 'إنشاء عميل'));
      await tester.pumpAndSettle();

      expect(find.text('إنشاء عميل'), findsWidgets);
      expect(find.text('اسم المتجر'), findsWidgets);
      expect(find.text('الهوية'), findsOneWidget);
      expect(find.text('التواصل'), findsOneWidget);
      expect(find.text('بيانات الدخول'), findsOneWidget);
      expect(find.text('الخصم والحالة'), findsOneWidget);
      expect(
        find.textContaining('أرقام الهاتف كاسم مستخدم'),
        findsWidgets,
      );

      await tester.enterText(
        find.byKey(const ValueKey('admin-customer-business-field')),
        'متجر الهاتف',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-customer-contact-field')),
        'سالم علي',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-customer-phone-field')),
        '+218910000099',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('admin-customer-username-field')),
            )
            .controller
            ?.text,
        isEmpty,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('admin-customer-form-save')),
      );
      await tester.tap(find.byKey(const ValueKey('admin-customer-form-save')));
      await tester.pumpAndSettle();

      final created = (await repository.listCustomers()).single;
      expect(created.businessName, 'متجر الهاتف');
      expect(created.username, '218910000099');
      expect(created.phone, '+218910000099');
    },
  );
}
