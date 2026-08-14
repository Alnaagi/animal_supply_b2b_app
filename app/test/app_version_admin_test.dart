import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo version metadata preserves the requested platform', () async {
    final repository = AdminRepository();

    final android = await repository.latestVersion(platform: 'android');
    final ios = await repository.latestVersion(platform: 'ios');

    expect(android.platform, 'android');
    expect(android.releaseNotes, contains('APK'));
    expect(ios.platform, 'ios');
    expect(ios.releaseNotes, contains('iOS'));
    expect(ios.apkUrl, isEmpty);
  });

  test('Android publication requires HTTPS, checksum, and exact file size', () {
    const valid = AppVersionInfo(
      platform: 'android',
      versionName: '1.0.4',
      versionCode: 5,
      minimumSupportedCode: 4,
      apkUrl: 'https://downloads.client.ly/animal-supply-1.0.4.apk',
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      fileSizeBytes: 60000000,
    );

    expect(
      () => AdminRepository.validateVersionForPublication(valid),
      returnsNormally,
    );
    expect(
      () => AdminRepository.validateVersionForPublication(
        const AppVersionInfo(
          platform: 'android',
          versionName: '1.0.4',
          versionCode: 5,
          minimumSupportedCode: 4,
          apkUrl: 'https://downloads.client.ly/animal-supply-1.0.4.apk',
        ),
      ),
      throwsFormatException,
    );
  });

  test('iOS publication accepts a trusted distribution URL without APK hash',
      () {
    expect(
      () => AdminRepository.validateVersionForPublication(
        const AppVersionInfo(
          platform: 'ios',
          versionName: '1.0.4',
          versionCode: 5,
          minimumSupportedCode: 4,
          apkUrl: 'https://testflight.apple.com/join/example',
        ),
      ),
      returnsNormally,
    );
  });
}
