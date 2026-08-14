import 'package:animal_supply_b2b/src/core/routing/banner_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves supported internal banner targets', () {
    expect(
      resolveBannerDestination(
        targetType: 'category',
        targetValue: 'قطط',
      ).path,
      '/catalog?category=${Uri.encodeComponent('قطط')}',
    );
    expect(
      resolveBannerDestination(
        targetType: 'product',
        targetValue: 'cat-001',
      ).path,
      '/product/cat-001',
    );
  });

  test('accepts safe HTTPS external targets', () {
    final destination = resolveBannerDestination(
      targetType: 'url',
      targetValue: 'https://client.example.ly/offers?source=banner',
    );

    expect(destination.isExternal, isTrue);
    expect(destination.externalUri?.host, 'client.example.ly');
  });

  test('unsafe or malformed targets fail closed to the catalog', () {
    for (final input in [
      (type: 'url', value: 'javascript:alert(1)'),
      (type: 'url', value: 'https://user:secret@example.ly/offers'),
      (type: 'product', value: '../admin'),
      (type: 'category', value: ''),
      (type: 'unknown', value: 'anything'),
    ]) {
      final destination = resolveBannerDestination(
        targetType: input.type,
        targetValue: input.value,
      );
      expect(destination.isExternal, isFalse);
      expect(destination.path, '/catalog');
    }
  });
}
