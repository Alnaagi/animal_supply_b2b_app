import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const customer = BusinessCustomer(
    id: '11111111-1111-4111-8111-111111111111',
    profileId: '22222222-2222-4222-8222-222222222222',
    businessName: 'شركة طرابلس للحيوانات',
    username: 'tripoli-pets',
    contactPerson: 'محمد',
    phone: '+218910000001',
    city: 'طرابلس',
    area: 'حي الأندلس',
    address: 'شارع السوق',
    discountPercent: 12.5,
    accountStatus: 'active',
    creditLimit: 2500.5,
    outstandingBalance: 420,
  );

  test('customer update payload contains only the audited function contract',
      () {
    final payload = AdminRepository.customerUpdatePayload(customer);

    expect(payload['customer_id'], customer.id);
    expect(payload['business_name'], customer.businessName);
    expect(payload['credit_limit'], 2500.5);
    expect(payload['outstanding_balance'], 420);
    expect(payload['discount_percent'], 12.5);
    expect(
      payload.keys,
      unorderedEquals(const [
        'customer_id',
        'business_name',
        'contact_person',
        'phone',
        'city',
        'area',
        'address',
        'discount_percent',
        'account_status',
        'credit_limit',
        'outstanding_balance',
      ]),
    );
    expect(payload, isNot(contains('profile_id')));
    expect(payload, isNot(contains('username')));
    expect(payload, isNot(contains('role')));
  });

  test('customer create payload carries the validated account discount', () {
    final payload = AdminRepository.customerCreatePayload(customer);

    expect(payload['username'], customer.username);
    expect(payload['discount_percent'], 12.5);
    expect(
      payload.keys,
      unorderedEquals(const [
        'business_name',
        'contact_person',
        'phone',
        'city',
        'area',
        'address',
        'username',
        'discount_percent',
        'credit_limit',
      ]),
    );
    expect(payload, isNot(contains('price_group_id')));
  });

  test('customer update response parses the server-enriched customer', () {
    final saved = AdminRepository.customerFromUpdateResponse({
      'ok': true,
      'data': {
        'customer': {
          'id': customer.id,
          'profile_id': customer.profileId,
          'business_name': customer.businessName,
          'contact_person': customer.contactPerson,
          'phone': customer.phone,
          'city': customer.city,
          'area': customer.area,
          'address': customer.address,
          'discount_percent': 17.25,
          'account_status': 'suspended',
          'credit_limit': 3000,
          'outstanding_balance': 500,
          'profiles': {'username': customer.username},
        },
      },
    });

    expect(saved.id, customer.id);
    expect(saved.username, customer.username);
    expect(saved.accountStatus, 'suspended');
    expect(saved.creditLimit, 3000);
    expect(saved.discountPercent, 17.25);
  });

  test('customer payload rejects invalid discount percentages', () {
    for (final invalid in <double>[-0.01, 100, 12.345, double.nan]) {
      expect(
        () => AdminRepository.customerUpdatePayload(
          customer.copyWith(discountPercent: invalid),
        ),
        throwsArgumentError,
      );
      expect(
        () => AdminRepository.customerCreatePayload(
          customer.copyWith(discountPercent: invalid),
        ),
        throwsArgumentError,
      );
    }
  });

  test('customer update response fails closed without a saved customer', () {
    expect(
      () => AdminRepository.customerFromUpdateResponse({
        'ok': true,
        'data': const <String, dynamic>{},
      }),
      throwsStateError,
    );
  });
}
