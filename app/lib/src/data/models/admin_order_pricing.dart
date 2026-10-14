import '../../core/constants/order_status.dart';
import '../models/order.dart';
import '../models/product.dart';

class AdminOrderPricingException implements Exception {
  const AdminOrderPricingException(this.code, this.message);

  final String code;
  final String message;
}

class AdminOrderEditItem {
  const AdminOrderEditItem({
    required this.id,
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });

  final String id;
  final Product product;
  final int quantity;
  final double unitPrice;

  String get productId => product.id;
}

class AdminOrderPricing {
  const AdminOrderPricing._();

  static const maxMoney = 1000000.0;

  static bool canEdit(Order order) =>
      order.status != OrderStatus.delivered &&
      order.status != OrderStatus.cancelled &&
      order.items.isNotEmpty;

  static double roundMoney(double value) => (value * 100).round() / 100;

  static void validateMoney(double value, String field) {
    if (!value.isFinite || value < 0 || value > maxMoney) {
      throw const AdminOrderPricingException(
        'ORDER_PRICING_INVALID',
        'قيمة مالية غير صالحة.',
      );
    }
    if ((roundMoney(value) - value).abs() > 0.0000001) {
      throw const AdminOrderPricingException(
        'ORDER_PRICING_INVALID',
        'استخدم رقمين بعد الفاصلة فقط.',
      );
    }
  }

  static Order apply({
    required Order order,
    required List<double> unitPrices,
    required double deliveryFee,
    required double discountAmount,
  }) {
    if (!canEdit(order)) {
      throw const AdminOrderPricingException(
        'ORDER_PRICING_LOCKED',
        'لا يمكن تعديل تسعير طلب مسلّم أو ملغى.',
      );
    }
    if (unitPrices.length != order.items.length) {
      throw const AdminOrderPricingException(
        'ORDER_ITEM_MISMATCH',
        'بنود الفاتورة غير مكتملة.',
      );
    }
    validateMoney(deliveryFee, 'deliveryFee');
    validateMoney(discountAmount, 'discountAmount');

    final items = <OrderItem>[
      for (var index = 0; index < order.items.length; index++)
        _pricedItem(order.items[index], unitPrices[index]),
    ];
    final subtotal = roundMoney(
      items.fold<double>(0, (sum, item) => sum + item.lineTotal),
    );
    if (discountAmount > subtotal) {
      throw const AdminOrderPricingException(
        'ORDER_DISCOUNT_INVALID',
        'الخصم لا يمكن أن يتجاوز الإجمالي الفرعي.',
      );
    }
    final total = roundMoney(
      subtotal + deliveryFee + order.handlingFee - discountAmount,
    );
    return order.copyWith(
      items: items,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      discountAmount: discountAmount,
      total: total,
      updatedAt: DateTime.now(),
    );
  }

  static Order applyOrderEdit({
    required Order order,
    required List<AdminOrderEditItem> items,
    required double deliveryFee,
    required double discountAmount,
    String? adminNote,
  }) {
    if (!canEdit(order)) {
      throw const AdminOrderPricingException(
        'ORDER_PRICING_LOCKED',
        'لا يمكن تعديل طلب مسلّم أو ملغى.',
      );
    }
    if (items.length != order.items.length || items.isEmpty) {
      throw const AdminOrderPricingException(
        'ORDER_ITEM_MISMATCH',
        'بنود الفاتورة غير مكتملة.',
      );
    }
    validateMoney(deliveryFee, 'deliveryFee');
    validateMoney(discountAmount, 'discountAmount');

    final existingIds = <String>{
      for (final line in order.items)
        if (line is OrderItem && (line.id ?? '').isNotEmpty) line.id!,
    };
    final submittedIds = <String>{};
    final editedItems = <OrderItem>[];
    for (final edit in items) {
      if (edit.id.trim().isEmpty || !submittedIds.add(edit.id)) {
        throw const AdminOrderPricingException(
          'ORDER_ITEM_MISMATCH',
          'بنود الفاتورة غير مكتملة.',
        );
      }
      if (!existingIds.contains(edit.id)) {
        throw const AdminOrderPricingException(
          'ORDER_ITEM_MISMATCH',
          'بنود الفاتورة غير مكتملة.',
        );
      }
      validateMoney(edit.unitPrice, 'unitPrice');
      if (edit.quantity <= 0 || edit.quantity > 1000000) {
        throw const AdminOrderPricingException(
          'INVALID_QUANTITY',
          'الكمية يجب أن تكون أكبر من صفر.',
        );
      }
      if (edit.quantity < edit.product.minOrderQty) {
        throw AdminOrderPricingException(
          'MINIMUM_QUANTITY_NOT_MET',
          'الحد الأدنى لمنتج «${edit.product.name}» هو ${edit.product.minOrderQty}.',
        );
      }
      final roundedPrice = roundMoney(edit.unitPrice);
      editedItems.add(
        OrderItem(
          id: edit.id,
          productId: edit.product.id,
          productName: edit.product.name,
          productSku: edit.product.sku,
          unitSize: edit.product.unitSize,
          packageLabel: edit.product.effectivePackageSize,
          unitsPerBox: edit.product.unitsPerBox,
          quantity: edit.quantity,
          unitPrice: roundedPrice,
          lineTotal: roundMoney(roundedPrice * edit.quantity),
          product: edit.product,
        ),
      );
    }
    if (submittedIds.length != existingIds.length) {
      throw const AdminOrderPricingException(
        'ORDER_ITEM_MISMATCH',
        'بنود الفاتورة غير مكتملة.',
      );
    }

    final subtotal = roundMoney(
      editedItems.fold<double>(0, (sum, item) => sum + item.lineTotal),
    );
    if (discountAmount > subtotal) {
      throw const AdminOrderPricingException(
        'ORDER_DISCOUNT_INVALID',
        'الخصم لا يمكن أن يتجاوز الإجمالي الفرعي.',
      );
    }
    final note = adminNote?.trim();
    if (note != null && note.length > 1000) {
      throw const AdminOrderPricingException(
        'ORDER_NOTE_TOO_LONG',
        'ملاحظة الإدارة طويلة جداً.',
      );
    }
    return order.copyWith(
      items: editedItems,
      subtotal: subtotal,
      deliveryFee: roundMoney(deliveryFee),
      discountAmount: roundMoney(discountAmount),
      total: roundMoney(
        subtotal + deliveryFee + order.handlingFee - discountAmount,
      ),
      adminNote: note ?? order.adminNote,
      updatedAt: DateTime.now(),
    );
  }

  static OrderItem _pricedItem(OrderLine line, double unitPrice) {
    validateMoney(unitPrice, 'unitPrice');
    final priced = roundMoney(unitPrice);
    if (line is OrderItem) {
      return line.copyWith(unitPrice: priced);
    }
    return OrderItem(
      productId: line.productId,
      productName: line.productName,
      productSku: line.productSku,
      unitSize: line.unitSize,
      packageLabel: line.packageLabel,
      unitsPerBox: line.unitsPerBox,
      quantity: line.quantity,
      unitPrice: priced,
      lineTotal: roundMoney(priced * line.quantity),
      product: line.product,
    );
  }
}
