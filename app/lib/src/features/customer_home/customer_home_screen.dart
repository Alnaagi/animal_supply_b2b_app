import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../data/models/product.dart';
import '../../data/models/order.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_controller.dart';

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  final _bannerController = PageController();
  Timer? _bannerTimer;
  int _activeBanner = 0;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  void _startBannerTimer(int count) {
    if (count < 2 || _bannerTimer != null) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_bannerController.hasClients || !mounted) return;
      final next = (_activeBanner + 1) % count;
      _bannerController.animateToPage(next,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user!;
    return FutureBuilder(
      future: Future.wait([
        ref.read(catalogRepositoryProvider).products(),
        ref
            .read(ordersRepositoryProvider)
            .ordersForCustomer(user.customerId ?? user.id),
      ]),
      builder: (context, snapshot) {
        final products = (snapshot.data?[0] ?? <Product>[]) as List<Product>;
        final orders = (snapshot.data?[1] ?? <Order>[]) as List<Order>;
        final categories =
            products.map((product) => product.category).toSet().toList();
        final top = products.where((p) => p.isTopSelling).toList();
        final offers =
            products.where((p) => p.discountPercent != null).toList();
        final banners = _HomeBannerData.fromProducts(products);
        _startBannerTimer(banners.length);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('مرحباً، ${user.businessName ?? user.username}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      const Text('طرابلس - حي الأندلس',
                          style: TextStyle(color: Colors.grey)),
                    ]),
              ),
              IconButton.filledTonal(
                  onPressed: () => context.go('/catalog'),
                  icon: const Icon(Icons.search)),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                  onPressed: () {}, icon: const Icon(Icons.notifications_none)),
            ]),
            const SizedBox(height: 16),
            _OfferBannerCarousel(
              banners: banners,
              controller: _bannerController,
              activeIndex: _activeBanner,
              onChanged: (index) => setState(() => _activeBanner = index),
            ),
            const SizedBox(height: 20),
            _SectionHeader(
                title: 'التصنيفات', onTap: () => context.go('/catalog')),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                  children: categories
                      .map((c) => _CategoryCircle(
                          label: c,
                          onTap: () => context.go(
                              '/catalog?category=${Uri.encodeComponent(c)}')))
                      .toList()),
            ),
            const SizedBox(height: 20),
            _SectionHeader(
                title: 'الأكثر طلباً', onTap: () => context.go('/catalog')),
            const SizedBox(height: 10),
            SizedBox(
              height: 248,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: top.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _HomeProductCard(product: top[index]),
              ),
            ),
            const SizedBox(height: 20),
            _SectionHeader(
                title: 'آخر العروض', onTap: () => context.go('/catalog')),
            const SizedBox(height: 10),
            if (offers.isEmpty)
              const EmptyState(
                  title: 'لا توجد عروض حالياً',
                  message: 'ستظهر العروض الجديدة هنا.',
                  icon: Icons.local_offer_outlined)
            else
              for (final product in offers.take(3))
                Card(
                  child: ListTile(
                    leading: ProductImagePlaceholder(
                        category: product.category,
                        productId: product.id,
                        imageUrl: product.imageUrl,
                        size: 56),
                    title: Text(product.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${product.discountPercent}% خصم • ${product.sku}'),
                    trailing: PriceText(
                        price: product.price, oldPrice: product.oldPrice),
                    onTap: () => context.go('/product/${product.id}'),
                  ),
                ),
            const SizedBox(height: 12),
            if (orders.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.refresh, color: AppTheme.green),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            'إعادة آخر طلب (${orders.first.items.length} منتجات)',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                    FilledButton(
                        onPressed: () {
                          for (final item in orders.first.items) {
                            ref
                                .read(cartControllerProvider.notifier)
                                .add(item.product);
                          }
                          context.go('/cart');
                        },
                        child: const Text('إعادة الطلب')),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onTap});
  final String title;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const Spacer(),
        TextButton(onPressed: onTap, child: const Text('عرض الكل')),
      ]);
}

class _HomeBannerData {
  const _HomeBannerData({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.imageUrl,
    required this.category,
    required this.onTapPath,
    required this.sourceUrl,
  });

  final String title;
  final String subtitle;
  final String cta;
  final String imageUrl;
  final String category;
  final String onTapPath;
  final String sourceUrl;

  static List<_HomeBannerData> fromProducts(List<Product> products) {
    // External demo photo URLs only. Do not copy these images into the repo.
    // Replace with client-approved Supabase Storage banners before production.
    return [
      _HomeBannerData(
        title: 'عروض خاصة لتجار مستلزمات الحيوانات',
        subtitle: 'أصناف قطط وكلاب بالجملة مع أسعار تجريبية للعرض',
        cta: 'تسوق الآن',
        imageUrl:
            'https://images.unsplash.com/photo-1714068691210-073dc52c6c1d?auto=format&fit=crop&w=1600&h=620&q=80',
        sourceUrl:
            'https://unsplash.com/photos/a-brown-and-white-dog-eating-food-out-of-a-bowl-Qvbr5Uxgz_Q',
        category: 'كلاب',
        onTapPath: '/catalog?category=${Uri.encodeComponent('كلاب')}',
      ),
      _HomeBannerData(
        title: 'توريد أكل قطط للمحال والعيادات',
        subtitle: 'منتجات مختارة بكميات جملة وحد أدنى مناسب للطلبات',
        cta: 'منتجات القطط',
        imageUrl:
            'https://images.unsplash.com/photo-1520811607976-6d7812b0ecac?auto=format&fit=crop&w=1600&h=620&q=80',
        sourceUrl:
            'https://unsplash.com/photos/two-gray-and-black-cats-eating-food-on-white-plastic-pet-bowl-2Cl0lX_4bag',
        category: 'قطط',
        onTapPath: '/catalog?category=${Uri.encodeComponent('قطط')}',
      ),
      _HomeBannerData(
        title: 'أغذية وأدوات الطيور',
        subtitle: 'خلطات بذور، مكملات، وأقفاص للتوريد التجاري',
        cta: 'تصفح الطيور',
        imageUrl:
            'https://images.unsplash.com/photo-1728774266756-abd3d2b36047?auto=format&fit=crop&w=1600&h=620&q=80',
        sourceUrl:
            'https://unsplash.com/photos/a-bird-is-eating-seeds-from-a-bird-feeder--9IwHUIqdXM',
        category: 'طيور',
        onTapPath: '/catalog?category=${Uri.encodeComponent('طيور')}',
      ),
      _HomeBannerData(
        title: 'مستلزمات أحواض وأسماك',
        subtitle: 'طعام أسماك ومنظفات ومستلزمات للأحواض',
        cta: 'منتجات الأسماك',
        imageUrl:
            'https://images.unsplash.com/photo-1732312645795-c25b0f4f5759?auto=format&fit=crop&w=1600&h=620&q=80',
        sourceUrl:
            'https://unsplash.com/photos/a-large-aquarium-filled-with-lots-of-different-types-of-fish-kHjAZor7dh0',
        category: 'أسماك',
        onTapPath: '/catalog?category=${Uri.encodeComponent('أسماك')}',
      ),
      const _HomeBannerData(
        title: 'طلبات علف ومستلزمات بالجملة',
        subtitle: 'جهز طلبك بسرعة وسيقوم فريق المتجر بالتأكيد عبر واتساب',
        cta: 'عرض كل المنتجات',
        imageUrl:
            'https://images.unsplash.com/photo-1758778820716-df5ab0444e93?auto=format&fit=crop&w=1600&h=620&q=80',
        sourceUrl:
            'https://unsplash.com/photos/a-bird-feeder-filled-with-seed-and-suet-jUJoWw1pdGI',
        category: 'مستلزمات',
        onTapPath: '/catalog',
      ),
    ];
  }
}

class _OfferBannerCarousel extends StatelessWidget {
  const _OfferBannerCarousel({
    required this.banners,
    required this.controller,
    required this.activeIndex,
    required this.onChanged,
  });

  final List<_HomeBannerData> banners;
  final PageController controller;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = width >= 900
              ? 280.0
              : width >= 640
                  ? 230.0
                  : 184.0;
          return SizedBox(
            height: height,
            child: PageView.builder(
              controller: controller,
              onPageChanged: onChanged,
              itemCount: banners.length,
              itemBuilder: (context, index) =>
                  _OfferBannerCard(banner: banners[index]),
            ),
          );
        },
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < banners.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: activeIndex == i ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: activeIndex == i
                    ? AppTheme.green
                    : AppTheme.green.withValues(alpha: .22),
              ),
            ),
        ],
      ),
    ]);
  }
}

class _OfferBannerCard extends StatelessWidget {
  const _OfferBannerCard({required this.banner});
  final _HomeBannerData banner;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => context.go(banner.onTapPath),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
                colors: [AppTheme.green, AppTheme.darkGreen],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft),
          ),
          child: Stack(fit: StackFit.expand, children: [
            Image.network(
              banner.imageUrl,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppTheme.green, AppTheme.darkGreen],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft),
                  ),
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.white)),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [AppTheme.green, AppTheme.darkGreen],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft),
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 24),
                      child: Icon(Icons.pets,
                          color: Colors.white.withValues(alpha: .24),
                          size: 112),
                    ),
                  ),
                );
              },
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: .70),
                      Colors.black.withValues(alpha: .36),
                      Colors.black.withValues(alpha: .08),
                    ],
                    stops: const [0, .54, 1],
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                  ),
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(99)),
                          child: const Text('بانر تجريبي من الإنترنت',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12)),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          banner.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  height: 1.12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          banner.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTheme.green),
                          onPressed: () => context.go(banner.onTapPath),
                          icon: const Icon(Icons.arrow_back),
                          label: Text(banner.cta),
                        ),
                      ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CategoryCircle extends StatelessWidget {
  const _CategoryCircle({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(children: [
              ProductImagePlaceholder(category: label, size: 64),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class _HomeProductCard extends ConsumerWidget {
  const _HomeProductCard({required this.product});
  final Product product;
  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
        onTap: () => context.go('/product/${product.id}'),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 170,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))
              ]),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Center(
                  child: ProductImagePlaceholder(
                      category: product.category,
                      productId: product.id,
                      imageUrl: product.imageUrl,
                      size: 92)),
              if (product.discountPercent != null)
                Positioned(
                    top: 0,
                    right: 0,
                    child: Chip(
                        label: Text('${product.discountPercent}%'),
                        visualDensity: VisualDensity.compact)),
            ]),
            const SizedBox(height: 8),
            Text(product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(product.sku,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Spacer(),
            PriceText(price: product.price, oldPrice: product.oldPrice),
            Row(children: [
              Text(product.inStock ? 'متوفر' : 'نفد',
                  style: TextStyle(
                      color: product.inStock ? AppTheme.green : AppTheme.red,
                      fontSize: 12)),
              const Spacer(),
              IconButton.filled(
                  onPressed: product.inStock
                      ? () =>
                          ref.read(cartControllerProvider.notifier).add(product)
                      : null,
                  icon: const Icon(Icons.add)),
            ]),
          ]),
        ),
      );
}
