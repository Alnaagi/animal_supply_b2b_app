import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/order_status.dart';
import '../models/order.dart';
import '../remote/supabase_clients.dart';
import 'demo_data.dart';

final ordersRepositoryProvider =
    Provider<OrdersRepository>((ref) => OrdersRepository());

class OrdersRepository {
  final List<Order> _orders = [...demoOrders];

  Future<List<Order>> ordersForCustomer(String customerId) async {
    final client = supabaseClient;
    if (client != null) {
      final rows = await client
          .from('orders')
          .select('*, order_items(quantity, products(*, categories(name)))')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return rows.map<Order>((row) => Order.fromSupabase(row)).toList();
    }
    return _orders.where((o) => o.customerId == customerId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Order>> allOrders() async {
    final client = supabaseClient;
    if (client != null) {
      final rows = await client
          .from('orders')
          .select('*, order_items(quantity, products(*, categories(name)))')
          .order('created_at', ascending: false);
      return rows.map<Order>((row) => Order.fromSupabase(row)).toList();
    }
    return [..._orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> createOrder(Order order) async {
    final client = supabaseClient;
    if (client != null) {
      final inserted = await client
          .from('orders')
          .insert({
            'customer_id': order.customerId,
            'status': order.status.value,
            'subtotal': order.total,
            'customer_note': order.customerNote,
          })
          .select('id')
          .single();
      await client.from('order_items').insert([
        for (final item in order.items)
          {
            'order_id': inserted['id'],
            'product_id': item.product.id,
            'quantity': item.quantity,
            'unit_price': item.product.price,
          }
      ]);
      await client.functions.invoke('send-admin-notification',
          body: {'order_id': inserted['id']});
      return;
    }
    _orders.insert(0, order);
    // Offline-ready hook: persist to local cache/outbox before remote sync in production.
  }

  Future<void> updateOrderStatus(String orderId, String status,
      {String adminNote = ''}) async {
    final client = supabaseClient;
    if (client != null) {
      await client.from('orders').update({
        'status': status,
        'admin_note': adminNote,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);
      return;
    }
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index != -1) {
      final parsed = _parseStatus(status);
      _orders[index] =
          _orders[index].copyWith(status: parsed, adminNote: adminNote);
    }
  }

  OrderStatus _parseStatus(String value) => OrderStatus.values.firstWhere(
        (status) => status.value == value,
        orElse: () => OrderStatus.pending,
      );

  String whatsappSummary(Order order, String businessName) {
    final lines = <String>[
      'طلب جديد من: $businessName',
      'رقم الطلب: ${order.id}',
      '',
      'المنتجات:',
      for (var i = 0; i < order.items.length; i++)
        '${i + 1}. ${order.items[i].product.name} × ${order.items[i].quantity} — ${order.items[i].total.toStringAsFixed(2)} د.ل',
      '',
      'الإجمالي: ${order.total.toStringAsFixed(2)} د.ل',
      'ملاحظة العميل: ${order.customerNote.isEmpty ? 'لا توجد' : order.customerNote}',
    ];
    return lines.join('\n');
  }
}
