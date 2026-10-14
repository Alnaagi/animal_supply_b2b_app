import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../data/models/admin_order_pricing.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';

enum AdminOrderDiscountMode { amount, percent }

Future<AdminOrderPricingResult?> showAdminOrderPricingSheet({
  required BuildContext context,
  required Order order,
  required bool demoData,
  Future<List<Product>>? productsFuture,
}) {
  return showModalBottomSheet<AdminOrderPricingResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _AdminOrderPricingSheet(
        order: order,
        demoData: demoData,
        productsFuture: productsFuture,
      ),
    ),
  );
}

class AdminOrderPricingResult {
  const AdminOrderPricingResult({
    required this.items,
    required this.unitPrices,
    required this.deliveryFee,
    required this.discountAmount,
    required this.adminNote,
  });

  final List<AdminOrderEditItem> items;
  @Deprecated('Use items; retained for compatibility with older callers.')
  final List<double> unitPrices;
  final double deliveryFee;
  final double discountAmount;
  final String adminNote;
}

class _AdminOrderPricingSheet extends StatefulWidget {
  const _AdminOrderPricingSheet({
    required this.order,
    required this.demoData,
    required this.productsFuture,
  });

  final Order order;
  final bool demoData;
  final Future<List<Product>>? productsFuture;

  @override
  State<_AdminOrderPricingSheet> createState() =>
      _AdminOrderPricingSheetState();
}

class _AdminOrderPricingSheetState extends State<_AdminOrderPricingSheet> {
  late final List<Product> initialProducts;
  late final List<Product?> selectedProducts;
  late final List<TextEditingController> prices;
  late final List<TextEditingController> quantities;
  late final TextEditingController delivery;
  late final TextEditingController discount;
  late final TextEditingController adminNote;
  AdminOrderDiscountMode discountMode = AdminOrderDiscountMode.amount;
  String? error;

  @override
  void initState() {
    super.initState();
    initialProducts = [
      for (final item in widget.order.items) item.product,
    ];
    selectedProducts = [...initialProducts];
    prices = [
      for (final item in widget.order.items)
        TextEditingController(text: item.unitPrice.toStringAsFixed(2)),
    ];
    quantities = [
      for (final item in widget.order.items)
        TextEditingController(text: item.quantity.toString()),
    ];
    delivery = TextEditingController(
      text: widget.order.deliveryFee.toStringAsFixed(2),
    );
    discount = TextEditingController(
      text: widget.order.discountAmount.toStringAsFixed(2),
    );
    adminNote = TextEditingController(text: widget.order.adminNote);
  }

  @override
  void dispose() {
    for (final controller in prices) {
      controller.dispose();
    }
    for (final controller in quantities) {
      controller.dispose();
    }
    delivery.dispose();
    discount.dispose();
    adminNote.dispose();
    super.dispose();
  }

  double? _parseMoney(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  int? _parseQuantity(String raw) => int.tryParse(raw.trim());

  bool _hasAtMostTwoDecimals(double value) =>
      (AdminOrderPricing.roundMoney(value) - value).abs() <= 0.0000001;

  double? _editedSubtotal() {
    var subtotal = 0.0;
    for (var index = 0; index < widget.order.items.length; index++) {
      final product = selectedProducts[index];
      final unitPrice = _parseMoney(prices[index].text);
      final quantity = _parseQuantity(quantities[index].text);
      if (product == null ||
          unitPrice == null ||
          !unitPrice.isFinite ||
          unitPrice < 0 ||
          quantity == null ||
          quantity <= 0) {
        return null;
      }
      subtotal += unitPrice * quantity;
    }
    if (!subtotal.isFinite || subtotal < 0) return null;
    return AdminOrderPricing.roundMoney(subtotal);
  }

  double? _discountAmountForPreview() {
    final entered = _parseMoney(discount.text);
    if (entered == null ||
        !entered.isFinite ||
        entered < 0 ||
        !_hasAtMostTwoDecimals(entered)) {
      return null;
    }
    if (discountMode == AdminOrderDiscountMode.amount) {
      return entered;
    }
    if (entered > 100) return null;
    final subtotal = _editedSubtotal();
    if (subtotal == null) return null;
    return AdminOrderPricing.roundMoney(subtotal * entered / 100);
  }

  void _setDiscountMode(AdminOrderDiscountMode nextMode) {
    if (nextMode == discountMode) return;
    final entered = _parseMoney(discount.text);
    final subtotal = _editedSubtotal();
    if (entered != null &&
        subtotal != null &&
        entered.isFinite &&
        entered >= 0) {
      final converted = discountMode == AdminOrderDiscountMode.amount
          ? subtotal > 0
              ? entered / subtotal * 100
              : 0.0
          : subtotal * entered / 100;
      discount.text =
          AdminOrderPricing.roundMoney(converted).toStringAsFixed(2);
      discount.selection = TextSelection.collapsed(
        offset: discount.text.length,
      );
    }
    setState(() {
      discountMode = nextMode;
      error = null;
    });
  }

  List<Product> _mergeProducts(List<Product>? loaded) {
    final byId = <String, Product>{
      for (final product in initialProducts) product.id: product,
    };
    for (final product in loaded ?? const <Product>[]) {
      byId[product.id] = product;
    }
    for (final product in selectedProducts) {
      if (product != null) byId[product.id] = product;
    }
    return byId.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Order? _preview() {
    final deliveryFee = _parseMoney(delivery.text);
    final discountAmount = _discountAmountForPreview();
    if (deliveryFee == null || discountAmount == null) {
      return null;
    }
    try {
      final items = <AdminOrderEditItem>[];
      for (var index = 0; index < widget.order.items.length; index++) {
        final product = selectedProducts[index];
        final unitPrice = _parseMoney(prices[index].text);
        final quantity = _parseQuantity(quantities[index].text);
        if (product == null || unitPrice == null || quantity == null) {
          return null;
        }
        final original = widget.order.items[index];
        final id = original is OrderItem ? original.id : null;
        if (id == null || id.isEmpty) return null;
        items.add(
          AdminOrderEditItem(
            id: id,
            product: product,
            quantity: quantity,
            unitPrice: unitPrice,
          ),
        );
      }
      return AdminOrderPricing.applyOrderEdit(
        order: widget.order,
        items: items,
        deliveryFee: deliveryFee,
        discountAmount: discountAmount,
        adminNote: adminNote.text,
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
        items: [
          for (var index = 0; index < preview.items.length; index++)
            AdminOrderEditItem(
              id: (preview.items[index] as OrderItem).id!,
              product: preview.items[index].product,
              quantity: preview.items[index].quantity,
              unitPrice: preview.items[index].unitPrice,
            ),
        ],
        unitPrices: [for (final item in preview.items) item.unitPrice],
        deliveryFee: preview.deliveryFee,
        discountAmount: preview.discountAmount,
        adminNote: preview.adminNote,
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
      prefixIcon: Icon(icon, size: 20, color: scheme.primary),
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
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
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .92,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            color: scheme.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'تعديل الطلب',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16),
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
                    FutureBuilder<List<Product>>(
                      future: widget.productsFuture,
                      initialData: initialProducts,
                      builder: (context, snapshot) {
                        final products = _mergeProducts(snapshot.data);
                        return _PricingSectionCard(
                          key: const ValueKey(
                              'admin-order-pricing-products-section'),
                          title: 'المنتجات',
                          icon: Icons.inventory_2_outlined,
                          child: Column(
                            children: [
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: LinearProgressIndicator(minHeight: 2),
                                ),
                              for (var index = 0;
                                  index < widget.order.items.length;
                                  index++) ...[
                                if (index > 0) const Divider(height: 20),
                                _ProductEditRow(
                                  orderId: widget.order.id,
                                  index: index,
                                  originalItem: widget.order.items[index],
                                  products: products,
                                  selectedProduct: selectedProducts[index]!,
                                  quantityController: quantities[index],
                                  priceController: prices[index],
                                  priceDecoration: _fieldDecoration(
                                    label: 'سعر الوحدة',
                                    icon: Icons.sell_outlined,
                                    suffixText: 'د.ل',
                                  ),
                                  quantityDecoration: _fieldDecoration(
                                    label: 'الكمية',
                                    icon: Icons.numbers_outlined,
                                  ),
                                  onProductChanged: (product) {
                                    setState(() {
                                      selectedProducts[index] = product;
                                      final currentQuantity = _parseQuantity(
                                              quantities[index].text) ??
                                          1;
                                      quantities[index].text = product
                                          .normalizeOrderQuantity(
                                              currentQuantity)
                                          .toString();
                                      error = null;
                                    });
                                  },
                                  onChanged: () => setState(() => error = null),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'طريقة إدخال الخصم',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              SegmentedButton<AdminOrderDiscountMode>(
                                key: ValueKey(
                                  'admin-order-discount-mode-${widget.order.id}',
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: AdminOrderDiscountMode.amount,
                                    label: Text('مبلغ'),
                                  ),
                                  ButtonSegment(
                                    value: AdminOrderDiscountMode.percent,
                                    label: Text('نسبة'),
                                  ),
                                ],
                                selected: {discountMode},
                                showSelectedIcon: false,
                                onSelectionChanged: (selection) =>
                                    _setDiscountMode(selection.first),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: ValueKey(
                                'admin-order-discount-${widget.order.id}'),
                            controller: discount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _fieldDecoration(
                              label:
                                  discountMode == AdminOrderDiscountMode.amount
                                      ? 'قيمة الخصم'
                                      : 'نسبة الخصم',
                              icon:
                                  discountMode == AdminOrderDiscountMode.amount
                                      ? Icons.payments_outlined
                                      : Icons.percent_outlined,
                              suffixText:
                                  discountMode == AdminOrderDiscountMode.amount
                                      ? 'د.ل'
                                      : '%',
                            ),
                            onChanged: (_) => setState(() => error = null),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              discountMode == AdminOrderDiscountMode.amount
                                  ? 'أدخل الخصم كمبلغ ثابت بالدينار.'
                                  : 'أدخل نسبة من الإجمالي الفرعي (من 0 إلى 100%).',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PricingSectionCard(
                      key: const ValueKey('admin-order-admin-note-section'),
                      title: 'ملاحظة للعميل',
                      icon: Icons.sticky_note_2_outlined,
                      child: TextField(
                        key: ValueKey(
                            'admin-order-admin-note-${widget.order.id}'),
                        controller: adminNote,
                        maxLines: 3,
                        maxLength: 1000,
                        decoration: _fieldDecoration(
                          label: 'ملاحظة الإدارة التي ستظهر للعميل',
                          icon: Icons.notes_outlined,
                        ).copyWith(
                          hintText: 'مثال: تم تعديل الكمية أو موعد التوصيل.',
                          alignLabelWithHint: true,
                        ),
                        onChanged: (_) => setState(() => error = null),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (preview != null)
                      _PricingSummaryCard(preview: preview)
                    else
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: .45),
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
                                style:
                                    TextStyle(color: scheme.onSurfaceVariant),
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
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                key: ValueKey('admin-order-save-pricing-${widget.order.id}'),
                onPressed: preview == null ? null : _submit,
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text('حفظ تعديلات الطلب'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductEditRow extends StatelessWidget {
  const _ProductEditRow({
    required this.orderId,
    required this.index,
    required this.originalItem,
    required this.products,
    required this.selectedProduct,
    required this.quantityController,
    required this.priceController,
    required this.priceDecoration,
    required this.quantityDecoration,
    required this.onProductChanged,
    required this.onChanged,
  });

  final String orderId;
  final int index;
  final OrderLine originalItem;
  final List<Product> products;
  final Product selectedProduct;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  final InputDecoration priceDecoration;
  final InputDecoration quantityDecoration;
  final ValueChanged<Product> onProductChanged;
  final VoidCallback onChanged;

  Future<void> _pickProduct(BuildContext context) async {
    final selected = await showDialog<Product>(
      context: context,
      builder: (context) => _ProductPickerDialog(
        products: products,
        selectedProductId: selectedProduct.id,
      ),
    );
    if (selected != null) onProductChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('admin-order-product-picker-$orderId-$index'),
          onTap: () => _pickProduct(context),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                ProductImagePlaceholder(
                  category: selectedProduct.category,
                  productId: selectedProduct.id,
                  imageUrl: selectedProduct.imageUrl,
                  size: 52,
                  borderRadius: BorderRadius.circular(12),
                  semanticLabel: 'صورة ${selectedProduct.name}',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedProduct.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${selectedProduct.sku} · الحد الأدنى ${selectedProduct.minOrderQty}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (selectedProduct.id != originalItem.productId)
                        Text(
                          'تم تغيير المنتج',
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.swap_horiz, color: scheme.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('admin-order-quantity-field-$orderId-$index'),
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: quantityDecoration.copyWith(
                  helperText: 'الحد الأدنى ${selectedProduct.minOrderQty}',
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: ValueKey('admin-order-price-field-$orderId-$index'),
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: priceDecoration,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({
    required this.products,
    required this.selectedProductId,
  });

  final List<Product> products;
  final String selectedProductId;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final filtered = widget.products.where((product) {
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
    }).toList(growable: false);
    return AlertDialog(
      title: const Text('اختيار منتج'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: search,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ابحث بالاسم أو الرمز',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('لا توجد منتجات مطابقة.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        return ListTile(
                          selected: product.id == widget.selectedProductId,
                          leading: ProductImagePlaceholder(
                            category: product.category,
                            productId: product.id,
                            imageUrl: product.imageUrl,
                            size: 42,
                            borderRadius: BorderRadius.circular(10),
                            semanticLabel: 'صورة ${product.name}',
                          ),
                          title: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${product.sku} · الحد الأدنى ${product.minOrderQty}',
                          ),
                          trailing: product.id == widget.selectedProductId
                              ? const Icon(Icons.check_circle)
                              : null,
                          onTap: () => Navigator.of(context).pop(product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
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
              Icon(icon, size: 18, color: scheme.primary),
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
        color: scheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.primary.withValues(alpha: .28),
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
            color: bold
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
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
