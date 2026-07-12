import '../../core/constants/order_status.dart';
import 'product.dart';

class CartItem {
  const CartItem({required this.product, required this.quantity});
  final Product product;
  final int quantity;
  double get total => product.price * quantity;

  CartItem copyWith({int? quantity}) =>
      CartItem(product: product, quantity: quantity ?? this.quantity);
}

class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.status,
    required this.items,
    required this.createdAt,
    this.customerNote = '',
    this.adminNote = '',
  });

  final String id;
  final String customerId;
  final OrderStatus status;
  final List<CartItem> items;
  final DateTime createdAt;
  final String customerNote;
  final String adminNote;
  double get total => items.fold(0, (sum, item) => sum + item.total);

  Order copyWith({
    String? id,
    String? customerId,
    OrderStatus? status,
    List<CartItem>? items,
    DateTime? createdAt,
    String? customerNote,
    String? adminNote,
  }) {
    return Order(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      status: status ?? this.status,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      customerNote: customerNote ?? this.customerNote,
      adminNote: adminNote ?? this.adminNote,
    );
  }

  factory Order.fromSupabase(Map<String, dynamic> row) {
    final rawItems = row['order_items'] as List? ?? const [];
    return Order(
      id: row['id'].toString(),
      customerId: row['customer_id'].toString(),
      status: OrderStatus.values.firstWhere(
        (status) => status.value == row['status'],
        orElse: () => OrderStatus.pending,
      ),
      items: [
        for (final raw in rawItems)
          if (raw is Map<String, dynamic> &&
              raw['products'] is Map<String, dynamic>)
            CartItem(
              product:
                  Product.fromSupabase(raw['products'] as Map<String, dynamic>),
              quantity: (raw['quantity'] ?? 1) as int,
            ),
      ],
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
      customerNote: (row['customer_note'] ?? '').toString(),
      adminNote: (row['admin_note'] ?? '').toString(),
    );
  }
}
