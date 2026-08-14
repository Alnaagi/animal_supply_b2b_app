import 'package:animal_supply_b2b/src/core/updates/update_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a normal HTTPS update URL', () {
    expect(
      safeHttpsUpdateUri('https://downloads.example.ly/app-release.apk'),
      Uri.parse('https://downloads.example.ly/app-release.apk'),
    );
  });

  test('rejects unsafe update destinations', () {
    for (final value in [
      'http://downloads.example.ly/app-release.apk',
      'http://localhost/app-release.apk',
      '/app-release.apk',
      'javascript:alert(1)',
      'https://user:password@downloads.example.ly/app-release.apk',
      '',
    ]) {
      expect(safeHttpsUpdateUri(value), isNull, reason: value);
    }
  });
}
