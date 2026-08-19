import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/empty_state.dart';
import '../../core/widgets/shop_loading.dart';
import '../../core/widgets/shop_refresh_indicator.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../catalog/catalog_screen.dart';

class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  late Future<List<Product>> _offersFuture;

  @override
  void initState() {
    super.initState();
    _offersFuture = _loadOffers();
  }

  Future<List<Product>> _loadOffers() async {
    final products = await ref.read(catalogRepositoryProvider).products();
    return products
        .where((product) => (product.discountPercent ?? 0) > 0)
        .toList(growable: false);
  }

  Future<void> _reload() async {
    setState(() => _offersFuture = _loadOffers());
    await _offersFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العروض')),
      body: ShopRefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Product>>(
          future: _offersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ShopLoading.page();
            }
            if (snapshot.hasError) {
              return EmptyState(
                title: 'تعذر تحميل العروض',
                message: 'تحقق من الاتصال ثم أعد المحاولة.',
                icon: Icons.local_offer_outlined,
                action: FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              );
            }
            final offers = snapshot.data ?? const <Product>[];
            if (offers.isEmpty) {
              return const EmptyState(
                title: 'لا توجد عروض حالياً',
                message: 'ستظهر المنتجات المخفضة هنا عند توفرها.',
                icon: Icons.sell_outlined,
              );
            }
            return ListView(
              key: const Key('offers-screen-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'العروض المتاحة',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                for (final product in offers) ProductListCard(product: product),
              ],
            );
          },
        ),
      ),
    );
  }
}
