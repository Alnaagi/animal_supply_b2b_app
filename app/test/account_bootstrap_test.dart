import 'package:animal_supply_b2b/src/core/auth/account_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a fully active customer account', () {
    final user = appUserFromBootstrapPayload(
      {
        'id': 'profile-1',
        'username': 'tripoli-pets',
        'role': 'customer',
        'active': true,
        'must_change_password': false,
        'customer': {
          'id': 'customer-1',
          'account_status': 'active',
          'business_name': 'متجر طرابلس',
          'contact_person': 'محمد',
          'phone': '+218910000001',
          'city': 'طرابلس',
          'credit_limit': 1000,
          'outstanding_balance': 125,
          'discount_percent': 12.5,
        },
      },
      authUserId: 'profile-1',
    );

    expect(user.isCustomer, isTrue);
    expect(user.businessName, 'متجر طرابلس');
    expect(user.customerId, 'customer-1');
    expect(user.creditLimit, 1000);
    expect(user.outstandingBalance, 125);
    expect(user.discountPercent, 12.5);
  });

  test('accepts the minimal pre-activation payload without exposing details',
      () {
    final user = appUserFromBootstrapPayload(
      {
        'id': 'profile-1',
        'username': 'tripoli-pets',
        'role': 'customer',
        'active': true,
        'must_change_password': true,
        'customer': {
          'id': 'customer-1',
          'account_status': 'active',
        },
      },
      authUserId: 'profile-1',
    );

    expect(user.mustChangePassword, isTrue);
    expect(user.customerId, 'customer-1');
    expect(user.businessName, isNull);
    expect(user.creditLimit, 0);
    expect(user.discountPercent, 0);
  });

  test('rejects malformed customer discount data', () {
    for (final invalid in [-1, 100, 12.345, 'invalid']) {
      expect(
        () => appUserFromBootstrapPayload(
          {
            'id': 'profile-1',
            'username': 'tripoli-pets',
            'role': 'customer',
            'active': true,
            'must_change_password': false,
            'customer': {
              'id': 'customer-1',
              'account_status': 'active',
              'discount_percent': invalid,
            },
          },
          authUserId: 'profile-1',
        ),
        throwsA(
          isA<AccountBootstrapException>().having(
            (error) => error.message,
            'message',
            contains('خصم العميل'),
          ),
        ),
      );
    }
  });

  test('rejects inactive and mismatched bootstrap payloads', () {
    expect(
      () => appUserFromBootstrapPayload(
        {
          'id': 'other-profile',
          'role': 'admin',
          'active': true,
          'must_change_password': false,
        },
        authUserId: 'profile-1',
      ),
      throwsA(isA<AccountBootstrapException>()),
    );
    expect(
      () => appUserFromBootstrapPayload(
        {
          'id': 'profile-1',
          'role': 'customer',
          'active': true,
          'must_change_password': false,
          'customer': {
            'id': 'customer-1',
            'account_status': 'suspended',
          },
        },
        authUserId: 'profile-1',
      ),
      throwsA(
        isA<AccountBootstrapException>().having(
          (error) => error.message,
          'message',
          contains('موقوف'),
        ),
      ),
    );
  });
}
