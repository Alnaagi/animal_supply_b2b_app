import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
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

  double? _parseMoney(String raw) => double.tryParse(raw.trim().replaceAll(',', '.'));

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

  @override
  Widget build(BuildContext context) {
    final preview = _preview();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تعديل تسعير الفاتورة',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              widget.demoData
                  ? 'البيانات تجريبية محلياً ولن تُحفظ في الخادم.'
                  : 'الحفظ يعتمد الإجمالي من الخادم بعد إعادة الحساب.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < widget.order.items.length; index++) ...[
              Text(
                widget.order.items[index].productName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              TextField(
                key: ValueKey(
                  'admin-order-price-field-${widget.order.id}-$index',
                ),
                controller: prices[index],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      'سعر الوحدة × ${widget.order.items[index].quantity}',
                ),
                onChanged: (_) => setState(() => error = null),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              key: ValueKey('admin-order-delivery-fee-${widget.order.id}'),
              controller: delivery,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'رسوم التوصيل'),
              onChanged: (_) => setState(() => error = null),
            ),
            const SizedBox(height: 10),
            TextField(
              key: ValueKey('admin-order-discount-${widget.order.id}'),
              controller: discount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'قيمة الخصم'),
              onChanged: (_) => setState(() => error = null),
            ),
            const SizedBox(height: 12),
            if (preview != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _row('الإجمالي الفرعي', preview.subtotal),
                    if (preview.discountAmount > 0)
                      _row('الخصم', preview.discountAmount),
                    if (preview.deliveryFee > 0)
                      _row('التوصيل', preview.deliveryFee),
                    if (preview.handlingFee > 0)
                      _row('المناولة', preview.handlingFee),
                    const SizedBox(height: 4),
                    _row('الإجمالي المعتمد', preview.total, bold: true),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('أدخل قيماً صحيحة لعرض الإجمالي المعتمد.'),
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              key: ValueKey('admin-order-save-pricing-${widget.order.id}'),
              onPressed: preview == null ? null : _submit,
              child: const Text('اعتماد التسعير'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
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
