import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/concurrency/stale_write.dart';
import '../../core/config/app_config.dart';
import '../../core/config/shop_branding.dart';
import '../../core/config/shop_branding_cache.dart';
import '../../core/refresh/screen_reload.dart';
import '../../core/theme/app_theme.dart';
import '../../core/updates/update_link.dart';
import '../../core/widgets/shop_brand_logo.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/admin_models.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/product_images_repository.dart';
import '../admin_dashboard/admin_shell.dart';
import 'admin_data_mode_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int refreshKey = 0;
  late Future<AppSettingsData> _settingsFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _settingsFuture = ref.read(adminRepositoryProvider).settings();
  }

  Future<void> _reloadSettings() async {
    final next = ref.read(adminRepositoryProvider).settings();
    setState(() {
      refreshKey++;
      _settingsFuture = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder shows the load error.
    }
  }

  @override
  Widget build(BuildContext context) {
    listenForScreenReload(ref, _reloadSettings);
    return AdminShell(
      title: 'الإعدادات والتحديثات',
      actions: [
        IconButton(
          tooltip: 'تحديث الإعدادات',
          icon: const Icon(Icons.refresh),
          onPressed: _reloadSettings,
        ),
      ],
      child: FutureBuilder<AppSettingsData>(
        key: ValueKey(refreshKey),
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ShopLoading.page();
          }
          if (snapshot.hasError) {
            return _SettingsLoadError(
              onRetry: _reloadSettings,
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
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ShopBrandLogo(
                              key: const Key('store-settings-logo-preview'),
                              logoUrl: settings.shopLogoUrl,
                              size: 64,
                              backgroundColor: const Color(0xffe3f3eb),
                              fallbackIconColor: AppTheme.green,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                settings.shopName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _SettingRow(
                            label: 'اسم المتجر', value: settings.shopName),
                        _SettingRow(
                            label: 'شعار المتجر',
                            value: settings.shopLogoUrl.trim().isEmpty
                                ? 'الشعار الافتراضي'
                                : 'مرفوع'),
                        _SettingRow(
                            label: 'واتساب الدعم',
                            value: settings.supportWhatsapp),
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
                onLocalDataReset: () {
                  unawaited(_reloadSettings());
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editSettings(AppSettingsData settings) async {
    if (_saving) return;
    final shop = TextEditingController(text: settings.shopName);
    final whats = TextEditingController(text: settings.supportWhatsapp);
    var maintenance = settings.maintenanceMode;
    var logoUrl = settings.shopLogoUrl;
    var uploadingLogo = false;
    Uint8List? logoPreviewBytes;
    String? logoError;
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
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ShopBrandLogo(
                    key: const Key('store-settings-logo-edit-preview'),
                    logoUrl: logoUrl,
                    logoBytes: logoPreviewBytes,
                    size: 72,
                    backgroundColor: const Color(0xffe3f3eb),
                    fallbackIconColor: AppTheme.green,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('store-settings-logo-upload'),
                        onPressed: uploadingLogo ||
                                !ref
                                    .read(productImagesRepositoryProvider)
                                    .canUpload
                            ? null
                            : () async {
                                setDialogState(() {
                                  uploadingLogo = true;
                                  logoError = null;
                                });
                                try {
                                  final images = ref
                                      .read(productImagesRepositoryProvider);
                                  final picked = await images.pick();
                                  if (picked == null) {
                                    setDialogState(() => uploadingLogo = false);
                                    return;
                                  }
                                  setDialogState(
                                    () => logoPreviewBytes = picked.bytes,
                                  );
                                  final result = await images.uploadPicked(
                                    picked,
                                    folder: ProductImagesRepository.logosFolder,
                                  );
                                  setDialogState(() {
                                    logoUrl = result.publicUrl;
                                    uploadingLogo = false;
                                  });
                                } on ProductImageUploadException catch (error) {
                                  setDialogState(() {
                                    uploadingLogo = false;
                                    logoError = error.message;
                                  });
                                } catch (error) {
                                  setDialogState(() {
                                    uploadingLogo = false;
                                    logoError = mapProductImageUploadError(
                                      error,
                                      folder:
                                          ProductImagesRepository.logosFolder,
                                    ).message;
                                  });
                                }
                              },
                        icon: uploadingLogo
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(
                          uploadingLogo ? 'جارٍ الرفع...' : 'رفع شعار المتجر',
                        ),
                      ),
                      if (logoUrl.trim().isNotEmpty)
                        TextButton(
                          onPressed: uploadingLogo
                              ? null
                              : () => setDialogState(() {
                                    logoUrl = '';
                                    logoPreviewBytes = null;
                                    logoError = null;
                                  }),
                          child: const Text('إزالة الشعار'),
                        ),
                    ],
                  ),
                ),
                if (AppConfig.isDemoMode ||
                    !ref.read(productImagesRepositoryProvider).canUpload) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      AppConfig.isDemoMode
                          ? 'رفع الشعار غير متاح في الوضع التجريبي. يُحفظ اسم المتجر محلياً لهذه الجلسة.'
                          : 'رفع الشعار يحتاج ربط Supabase وتسجيل دخول إداري.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
                if (logoError != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      logoError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                    controller: whats,
                    decoration:
                        const InputDecoration(labelText: 'واتساب الدعم')),
                const SizedBox(height: 10),
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
                final rawWhatsapp = whats.text.trim();
                final validWhatsapp =
                    rawWhatsapp.isEmpty || _isValidWhatsapp(rawWhatsapp);
                final rawLogo = logoUrl.trim();
                final validLogo = rawLogo.isEmpty ||
                    safeHttpsUpdateUri(rawLogo) != null;
                if (shop.text.trim().isEmpty ||
                    !validWhatsapp ||
                    !validLogo) {
                  setDialogState(() {
                    validationMessage =
                        'أدخل اسم المتجر ورقم واتساب صحيحاً، '
                        'واستخدم روابط HTTPS فقط للشعار.';
                  });
                  return;
                }
                Navigator.pop(
                  context,
                  settings.copyWith(
                    shopName: shop.text.trim(),
                    shopLogoUrl: rawLogo,
                    supportWhatsapp: rawWhatsapp,
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
    ]) {
      controller.dispose();
    }
    if (saved == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).saveSettings(saved);
      ShopBrandingCache.rememberSaved(ShopBranding.fromSettings(saved));
      ref.invalidate(appSettingsProvider);
      if (mounted) {
        await reloadAfterMutation(this, _reloadSettings);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mutationFailureMessageAr(
              error,
              fallback: 'تعذر حفظ الإعدادات. تحقق من الاتصال وحاول مجدداً.',
            ),
          ),
        ),
      );
      if (error is StaleWriteException) {
        await _reloadSettings();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
