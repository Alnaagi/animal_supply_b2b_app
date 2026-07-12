import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../admin_dashboard/admin_shell.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'الإعدادات والتحديثات',
      child: FutureBuilder<AppSettingsData>(
        key: ValueKey(refreshKey),
        future: ref.read(adminRepositoryProvider).settings(),
        builder: (context, snapshot) {
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
                            label: 'رابط تحميل التطبيق',
                            value: settings.downloadLink),
                        _SettingRow(label: 'رابط APK', value: settings.apkLink),
                        _SettingRow(
                            label: 'سياسة التوصيل',
                            value: settings.deliveryPolicy),
                        _SettingRow(
                            label: 'الحد الأدنى للطلب',
                            value: lyd(settings.minimumOrderAmount)),
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
              FutureBuilder<AppVersionInfo>(
                future: ref.read(adminRepositoryProvider).latestVersion(),
                builder: (context, versionSnapshot) {
                  final version = versionSnapshot.data ??
                      AppVersionInfo(apkUrl: settings.apkLink);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.system_update_alt,
                                  color: AppTheme.green),
                              SizedBox(width: 8),
                              Text('تحديثات APK و OTA',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20))
                            ]),
                            const SizedBox(height: 10),
                            Text(
                                'آخر إصدار Android: ${version.versionName} (${version.versionCode})'),
                            Text(
                                'نوع التحديث: ${version.required ? 'إجباري' : 'اختياري'}'),
                            Text(version.releaseNotes.isEmpty
                                ? 'لا توجد ملاحظات إصدار.'
                                : version.releaseNotes),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              FilledButton.icon(
                                onPressed: version.apkUrl.isEmpty
                                    ? null
                                    : () => launchUrl(Uri.parse(version.apkUrl),
                                        mode: LaunchMode.externalApplication),
                                icon: const Icon(Icons.download),
                                label: const Text('فتح رابط APK'),
                              ),
                              OutlinedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.flash_on),
                                  label: const Text(
                                      'Shorebird OTA: جاهز للتوثيق')),
                            ]),
                            const SizedBox(height: 10),
                            const Text(
                                'ملاحظة: APK لا يحدّث نفسه بصمت. المستخدم سيؤكد التثبيت، أما إصلاحات Flutter/Dart السريعة فتتم عبر Shorebird بعد إعداده.',
                                style: TextStyle(color: Colors.grey)),
                          ]),
                    ),
                  );
                },
              ),
            ],
          );
        },
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
    var maintenance = settings.maintenanceMode;
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
                    decoration:
                        const InputDecoration(labelText: 'رابط تحميل التطبيق')),
                const SizedBox(height: 10),
                TextField(
                    controller: apk,
                    decoration: const InputDecoration(labelText: 'رابط APK')),
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
                SwitchListTile(
                    value: maintenance,
                    onChanged: (value) =>
                        setDialogState(() => maintenance = value),
                    title: const Text('وضع الصيانة placeholder')),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                AppSettingsData(
                  shopName: shop.text.trim(),
                  supportWhatsapp: whats.text.trim(),
                  downloadLink: download.text.trim(),
                  apkLink: apk.text.trim(),
                  deliveryPolicy: delivery.text.trim(),
                  minimumOrderAmount: double.tryParse(minimum.text) ?? 0,
                  maintenanceMode: maintenance,
                ),
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [shop, whats, download, apk, delivery, minimum]) {
      controller.dispose();
    }
    if (saved == null) return;
    await ref.read(adminRepositoryProvider).saveSettings(saved);
    setState(() => refreshKey++);
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
