import 'package:animal_supply_b2b/src/core/auth/login_identifier.dart';
import 'package:animal_supply_b2b/src/data/repositories/demo_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a valid customer username to the configured real domain', () {
    expect(
      loginEmailForIdentifier(
        identifier: 'Tripoli-Pets',
        customerLoginDomain: 'accounts.client.ly',
      ),
      'tripoli-pets@accounts.client.ly',
    );
  });

  test('maps a Libyan WhatsApp number to E.164 instead of an email', () {
    expect(
      normalizeLibyanLoginPhone('0910000001'),
      '+218910000001',
    );
    expect(
      loginAuthTargetForIdentifier(
        identifier: '0910000001',
        customerLoginDomain: 'accounts.client.ly',
      )?.phone,
      '+218910000001',
    );
    expect(
      loginEmailForIdentifier(
        identifier: '0910000001',
        customerLoginDomain: 'accounts.client.ly',
      ),
      isNull,
    );
  });

  test('keeps a supplied staff or admin email unchanged', () {
    expect(
      loginEmailForIdentifier(
        identifier: 'ADMIN@CLIENT.LY',
        customerLoginDomain: '',
      ),
      'admin@client.ly',
    );
  });

  test('maps reserved staff usernames without a customer domain', () {
    expect(
      loginEmailForIdentifier(
        identifier: 'admin',
        customerLoginDomain: '',
      ),
      'admin@demo.ly',
    );
    expect(
      loginEmailForIdentifier(
        identifier: 'staff',
        customerLoginDomain: 'animal-supply-b2b.alnaagi-ai.workers.dev',
      ),
      'staff@demo.ly',
    );
    expect(
      loginEmailForIdentifier(
        identifier: 'test',
        customerLoginDomain: 'animal-supply-b2b.alnaagi-ai.workers.dev',
      ),
      'test@animal-supply-b2b.alnaagi-ai.workers.dev',
    );
    expect(matchesDemoLoginCredentials('admin', 'Admin123!'), isFalse);
  });

  test('rejects placeholder domains and invalid usernames', () {
    for (final domain in [
      '',
      'example.com',
      'accounts.example.invalid',
      'localhost',
    ]) {
      expect(
        loginEmailForIdentifier(
          identifier: 'tripoli-pets',
          customerLoginDomain: domain,
        ),
        isNull,
      );
    }
    expect(
      loginEmailForIdentifier(
        identifier: 'not valid',
        customerLoginDomain: 'accounts.client.ly',
      ),
      isNull,
    );
  });

  test('derives a username from phone digits when the username is empty', () {
    expect(
      usernameFromPhoneDigits('+218910000010'),
      '218910000010',
    );
    expect(usernameFromPhoneDigits('0910000010'), '218910000010');
    expect(
      resolveCustomerCreateUsername(
        username: '  ',
        phone: '+21891 0000010',
      ),
      '218910000010',
    );
    expect(
      resolveCustomerCreateUsername(
        username: 'shop-one',
        phone: '+218910000010',
      ),
      'shop-one',
    );
    expect(usernameFromPhoneDigits('12'), isNull);
  });
}
