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

  testWidgets('overflow menu can disable and archive a customer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = AdminRepository(
      demoCustomers: const [
        BusinessCustomer(
          id: 'customer-status',
          businessName: 'متجر الحالة',
          username: 'status-shop',
          contactPerson: 'سالم علي',
          phone: '+218910000010',
          city: 'طرابلس',
          area: 'الاندلس',
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

    await tester.tap(
      find.byKey(const ValueKey('admin-customer-menu-customer-status')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-customer-toggle-customer-status')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('تأكيد إيقاف العميل'), findsOneWidget);
    expect(find.text('تعديل عميل'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'إيقاف الحساب'));
    await tester.pumpAndSettle();

    expect(
      (await repository.listCustomers()).single.accountStatus,
      'suspended',
    );

    await tester.tap(
      find.byKey(const ValueKey('admin-customer-menu-customer-status')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('أرشفة العميل'));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'أرشفة الحساب'));
    await tester.pumpAndSettle();

    expect(
      (await repository.listCustomers()).single.accountStatus,
      'archived',
    );
  });

  testWidgets('failed disable shows the server reason in Arabic',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _FailingCustomerSaveRepository();

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
      find.byKey(const ValueKey('admin-customer-menu-customer-status')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-customer-toggle-customer-status')),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'إيقاف الحساب'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('تعذر حفظ حالة العميل'), findsOneWidget);
    expect(find.textContaining('phone_is_whatsapp'), findsOneWidget);
    expect(
      find.text('تعذر إكمال العملية. تحقق من الاتصال وحاول مجدداً.'),
      findsNothing,
    );
  });
}

class _FailingCustomerSaveRepository extends AdminRepository {
  _FailingCustomerSaveRepository()
      : super(
          demoCustomers: const [
            BusinessCustomer(
              id: 'customer-status',
              businessName: 'متجر الحالة',
              username: 'status-shop',
              contactPerson: 'سالم علي',
              phone: '+218910000010',
              city: 'طرابلس',
              area: 'الاندلس',
            ),
          ],
        );

  @override
  Future<BusinessCustomer> saveCustomer(BusinessCustomer customer) {
    throw const AdminRemoteException(
      code: 'CUSTOMER_UPDATE_FAILED',
      message: 'column phone_is_whatsapp does not exist',
    );
  }
}
