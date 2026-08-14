import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_customers/admin_customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('demo customer pages preserve ordering and full-list callers', () async {
    final repository = AdminRepository(demoCustomers: _customers(120));

    final first = await repository.listCustomersPage();
    final second = await repository.listCustomersPage(offset: first.nextOffset);
    final third = await repository.listCustomersPage(offset: second.nextOffset);

    expect(first.customers, hasLength(50));
    expect(first.customers.first.id, 'customer-000');
    expect(first.customers.last.id, 'customer-049');
    expect(first.hasMore, isTrue);
    expect(first.nextOffset, 50);

    expect(second.customers, hasLength(50));
    expect(second.customers.first.id, 'customer-050');
    expect(second.customers.last.id, 'customer-099');
    expect(second.hasMore, isTrue);
    expect(second.nextOffset, 100);

    expect(third.customers, hasLength(20));
    expect(third.customers.first.id, 'customer-100');
    expect(third.customers.last.id, 'customer-119');
    expect(third.hasMore, isFalse);
    expect(third.nextOffset, 120);

    final activeCustomers = await repository.listCustomers(status: 'active');
    expect(activeCustomers, hasLength(80));
  });

  test('demo pagination applies status and search before slicing', () async {
    final repository = AdminRepository(demoCustomers: _customers(120));

    final suspended = await repository.listCustomersPage(
      status: 'suspended',
    );
    final phoneMatch = await repository.listCustomersPage(
      query: '+218910000119',
    );

    expect(suspended.customers, hasLength(40));
    expect(
      suspended.customers.every(
        (customer) => customer.accountStatus == 'suspended',
      ),
      isTrue,
    );
    expect(suspended.hasMore, isFalse);
    expect(phoneMatch.customers.single.id, 'customer-119');
    expect(phoneMatch.hasMore, isFalse);
  });

  test('server customer search filter accepts bounded Arabic and phone input',
      () {
    const query = 'شركة طرابلس 218-91';

    expect(
      AdminRepository.canUseServerSideCustomerSearch(query),
      isTrue,
    );
    expect(
      AdminRepository.customerSearchFilterForServer(query),
      allOf(
        contains('business_name.ilike.*$query*'),
        contains('contact_person.ilike.*$query*'),
        contains('phone.ilike.*$query*'),
        contains('city.ilike.*$query*'),
        contains('area.ilike.*$query*'),
      ),
    );
  });

  test('server customer search rejects PostgREST control syntax', () {
    for (final query in [
      'shop),account_status.eq.active',
      'shop*',
      'shop%',
      'shop\nactive',
    ]) {
      expect(
        AdminRepository.canUseServerSideCustomerSearch(query),
        isFalse,
      );
      expect(
        () => AdminRepository.customerSearchFilterForServer(query),
        throwsArgumentError,
      );
    }
  });

  test('customer page parsing fails closed on malformed server responses', () {
    expect(
      () => AdminRepository.customerPageFromResponse(
        const {'id': 'not-a-list'},
        offset: 0,
        limit: 50,
      ),
      throwsStateError,
    );
    expect(
      () => AdminRepository.customerPageFromResponse(
        [
          _customerRow(1),
          _customerRow(1),
        ],
        offset: 0,
        limit: 50,
      ),
      throwsStateError,
    );
    for (final discount in ['ten', -0.01, 100, 12.345]) {
      expect(
        () => AdminRepository.customerPageFromResponse(
          [
            {
              ..._customerRow(1),
              'discount_percent': discount,
            },
          ],
          offset: 0,
          limit: 50,
        ),
        throwsStateError,
      );
    }
    expect(
      () => AdminRepository.customerPageFromResponse(
        [
          {
            ..._customerRow(1),
            'business_name': '',
          },
        ],
        offset: 0,
        limit: 50,
      ),
      throwsStateError,
    );
    expect(
      () => AdminRepository.customerPageFromResponse(
        [
          for (var index = 0; index < 52; index++) _customerRow(index),
        ],
        offset: 0,
        limit: 50,
      ),
      throwsStateError,
    );
  });

  test('customer pagination validates offset, limit, status, and query',
      () async {
    final repository = AdminRepository(demoCustomers: _customers(1));

    await expectLater(
      repository.listCustomersPage(offset: -1),
      throwsArgumentError,
    );
    await expectLater(
      repository.listCustomersPage(limit: 0),
      throwsArgumentError,
    );
    await expectLater(
      repository.listCustomersPage(
        limit: adminCustomersMaximumPageSize + 1,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.listCustomersPage(status: 'owner'),
      throwsArgumentError,
    );
    await expectLater(
      repository.listCustomersPage(
        query: List<String>.filled(121, 'x').join(),
      ),
      throwsArgumentError,
    );
  });

  testWidgets('admin customer screen loads more with Arabic feedback',
      (tester) async {
    final repository = AdminRepository(demoCustomers: _customers(55));

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

    final customerList = find.byKey(const Key('admin-customers-list'));
    await tester.fling(
      customerList,
      const Offset(0, -10000),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('تم عرض 50 من العملاء'), findsOneWidget);
    expect(find.text('تحميل المزيد'), findsOneWidget);

    final loadMore = find.byKey(const Key('admin-customers-load-more'));
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    await tester.fling(
      customerList,
      const Offset(0, -2000),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('تم عرض 55 من العملاء'), findsOneWidget);
    expect(loadMore, findsNothing);
  });
}

List<BusinessCustomer> _customers(int count) {
  return [
    for (var index = 0; index < count; index++)
      BusinessCustomer(
        id: 'customer-${index.toString().padLeft(3, '0')}',
        businessName: 'عميل ${index.toString().padLeft(3, '0')}',
        username: 'customer-$index',
        contactPerson: 'مسؤول $index',
        phone: '+21891${index.toString().padLeft(7, '0')}',
        city: index.isEven ? 'طرابلس' : 'بنغازي',
        area: 'منطقة $index',
        accountStatus: index % 3 == 0 ? 'suspended' : 'active',
      ),
  ];
}

Map<String, dynamic> _customerRow(int index) {
  return {
    'id': '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
    'profile_id':
        '10000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
    'business_name': 'عميل $index',
    'contact_person': 'مسؤول $index',
    'phone': '+218910000000',
    'city': 'طرابلس',
    'area': 'الأندلس',
    'address': '',
    'discount_percent': 12.5,
    'account_status': 'active',
    'credit_limit': 0,
    'outstanding_balance': 0,
    'profiles': {'username': 'customer-$index'},
  };
}
