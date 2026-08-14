import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
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
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(user.businessName ?? user.username),
                    subtitle: const Text(
                      'سيستخدم عنوان العميل التجاري المسجل إذا تركت العنوان الإضافي فارغاً.',
                    ),
                  ),
                ),
                if (settings == null) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: settingsAsync.hasError
                        ? Theme.of(context).colorScheme.errorContainer
                        : Colors.amber.shade50,
                    child: ListTile(
                      leading: settingsAsync.hasError
                          ? const Icon(Icons.cloud_off_outlined)
                          : const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
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
                ],
                if (maintenanceMode) ...[
                  const SizedBox(height: 10),
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
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: deliveryAddress,
                  enabled: !submitting,
                  minLines: 2,
                  maxLines: 3,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.location_on_outlined),
                    labelText: 'عنوان تسليم إضافي (اختياري)',
                    hintText: 'مثال: طرابلس - حي الأندلس - اسم الشارع',
                  ),
                ),
                const SizedBox(height: 12),
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
                  for (final item in items)
                    Card(
                      child: ListTile(
                        title: Text(item.productName),
                        subtitle: Text(
                          '${item.quantity} × ${lyd(item.unitPrice)}'
                          '${item.unitsPerBox == null ? '' : ' • ${item.unitsPerBox} قطعة في الصندوق'}',
                        ),
                        trailing: Text(lyd(item.lineTotal)),
                      ),
                    ),
                const SizedBox(height: 4),
                TextField(
                  controller: note,
                  enabled: !submitting,
                  minLines: 3,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.notes_outlined),
                    labelText: 'ملاحظة العميل (اختيارية)',
                  ),
                ),
                const SizedBox(height: 12),
                if (settings != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _CheckoutTotalRow(
                            label: 'الإجمالي الفرعي التقديري',
                            value: lyd(pricing.subtotal),
                          ),
                          if (pricing.deliveryFee > 0)
                            _CheckoutTotalRow(
                              label: 'توصيل تقديري',
                              value: lyd(pricing.deliveryFee),
                            ),
                          if (pricing.handlingFee > 0)
                            _CheckoutTotalRow(
                              label: 'مناولة تقديرية',
                              value: lyd(pricing.handlingFee),
                            ),
                          const Divider(),
                          _CheckoutTotalRow(
                            label: 'الإجمالي التقديري',
                            value: lyd(pricing.total),
                            bold: true,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'السعر والرسوم النهائية يعتمدها الخادم حسب حساب العميل والمخزون.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          if (!meetsMinimum) ...[
                            const SizedBox(height: 10),
                            Text(
                              'الحد الأدنى للطلب ${lyd(minimumOrderAmount)}. '
                              'أضف منتجات بقيمة تقديرية ${lyd(pricing.amountNeededForMinimum(minimumOrderAmount))}.',
                              textAlign: TextAlign.center,
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
                if (error case final message?) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('checkout-submit-button'),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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

class _CheckoutTotalRow extends StatelessWidget {
  const _CheckoutTotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style =
        TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}
