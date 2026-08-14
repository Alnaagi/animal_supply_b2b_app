import 'package:animal_supply_b2b/src/core/auth/login_identifier.dart';
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

  test('keeps a supplied staff or admin email unchanged', () {
    expect(
      loginEmailForIdentifier(
        identifier: 'ADMIN@CLIENT.LY',
        customerLoginDomain: '',
      ),
      'admin@client.ly',
    );
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
}
