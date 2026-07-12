import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/order_status.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';

final cartControllerProvider =
    StateNotifierProvider<CartController, List<CartItem>>(
        (ref) => CartController(ref));

class CartController extends StateNotifier<List<CartItem>> {
  CartController(this.ref) : super(const []);
  final Ref ref;

  void add(Product product) {
    addQuantity(product, product.minOrderQuantity);
  }

  void addQuantity(Product product, int quantity) {
    if (!product.inStock) return;
    final safeQty =
        quantity.clamp(product.minOrderQuantity, product.stockQuantity);
    final index = state.indexWhere((item) => item.product.id == product.id);
    if (index == -1) {
      state = [...state, CartItem(product: product, quantity: safeQty)];
      return;
    }
    state = [
      for (final item in state)
        if (item.product.id == product.id)
          item.copyWith(
              quantity: (item.quantity + safeQty)
                  .clamp(product.minOrderQuantity, product.stockQuantity))
        else
          item,
    ];
  }

  void updateQty(String productId, int qty) {
    state = [
      for (final item in state)
        if (item.product.id == productId)
          item.copyWith(
              quantity: qty.clamp(
                  item.product.minOrderQuantity, item.product.stockQuantity))
        else
          item,
    ];
  }

  void remove(String productId) =>
      state = state.where((item) => item.product.id != productId).toList();
  void clear() => state = const [];

  Future<Order> submit(String note) async {
    final user = ref.read(authControllerProvider).user!;
    final order = Order(
      id: const Uuid().v4(),
      customerId: user.customerId ?? user.id,
      status: OrderStatus.pending,
      items: state,
      createdAt: DateTime.now(),
      customerNote: note,
    );
    await ref.read(ordersRepositoryProvider).createOrder(order);
    clear();
    return order;
  }
}
