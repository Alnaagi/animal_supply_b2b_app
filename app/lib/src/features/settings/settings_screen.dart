import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/notifications/push_permission_card.dart';
import '../../core/updates/update_link.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/responsive_field_group.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../admin_dashboard/admin_shell.dart';
import 'admin_data_mode_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int refreshKey = 0;
  String versionPlatform = 'android';

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'الإعدادات والتحديثات',
      child: FutureBuilder<AppSettingsData>(
        key: ValueKey(refreshKey),
        future: ref.read(adminRepositoryProvider).settings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _SettingsLoadError(
              onRetry: () => setState(() => refreshKey++),
            );
          }
          final settings = snapshot.data ?? const AppSettingsData();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('إعدادات المتجر',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 20)),
                        const SizedBox(height: 10),
                        _SettingRow(
                            label: 'اسم المتجر', value: settings.shopName),
                        _SettingRow(
                            label: 'واتساب الدعم',
                            value: settings.supportWhatsapp),
                        _SettingRow(
                            label: 'صفحة التنزيل والانضمام',
                            value: settings.downloadLink),
                        _SettingRow(
                            label: 'رابط APK المباشر', value: settings.apkLink),
                        _SettingRow(
                            label: 'سياسة التوصيل',
                            value: settings.deliveryPolicy),
                        _SettingRow(
                            label: 'الحد الأدنى للطلب',
                            value: lyd(settings.minimumOrderAmount)),
                        _SettingRow(
                            label: 'رسوم التوصيل',
                            value: lyd(settings.deliveryFee)),
                        _SettingRow(
                            label: 'رسوم المناولة',
                            value: lyd(settings.handlingFee)),
                        _SettingRow(label: 'العملة', value: settings.currency),
                        _SettingRow(
                            label: 'وضع الصيانة',
                            value: settings.maintenanceMode ? 'مفعل' : 'متوقف'),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                            onPressed: () => _editSettings(settings),
                            icon: const Icon(Icons.edit),
                            label: const Text('تعديل الإعدادات')),
                      ]),
                ),
              ),
              const SizedBox(height: 14),
              AdminDataModeCard(
                onLocalDataReset: () => setState(() => refreshKey++),
              ),
              const SizedBox(height: 14),
              const PushPermissionCard(),
              const SizedBox(height: 14),
              _buildVersionSection(settings),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVersionSection(AppSettingsData settings) {
    final isAndroid = versionPlatform == 'android';
    final fallbackLink = isAndroid ? settings.apkLink : settings.downloadLink;
    final platformLabel = isAndroid ? 'Android' : 'iOS';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.system_update_alt, color: AppTheme.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'إدارة إصدارات التطبيق',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'android',
                  label: Text('Android'),
                  icon: Icon(Icons.android),
                ),
                ButtonSegment(
                  value: 'ios',
                  label: Text('iOS'),
                  icon: Icon(Icons.phone_iphone),
                ),
              ],
              selected: {versionPlatform},
              onSelectionChanged: (selection) {
                setState(() => versionPlatform = selection.single);
              },
            ),
            const SizedBox(height: 14),
            FutureBuilder<AppVersionInfo>(
              key: ValueKey('$refreshKey-$versionPlatform'),
              future: ref
                  .read(adminRepositoryProvider)
                  .latestVersion(platform: versionPlatform),
              builder: (context, versionSnapshot) {
                if (versionSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (versionSnapshot.hasError) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: Text('تعذر تحميل إصدار $platformLabel'),
                    subtitle: const Text('تحقق من الاتصال ثم أعد المحاولة.'),
                    trailing: IconButton(
                      onPressed: () => setState(() => refreshKey++),
                      tooltip: 'إعادة المحاولة',
                      icon: const Icon(Icons.refresh),
                    ),
                  );
                }
                final version = versionSnapshot.data ??
                    AppVersionInfo(
                      platform: versionPlatform,
                      apkUrl: fallbackLink,
                    );
                final versionUri = safeHttpsUpdateUri(version.apkUrl);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'آخر إصدار $platformLabel: '
                      '${version.versionName} (${version.versionCode})',
                    ),
                    Text(
                      'نوع التحديث: '
                      '${version.required ? 'إجباري' : 'اختياري'}',
                    ),
                    Text(
                      version.releaseNotes.isEmpty
                          ? 'لا توجد ملاحظات إصدار.'
                          : version.releaseNotes,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: versionUri == null
                              ? null
                              : () => launchUrl(
                                    versionUri,
                                    mode: LaunchMode.externalApplication,
                                  ),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(
                            isAndroid ? 'فتح رابط APK' : 'فتح رابط توزيع iOS',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _publishVersion(version),
                          icon: const Icon(Icons.publish_outlined),
                          label: Text('نشر إصدار $platformLabel'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isAndroid
                          ? 'Android: يحمّل المستخدم ملف APK ويؤكد التثبيت؛ '
                              'لا يمكن التحديث الصامت من خارج Google Play.'
                          : 'iOS: استخدم TestFlight أو App Store أو توزيعاً '
                              'مؤسسياً/Ad Hoc صالحاً. رابط IPA عادي على Google '
                              'Drive لا يثبت على أجهزة العملاء العامة.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSettings(AppSettingsData settings) async {
    final shop = TextEditingController(text: settings.shopName);
    final whats = TextEditingController(text: settings.supportWhatsapp);
    final download = TextEditingController(text: settings.downloadLink);
    final apk = TextEditingController(text: settings.apkLink);
    final delivery = TextEditingController(text: settings.deliveryPolicy);
    final minimum = TextEditingController(
        text: settings.minimumOrderAmount.toStringAsFixed(2));
    final deliveryFee =
        TextEditingController(text: settings.deliveryFee.toStringAsFixed(2));
    final handlingFee =
        TextEditingController(text: settings.handlingFee.toStringAsFixed(2));
    var maintenance = settings.maintenanceMode;
    String? validationMessage;
    final saved = await showDialog<AppSettingsData>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل الإعدادات'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(children: [
                TextField(
                    controller: shop,
                    decoration: const InputDecoration(labelText: 'اسم المتجر')),
                const SizedBox(height: 10),
                TextField(
                    controller: whats,
                    decoration:
                        const InputDecoration(labelText: 'واتساب الدعم')),
                const SizedBox(height: 10),
                TextField(
                    controller: download,
                    decoration: const InputDecoration(
                      labelText: 'صفحة التنزيل والانضمام',
                      helperText:
                          'رابط HTTPS ثابت يُرسل في دعوات العملاء ويعرض خيارات المنصات.',
                    )),
                const SizedBox(height: 10),
                TextField(
                    controller: apk,
                    decoration: const InputDecoration(
                      labelText: 'رابط APK المباشر',
                      helperText: 'رابط ملف Android الموقع للإصدار الحالي فقط.',
                    )),
                const SizedBox(height: 10),
                TextField(
                    controller: delivery,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'سياسة التوصيل')),
                const SizedBox(height: 10),
                TextField(
                    controller: minimum,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'الحد الأدنى للطلب')),
                const SizedBox(height: 10),
                TextField(
                    controller: deliveryFee,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'رسوم التوصيل')),
                const SizedBox(height: 10),
                TextField(
                    controller: handlingFee,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'رسوم المناولة')),
                SwitchListTile(
                    value: maintenance,
                    onChanged: (value) =>
                        setDialogState(() => maintenance = value),
                    title: const Text('وضع الصيانة'),
                    subtitle: const Text(
                      'يمنع إرسال طلبات جديدة مؤقتاً مع بقاء لوحة الإدارة متاحة.',
                    )),
                if (validationMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final parsedMinimum = double.tryParse(minimum.text.trim());
                final parsedDeliveryFee =
                    double.tryParse(deliveryFee.text.trim());
                final parsedHandlingFee =
                    double.tryParse(handlingFee.text.trim());
                final values = [
                  parsedMinimum,
                  parsedDeliveryFee,
                  parsedHandlingFee,
                ];
                final rawWhatsapp = whats.text.trim();
                final rawDownload = download.text.trim();
                final rawApk = apk.text.trim();
                final validMoney = values.every(
                  (value) => value != null && value.isFinite && value >= 0,
                );
                final validWhatsapp =
                    rawWhatsapp.isEmpty || _isValidWhatsapp(rawWhatsapp);
                final validDownload = rawDownload.isEmpty ||
                    safeHttpsUpdateUri(rawDownload) != null;
                final validApk =
                    rawApk.isEmpty || safeHttpsUpdateUri(rawApk) != null;
                if (shop.text.trim().isEmpty ||
                    !validMoney ||
                    !validWhatsapp ||
                    !validDownload ||
                    !validApk) {
                  setDialogState(() {
                    validationMessage =
                        'أدخل اسم المتجر، أرقاماً غير سالبة، ورقم واتساب صحيحاً، '
                        'واستخدم روابط HTTPS فقط.';
                  });
                  return;
                }
                Navigator.pop(
                  context,
                  AppSettingsData(
                    shopName: shop.text.trim(),
                    supportWhatsapp: rawWhatsapp,
                    downloadLink: rawDownload,
                    apkLink: rawApk,
                    deliveryPolicy: delivery.text.trim(),
                    minimumOrderAmount: parsedMinimum!,
                    deliveryFee: parsedDeliveryFee!,
                    handlingFee: parsedHandlingFee!,
                    currency: settings.currency,
                    maintenanceMode: maintenance,
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      shop,
      whats,
      download,
      apk,
      delivery,
      minimum,
      deliveryFee,
      handlingFee,
    ]) {
      controller.dispose();
    }
    if (saved == null) return;
    try {
      await ref.read(adminRepositoryProvider).saveSettings(saved);
      ref.invalidate(appSettingsProvider);
      if (mounted) setState(() => refreshKey++);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر حفظ الإعدادات. تحقق من الاتصال وحاول مجدداً.'),
        ),
      );
    }
  }

  Future<void> _publishVersion(AppVersionInfo current) async {
    final platform = current.platform;
    var requiredUpdate = current.required;
    final versionName = TextEditingController(text: current.versionName);
    final versionCode =
        TextEditingController(text: current.versionCode.toString());
    final minimumCode =
        TextEditingController(text: current.minimumSupportedCode.toString());
    final downloadUrl = TextEditingController(text: current.apkUrl);
    final sha256 = TextEditingController(text: current.sha256);
    final fileSize =
        TextEditingController(text: current.fileSizeBytes?.toString() ?? '');
    final notes = TextEditingController(text: current.releaseNotes);
    String? validationMessage;

    final saved = await showDialog<AppVersionInfo>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('نشر إصدار تطبيق'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'المنصة'),
                    child: Text(
                      platform == 'android' ? 'Android' : 'iOS',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ResponsiveFieldGroup(
                    columns: 3,
                    children: [
                      TextField(
                        controller: versionName,
                        decoration:
                            const InputDecoration(labelText: 'اسم الإصدار'),
                      ),
                      TextField(
                        controller: versionCode,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'رقم البناء'),
                      ),
                      TextField(
                        controller: minimumCode,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'أقل بناء مدعوم',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: downloadUrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: platform == 'android'
                          ? 'رابط APK المباشر'
                          : 'رابط TestFlight أو App Store',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sha256,
                    decoration: InputDecoration(
                      labelText: platform == 'android'
                          ? 'SHA-256 لملف APK (إجباري)'
                          : 'SHA-256 اختياري',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fileSize,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: platform == 'android'
                          ? 'حجم ملف APK بالبايت (إجباري)'
                          : 'حجم الملف بالبايت اختياري',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 6,
                    decoration:
                        const InputDecoration(labelText: 'ملاحظات الإصدار'),
                  ),
                  SwitchListTile(
                    value: requiredUpdate,
                    onChanged: (value) =>
                        setDialogState(() => requiredUpdate = value),
                    title: const Text('تحديث إجباري'),
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final parsedCode = int.tryParse(versionCode.text);
                final parsedMinimum = int.tryParse(minimumCode.text);
                final parsedFileSize = fileSize.text.trim().isEmpty
                    ? null
                    : int.tryParse(fileSize.text.trim());
                final cleanHash = sha256.text.trim().toLowerCase();
                final parsedDownload =
                    safeHttpsUpdateUri(downloadUrl.text.trim());
                final candidate = AppVersionInfo(
                  platform: platform,
                  versionName: versionName.text.trim(),
                  versionCode: parsedCode ?? 0,
                  minimumSupportedCode: parsedMinimum ?? 0,
                  apkUrl: parsedDownload?.toString() ?? '',
                  required: requiredUpdate,
                  releaseNotes: notes.text.trim(),
                  sha256: cleanHash,
                  fileSizeBytes: parsedFileSize,
                );
                try {
                  AdminRepository.validateVersionForPublication(candidate);
                } on FormatException {
                  setDialogState(() {
                    validationMessage = platform == 'android'
                        ? 'راجع الإصدار والأرقام ورابط HTTPS، وأدخل بصمة '
                            'SHA-256 وحجم ملف APK الصحيحين.'
                        : 'راجع الإصدار والأرقام ورابط HTTPS والبيانات '
                            'الاختيارية.';
                  });
                  return;
                }
                Navigator.pop(context, candidate);
              },
              child: const Text('نشر'),
            ),
          ],
        ),
      ),
    );

    for (final controller in [
      versionName,
      versionCode,
      minimumCode,
      downloadUrl,
      sha256,
      fileSize,
      notes,
    ]) {
      controller.dispose();
    }
    if (saved == null) return;
    try {
      await ref.read(adminRepositoryProvider).publishVersion(saved);
      if (!mounted) return;
      setState(() {
        versionPlatform = saved.platform;
        refreshKey++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر بيانات الإصدار.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('تعذر نشر بيانات الإصدار. تحقق من الاتصال وحاول مجدداً.'),
        ),
      );
    }
  }

  bool _isValidWhatsapp(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 8 && digits.length <= 15;
  }
}

class _SettingsLoadError extends StatelessWidget {
  const _SettingsLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 52),
            const SizedBox(height: 12),
            Text(
              'تعذر تحميل الإعدادات',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text('تحقق من الاتصال بالخادم ثم أعد المحاولة.'),
            const SizedBox(height: 14),
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

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(
              width: 160,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}
