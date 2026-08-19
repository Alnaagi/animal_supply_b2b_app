import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/admin_data_reset_visibility.dart';
import '../../core/config/app_config.dart';
import '../../core/config/app_runtime_mode.dart';
import '../../core/refresh/screen_reload.dart';
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

enum AdminResetTarget { demoLocal, localCache, productionRemote }

class AdminDataModeCard extends ConsumerWidget {
  const AdminDataModeCard({
    super.key,
    this.onLocalDataReset,
    this.visibilityOverride,
  });

  final VoidCallback? onLocalDataReset;
  final AdminDataResetVisibility? visibilityOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferLocalDemo = ref.watch(appRuntimeModeProvider);
    final demoMode = AppConfig.isDemoMode || preferLocalDemo;
    final canUseProduction = AppConfig.hasInitializedRemoteBackend;
    final visibility = visibilityOverride ??
        AdminDataResetVisibility(
          demoMode: demoMode,
          productionBackendLive: AppConfig.remoteBackendEnabled,
        );
    final demoSwitchOn = canUseProduction ? preferLocalDemo : true;

    return Card(
      key: const Key('admin-data-mode-card'),
      color: visibility.demoMode
          ? const Color(0xfffff4e8)
          : const Color(0xfffff1f1),
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
              visibility.demoMode
                  ? 'البيانات المعروضة الآن تجريبية وغير تشغيلية. '
                      'أي مسح من هنا يطال هذا الجهاز فقط، وليس خادم الإنتاج.'
                  : 'التطبيق متصل ببيانات التشغيل. مسح قاعدة البيانات الحقيقية '
                      'يحذف بيانات المتجر على الخادم بعد تأكيد مزدوج، '
                      'والعملية لا رجعة فيها.',
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
                    : visibility.demoMode
                        ? 'مفعل: الكتالوج والطلبات والإعدادات هنا محلية للتجربة، '
                            'وليست عمليات حقيقية.'
                        : 'متوقف: تعرض الشاشات بيانات الخادم حسب صلاحيات حسابك.',
              ),
            ),
            if (visibility.showDemoLocalReset) ...[
              const Divider(height: 28),
              _ResetActionBlock(
                title: 'مسح البيانات التجريبية',
                warning:
                    'تحذير لا رجعة فيه: سيتم مسح البيانات التجريبية المحلية '
                    'والكاش وطابور المزامنة على هذا الجهاز. خادم الإنتاج غير '
                    'مستهدف ولن يُمسح من التطبيق.',
                buttonKey: const Key('admin-local-reset-button'),
                buttonLabel: 'مسح البيانات التجريبية',
                onPressed: () => _confirmAndReset(
                  context,
                  ref,
                  AdminResetTarget.demoLocal,
                ),
              ),
            ],
            if (visibility.showProductionRemoteReset) ...[
              const Divider(height: 28),
              _ResetActionBlock(
                title: 'مسح قاعدة البيانات الحقيقية',
                warning:
                    'تحذير لا رجعة فيه على الخادم: بعد التأكيد ستُحذف المنتجات '
                    'والتصنيفات والطلبات والعملاء وحساباتهم والبنرات والمخزون '
                    'والدعوات والإشعارات من قاعدة التشغيل. حسابك الإداري الحالي '
                    'وإعدادات المتجر وسجل التدقيق وإصدارات التطبيق لن تُحذف. '
                    'لا يوجد مفتاح خدمة داخل التطبيق؛ العملية تتم عبر دالة خادم '
                    'محمية للمدير فقط. لا يمكن استرجاع البيانات بعد المسح.',
                buttonKey: const Key('admin-production-reset-button'),
                buttonLabel: 'مسح قاعدة البيانات الحقيقية',
                onPressed: () => _confirmAndReset(
                  context,
                  ref,
                  AdminResetTarget.productionRemote,
                ),
              ),
            ],
            if (visibility.showLocalCacheOnlyReset) ...[
              const SizedBox(height: 18),
              _ResetActionBlock(
                title: 'مسح التخزين المحلي فقط',
                warning:
                    'هذا أضعف خطراً: يُحذف الكاش وطابور المزامنة على هذا الجهاز '
                    'فقط. قاعدة بيانات الإنتاج لن تُمس.',
                buttonKey: const Key('admin-local-cache-reset-button'),
                buttonLabel: 'مسح التخزين المحلي فقط',
                filled: false,
                onPressed: () => _confirmAndReset(
                  context,
                  ref,
                  AdminResetTarget.localCache,
                ),
              ),
            ],
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

    final result =
        await ref.read(appRuntimeModeProvider.notifier).setPreferLocalDemo(
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
    WidgetRef ref,
    AdminResetTarget target,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AdminResetConfirmDialog(target: target),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      if (target == AdminResetTarget.productionRemote) {
        await ref
            .read(adminRepositoryProvider)
            .resetProductionApplicationData();
      }
      await LocalDeviceDataReset(
        cache: ref.read(localCacheProvider),
        outbox: ref.read(syncOutboxProvider),
      ).wipeLocalDemoCacheAndOutbox();
      invalidateAdminDataProviders(ref);
      onLocalDataReset?.call();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_successMessage(target))),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(target))),
      );
    }
  }

  String _successMessage(AdminResetTarget target) {
    return switch (target) {
      AdminResetTarget.demoLocal =>
        'تم مسح البيانات التجريبية المحلية والكاش والطابور.',
      AdminResetTarget.localCache =>
        'تم مسح التخزين المحلي على هذا الجهاز. قاعدة بيانات الإنتاج لم تُمس.',
      AdminResetTarget.productionRemote =>
        'تم مسح بيانات التشغيل على الخادم. حسابك الإداري لم يُحذف. '
            'العملية لا رجعة فيها.',
    };
  }

  String _failureMessage(AdminResetTarget target) {
    return switch (target) {
      AdminResetTarget.productionRemote =>
        'تعذر مسح قاعدة البيانات الحقيقية. تحقق من صلاحيات المدير والاتصال.',
      AdminResetTarget.demoLocal ||
      AdminResetTarget.localCache =>
        'تعذر مسح البيانات المحلية. حاول مرة أخرى.',
    };
  }
}

class _ResetActionBlock extends StatelessWidget {
  const _ResetActionBlock({
    required this.title,
    required this.warning,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
    this.filled = true,
  });

  final String title;
  final String warning;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: AppTheme.red,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          warning,
          style: TextStyle(
            color: Colors.red.shade900,
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        if (filled)
          FilledButton.icon(
            key: buttonKey,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.red,
              foregroundColor: Colors.white,
            ),
            onPressed: onPressed,
            icon: const Icon(Icons.delete_forever),
            label: Text(buttonLabel),
          )
        else
          OutlinedButton.icon(
            key: buttonKey,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.red,
              side: const BorderSide(color: AppTheme.red),
            ),
            onPressed: onPressed,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(buttonLabel),
          ),
      ],
    );
  }
}

class _AdminResetConfirmDialog extends ConsumerStatefulWidget {
  const _AdminResetConfirmDialog({required this.target});

  final AdminResetTarget target;

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

  String get _dialogWarning {
    return switch (widget.target) {
      AdminResetTarget.demoLocal =>
        'سيتم مسح البيانات التجريبية والكاش والطابور على '
            'هذا الجهاز بشكل لا رجعة فيه. خادم الإنتاج لن يُمسح.',
      AdminResetTarget.localCache =>
        'هذا لا يمسح قاعدة بيانات الإنتاج. بعد التأكيد '
            'سيُحذف الكاش وطابور المزامنة على هذا الجهاز فقط. '
            'العملية لا رجعة فيها محلياً.',
      AdminResetTarget.productionRemote =>
        'تحذير لا رجعة فيه: ستُحذف بيانات التشغيل على الخادم '
            '(منتجات، طلبات، عملاء، بنرات، مخزون، دعوات، إشعارات). '
            'حسابك الإداري الحالي لن يُحذف. لا يمكن التراجع.',
    };
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
                  _dialogWarning,
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
  requestScreenReload(ref);
}
