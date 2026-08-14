import 'package:animal_supply_b2b/src/core/support/invite_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'invite delivery opens a bare WhatsApp contact without secret query data',
      () {
    final uri = inviteWhatsappContactUri('218910000001');

    expect(uri.scheme, 'https');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/218910000001');
    expect(uri.query, isEmpty);
    expect(uri.queryParameters, isEmpty);
  });

  test('invite delivery rejects unnormalized phone input', () {
    expect(
      () => inviteWhatsappContactUri('+218 91 000 0001'),
      throwsArgumentError,
    );
  });
}
