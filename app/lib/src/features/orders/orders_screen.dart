import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_controller.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    return FutureBuilder(
      future: ref
          .read(ordersRepositoryProvider)
          .ordersForCustomer(user.customerId ?? user.id),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? const [];
        if (orders.isEmpty) {
          return EmptyState(
              title: 'لا توجد طلبات',
              message: 'طلباتك المرسلة ستظهر هنا.',
              action: FilledButton(
                  onPressed: () => context.go('/catalog'),
                  child: const Text('ابدأ الطلب')));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('طلباتي',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            for (final order in orders)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  title: Text('طلب ${order.id}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(
                      '${order.createdAt.year}/${order.createdAt.month}/${order.createdAt.day} • ${order.items.length} منتجات'),
                  trailing: StatusChip.order(order.status),
                  children: [
                    for (final item in order.items)
                      ListTile(
                          title: Text(item.product.name),
                          subtitle: Text(item.product.sku),
                          trailing: Text(
                              '${item.quantity} × ${lyd(item.product.price)}')),
                    ListTile(
                        title: const Text('الإجمالي'),
                        trailing: Text(lyd(order.total),
                            style:
                                const TextStyle(fontWeight: FontWeight.w900))),
                    const ListTile(
                        title: Text('مسار الحالة'),
                        subtitle: Text(
                            'قيد المراجعة ← مؤكد ← تجهيز ← جاهز ← تم التسليم')),
                    if (order.customerNote.isNotEmpty)
                      ListTile(
                          title: const Text('ملاحظة العميل'),
                          subtitle: Text(order.customerNote)),
                    OverflowBar(children: [
                      TextButton(
                          onPressed: () {
                            for (final item in order.items) {
                              ref
                                  .read(cartControllerProvider.notifier)
                                  .addQuantity(item.product, item.quantity);
                            }
                            context.go('/cart');
                          },
                          child: const Text('إعادة الطلب')),
                      TextButton(
                          onPressed: () {
                            final summary = ref
                                .read(ordersRepositoryProvider)
                                .whatsappSummary(
                                    order, user.businessName ?? user.username);
                            Clipboard.setData(ClipboardData(text: summary));
                          },
                          child: const Text('نسخ ملخص واتساب')),
                    ]),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
