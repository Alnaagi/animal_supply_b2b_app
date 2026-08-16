import 'package:animal_supply_b2b/src/core/refresh/screen_reload.dart';
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

  test('requestScreenReload increments the shared tick', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(screenReloadTickProvider), 0);
    container.read(screenReloadTickProvider.notifier).state++;
    expect(container.read(screenReloadTickProvider), 1);
  });

  testWidgets('disabling a customer updates the list without the refresh icon',
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

    expect(find.byIcon(Icons.store), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('admin-customer-menu-customer-status')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-customer-toggle-customer-status')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'إيقاف الحساب'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.block), findsOneWidget);
    expect(find.byIcon(Icons.store), findsNothing);
  });
}
