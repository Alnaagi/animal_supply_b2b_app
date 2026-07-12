import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import 'cart_controller.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartControllerProvider);
    final user = ref.watch(authControllerProvider).user!;
    final total = items.fold<double>(0, (sum, item) => sum + item.total);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: () => context.go('/cart'),
        ),
        title: const Text('تأكيد الطلب'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
              child: ListTile(
                  title: Text(user.businessName ?? user.username),
                  subtitle:
                      const Text('طرابلس - حي الأندلس\nعنوان العميل التجاري'))),
          const SizedBox(height: 10),
          for (final item in items)
            Card(
                child: ListTile(
                    title: Text(item.product.name),
                    subtitle:
                        Text('${item.quantity} × ${lyd(item.product.price)}'),
                    trailing: Text(lyd(item.total)))),
          TextField(
              controller: note,
              minLines: 3,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'ملاحظة العميل')),
          const SizedBox(height: 12),
          Text('الإجمالي: ${lyd(total)}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: items.isEmpty
                ? null
                : () async {
                    final order = await ref
                        .read(cartControllerProvider.notifier)
                        .submit(note.text);
                    final summary = ref
                        .read(ordersRepositoryProvider)
                        .whatsappSummary(
                            order, user.businessName ?? user.username);
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('تم إرسال الطلب بنجاح'),
                        content: Text('رقم الطلب: ${order.id}'),
                        actions: [
                          TextButton(
                              onPressed: () => Clipboard.setData(
                                  ClipboardData(text: summary)),
                              child: const Text('نسخ ملخص الطلب للواتساب')),
                          TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                context.go('/orders');
                              },
                              child: const Text('عرض الطلب')),
                        ],
                      ),
                    );
                  },
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }
}
