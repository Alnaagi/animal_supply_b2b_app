import 'package:animal_supply_b2b/src/core/support/customer_last_active_copy.dart';
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

  test('admin customer rows prefer the staff last-active computed timestamp',
      () {
    final recent = DateTime.utc(2026, 8, 18, 9, 15);
    final older = DateTime.utc(2026, 8, 17, 11, 0);
    final customer = BusinessCustomer.fromSupabase({
      'id': '11111111-1111-4111-8111-111111111111',
      'profile_id': '22222222-2222-4222-8222-222222222222',
      'business_name': 'متجر طرابلس',
      'contact_person': 'سالم',
      'phone': '+218910000001',
      'city': 'طرابلس',
      'area': 'الأندلس',
      'address': '',
      'discount_percent': 0,
      'account_status': 'active',
      'credit_limit': 0,
      'outstanding_balance': 0,
      'profiles': {
        'username': 'tripoli-shop',
        'last_active_at': recent.toIso8601String(),
        'last_seen_at': older.toIso8601String(),
        'last_login_at': older.toIso8601String(),
      },
    });

    expect(customer.lastActiveAt, recent);
    expect(customer.username, 'tripoli-shop');
  });

  test(
      'admin customer rows fall back to last_seen_at when last-active is absent',
      () {
    final seen = DateTime.utc(2026, 8, 18, 8, 0);
    final customer = BusinessCustomer.fromSupabase({
      'id': '11111111-1111-4111-8111-111111111111',
      'profile_id': '22222222-2222-4222-8222-222222222222',
      'business_name': 'متجر بنغازي',
      'contact_person': 'أحمد',
      'phone': '+218920000002',
      'city': 'بنغازي',
      'area': '',
      'address': '',
      'discount_percent': 0,
      'account_status': 'active',
      'credit_limit': 0,
      'outstanding_balance': 0,
      'profiles': {
        'username': 'benghazi-shop',
        'last_seen_at': seen.toIso8601String(),
      },
    });

    expect(customer.lastActiveAt, seen);
  });

  testWidgets(
    'customer cards show last active time and a never-signed-in fallback',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final lastActive = DateTime.now().subtract(const Duration(minutes: 5));
      final yesterdayAfternoon =
          DateTime.now().subtract(const Duration(days: 1)).copyWith(
                hour: 14,
                minute: 52,
                second: 0,
                millisecond: 0,
                microsecond: 0,
              );
      final repository = AdminRepository(
        demoCustomers: [
          BusinessCustomer(
            id: 'customer-active',
            businessName: 'متجر النشاط',
            username: 'active-shop',
            contactPerson: 'طارق',
            phone: '+218910000111',
            city: 'طرابلس',
            area: 'صلاح الدين',
            lastActiveAt: lastActive,
          ),
          BusinessCustomer(
            id: 'customer-yesterday',
            businessName: 'متجر الأمس',
            username: 'yesterday-shop',
            contactPerson: 'محمد',
            phone: '+218910000333',
            city: 'طرابلس',
            area: 'حي الأندلس',
            lastActiveAt: yesterdayAfternoon,
          ),
          const BusinessCustomer(
            id: 'customer-never',
            businessName: 'متجر جديد',
            username: 'new-shop',
            contactPerson: 'سالم',
            phone: '+218910000222',
            city: 'طرابلس',
            area: 'حي الأندلس',
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

      final activeLine = find.byKey(
        const ValueKey('admin-customer-last-active-customer-active'),
      );
      final yesterdayLine = find.byKey(
        const ValueKey('admin-customer-last-active-customer-yesterday'),
      );
      final neverLine = find.byKey(
        const ValueKey('admin-customer-last-active-customer-never'),
      );

      expect(activeLine, findsOneWidget);
      expect(yesterdayLine, findsOneWidget);
      expect(neverLine, findsOneWidget);
      expect(
        tester.widget<Text>(activeLine).data,
        formatCustomerLastActiveAr(lastActive),
      );
      expect(
        tester.widget<Text>(yesterdayLine).data,
        formatCustomerLastActiveAr(yesterdayAfternoon),
      );
      expect(
        tester.widget<Text>(neverLine).data,
        customerLastActiveNeverAr,
      );
      expect(find.textContaining('آخر نشاط: منذ'), findsOneWidget);
      expect(find.textContaining('أمس • 2:52 مساءً'), findsOneWidget);
      expect(find.textContaining('14:52'), findsNothing);
      expect(find.text(customerLastActiveNeverAr), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('admin-customer-card-customer-yesterday'),
          ),
          matching: find.byIcon(Icons.schedule),
        ),
        findsOneWidget,
      );
      expect(
        Directionality.of(tester.element(activeLine)),
        TextDirection.rtl,
      );

      final filters = find.byKey(const Key('admin-customers-status-filters'));
      expect(filters, findsOneWidget);
      expect(
        find.descendant(of: filters, matching: find.text('إنشاء عميل')),
        findsNothing,
      );
      expect(find.widgetWithText(FilledButton, 'إنشاء عميل'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'الكل'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'مؤرشف'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );
}
