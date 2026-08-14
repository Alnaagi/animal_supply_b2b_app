import 'package:animal_supply_b2b/src/core/routing/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyz123456';

  test('accepts the native custom invite scheme without passwords', () {
    final normalized = DeepLinkService.normalizeInviteUri(
      Uri.parse('animalsupplyb2b://invite?token=$token&client=shop-1'),
    );

    expect(normalized?.path, '/invite');
    expect(normalized?.queryParameters['token'], token);
    expect(normalized?.queryParameters['client'], 'shop-1');
    expect(normalized?.queryParameters.containsKey('password'), isFalse);
  });

  test('accepts HTTPS invites only for the exact trusted host', () {
    expect(
      DeepLinkService.normalizeInviteUri(
        Uri.parse('https://shop.client.ly/invite?token=$token'),
        trustedHttpsHost: 'shop.client.ly',
      ),
      isNotNull,
    );
    expect(
      DeepLinkService.normalizeInviteUri(
        Uri.parse('https://attacker.example/invite?token=$token'),
        trustedHttpsHost: 'shop.client.ly',
      ),
      isNull,
    );
    expect(
      DeepLinkService.normalizeInviteUri(
        Uri.parse('http://shop.client.ly/invite?token=$token'),
        trustedHttpsHost: 'shop.client.ly',
      ),
      isNull,
    );
  });

  test('rejects malformed or suspicious invite tokens', () {
    for (final tokenValue in [
      '',
      'short',
      'bad token',
      List.filled(513, 'x').join(),
    ]) {
      expect(
        DeepLinkService.normalizeInviteUri(
          Uri.parse(
            'animalsupplyb2b://invite?token=${Uri.encodeComponent(tokenValue)}',
          ),
        ),
        isNull,
      );
    }
  });
}
