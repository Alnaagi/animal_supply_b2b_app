import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/refresh/screen_reload.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/order.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import 'cart_controller.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final note = TextEditingController();
  final deliveryAddress = TextEditingController();
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    note.dispose();
    deliveryAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.asData?.value;
    final pricing = CartPricingSummary.estimate(
      items,
      handlingFee: settings?.handlingFee ?? 0,
      deliveryFee: settings?.deliveryFee ?? 0,
    );
    final minimumOrderAmount = settings?.minimumOrderAmount ?? 0;
    final meetsMinimum = pricing.meetsMinimum(minimumOrderAmount);
    final maintenanceMode = settings?.maintenanceMode ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: submitting ? null : () => context.go('/cart'),
        ),
        title: const Text('تأكيد الطلب'),
      ),
      body: user == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'انتهت جلسة الدخول. ارجع إلى صفحة الدخول ثم حاول مجدداً.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (settings == null) ...[
                  Card(
                    color: settingsAsync.hasError
                        ? scheme.errorContainer
                        : Colors.amber.shade50,
                    child: ListTile(
                      leading: settingsAsync.hasError
                          ? const Icon(Icons.cloud_off_outlined)
                          : const ShopLoading.compact(size: 22),
                      title: Text(
                        settingsAsync.hasError
                            ? 'تعذر تحميل إعدادات الطلب'
                            : 'جارٍ تحميل إعدادات الطلب...',
                      ),
                      subtitle: Text(
                        settingsAsync.hasError
                            ? 'لن نرسل الطلب قبل استرجاع الرسوم والحد الأدنى من الخادم.'
                            : 'سيتم تفعيل زر الإرسال بعد اكتمال الحساب التقديري.',
                      ),
                      trailing: settingsAsync.hasError
                          ? IconButton(
                              tooltip: 'إعادة تحميل إعدادات الطلب',
                              onPressed: () =>
                                  ref.invalidate(appSettingsProvider),
                              icon: const Icon(Icons.refresh),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (maintenanceMode) ...[
                  Card(
                    key: const Key('checkout-maintenance-notice'),
                    color: Colors.amber.shade50,
                    child: const ListTile(
                      leading: Icon(Icons.build_circle_outlined),
                      title: Text('الطلبات متوقفة مؤقتاً للصيانة'),
                      subtitle: Text(
                        'يمكنك مراجعة التفاصيل، لكن إرسال الطلب سيبقى متوقفاً حتى انتهاء الصيانة.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const _CheckoutSectionHeader(
                  icon: Icons.edit_location_alt_outlined,
                  title: 'بيانات التسليم',
                  subtitle: 'عبّئ العنوان والملاحظة قبل مراجعة الطلب.',
                ),
                const SizedBox(height: 10),
                _CheckoutEditableFieldsCard(
                  deliveryAddress: deliveryAddress,
                  note: note,
                  enabled: !submitting,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 20),
                const _CheckoutSectionHeader(
                  icon: Icons.receipt_long_outlined,
                  title: 'مراجعة الطلب',
                  subtitle: 'تأكد من المتجر والمنتجات والإجمالي قبل الإرسال.',
                ),
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.storefront_outlined,
                      color: AppTheme.green,
                    ),
                    title: Text(
                      user.businessName ?? user.username,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'سيستخدم عنوان العميل التجاري المسجل إذا تركت العنوان الإضافي فارغاً.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  Card(
                    color: Colors.amber.shade50,
                    child: const ListTile(
                      leading: Icon(Icons.shopping_cart_outlined),
                      title: Text('السلة فارغة'),
                      subtitle:
                          Text('ارجع إلى الكتالوج وأضف المنتجات قبل الإرسال.'),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            title: Text(
                              items[i].productName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${items[i].quantity} × ${lyd(items[i].unitPrice)}'
                              '${items[i].unitsPerBox == null ? '' : ' • ${items[i].unitsPerBox} قطعة في الصندوق'}',
                            ),
                            trailing: Text(
                              lyd(items[i].lineTotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.darkGreen,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (settings != null) ...[
                  const SizedBox(height: 10),
                  _CheckoutTotalsCard(
                    pricing: pricing,
                    minimumOrderAmount: minimumOrderAmount,
                    meetsMinimum: meetsMinimum,
                  ),
                ],
                if (error case final message?) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: scheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('checkout-submit-button'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: AppTheme.green,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                    elevation: 2,
                    shadowColor: AppTheme.green.withValues(alpha: 0.35),
                  ),
                  onPressed: items.isEmpty ||
                          submitting ||
                          settings == null ||
                          maintenanceMode ||
                          !meetsMinimum
                      ? null
                      : _submitOrder,
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  label:
                      Text(submitting ? 'جارٍ اعتماد الطلب...' : 'إرسال الطلب'),
                ),
                if (items.isEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: submitting ? null : () => context.go('/catalog'),
                    child: const Text('العودة إلى المنتجات'),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _submitOrder() async {
    if (submitting) return;
    final items = ref.read(cartControllerProvider);
    final settings = ref.read(appSettingsProvider).asData?.value;
    if (settings == null) {
      setState(
        () => error =
            'لم تكتمل إعدادات الرسوم والحد الأدنى بعد. أعد تحميل الصفحة ثم حاول مجدداً.',
      );
      return;
    }
    if (settings.maintenanceMode) {
      setState(
        () => error =
            'الطلبات متوقفة مؤقتاً للصيانة. احتفظ بالسلة وحاول بعد انتهاء الصيانة.',
      );
      return;
    }
    final pricing = CartPricingSummary.estimate(
      items,
      handlingFee: settings.handlingFee,
      deliveryFee: settings.deliveryFee,
    );
    final minimumOrderAmount = settings.minimumOrderAmount;
    if (!pricing.meetsMinimum(minimumOrderAmount)) {
      setState(
        () => error =
            'لم يصل الطلب إلى الحد الأدنى ${lyd(minimumOrderAmount)}. أضف منتجات ثم حاول مجدداً.',
      );
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();

    try {
      final order = await ref.read(cartControllerProvider.notifier).submit(
            note: note.text,
            deliveryAddress: deliveryAddress.text,
          );
      final user = ref.read(authControllerProvider).user;
      final summary = ref.read(ordersRepositoryProvider).whatsappSummary(
            order,
            user?.businessName ?? user?.username ?? 'عميل B2B',
          );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تم إرسال الطلب بنجاح'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('رقم الطلب: ${order.displayNumber}'),
              const SizedBox(height: 6),
              Text('الإجمالي المعتمد: ${lyd(order.total)}'),
              if (order.deliveryAddress.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('عنوان التسليم: ${order.deliveryAddress}'),
              ],
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: summary));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('تم نسخ ملخص الطلب')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('نسخ ملخص واتساب'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('عرض الطلب'),
            ),
          ],
        ),
      );
      requestScreenReload(ref);
      if (mounted) context.go('/orders');
    } on OrdersRepositoryException catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.isRetryable
              ? '${exception.message}\n'
                  'السلة والطلب محفوظان لهذا الحساب بانتظار إعادة الإرسال.'
              : exception.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'تعذر إرسال الطلب ولم نتمكن من تأكيد الحفظ الدائم. '
              'قد تبقى السلة في هذه الجلسة فقط؛ لا تغلق التطبيق وحاول من جديد.',
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }
}

class _CheckoutSectionHeader extends StatelessWidget {
  const _CheckoutSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.green, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppTheme.darkGreen,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppTheme.darkGreen.withValues(alpha: 0.7),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckoutEditableFieldsCard extends StatelessWidget {
  const _CheckoutEditableFieldsCard({
    required this.deliveryAddress,
    required this.note,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController deliveryAddress;
  final TextEditingController note;
  final bool enabled;
  final VoidCallback onChanged;

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: AppTheme.green),
      suffixIcon: controller.text.trim().isEmpty
          ? null
          : IconButton(
              tooltip: 'مسح',
              onPressed: enabled
                  ? () {
                      controller.clear();
                      onChanged();
                    }
                  : null,
              icon: const Icon(Icons.clear, size: 20),
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppTheme.green.withValues(alpha: 0.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppTheme.green.withValues(alpha: 0.35)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.green, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('checkout-editable-fields'),
      color: const Color(0xffeef6f1),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: AppTheme.green.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('checkout-delivery-address'),
              controller: deliveryAddress,
              enabled: enabled,
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.next,
              onChanged: (_) => onChanged(),
              decoration: _fieldDecoration(
                label: 'عنوان تسليم إضافي (اختياري)',
                hint: 'مثال: طرابلس - حي الأندلس - اسم الشارع',
                icon: Icons.location_on_outlined,
                controller: deliveryAddress,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'إذا تركته فارغاً يُستخدم عنوان المتجر المسجل تلقائياً.',
              style: TextStyle(
                color: AppTheme.darkGreen.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('checkout-customer-note'),
              controller: note,
              enabled: enabled,
              minLines: 3,
              maxLines: 4,
              onChanged: (_) => onChanged(),
              decoration: _fieldDecoration(
                label: 'ملاحظة العميل (اختيارية)',
                hint: 'مثال: وقت الاستلام المفضل أو تعليمات للمندوب',
                icon: Icons.notes_outlined,
                controller: note,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutTotalsCard extends StatelessWidget {
  const _CheckoutTotalsCard({
    required this.pricing,
    required this.minimumOrderAmount,
    required this.meetsMinimum,
  });

  final CartPricingSummary pricing;
  final double minimumOrderAmount;
  final bool meetsMinimum;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('checkout-totals-card'),
      color: AppTheme.darkGreen,
      elevation: 3,
      shadowColor: AppTheme.darkGreen.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          children: [
            _CheckoutTotalRow(
              label: 'الإجمالي الفرعي التقديري',
              value: lyd(pricing.subtotal),
              muted: true,
            ),
            if (pricing.deliveryFee > 0)
              _CheckoutTotalRow(
                label: 'توصيل تقديري',
                value: lyd(pricing.deliveryFee),
                muted: true,
              ),
            if (pricing.handlingFee > 0)
              _CheckoutTotalRow(
                label: 'مناولة تقديرية',
                value: lyd(pricing.handlingFee),
                muted: true,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            _CheckoutTotalRow(
              label: 'الإجمالي التقديري',
              value: lyd(pricing.total),
              emphasize: true,
            ),
            const SizedBox(height: 10),
            Text(
              'السعر والرسوم النهائية يعتمدها الخادم حسب حساب العميل والمخزون.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 12,
              ),
            ),
            if (!meetsMinimum) ...[
              const SizedBox(height: 10),
              Text(
                'الحد الأدنى للطلب ${lyd(minimumOrderAmount)}. '
                'أضف منتجات بقيمة تقديرية ${lyd(pricing.amountNeededForMinimum(minimumOrderAmount))}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xffffd4a8),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckoutTotalRow extends StatelessWidget {
  const _CheckoutTotalRow({
    required this.label,
    required this.value,
    this.muted = false,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool muted;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: muted
          ? Colors.white.withValues(alpha: 0.82)
          : Colors.white,
      fontWeight: emphasize ? FontWeight.w900 : FontWeight.w600,
      fontSize: emphasize ? 18 : 14,
      letterSpacing: emphasize ? 0.2 : 0,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
