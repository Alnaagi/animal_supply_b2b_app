import 'package:animal_supply_b2b/src/core/support/customer_contact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer contact builds safe whatsapp uri', () {
    final uri = CustomerContact.whatsappUri(
      phone: '+218 91 234 5678',
      text: 'مرحبا',
    );
    expect(uri, isNotNull);
    expect(uri!.host, 'wa.me');
    expect(uri.path, '/218912345678');
    expect(uri.queryParameters['text'], 'مرحبا');
  });
}
