import 'package:animal_supply_b2b/src/core/updates/download_page_links.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/features/download/app_download_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('demo download metadata uses the installed release version', () {
    final result = downloadVersionForDisplay(
      metadata: const AppVersionInfo(
        platform: 'android',
        versionName: '1.0.0',
        versionCode: 1,
        releaseNotes: 'نسخة تجريبية',
      ),
      package: PackageInfo(
        appName: 'Animal Supply',
        packageName: 'ly.animalsupply.b2b',
        version: '1.0.4',
        buildNumber: '5',
      ),
      demoMode: true,
    );

    expect(result.versionName, '1.0.4');
    expect(result.versionCode, 5);
    expect(result.releaseNotes, 'نسخة تجريبية');
  });

  test('download page links prefer configured safe HTTPS destinations', () {
    expect(
      resolvePublicDownloadPageUri(
        configuredDownloadLink: 'https://downloads.client.ly/app',
        publicAppOrigin: 'https://shop.client.ly',
        currentBase: Uri.parse('https://fallback.client.ly/admin'),
        isWeb: true,
      ),
      Uri.parse('https://downloads.client.ly/app'),
    );
    expect(
      resolvePublicDownloadPageUri(
        configuredDownloadLink: '',
        publicAppOrigin: 'https://shop.client.ly',
        currentBase: Uri.parse('https://fallback.client.ly/admin'),
        isWeb: true,
      ),
      Uri.parse('https://shop.client.ly/download'),
    );
  });

  test('download page links reject unsafe non-web fallbacks', () {
    expect(
      resolvePublicDownloadPageUri(
        configuredDownloadLink: 'http://downloads.client.ly/app',
        publicAppOrigin: 'https://user:pass@shop.client.ly',
        currentBase: Uri.parse('file:///tmp/app'),
        isWeb: false,
      ),
      isNull,
    );
  });

  testWidgets('Arabic public download page shows platforms, QR, and no signup',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/download',
      routes: [
        GoRoute(
          path: '/download',
          builder: (context, state) => const AppDownloadScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('login')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          downloadPageDataProvider.overrideWith(
            (ref) async => DownloadPageData(
              android: const AppVersionInfo(
                platform: 'android',
                versionName: '1.0.3',
                versionCode: 4,
                apkUrl: 'https://downloads.client.ly/app-release.apk',
                sha256:
                    '885668baa816f18d9e36c226e068c013f4ff050ac102114d67b6ab7ed1192520',
                fileSizeBytes: 60749421,
              ),
              ios: const AppVersionInfo(
                platform: 'ios',
                versionName: '1.0.3',
                versionCode: 4,
                apkUrl: 'https://testflight.apple.com/join/example',
              ),
              downloadPageUri: Uri.parse('https://shop.client.ly/download'),
              webAppUri: Uri.parse('https://shop.client.ly/'),
            ),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('ar'),
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تحميل التطبيق'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('iPhone وiPad'), findsOneWidget);
    expect(find.text('نسخة الويب'), findsOneWidget);
    expect(find.byKey(const Key('download-qr')), findsOneWidget);
    expect(find.textContaining('لا يوجد تسجيل ذاتي'), findsOneWidget);
    expect(find.textContaining('إنشاء حساب جديد'), findsOneWidget);
    expect(find.textContaining('إنشاء حساب الآن'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text('تحميل التطبيق'))),
      TextDirection.rtl,
    );
  });
}
