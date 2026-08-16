import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../data/models/admin_order_pricing.dart';
import '../../data/models/order.dart';

Future<AdminOrderPricingResult?> showAdminOrderPricingSheet({
  required BuildContext context,
  required Order order,
  required bool demoData,
}) {
  return showModalBottomSheet<AdminOrderPricingResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _AdminOrderPricingSheet(order: order, demoData: demoData),
    ),
  );
}

class AdminOrderPricingResult {
  const AdminOrderPricingResult({
    required this.unitPrices,
    required this.deliveryFee,
    required this.discountAmount,
  });

  final List<double> unitPrices;
  final double deliveryFee;
  final double discountAmount;
}

class _AdminOrderPricingSheet extends StatefulWidget {
  const _AdminOrderPricingSheet({
    required this.order,
    required this.demoData,
  });

  final Order order;
  final bool demoData;

  @override
  State<_AdminOrderPricingSheet> createState() => _AdminOrderPricingSheetState();
}

class _AdminOrderPricingSheetState extends State<_AdminOrderPricingSheet> {
  late final List<TextEditingController> prices;
  late final TextEditingController delivery;
  late final TextEditingController discount;
  String? error;

  @override
  void initState() {
    super.initState();
    prices = [
      for (final item in widget.order.items)
        TextEditingController(text: item.unitPrice.toStringAsFixed(2)),
    ];
    delivery = TextEditingController(
      text: widget.order.deliveryFee.toStringAsFixed(2),
    );
    discount = TextEditingController(
      text: widget.order.discountAmount.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    for (final controller in prices) {
      controller.dispose();
    }
    delivery.dispose();
    discount.dispose();
    super.dispose();
  }

  double? _parseMoney(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  Order? _preview() {
    final unitPrices = [
      for (final controller in prices) _parseMoney(controller.text),
    ];
    final deliveryFee = _parseMoney(delivery.text);
    final discountAmount = _parseMoney(discount.text);
    if (unitPrices.any((value) => value == null) ||
        deliveryFee == null ||
        discountAmount == null) {
      return null;
    }
    try {
      return AdminOrderPricing.apply(
        order: widget.order,
        unitPrices: [for (final value in unitPrices) value!],
        deliveryFee: deliveryFee,
        discountAmount: discountAmount,
      );
    } on AdminOrderPricingException {
      return null;
    }
  }

  void _submit() {
    final preview = _preview();
    if (preview == null) {
      setState(() => error = 'راجع الأسعار والرسوم والخصم ثم أعد المحاولة.');
      return;
    }
    Navigator.of(context).pop(
      AdminOrderPricingResult(
        unitPrices: [for (final item in preview.items) item.unitPrice],
        deliveryFee: preview.deliveryFee,
        discountAmount: preview.discountAmount,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? suffixText,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return InputDecoration(
      labelText: label,
      suffixText: suffixText,
      prefixIcon: Icon(icon, size: 20, color: AppTheme.green),
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.green, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'تعديل تسعير الفاتورة',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.demoData
                  ? 'البيانات تجريبية محلياً ولن تُحفظ في الخادم.'
                  : 'الحفظ يعتمد الإجمالي من الخادم بعد إعادة الحساب.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            _PricingSectionCard(
              key: const ValueKey('admin-order-pricing-products-section'),
              title: 'المنتجات',
              icon: Icons.inventory_2_outlined,
              child: Column(
                children: [
                  for (var index = 0;
                      index < widget.order.items.length;
                      index++) ...[
                    if (index > 0) const Divider(height: 20),
                    _ProductPriceRow(
                      orderId: widget.order.id,
                      index: index,
                      item: widget.order.items[index],
                      controller: prices[index],
                      decoration: _fieldDecoration(
                        label:
                            'سعر الوحدة × ${widget.order.items[index].quantity}',
                        icon: Icons.sell_outlined,
                        suffixText: 'د.ل',
                      ),
                      onChanged: () => setState(() => error = null),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PricingSectionCard(
              key: const ValueKey('admin-order-pricing-fees-section'),
              title: 'الرسوم والخصم',
              icon: Icons.local_shipping_outlined,
              child: Column(
                children: [
                  TextField(
                    key: ValueKey(
                      'admin-order-delivery-fee-${widget.order.id}',
                    ),
                    controller: delivery,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      label: 'رسوم التوصيل',
                      icon: Icons.delivery_dining_outlined,
                      suffixText: 'د.ل',
                    ),
                    onChanged: (_) => setState(() => error = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: ValueKey('admin-order-discount-${widget.order.id}'),
                    controller: discount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      label: 'قيمة الخصم',
                      icon: Icons.percent_outlined,
                      suffixText: 'د.ل',
                    ),
                    onChanged: (_) => setState(() => error = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (preview != null)
              _PricingSummaryCard(preview: preview)
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'أدخل قيماً صحيحة لعرض الإجمالي المعتمد.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: ValueKey('admin-order-save-pricing-${widget.order.id}'),
              onPressed: preview == null ? null : _submit,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('اعتماد التسعير'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPriceRow extends StatelessWidget {
  const _ProductPriceRow({
    required this.orderId,
    required this.index,
    required this.item,
    required this.controller,
    required this.decoration,
    required this.onChanged,
  });

  final String orderId;
  final int index;
  final OrderLine item;
  final TextEditingController controller;
  final InputDecoration decoration;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductImagePlaceholder(
              category: item.product.category,
              productId: item.productId,
              imageUrl: item.product.imageUrl,
              size: 48,
              borderRadius: BorderRadius.circular(12),
              semanticLabel: 'صورة ${item.productName}',
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
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الكمية: ${item.quantity}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: ValueKey('admin-order-price-field-$orderId-$index'),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: decoration,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class _PricingSectionCard extends StatelessWidget {
  const _PricingSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.green),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PricingSummaryCard extends StatelessWidget {
  const _PricingSummaryCard({required this.preview});

  final Order preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('admin-order-pricing-summary-section'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.green.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.green.withValues(alpha: .28),
        ),
      ),
      child: Column(
        children: [
          _SummaryRow(
            icon: Icons.shopping_bag_outlined,
            label: 'الإجمالي الفرعي',
            amount: preview.subtotal,
          ),
          if (preview.discountAmount > 0)
            _SummaryRow(
              icon: Icons.percent_outlined,
              label: 'الخصم',
              amount: preview.discountAmount,
            ),
          if (preview.deliveryFee > 0)
            _SummaryRow(
              icon: Icons.local_shipping_outlined,
              label: 'التوصيل',
              amount: preview.deliveryFee,
            ),
          if (preview.handlingFee > 0)
            _SummaryRow(
              icon: Icons.handyman_outlined,
              label: 'المناولة',
              amount: preview.handlingFee,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .8),
            ),
          ),
          _SummaryRow(
            icon: Icons.payments_outlined,
            label: 'الإجمالي المعتمد',
            amount: preview.total,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.amount,
    this.bold = false,
  });

  final IconData icon;
  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: bold ? AppTheme.green : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            lyd(amount),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
