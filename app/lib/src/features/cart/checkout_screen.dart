import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/refresh/screen_reload.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/order.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import 'cart_controller.dart';

const _checkoutDesktopBreakpoint = 1024.0;
const _checkoutDesktopMaxWidth = 1280.0;
const _checkoutDesktopSummaryWidth = 380.0;

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
    final isDesktop =
        MediaQuery.sizeOf(context).width >= _checkoutDesktopBreakpoint;
    final registeredAddress = [
      user?.city?.trim(),
      user?.area?.trim(),
      user?.address?.trim(),
    ].whereType<String>().where((part) => part.isNotEmpty).join(' - ');

    final appBar = AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'رجوع',
        onPressed: submitting ? null : () => context.go('/cart'),
      ),
      title: const Text('تأكيد الطلب'),
    );
    if (user == null) {
      return Scaffold(
        appBar: appBar,
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'انتهت جلسة الدخول. ارجع إلى صفحة الدخول ثم حاول مجدداً.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final Widget? settingsNotice = settings == null
        ? Card(
            color: settingsAsync.hasError
                ? scheme.errorContainer
                : scheme.tertiaryContainer,
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
                      onPressed: () => ref.invalidate(appSettingsProvider),
                      icon: const Icon(Icons.refresh),
                    )
                  : null,
            ),
          )
        : null;
    final Widget? maintenanceNotice = maintenanceMode
        ? Card(
            key: const Key('checkout-maintenance-notice'),
            color: scheme.tertiaryContainer,
            child: const ListTile(
              leading: Icon(Icons.build_circle_outlined),
              title: Text('الطلبات متوقفة مؤقتاً للصيانة'),
              subtitle: Text(
                'يمكنك مراجعة التفاصيل، لكن إرسال الطلب سيبقى متوقفاً حتى انتهاء الصيانة.',
              ),
            ),
          )
        : null;
    final deliveryControls = _CheckoutDeliveryControls(
      deliveryAddress: deliveryAddress,
      note: note,
      registeredAddress: registeredAddress,
      enabled: !submitting,
      onChanged: () => setState(() {}),
    );
    final productReview = items.isEmpty
        ? Card(
            color: scheme.tertiaryContainer,
            child: const ListTile(
              leading: Icon(Icons.shopping_cart_outlined),
              title: Text('السلة فارغة'),
              subtitle: Text('ارجع إلى الكتالوج وأضف المنتجات قبل الإرسال.'),
            ),
          )
        : Card(
            key: const Key('checkout-products-card'),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            color: scheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _CheckoutProductRow(item: items[i]),
                ],
              ],
            ),
          );
    final Widget? totals = settings == null
        ? null
        : _CheckoutTotalsCard(
            pricing: pricing,
            minimumOrderAmount: minimumOrderAmount,
            meetsMinimum: meetsMinimum,
            detailed: isDesktop,
          );
    final errorMessage = error;
    final Widget? errorNotice = errorMessage == null
        ? null
        : Material(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: scheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      errorMessage,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          );
    final submitButton = FilledButton.icon(
      key: const Key('checkout-submit-button'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.surfaceContainerHighest,
        disabledForegroundColor: scheme.onSurfaceVariant,
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
        elevation: isDesktop ? 0 : 2,
        shadowColor: scheme.shadow.withValues(alpha: 0.2),
      ),
      onPressed: items.isEmpty ||
              submitting ||
              settings == null ||
              maintenanceMode ||
              !meetsMinimum
          ? null
          : _submitOrder,
      icon: submitting
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onPrimary,
              ),
            )
          : const Icon(Icons.send_outlined),
      label: Text(submitting ? 'جارٍ اعتماد الطلب...' : 'إرسال الطلب'),
    );
    final Widget? emptyCartAction = items.isEmpty
        ? OutlinedButton(
            onPressed: submitting ? null : () => context.go('/catalog'),
            child: const Text('العودة إلى المنتجات'),
          )
        : null;

    if (!isDesktop) {
      return Scaffold(
        appBar: appBar,
        body: ListView(
          key: const Key('checkout-mobile-layout'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            if (settingsNotice != null) ...[
              settingsNotice,
              const SizedBox(height: 12),
            ],
            if (maintenanceNotice != null) ...[
              maintenanceNotice,
              const SizedBox(height: 12),
            ],
            deliveryControls,
            const SizedBox(height: 12),
            productReview,
            if (totals != null) ...[
              const SizedBox(height: 10),
              totals,
            ],
            if (errorNotice != null) ...[
              const SizedBox(height: 12),
              errorNotice,
            ],
            const SizedBox(height: 16),
            submitButton,
            if (emptyCartAction != null) ...[
              const SizedBox(height: 8),
              emptyCartAction,
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            key: const Key('checkout-desktop-layout'),
            constraints: const BoxConstraints(
              maxWidth: _checkoutDesktopMaxWidth,
            ),
            child: SizedBox(
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: const Key('checkout-desktop-main'),
                        child: ListView(
                          key: const Key('checkout-desktop-main-scroll'),
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            if (settingsNotice != null) ...[
                              settingsNotice,
                              const SizedBox(height: 12),
                            ],
                            if (maintenanceNotice != null) ...[
                              maintenanceNotice,
                              const SizedBox(height: 12),
                            ],
                            deliveryControls,
                            const SizedBox(height: 12),
                            productReview,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: _checkoutDesktopSummaryWidth,
                      child: SingleChildScrollView(
                        key: const Key('checkout-desktop-summary-scroll'),
                        child: KeyedSubtree(
                          key: const Key('checkout-desktop-summary'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (totals != null) totals,
                              if (errorNotice != null) ...[
                                if (totals != null) const SizedBox(height: 12),
                                errorNotice,
                              ],
                              const SizedBox(height: 16),
                              submitButton,
                              if (emptyCartAction != null) ...[
                                const SizedBox(height: 8),
                                emptyCartAction,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

      await Clipboard.setData(ClipboardData(text: summary));
      requestScreenReload(ref);
      if (mounted) {
        final destination = Uri(
          path: '/orders',
          queryParameters: {
            'order': order.id,
            'success': '1',
          },
        ).toString();
        context.replace(destination);
      }
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

class _CheckoutDeliveryControls extends StatelessWidget {
  const _CheckoutDeliveryControls({
    required this.deliveryAddress,
    required this.note,
    required this.registeredAddress,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController deliveryAddress;
  final TextEditingController note;
  final String registeredAddress;
  final bool enabled;
  final VoidCallback onChanged;

  String get _registeredAddressLabel => registeredAddress.isEmpty
      ? 'العنوان المحفوظ في حساب المتجر'
      : registeredAddress;

  Future<void> _showAddressPicker(BuildContext context) async {
    final selectedAddress = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CheckoutAddressPickerSheet(
        initialCustomAddress: deliveryAddress.text.trim(),
        registeredAddressLabel: _registeredAddressLabel,
      ),
    );

    if (selectedAddress == null) return;
    deliveryAddress.value = TextEditingValue(
      text: selectedAddress,
      selection: TextSelection.collapsed(offset: selectedAddress.length),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final customAddress = deliveryAddress.text.trim();
    final usesRegisteredAddress = customAddress.isEmpty;
    return Column(
      key: const Key('checkout-editable-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          key: const Key('checkout-address-selector'),
          color: scheme.surfaceContainerLowest,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.primary.withValues(alpha: 0.28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => _showAddressPicker(context) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.location_on_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          usesRegisteredAddress
                              ? 'عنوان المتجر المسجل'
                              : 'عنوان تسليم آخر',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          usesRegisteredAddress
                              ? _registeredAddressLabel
                              : customAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'تغيير',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_left,
                    color: scheme.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('checkout-customer-note'),
          controller: note,
          enabled: enabled,
          minLines: 2,
          maxLines: 3,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: 'ملاحظة للطلب (اختيارية)',
            hintText: 'وقت الاستلام المفضل أو تعليمات للمندوب',
            alignLabelWithHint: true,
            filled: true,
            fillColor: scheme.secondaryContainer,
            prefixIcon: Icon(
              Icons.edit_note_outlined,
              color: scheme.onSecondaryContainer,
            ),
            suffixIcon: note.text.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'مسح الملاحظة',
                    onPressed: enabled
                        ? () {
                            note.clear();
                            onChanged();
                          }
                        : null,
                    icon: const Icon(Icons.clear, size: 20),
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: scheme.secondary,
                width: 1.4,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: scheme.secondary,
                width: 1.4,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: scheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckoutAddressPickerSheet extends StatefulWidget {
  const _CheckoutAddressPickerSheet({
    required this.initialCustomAddress,
    required this.registeredAddressLabel,
  });

  final String initialCustomAddress;
  final String registeredAddressLabel;

  @override
  State<_CheckoutAddressPickerSheet> createState() =>
      _CheckoutAddressPickerSheetState();
}

class _CheckoutAddressPickerSheetState
    extends State<_CheckoutAddressPickerSheet> {
  late final TextEditingController customAddress;
  late bool useRegisteredAddress;

  @override
  void initState() {
    super.initState();
    customAddress = TextEditingController(text: widget.initialCustomAddress);
    useRegisteredAddress = customAddress.text.trim().isEmpty;
  }

  @override
  void dispose() {
    customAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final customIsValid = customAddress.text.trim().isNotEmpty;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        18,
        10,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'اختر عنوان التسليم',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _AddressChoice(
            key: const Key('checkout-address-registered-option'),
            selected: useRegisteredAddress,
            title: 'عنوان المتجر المسجل',
            subtitle: widget.registeredAddressLabel,
            onTap: () => setState(() => useRegisteredAddress = true),
          ),
          const SizedBox(height: 10),
          _AddressChoice(
            key: const Key('checkout-address-custom-option'),
            selected: !useRegisteredAddress,
            title: 'عنوان تسليم آخر',
            subtitle: customIsValid
                ? customAddress.text.trim()
                : 'أدخل عنواناً مختلفاً لهذا الطلب',
            onTap: () => setState(() => useRegisteredAddress = false),
          ),
          if (!useRegisteredAddress) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('checkout-delivery-address'),
              controller: customAddress,
              autofocus: true,
              minLines: 2,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'عنوان التسليم',
                hintText: 'مثال: طرابلس - حي الأندلس - اسم الشارع',
                filled: true,
                fillColor: scheme.surfaceContainerLowest,
                prefixIcon: Icon(
                  Icons.location_on_outlined,
                  color: scheme.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: scheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('checkout-address-apply'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            onPressed: useRegisteredAddress || customIsValid
                ? () => Navigator.of(context).pop(
                      useRegisteredAddress ? '' : customAddress.text.trim(),
                    )
                : null,
            child: const Text('اعتماد العنوان'),
          ),
        ],
      ),
    );
  }
}

class _AddressChoice extends StatelessWidget {
  const _AddressChoice({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutProductRow extends StatelessWidget {
  const _CheckoutProductRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 64,
            child: ProductImagePlaceholder(
              key: ValueKey('checkout-product-image-${item.product.id}'),
              category: item.product.category,
              productId: item.product.id,
              imageUrl: item.product.imageUrl,
              expand: true,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.quantity} × ${lyd(item.unitPrice)}'
                  '${item.unitsPerBox == null ? '' : ' • ${item.unitsPerBox} قطعة في الصندوق'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            lyd(item.lineTotal),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutTotalsCard extends StatelessWidget {
  const _CheckoutTotalsCard({
    required this.pricing,
    required this.minimumOrderAmount,
    required this.meetsMinimum,
    this.detailed = false,
  });

  final CartPricingSummary pricing;
  final double minimumOrderAmount;
  final bool meetsMinimum;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSupplementalEstimates =
        pricing.deliveryFee > 0 || pricing.handlingFee > 0;
    return Material(
      key: const Key('checkout-totals-card'),
      color: scheme.primary,
      elevation: 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          children: [
            if (detailed) ...[
              Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    color: scheme.onPrimary,
                    size: 22,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'ملخص الطلب',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CheckoutTotalRow(
                label: 'الإجمالي الفرعي',
                value: lyd(pricing.subtotal),
              ),
            ],
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
            if (hasSupplementalEstimates)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  color: scheme.onPrimary.withValues(alpha: 0.22),
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
                color: scheme.onPrimary.withValues(alpha: 0.78),
                fontSize: 12,
              ),
            ),
            if (!meetsMinimum) ...[
              const SizedBox(height: 10),
              Text(
                'الحد الأدنى للطلب ${lyd(minimumOrderAmount)}. '
                'أضف منتجات بقيمة تقديرية ${lyd(pricing.amountNeededForMinimum(minimumOrderAmount))}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onPrimary,
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
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final style = TextStyle(
      color: muted ? onPrimary.withValues(alpha: 0.82) : onPrimary,
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
