import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/app_runtime_mode.dart';
import '../../core/security/destructive_confirm_phrase.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/local_cache.dart';
import '../../data/local/local_device_data_reset.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../../data/repositories/product_images_repository.dart';
import '../../data/sync/sync_outbox.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_controller.dart';

class AdminDataModeCard extends ConsumerWidget {
  const AdminDataModeCard({super.key, this.onLocalDataReset});

  final VoidCallback? onLocalDataReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferLocalDemo = ref.watch(appRuntimeModeProvider);
    final demoMode = AppConfig.isDemoMode || preferLocalDemo;
    final canUseProduction = AppConfig.hasInitializedRemoteBackend;
    final productionResetGated = AppConfig.remoteBackendEnabled;
    final demoSwitchOn = canUseProduction ? preferLocalDemo : true;

    return Card(
      key: const Key('admin-data-mode-card'),
      color: demoMode ? const Color(0xfffff4e8) : const Color(0xfffff1f1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppTheme.red),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الوضع التجريبي وبيانات الجهاز',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              demoMode
                  ? 'البيانات المعروضة الآن تجريبية وغير تشغيلية. '
                      'أي مسح من هنا يطال هذا الجهاز فقط، وليس خادم الإنتاج.'
                  : 'التطبيق متصل ببيانات التشغيل. مسح قاعدة البيانات الحقيقية '
                      'غير متاح من التطبيق وهو إجراء تشغيلي على الخادم فقط.',
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.45),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('admin-demo-mode-switch'),
              contentPadding: EdgeInsets.zero,
              value: demoSwitchOn,
              onChanged: canUseProduction
                  ? (value) => _onDemoSwitchChanged(
                        context,
                        ref,
                        enableDemo: value,
                        currentlyDemo: preferLocalDemo,
                        canUseProduction: canUseProduction,
                      )
                  : null,
              title: const Text(
                'الوضع التجريبي المحلي',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                !canUseProduction
                    ? 'هذه النسخة مبنية للتجربة المحلية أو أن الخادم غير مهيأ. '
                        'لتجربة الإنتاج أعد البناء بـ APP_ENV=production مع '
                        'إعدادات Supabase العامة الصحيحة، دون اختصارات غير آمنة.'
                    : demoMode
                        ? 'مفعل: الكتالوج والطلبات والإعدادات هنا محلية للتجربة، '
                            'وليست عمليات حقيقية.'
                        : 'متوقف: تعرض الشاشات بيانات الخادم حسب صلاحيات حسابك.',
              ),
            ),
            const Divider(height: 28),
            Text(
              productionResetGated
                  ? 'مسح التخزين المحلي فقط'
                  : 'مسح البيانات التجريبية المحلية',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppTheme.red,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              productionResetGated
                  ? 'تحذير لا رجعة فيه على هذا الجهاز: لن تُمسح قاعدة بيانات '
                      'الإنتاج. لا يوجد مفتاح خدمة داخل التطبيق، ومسح قاعدة '
                      'البيانات الحقيقية يتم من الخادم/عمليات التشغيل فقط. '
                      'بعد التأكيد سيُحذف الكاش وطابور المزامنة المحليان فقط.'
                  : 'تحذير لا رجعة فيه: سيتم مسح البيانات التجريبية المحلية '
                      'والكاش وطابور المزامنة على هذا الجهاز. خادم الإنتاج غير '
                      'مستهدف ولن يُمسح من التطبيق.',
              style: TextStyle(
                color: Colors.red.shade900,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('admin-local-reset-button'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _confirmAndReset(
                context,
                ref,
                productionResetGated: productionResetGated,
              ),
              icon: const Icon(Icons.delete_forever),
              label: Text(
                productionResetGated
                    ? 'مسح التخزين المحلي فقط'
                    : 'مسح البيانات التجريبية',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDemoSwitchChanged(
    BuildContext context,
    WidgetRef ref, {
    required bool enableDemo,
    required bool currentlyDemo,
    required bool canUseProduction,
  }) async {
    if (enableDemo == currentlyDemo) return;
    if (!enableDemo && !canUseProduction) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppConfig.configurationMessageAr ??
                'الإنتاج غير متاح لأن الخادم غير مهيأ بأمان.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          enableDemo ? 'الانتقال إلى الوضع التجريبي؟' : 'العودة إلى الإنتاج؟',
        ),
        content: Text(
          enableDemo
              ? 'ستُعرض بيانات تجريبية محلية غير تشغيلية للاختبار. '
                  'بيانات العملاء والطلبات على الخادم لن تُحذف. '
                  'ستظهر شاشات التجربة وقد يتحول الحساب إلى مدير تجريبي.'
              : 'ستعود الشاشات إلى بيانات الخادم الحقيقية حسب صلاحياتك. '
                  'لا تستخدم هذا الوضع للتجربة العشوائية على بيانات التشغيل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(enableDemo ? 'تفعيل التجربة' : 'العودة للإنتاج'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(appRuntimeModeProvider.notifier)
        .setPreferLocalDemo(
          enableDemo,
          productionBackendAvailable: canUseProduction,
        );
    if (!result.applied) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.messageAr ?? 'تعذر تغيير الوضع.',
          ),
        ),
      );
      return;
    }

    final auth = ref.read(authControllerProvider.notifier);
    if (enableDemo) {
      await auth.enterLocalDemoSession();
    } else {
      await auth.rebindAfterRuntimeModeChange();
    }
    invalidateAdminDataProviders(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enableDemo
              ? 'تم تفعيل الوضع التجريبي المحلي. البيانات غير تشغيلية.'
              : 'تم العودة إلى وضع الإنتاج. راقب أنك تعمل على بيانات حقيقية.',
        ),
      ),
    );
  }

  Future<void> _confirmAndReset(
    BuildContext context,
    WidgetRef ref, {
    required bool productionResetGated,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AdminResetConfirmDialog(
        productionResetGated: productionResetGated,
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await LocalDeviceDataReset(
        cache: ref.read(localCacheProvider),
        outbox: ref.read(syncOutboxProvider),
      ).wipeLocalDemoCacheAndOutbox();
      invalidateAdminDataProviders(ref);
      onLocalDataReset?.call();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            productionResetGated
                ? 'تم مسح التخزين المحلي على هذا الجهاز. قاعدة بيانات '
                    'الإنتاج لم تُمس.'
                : 'تم مسح البيانات التجريبية المحلية والكاش والطابور.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر مسح البيانات المحلية. حاول مرة أخرى.'),
        ),
      );
    }
  }
}

class _AdminResetConfirmDialog extends ConsumerStatefulWidget {
  const _AdminResetConfirmDialog({required this.productionResetGated});

  final bool productionResetGated;

  @override
  ConsumerState<_AdminResetConfirmDialog> createState() =>
      _AdminResetConfirmDialogState();
}

class _AdminResetConfirmDialogState
    extends ConsumerState<_AdminResetConfirmDialog> {
  late final TextEditingController _password;
  late final TextEditingController _phrase;
  String? _error;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController();
    _phrase = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phraseError =
        DestructiveConfirmPhrase.validationMessage(_phrase.text);
    if (phraseError != null) {
      setState(() => _error = phraseError);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final passwordError = await ref
        .read(authControllerProvider.notifier)
        .verifyCurrentPassword(_password.text);
    if (!mounted) return;
    if (passwordError != null) {
      setState(() {
        _submitting = false;
        _error = passwordError;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تأكيد عملية مسح خطرة'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.red),
                ),
                child: Text(
                  widget.productionResetGated
                      ? 'هذا لا يمسح قاعدة بيانات الإنتاج. بعد التأكيد '
                          'سيُحذف الكاش وطابور المزامنة على هذا الجهاز فقط. '
                          'العملية لا رجعة فيها محلياً.'
                      : 'سيتم مسح البيانات التجريبية والكاش والطابور على '
                          'هذا الجهاز بشكل لا رجعة فيه. خادم الإنتاج لن يُمسح.',
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('admin-reset-password'),
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة مرور حساب الإدارة',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('admin-reset-confirm-phrase'),
                controller: _phrase,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'عبارة التأكيد: RESET',
                  helperText: DestructiveConfirmPhrase.instructionsAr,
                  helperMaxLines: 3,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
          onPressed: _submitting ? null : _submit,
          child: const Text('نعم، امسح'),
        ),
      ],
    );
  }
}

void invalidateAdminDataProviders(WidgetRef ref) {
  ref.invalidate(localCacheProvider);
  ref.invalidate(syncOutboxProvider);
  ref.invalidate(catalogRepositoryProvider);
  ref.invalidate(ordersRepositoryProvider);
  ref.invalidate(adminRepositoryProvider);
  ref.invalidate(notificationsRepositoryProvider);
  ref.invalidate(productImagesRepositoryProvider);
  ref.invalidate(appSettingsProvider);
  ref.invalidate(unreadNotificationsCountProvider);
  ref.invalidate(cartControllerProvider);
}
