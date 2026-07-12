import '../../core/constants/order_status.dart';
import 'product.dart';

/// A line that can be displayed in either the live cart or an immutable order.
abstract class OrderLine {
  const OrderLine();

  Product get product;
  String get productId;
  String get productName;
  String get productSku;
  String get unitSize;
  String get packageLabel;
  int get quantity;
  double get unitPrice;
  double get lineTotal;
  bool get canReorder;

  double get total => lineTotal;
}

/// A live cart line. Its price is still an estimate until the server places
/// the order and returns the customer's effective price.
class CartItem extends OrderLine {
  const CartItem({required this.product, required this.quantity});

  @override
  final Product product;

  @override
  final int quantity;

  @override
  String get productId => product.id;

  @override
  String get productName => product.name;

  @override
  String get productSku => product.sku;

  @override
  String get unitSize => product.unitSize;

  @override
  String get packageLabel => product.effectivePackageSize;

  @override
  double get unitPrice => product.price;

  @override
  double get lineTotal => unitPrice * quantity;

  @override
  bool get canReorder => product.active && product.inStock;

  CartItem copyWith({int? quantity}) =>
      CartItem(product: product, quantity: quantity ?? this.quantity);
}

/// An immutable order line snapshot returned by the server.
///
/// Product names, SKUs, package labels, quantities, and prices must remain
/// stable even when the catalog product changes later.
class OrderItem extends OrderLine {
  const OrderItem({
    this.id,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.unitSize,
    required this.packageLabel,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.product,
  });

  final String? id;

  @override
  final String productId;

  @override
  final String productName;

  @override
  final String productSku;

  @override
  final String unitSize;

  @override
  final String packageLabel;

  @override
  final int quantity;

  @override
  final double unitPrice;

  @override
  final double lineTotal;

  /// The current catalog product, when it is still available.
  ///
  /// A disabled snapshot product is supplied when the current catalog record
  /// is unavailable so legacy UI remains safe and cannot reorder stale data.
  @override
  final Product product;

  @override
  bool get canReorder => product.active && product.inStock;

  factory OrderItem.fromMap(Map<String, dynamic> row) {
    final productRow = _mapOrNull(row['products']) ??
        _mapOrNull(row['product']) ??
        const <String, dynamic>{};
    final quantity = _asInt(row['quantity'], fallback: 1);
    final unitPrice = _asDouble(
      row['unit_price'],
      fallback: _asDouble(productRow['base_price']),
    );
    final productId = (row['product_id'] ?? productRow['id'] ?? '').toString();
    final productName = (row['product_name'] ??
            row['product_name_snapshot'] ??
            productRow['name'] ??
            'منتج غير متوفر')
        .toString();
    final productSku = (row['product_sku'] ??
            row['product_sku_snapshot'] ??
            productRow['sku'] ??
            '')
        .toString();
    final unitSize = (row['unit_size'] ??
            row['unit_size_snapshot'] ??
            productRow['unit_size'] ??
            '')
        .toString();
    final packageLabel = (row['package_label'] ??
            row['package_label_snapshot'] ??
            row['package_size'] ??
            productRow['package_size'] ??
            productRow['unit_size'] ??
            '')
        .toString();

    final currentProduct = productRow.isEmpty
        ? Product(
            id: productId,
            nameAr: productName,
            sku: productSku,
            category: 'طلب سابق',
            animalType: '',
            brand: '',
            unitSize: unitSize,
            packageSize: packageLabel.isEmpty ? null : packageLabel,
            basePrice: unitPrice,
            stockQuantity: 0,
            minOrderQty: 1,
            isActive: false,
          )
        : Product.fromSupabase(productRow);

    return OrderItem(
      id: row['id']?.toString(),
      productId: productId,
      productName: productName,
      productSku: productSku,
      unitSize: unitSize,
      packageLabel: packageLabel,
      quantity: quantity,
      unitPrice: unitPrice,
      lineTotal: _asDouble(
        row['line_total'],
        fallback: unitPrice * quantity,
      ),
      product: currentProduct,
    );
  }
}

class OrderStatusHistoryEntry {
  const OrderStatusHistoryEntry({
    this.id,
    this.fromStatus,
    required this.toStatus,
    this.note = '',
    this.changedBy,
    required this.changedAt,
  });

  final String? id;
  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final String note;
  final String? changedBy;
  final DateTime changedAt;

  factory OrderStatusHistoryEntry.fromMap(Map<String, dynamic> row) {
    return OrderStatusHistoryEntry(
      id: row['id']?.toString(),
      fromStatus: _statusOrNull(row['from_status']),
      toStatus: _statusFrom(row['to_status']),
      note: (row['note'] ?? '').toString(),
      changedBy: row['changed_by']?.toString(),
      changedAt: _dateFrom(row['changed_at']),
    );
  }
}

class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.status,
    required this.items,
    required this.createdAt,
    this.orderNumber = '',
    this.clientRequestId,
    this.customerProfileId,
    this.businessName = '',
    this.contactPerson = '',
    this.contactPhone = '',
    this.deliveryAddress = '',
    this.deliveryNote = '',
    this.customerNote = '',
    this.adminNote = '',
    this.updatedAt,
    this.deliveryFee = 0,
    this.handlingFee = 0,
    this.statusHistory = const [],
    double? subtotal,
    double? total,
  })  : _subtotal = subtotal,
        _total = total;

  final String id;
  final String orderNumber;
  final String? clientRequestId;
  final String customerId;
  final String? customerProfileId;
  final String businessName;
  final String contactPerson;
  final String contactPhone;
  final OrderStatus status;
  final List<OrderLine> items;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String deliveryAddress;
  final String deliveryNote;
  final String customerNote;
  final String adminNote;
  final double deliveryFee;
  final double handlingFee;
  final List<OrderStatusHistoryEntry> statusHistory;
  final double? _subtotal;
  final double? _total;

  String get displayNumber => orderNumber.isEmpty ? id : orderNumber;

  double get subtotal =>
      _subtotal ?? items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get total => _total ?? subtotal + deliveryFee + handlingFee;

  List<OrderStatus> get allowedNextStatuses => allowedOrderTransitions(status);

  Order copyWith({
    String? id,
    String? orderNumber,
    String? clientRequestId,
    String? customerId,
    String? customerProfileId,
    String? businessName,
    String? contactPerson,
    String? contactPhone,
    OrderStatus? status,
    List<OrderLine>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? deliveryAddress,
    String? deliveryNote,
    String? customerNote,
    String? adminNote,
    double? subtotal,
    double? deliveryFee,
    double? handlingFee,
    double? total,
    List<OrderStatusHistoryEntry>? statusHistory,
  }) {
    return Order(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      clientRequestId: clientRequestId ?? this.clientRequestId,
      customerId: customerId ?? this.customerId,
      customerProfileId: customerProfileId ?? this.customerProfileId,
      businessName: businessName ?? this.businessName,
      contactPerson: contactPerson ?? this.contactPerson,
      contactPhone: contactPhone ?? this.contactPhone,
      status: status ?? this.status,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryNote: deliveryNote ?? this.deliveryNote,
      customerNote: customerNote ?? this.customerNote,
      adminNote: adminNote ?? this.adminNote,
      subtotal: subtotal ?? _subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      handlingFee: handlingFee ?? this.handlingFee,
      total: total ?? _total,
      statusHistory: statusHistory ?? this.statusHistory,
    );
  }

  factory Order.fromSupabase(Map<String, dynamic> row) => Order.fromMap(row);

  factory Order.fromMap(Map<String, dynamic> row) {
    final rawItems =
        row['items'] as List? ?? row['order_items'] as List? ?? const [];
    final rawHistory = row['status_history'] as List? ?? const [];
    final statusHistory = [
      for (final raw in rawHistory)
        if (_mapOrNull(raw) case final historyRow?)
          OrderStatusHistoryEntry.fromMap(historyRow),
    ]..sort((a, b) => a.changedAt.compareTo(b.changedAt));
    final customer = _mapOrNull(row['business_customers']) ??
        _mapOrNull(row['customer']) ??
        const <String, dynamic>{};
    final id = (row['id'] ?? '').toString();
    final customerAddress = [
      customer['city'],
      customer['area'],
      customer['address'],
    ]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .map((part) => part.toString().trim())
        .join(' - ');

    return Order(
      id: id,
      orderNumber: (row['order_number'] ?? '').toString(),
      clientRequestId: row['client_request_id']?.toString(),
      customerId: (row['customer_id'] ?? customer['id'] ?? '').toString(),
      customerProfileId:
          (row['customer_profile_id'] ?? customer['profile_id'])?.toString(),
      businessName: (row['business_name'] ??
              row['business_name_snapshot'] ??
              customer['business_name'] ??
              '')
          .toString(),
      contactPerson: (row['contact_person'] ??
              row['contact_person_snapshot'] ??
              customer['contact_person'] ??
              '')
          .toString(),
      contactPhone: (row['contact_phone'] ??
              row['contact_phone_snapshot'] ??
              row['phone'] ??
              customer['phone'] ??
              '')
          .toString(),
      status: _statusFrom(row['status']),
      items: [
        for (final raw in rawItems)
          if (_mapOrNull(raw) case final itemRow?) OrderItem.fromMap(itemRow),
      ],
      createdAt: _dateFrom(row['created_at']),
      updatedAt: _dateOrNull(row['updated_at']),
      deliveryAddress: (row['delivery_address'] ?? customerAddress).toString(),
      deliveryNote: (row['delivery_note'] ?? '').toString(),
      customerNote: (row['customer_note'] ?? row['notes'] ?? '').toString(),
      adminNote: (row['admin_note'] ?? '').toString(),
      subtotal: _asDoubleOrNull(row['subtotal']),
      deliveryFee: _asDouble(row['delivery_fee']),
      handlingFee: _asDouble(row['handling_fee']),
      total: _asDoubleOrNull(row['total']),
      statusHistory: statusHistory,
    );
  }
}

/// Shared estimate used by both cart and checkout.
///
/// The server remains authoritative and can return a different effective
/// product price, delivery fee, handling fee, or final total.
class CartPricingSummary {
  const CartPricingSummary({
    required this.subtotal,
    required this.handlingFee,
    required this.deliveryFee,
  });

  static const double defaultEstimatedHandlingFee = 10;

  final double subtotal;
  final double handlingFee;
  final double deliveryFee;

  double get total => subtotal + handlingFee + deliveryFee;

  factory CartPricingSummary.estimate(Iterable<CartItem> items) {
    final itemList = items.toList(growable: false);
    return CartPricingSummary(
      subtotal: itemList.fold<double>(0, (sum, item) => sum + item.lineTotal),
      handlingFee:
          itemList.isEmpty ? 0 : CartPricingSummary.defaultEstimatedHandlingFee,
      deliveryFee: 0,
    );
  }
}

List<OrderStatus> allowedOrderTransitions(OrderStatus current) {
  return switch (current) {
    OrderStatus.pending => const [
        OrderStatus.confirmed,
        OrderStatus.cancelled,
      ],
    OrderStatus.confirmed => const [
        OrderStatus.preparing,
        OrderStatus.cancelled,
      ],
    OrderStatus.preparing => const [
        OrderStatus.ready,
        OrderStatus.cancelled,
      ],
    OrderStatus.ready => const [
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ],
    OrderStatus.delivered || OrderStatus.cancelled => const [],
  };
}

Map<String, dynamic>? _mapOrNull(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

double? _asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime _dateFrom(Object? value) =>
    _dateOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _dateOrNull(Object? value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

OrderStatus _statusFrom(Object? value) =>
    _statusOrNull(value) ?? OrderStatus.pending;

OrderStatus? _statusOrNull(Object? value) {
  final raw = value?.toString();
  for (final status in OrderStatus.values) {
    if (status.value == raw) return status;
  }
  return null;
}
