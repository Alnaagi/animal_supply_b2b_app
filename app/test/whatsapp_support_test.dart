import 'package:animal_supply_b2b/src/core/support/whatsapp_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes and validates a Libyan support number', () {
    expect(
      WhatsAppSupport.digitsFor('+218 91 234 5678'),
      '218912345678',
    );
    expect(
      WhatsAppSupport.isConfiguredFor('+218 91 234 5678'),
      isTrue,
    );
    expect(WhatsAppSupport.isConfiguredFor('123'), isFalse);
  });
}
