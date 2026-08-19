import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/product_info_chip.dart';
import '../../data/models/product.dart';
import 'admin_product_discount_helpers.dart';

double? parseAdminLocalizedDouble(String value) {
  const easternArabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const westernArabicDigits = '0123456789';
  final buffer = StringBuffer();
  for (final rune in value.trim().runes) {
    final character = String.fromCharCode(rune);
    final digitIndex = easternArabicDigits.indexOf(character);
    if (digitIndex >= 0) {
      buffer.write(westernArabicDigits[digitIndex]);
    } else if (character == '٫' || character == '،' || character == ',') {
      buffer.write('.');
    } else {
      buffer.write(character);
    }
  }
  return double.tryParse(buffer.toString());
}

int? parseAdminLocalizedInt(String value) {
  final parsed = parseAdminLocalizedDouble(value);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed.round();
}

Future<double?> showAdminQuickPriceSheet({
  required BuildContext context,
  required Product product,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AdminQuickPriceSheet(product: product),
  );
}

class _AdminQuickPriceSheet extends StatefulWidget {
  const _AdminQuickPriceSheet({required this.product});

  final Product product;

  @override
  State<_AdminQuickPriceSheet> createState() => _AdminQuickPriceSheetState();
}

class _AdminQuickPriceSheetState extends State<_AdminQuickPriceSheet> {
  late final TextEditingController price;
  String? error;

  @override
  void initState() {
    super.initState();
    price = TextEditingController(
      text: widget.product.basePrice.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = parseAdminLocalizedDouble(price.text);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      setState(() => error = 'أدخل سعراً موجباً صحيحاً.');
      return;
    }
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تعديل السعر • ${widget.product.name}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('admin-quick-price-field'),
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,٫،]')),
            ],
            decoration: InputDecoration(
              labelText: 'السعر الحالي',
              errorText: error,
              suffixText: 'د.ل',
            ),
            autofocus: true,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('admin-quick-price-save'),
            onPressed: _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

Future<double?> showAdminQuickDiscountSheet({
  required BuildContext context,
  required Product product,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AdminQuickDiscountSheet(product: product),
  );
}

class _AdminQuickDiscountSheet extends StatefulWidget {
  const _AdminQuickDiscountSheet({required this.product});

  final Product product;

  @override
  State<_AdminQuickDiscountSheet> createState() =>
      _AdminQuickDiscountSheetState();
}

class _AdminQuickDiscountSheetState extends State<_AdminQuickDiscountSheet> {
  static const presets = [5, 10, 15, 20, 25, 30];

  double? selectedPercent;
  final custom = TextEditingController();
  String? error;

  @override
  void initState() {
    super.initState();
    final existing = widget.product.discountPercent ?? 0;
    if (existing > 0) selectedPercent = existing;
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  double? get _resolvedPercent {
    if (custom.text.trim().isNotEmpty) {
      return parseAdminLocalizedDouble(custom.text);
    }
    return selectedPercent;
  }

  void _apply() {
    final percent = _resolvedPercent;
    if (percent == null || !percent.isFinite || percent <= 0 || percent > 100) {
      setState(() => error = 'اختر أو أدخل نسبة خصم بين 1 و 100.');
      return;
    }
    Navigator.pop(context, percent);
  }

  void _remove() => Navigator.pop(context, 0.0);

  @override
  Widget build(BuildContext context) {
    final previewPercent = _resolvedPercent ?? 0;
    final original = widget.product.effectivePrice ?? widget.product.basePrice;
    final after = discountedPreviewPrice(widget.product, previewPercent);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تعديل الخصم • ${widget.product.name}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in presets)
                  ChoiceChip(
                    key: ValueKey('admin-discount-preset-$preset'),
                    label: Text('$preset%'),
                    selected:
                        selectedPercent == preset && custom.text.trim().isEmpty,
                    onSelected: (_) => setState(() {
                      selectedPercent = preset.toDouble();
                      custom.clear();
                      error = null;
                    }),
                  ),
                ActionChip(
                  key: const ValueKey('admin-discount-custom-chip'),
                  label: const Text('خصم مخصص'),
                  onPressed: () => setState(() {
                    selectedPercent = null;
                    error = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('admin-discount-custom-field'),
              controller: custom,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'خصم مخصص %',
                errorText: error,
              ),
              onChanged: (_) => setState(() => error = null),
            ),
            const SizedBox(height: 12),
            Card(
              color: AppTheme.green.withValues(alpha: .08),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('السعر الأصلي: ${lyd(original)}'),
                    Text('السعر بعد الخصم: ${lyd(after)}'),
                    Text(
                      'الخصم: ${previewPercent > 0 ? '${previewPercent.toStringAsFixed(previewPercent.truncateToDouble() == previewPercent ? 0 : 1)}%' : '—'}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              key: const ValueKey('admin-discount-apply'),
              onPressed: _apply,
              child: Text(
                widget.product.hasProductDiscount
                    ? 'تعديل الخصم'
                    : 'تطبيق الخصم',
              ),
            ),
            if (widget.product.hasProductDiscount) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('admin-discount-remove'),
                onPressed: _remove,
                child: const Text('إلغاء الخصم'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<int?> showAdminQuickStockSheet({
  required BuildContext context,
  required Product product,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AdminQuickStockSheet(product: product),
  );
}

class _AdminQuickStockSheet extends StatefulWidget {
  const _AdminQuickStockSheet({required this.product});

  final Product product;

  @override
  State<_AdminQuickStockSheet> createState() => _AdminQuickStockSheetState();
}

class _AdminQuickStockSheetState extends State<_AdminQuickStockSheet> {
  late int quantity;
  late final TextEditingController field;
  String? error;

  int get _minimum =>
      widget.product.stockTrackingEnabled ? widget.product.reservedQuantity : 0;

  @override
  void initState() {
    super.initState();
    quantity = widget.product.stockQuantity;
    field = TextEditingController(text: quantity.toString());
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  void _adjust(int delta) {
    final next = (quantity + delta).clamp(_minimum, 1000000);
    setState(() {
      quantity = next;
      field.text = next.toString();
      error = null;
    });
  }

  void _save() {
    final parsed = parseAdminLocalizedInt(field.text);
    if (parsed == null || parsed < _minimum) {
      setState(() {
        error = _minimum > 0
            ? 'لا يمكن خفض المخزون عن $_minimum (محجوز).'
            : 'أدخل كمية صحيحة لا تقل عن صفر.';
      });
      return;
    }
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.product.copyWith(
      stockQuantity: quantity,
      availableQuantity: widget.product.stockTrackingEnabled
          ? quantity - widget.product.reservedQuantity
          : null,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تعديل المخزون • ${widget.product.name}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          if (!widget.product.stockTrackingEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'تتبع المخزون معطّل لهذا المنتج. يمكنك ضبط الرقم المرجعي فقط.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StockStepButton(
                key: const ValueKey('admin-stock-minus-10'),
                label: '-10',
                onPressed: () => _adjust(-10),
              ),
              _StockStepButton(
                key: const ValueKey('admin-stock-minus-1'),
                label: '-1',
                onPressed: () => _adjust(-1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 72,
                  child: TextField(
                    key: const ValueKey('admin-stock-quantity-field'),
                    controller: field,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(errorText: error),
                    onChanged: (value) {
                      final parsed = parseAdminLocalizedInt(value);
                      if (parsed != null) {
                        setState(() => quantity = parsed);
                      }
                    },
                  ),
                ),
              ),
              _StockStepButton(
                key: const ValueKey('admin-stock-plus-1'),
                label: '+1',
                onPressed: () => _adjust(1),
              ),
              _StockStepButton(
                key: const ValueKey('admin-stock-plus-10'),
                label: '+10',
                onPressed: () => _adjust(10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: ProductInfoChip(
              adminStockStatusLabel(preview),
              icon: Icons.inventory_2_outlined,
              color: !preview.stockTrackingEnabled
                  ? Colors.blueGrey
                  : !preview.isOrderable
                      ? AppTheme.red
                      : preview.lowStock
                          ? AppTheme.orange
                          : AppTheme.green,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('admin-stock-save'),
            onPressed: _save,
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _StockStepButton extends StatelessWidget {
  const _StockStepButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(label),
      ),
    );
  }
}

Future<double?> showAdminBulkDiscountSheet({
  required BuildContext context,
  required int productCount,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AdminBulkDiscountSheet(productCount: productCount),
  );
}

class _AdminBulkDiscountSheet extends StatefulWidget {
  const _AdminBulkDiscountSheet({required this.productCount});

  final int productCount;

  @override
  State<_AdminBulkDiscountSheet> createState() =>
      _AdminBulkDiscountSheetState();
}

class _AdminBulkDiscountSheetState extends State<_AdminBulkDiscountSheet> {
  static const presets = [5, 10, 15, 20, 25, 30];
  double selected = 10;
  final custom = TextEditingController();

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  double? get _percent {
    if (custom.text.trim().isNotEmpty) {
      return parseAdminLocalizedDouble(custom.text);
    }
    return selected;
  }

  Future<void> _confirm() async {
    final percent = _percent;
    if (percent == null || percent <= 0 || percent > 100) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد خصم جماعي'),
            content: Text(
              '${widget.productCount} منتج / خصم ${percent.toStringAsFixed(percent.truncateToDouble() == percent ? 0 : 1)}%',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: const ValueKey('admin-bulk-discount-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تطبيق'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    Navigator.pop(context, percent);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'خصم جماعي (${widget.productCount} منتج)',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                ChoiceChip(
                  label: Text('$preset%'),
                  selected: selected == preset && custom.text.trim().isEmpty,
                  onSelected: (_) => setState(() {
                    selected = preset.toDouble();
                    custom.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('admin-bulk-discount-custom'),
            controller: custom,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'خصم مخصص %'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _confirm,
            child: const Text('معاينة وتأكيد'),
          ),
        ],
      ),
    );
  }
}

enum AdminBulkPriceMode { raise, lower }

Future<({AdminBulkPriceMode mode, double percent})?> showAdminBulkPriceSheet({
  required BuildContext context,
  required int productCount,
}) {
  return showModalBottomSheet<({AdminBulkPriceMode mode, double percent})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AdminBulkPriceSheet(productCount: productCount),
  );
}

class _AdminBulkPriceSheet extends StatefulWidget {
  const _AdminBulkPriceSheet({required this.productCount});

  final int productCount;

  @override
  State<_AdminBulkPriceSheet> createState() => _AdminBulkPriceSheetState();
}

class _AdminBulkPriceSheetState extends State<_AdminBulkPriceSheet> {
  AdminBulkPriceMode mode = AdminBulkPriceMode.raise;
  double selected = 5;
  final custom = TextEditingController();

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  double? get _percent {
    if (custom.text.trim().isNotEmpty) {
      return parseAdminLocalizedDouble(custom.text);
    }
    return selected;
  }

  Future<void> _confirm() async {
    final percent = _percent;
    if (percent == null || percent <= 0) return;
    final signed = mode == AdminBulkPriceMode.raise ? percent : -percent;
    final verb = mode == AdminBulkPriceMode.raise ? 'رفع' : 'خفض';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد تعديل الأسعار'),
            content: Text(
              '$verb ${percent.toStringAsFixed(percent.truncateToDouble() == percent ? 0 : 1)}% '
              'لـ ${widget.productCount} منتج',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: const ValueKey('admin-bulk-price-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تطبيق'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    Navigator.pop(context, (mode: mode, percent: signed));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تعديل أسعار جماعي (${widget.productCount} منتج)',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 10),
          SegmentedButton<AdminBulkPriceMode>(
            segments: const [
              ButtonSegment(
                value: AdminBulkPriceMode.raise,
                label: Text('رفع'),
              ),
              ButtonSegment(
                value: AdminBulkPriceMode.lower,
                label: Text('خفض'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (value) => setState(() => mode = value.first),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in const [5, 10])
                ChoiceChip(
                  label: Text(
                      '${mode == AdminBulkPriceMode.raise ? '+' : '-'}$preset%'),
                  selected: selected == preset && custom.text.trim().isEmpty,
                  onSelected: (_) => setState(() {
                    selected = preset.toDouble();
                    custom.clear();
                  }),
                ),
              ActionChip(
                label: const Text('مخصص'),
                onPressed: () => setState(() => custom.clear()),
              ),
            ],
          ),
          TextField(
            key: const ValueKey('admin-bulk-price-custom'),
            controller: custom,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'نسبة مخصصة %'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _confirm,
            child: const Text('معاينة وتأكيد'),
          ),
        ],
      ),
    );
  }
}
