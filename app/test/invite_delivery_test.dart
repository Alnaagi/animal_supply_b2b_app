import 'package:animal_supply_b2b/src/core/support/invite_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invite WhatsApp URI prefills the compose body for a phone', () {
    const message = 'مرحباً\nاسم المستخدم: test\nكلمة المرور: secret\n'
        'https://animal-supply-b2b.alnaagi-ai.workers.dev/login';
    final uri = inviteWhatsappComposeUri(
      normalizedPhone: '218910000001',
      text: message,
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/218910000001');
    expect(uri.queryParameters['text'], message);
    expect(uri.queryParameters['text'], isNot(contains('password=secret')));
    expect(uri.toString(), contains('text='));
  });

  test('invite WhatsApp URI without a phone uses wa.me/?text=', () {
    const message = 'رابط تسجيل الدخول:\nhttps://example.ly/login';
    final uri = inviteWhatsappComposeUri(text: message);

    expect(uri.host, 'wa.me');
    expect(uri.path, '/');
    expect(uri.queryParameters['text'], message);
    expect(uri.queryParameters.containsKey('password'), isFalse);
  });

  test('invite delivery rejects unnormalized phone input', () {
    expect(
      () => inviteWhatsappComposeUri(
        normalizedPhone: '+218 91 000 0001',
        text: 'مرحباً',
      ),
      throwsArgumentError,
    );
  });
}
