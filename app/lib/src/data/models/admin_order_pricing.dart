import '../../core/constants/order_status.dart';
import '../models/order.dart';

class AdminOrderPricingException implements Exception {
  const AdminOrderPricingException(this.code, this.message);

  final String code;
  final String message;
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
