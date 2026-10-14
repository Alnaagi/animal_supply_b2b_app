import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/shop_skeleton.dart';
import '../../../data/models/admin_models.dart';
import '../../../data/repositories/admin_repository.dart';
import '../admin_storefront_controller.dart';

class StorefrontPagePanel extends ConsumerWidget {
  const StorefrontPagePanel({
    required this.state,
    required this.controller,
    super.key,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      key: const Key('storefront-page-panel'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _GroupedCard(
          title: 'جهاز المعاينة',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final device in StorefrontPreviewDevice.values)
                    ChoiceChip(
                      label: Text(device.labelAr),
                      avatar: Icon(_deviceIcon(device), size: 18),
                      selected: state.previewDevice == device,
                      onSelected: (_) => controller.setPreviewDevice(device),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GroupedCard(
          title: 'مصدر المعاينة',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('معاينة المسودة'),
                    selected: !state.previewPublished,
                    onSelected: (_) => controller.togglePreviewPublished(false),
                  ),
                  ChoiceChip(
                    label: const Text('معاينة المنشور'),
                    selected: state.previewPublished,
                    onSelected: (_) => controller.togglePreviewPublished(true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                state.previewPublished
                    ? 'تعرض المعاينة النسخة المنشورة للعملاء.'
                    : 'تعرض المعاينة المسودة الحالية قبل النشر.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GroupedCard(
          title: 'معاينة الأسعار',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<StorefrontPricePreviewMode>(
                initialValue: state.pricePreviewMode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'وضع السعر'),
                items: [
                  for (final mode in StorefrontPricePreviewMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(
                        mode.labelAr,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) controller.setPricePreviewMode(value);
                },
              ),
              if (state.pricePreviewMode ==
                  StorefrontPricePreviewMode.customerPreview) ...[
                const SizedBox(height: 8),
                _PreviewCustomerPicker(
                  selectedCustomerId: state.previewCustomerId,
                  onChanged: controller.setPreviewCustomerId,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push('/admin/storefront/preview'),
          icon: const Icon(Icons.open_in_full),
          label: const Text('معاينة ملء الشاشة'),
        ),
      ],
    );
  }

  IconData _deviceIcon(StorefrontPreviewDevice device) {
    switch (device) {
      case StorefrontPreviewDevice.phone:
        return Icons.smartphone_outlined;
      case StorefrontPreviewDevice.desktop:
        return Icons.desktop_windows_outlined;
    }
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _PreviewCustomerPicker extends ConsumerWidget {
  const _PreviewCustomerPicker({
    required this.selectedCustomerId,
    required this.onChanged,
  });

  final String? selectedCustomerId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(_previewCustomersProvider);
    return customersAsync.when(
      loading: () => const ShopSkeleton(
        semanticLabel: 'جارٍ تحميل العملاء...',
        child: ShopSkeletonBox(
          height: 48,
          borderRadius: 12,
        ),
      ),
      error: (_, __) => const Text('تعذر تحميل العملاء'),
      data: (customers) {
        if (customers.isEmpty) {
          return const Text('لا يوجد عملاء للمعاينة');
        }
        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'عميل المعاينة'),
          hint: const Text('اختر عميلاً'),
          initialValue: selectedCustomerId,
          items: [
            for (final customer in customers)
              DropdownMenuItem(
                value: customer.id,
                child: Text(customer.businessName),
              ),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

final _previewCustomersProvider = FutureProvider<List<BusinessCustomer>>(
  (ref) async {
    final page =
        await ref.read(adminRepositoryProvider).listCustomersPage(limit: 20);
    return page.customers.where((c) => c.accountStatus == 'active').toList();
  },
);
