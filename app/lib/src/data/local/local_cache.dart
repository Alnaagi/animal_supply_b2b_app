import '../models/order.dart';
import '../models/product.dart';

class LocalCache {
  final List<Product> _cachedProducts = [];
  final List<Order> _draftOrders = [];

  Future<void> saveProducts(List<Product> products) async {
    _cachedProducts
      ..clear()
      ..addAll(products);
  }

  Future<List<Product>> cachedProducts() async => [..._cachedProducts];

  Future<void> saveDraftOrder(Order order) async {
    _draftOrders.add(order);
  }

  Future<List<Order>> draftOrders() async => [..._draftOrders];
}
