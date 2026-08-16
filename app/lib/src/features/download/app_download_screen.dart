import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/theme/app_theme.dart';
import '../../core/updates/download_page_links.dart';
import '../../core/updates/update_link.dart';
import '../../core/widgets/shop_brand_logo.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';

class DownloadPageData {
  const DownloadPageData({
    required this.android,
    required this.ios,
    required this.downloadPageUri,
    required this.webAppUri,
  });

  final AppVersionInfo android;
  final AppVersionInfo ios;
  final Uri? downloadPageUri;
  final Uri? webAppUri;
}

final downloadPageDataProvider = FutureProvider<DownloadPageData>((ref) async {
  final package = await PackageInfo.fromPlatform();
  final repository = ref.read(adminRepositoryProvider);
  final versions = await Future.wait([
    _loadVersion(
      repository: repository,
      platform: 'android',
      package: package,
    ),
    _loadVersion(
      repository: repository,
      platform: 'ios',
      package: package,
    ),
  ]);
  return DownloadPageData(
    android: versions[0],
    ios: versions[1],
    downloadPageUri: resolvePublicDownloadPageUri(
      configuredDownloadLink: AppConfig.downloadLink,
      publicAppOrigin: AppConfig.publicAppOrigin,
      currentBase: Uri.base,
      isWeb: kIsWeb,
    ),
    webAppUri: resolvePublicWebAppUri(
      publicAppOrigin: AppConfig.publicAppOrigin,
      currentBase: Uri.base,
      isWeb: kIsWeb,
    ),
  );
});

Future<AppVersionInfo> _loadVersion({
  required AdminRepository repository,
  required String platform,
  required PackageInfo package,
}) async {
  try {
    return downloadVersionForDisplay(
      metadata: await repository.latestVersion(platform: platform),
      package: package,
      demoMode: AppConfig.isDemoMode,
    );
  } catch (_) {
    final isAndroid = platform == 'android';
    return AppVersionInfo(
      platform: platform,
      versionName: package.version,
      versionCode: int.tryParse(package.buildNumber) ?? 1,
      apkUrl: isAndroid ? AppConfig.apkLink : '',
      releaseNotes: AppConfig.isDemoMode
          ? 'لم تُربط بيانات توزيع تشغيلية في النسخة التجريبية.'
          : 'تعذر تحميل بيانات هذا الإصدار مؤقتاً.',
    );
  }
}

AppVersionInfo downloadVersionForDisplay({
  required AppVersionInfo metadata,
  required PackageInfo package,
  required bool demoMode,
}) {
  if (!demoMode) return metadata;
  return AppVersionInfo(
    platform: metadata.platform,
    versionName: package.version,
    versionCode: int.tryParse(package.buildNumber) ?? metadata.versionCode,
    minimumSupportedCode: metadata.minimumSupportedCode,
    apkUrl: metadata.apkUrl,
    required: metadata.required,
    releaseNotes: metadata.releaseNotes,
    sha256: metadata.sha256,
    fileSizeBytes: metadata.fileSizeBytes,
  );
}

class AppDownloadScreen extends ConsumerWidget {
  const AppDownloadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(downloadPageDataProvider);
    final branding = ref.watch(shopBrandingProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحميل التطبيق'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.login),
            label: const Text('تسجيل الدخول'),
          ),
        ],
      ),
      body: SafeArea(
        child: data.when(
          loading: () => const ShopLoading.page(),
          error: (_, __) => _DownloadLoadError(
            onRetry: () => ref.invalidate(downloadPageDataProvider),
          ),
          data: (value) => _DownloadPageContent(
            data: value,
            branding: branding,
          ),
        ),
      ),
    );
  }
}

class _DownloadPageContent extends StatelessWidget {
  const _DownloadPageContent({
    required this.data,
    required this.branding,
  });

  final DownloadPageData data;
  final ShopBranding branding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (AppConfig.isDemoMode)
                  Container(
                    key: const Key('download-demo-notice'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: const Text(
                      'هذه صفحة توزيع تجريبية. لا ترسلها للعملاء قبل رفع '
                      'النسخ الموقعة وربط روابط الإنتاج.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                const SizedBox(height: 18),
                Center(
                  child: ShopBrandLogo(
                    logoUrl: branding.logoUrl,
                    size: 72,
                    backgroundColor: const Color(0xffe3f3eb),
                    fallbackIconColor: AppTheme.green,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  branding.shopName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'اختر المنصة المناسبة. لا يوجد تسجيل ذاتي؛ بيانات الدخول '
                  'يرسلها المتجر فقط بعد إنشاء حساب الأعمال.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth >= 780
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _PlatformDownloadCard(
                            icon: Icons.android,
                            title: 'Android',
                            version: data.android,
                            buttonLabel: 'تحميل APK الموقع',
                            unavailableMessage:
                                'لم يُرفع رابط APK الإنتاجي بعد.',
                            guidance:
                                'بعد التنزيل افتح الملف واسمح بالتثبيت من '
                                'المصدر الموثوق لهذا الإصدار فقط. قارن بصمة '
                                'SHA-256 قبل التثبيت.',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _PlatformDownloadCard(
                            icon: Icons.phone_iphone,
                            title: 'iPhone وiPad',
                            version: data.ios,
                            buttonLabel: 'فتح رابط توزيع iOS',
                            unavailableMessage:
                                'لم يُربط TestFlight أو App Store أو توزيع '
                                'مؤسسي معتمد بعد.',
                            guidance:
                                'ملف IPA عادي من رابط سحابي لا يثبت على أجهزة '
                                'العملاء العامة. استخدم رابط TestFlight أو '
                                'App Store أو توزيعاً مؤسسياً/Ad Hoc صالحاً.',
                            showChecksum: false,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _WebAppCard(webAppUri: data.webAppUri),
                const SizedBox(height: 24),
                _ShareCard(
                  downloadPageUri: data.downloadPageUri,
                  shopName: branding.shopName,
                ),
                const SizedBox(height: 20),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.security_outlined, color: AppTheme.green),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'تنبيه أمني: المتجر لا يرسل كلمة المرور داخل رابط '
                            'أو QR. رابط الدعوة يحتوي رمزاً لمرة واحدة فقط، '
                            'والتطبيق لا يطلب إنشاء حساب جديد.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlatformDownloadCard extends StatelessWidget {
  const _PlatformDownloadCard({
    required this.icon,
    required this.title,
    required this.version,
    required this.buttonLabel,
    required this.unavailableMessage,
    required this.guidance,
    this.showChecksum = true,
  });

  final IconData icon;
  final String title;
  final AppVersionInfo version;
  final String buttonLabel;
  final String unavailableMessage;
  final String guidance;
  final bool showChecksum;

  @override
  Widget build(BuildContext context) {
    final uri = safeHttpsUpdateUri(version.apkUrl);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.green.withValues(alpha: .12),
                  child: Icon(icon, color: AppTheme.green),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'الإصدار ${version.versionName} (${version.versionCode})',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (version.releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(version.releaseNotes),
            ],
            if (showChecksum && version.sha256.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                'SHA-256\n${version.sha256}',
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (version.fileSizeBytes != null) ...[
              const SizedBox(height: 6),
              Text('حجم الملف: ${_formatBytes(version.fileSizeBytes!)}'),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: uri == null
                  ? null
                  : () => launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      ),
              icon: const Icon(Icons.download_outlined),
              label: Text(buttonLabel),
            ),
            if (uri == null) ...[
              const SizedBox(height: 8),
              Text(
                unavailableMessage,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              guidance,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _WebAppCard extends StatelessWidget {
  const _WebAppCard({required this.webAppUri});

  final Uri? webAppUri;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              child: Icon(Icons.language_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نسخة الويب',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'تعمل من المتصفح على الهاتف والكمبيوتر، ويمكن إضافتها '
                    'للشاشة الرئيسية من قائمة المتصفح.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed:
                        webAppUri == null ? null : () => context.go('/login'),
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('فتح تطبيق الويب'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.downloadPageUri,
    required this.shopName,
  });

  final Uri? downloadPageUri;
  final String shopName;

  @override
  Widget build(BuildContext context) {
    final uri = downloadPageUri;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text(
              'شارك رابط التحميل',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'استخدم الرابط الثابت نفسه في واتساب والمطبوعات والـ QR.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (uri != null) ...[
              Container(
                key: const Key('download-qr'),
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: uri.toString(),
                  size: 190,
                  semanticsLabel: 'رمز QR لصفحة تحميل التطبيق',
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                uri.toString(),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: uri.toString()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ رابط التحميل.')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ الرابط'),
                  ),
                  FilledButton.icon(
                    onPressed: () => launchUrl(
                      whatsappDownloadShareUri(
                        downloadPage: uri,
                        shopName: shopName,
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('إرساله عبر واتساب'),
                  ),
                ],
              ),
            ] else
              const Text(
                'أضف APP_DOWNLOAD_LINK أو APP_PUBLIC_ORIGIN الحقيقي عند بناء '
                'نسخة الإنتاج لإظهار الرابط والـ QR.',
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadLoadError extends StatelessWidget {
  const _DownloadLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 56),
            const SizedBox(height: 12),
            const Text('تعذر تحميل بيانات التنزيل.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes بايت';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} كيلوبايت';
  final megabytes = kilobytes / 1024;
  return '${megabytes.toStringAsFixed(1)} ميجابايت';
}
