import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/routing/banner_destination.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/price_text.dart';
import '../../core/widgets/product_image_placeholder.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/product.dart';
import '../../data/models/order.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../auth/auth_controller.dart';
import '../cart/cart_controller.dart';
import '../notifications/notification_center_sheet.dart';

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  Future<List<Product>>? _productsFuture;
  Future<List<Order>>? _ordersFuture;
  Future<List<AppBanner>>? _bannersFuture;
  String? _homeCustomerKey;
  bool _reordering = false;

  void _ensureHomeFutures(String customerKey) {
    if (_productsFuture != null && _homeCustomerKey == customerKey) return;
    _homeCustomerKey = customerKey;
    _productsFuture = ref.read(catalogRepositoryProvider).products();
    _ordersFuture =
        ref.read(ordersRepositoryProvider).ordersForCustomer(customerKey);
    _bannersFuture = ref.read(adminRepositoryProvider).banners();
  }

  void _reloadHome() {
    _productsFuture = null;
    _ordersFuture = null;
    _bannersFuture = null;
    ref.invalidate(unreadNotificationsCountProvider);
    _homeCustomerKey = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user =
        ref.watch(authControllerProvider.select((state) => state.user))!;
    final customerKey = user.customerId ?? user.id;
    _ensureHomeFutures(customerKey);
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;
    final location = [
      user.city,
      user.area,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(
          ' - ',
        );

    return ListView(
      key: const Key('customer-home-scroll'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مرحباً، ${user.businessName ?? user.username}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  location,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ]),
          ),
          IconButton.filledTonal(
              tooltip: 'البحث في المنتجات',
              onPressed: () => context.go('/catalog'),
              icon: const Icon(Icons.search)),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'الإشعارات',
            onPressed: () => showNotificationCenter(context, ref),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_none),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        FutureBuilder<List<AppBanner>>(
          future: _bannersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _HomeSectionLoading(
                label: 'جارٍ تحميل العروض...',
                height: 88,
              );
            }
            if (snapshot.hasError) {
              return _HomeSectionNotice(
                icon: Icons.image_not_supported_outlined,
                title: 'تعذر تحميل العروض',
                message: 'يمكنك متابعة تصفح المنتجات والطلب بشكل طبيعي.',
                onRetry: _reloadHome,
              );
            }
            final banners = AppConfig.remoteBackendEnabled
                ? _HomeBannerData.fromAdminBanners(snapshot.data ?? const [])
                : _HomeBannerData.demo();
            if (banners.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                // Owns its own PageController/timer/setState so banner ticks
                // never rebuild product lists below.
                _OfferBannerCarousel(banners: banners),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
        FutureBuilder<List<Product>>(
          future: _productsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _HomeSectionLoading(
                label: 'جارٍ تحميل المنتجات...',
                height: 180,
              );
            }
            if (snapshot.hasError) {
              return _HomeSectionNotice(
                icon: Icons.cloud_off_outlined,
                title: 'تعذر تحميل المنتجات',
                message:
                    'لم نجد كتالوجاً محفوظاً على هذا الجهاز. تحقق من الاتصال ثم أعد المحاولة.',
                onRetry: _reloadHome,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _productSections(snapshot.data ?? const []),
            );
          },
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Order>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _HomeSectionLoading(
                label: 'جارٍ تحديث آخر الطلبات...',
                height: 72,
              );
            }
            if (snapshot.hasError) {
              return _HomeSectionNotice(
                icon: Icons.receipt_long_outlined,
                title: 'تعذر تحديث آخر الطلبات',
                message:
                    'الكتالوج والسلة ما زالا متاحين، ويمكنك مراجعة الطلبات لاحقاً.',
                onRetry: _reloadHome,
              );
            }
            final orders = snapshot.data ?? const [];
            if (orders.isEmpty) return const SizedBox.shrink();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.refresh, color: AppTheme.green),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'إعادة آخر طلب (${orders.first.items.length} منتجات)',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  FilledButton(
                    onPressed:
                        _reordering ? null : () => _reorder(orders.first),
                    child: _reordering
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('إعادة الطلب'),
                  ),
                ]),
              ),
            );
          },
        ),
      ],
    );
  }

  List<Widget> _productSections(List<Product> products) {
    if (products.isEmpty) {
      return [
        const EmptyState(
          title: 'لا توجد منتجات متاحة',
          message: 'ستظهر المنتجات النشطة هنا بعد إضافتها من الإدارة.',
          icon: Icons.inventory_2_outlined,
        ),
      ];
    }

    final categories =
        products.map((product) => product.category).toSet().toList();
    final latest = products.take(12).toList(growable: false);
    return [
      _SectionHeader(title: 'التصنيفات', onTap: () => context.go('/catalog')),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
            children: categories
                .map((category) => _CategoryCircle(
                    label: category,
                    onTap: () => context.go(
                        '/catalog?category=${Uri.encodeComponent(category)}')))
                .toList()),
      ),
      const SizedBox(height: 20),
      _SectionHeader(
          title: 'أحدث المنتجات', onTap: () => context.go('/catalog')),
      const SizedBox(height: 10),
      SizedBox(
        height: 300,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: latest.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) =>
              _HomeProductCard(product: latest[index]),
        ),
      ),
    ];
  }

  Future<void> _reorder(Order order) async {
    if (_reordering) return;
    setState(() => _reordering = true);

    var added = 0;
    var unavailable = 0;
    var adjusted = 0;
    var repriced = 0;
    final resolvedItems = <({Product product, int quantity})>[];

    try {
      final catalog = ref.read(catalogRepositoryProvider);
      for (final item in order.items) {
        final current = await catalog.productById(item.productId);
        if (!mounted) return;
        if (current == null ||
            !current.active ||
            current.isArchived ||
            !current.isOrderable) {
          unavailable++;
          continue;
        }

        final quantity = current.normalizeOrderQuantity(item.quantity);
        if (quantity != item.quantity) adjusted++;
        if ((current.price - item.unitPrice).abs() >= 0.005) repriced++;
        resolvedItems.add((product: current, quantity: quantity));
      }

      if (resolvedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('منتجات هذا الطلب غير متاحة حالياً لإضافتها من جديد.'),
          ),
        );
        return;
      }

      final cart = ref.read(cartControllerProvider.notifier);
      for (final item in resolvedItems) {
        cart.addQuantity(item.product, item.quantity);
        added++;
      }

      if (unavailable > 0 || adjusted > 0 || repriced > 0) {
        final parts = <String>[
          if (unavailable > 0) 'تعذر إضافة $unavailable منتج',
          if (adjusted > 0)
            'تم تعديل كمية $adjusted منتج حسب المخزون والحد الأدنى',
          if (repriced > 0) 'تم تحديث سعر $repriced منتج للسعر الحالي',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${parts.join('، ')}.')),
        );
      }
      if (added > 0 && mounted) context.go('/cart');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر التحقق من الأسعار والمخزون الحاليين. '
            'لم تتغير السلة، تحقق من الاتصال وحاول مجدداً.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }
}

class _HomeSectionLoading extends StatelessWidget {
  const _HomeSectionLoading({
    required this.label,
    required this.height,
  });

  final String label;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              Text(label),
            ],
          ),
        ),
      );
}

class _HomeSectionNotice extends StatelessWidget {
  const _HomeSectionNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(message),
                  ],
                ),
              ),
              if (onRetry != null)
                IconButton(
                  onPressed: onRetry,
                  tooltip: 'إعادة المحاولة',
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
        ),
      );
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
    required this.destination,
    required this.sourceUrl,
    required this.isDemo,
  });

  final String title;
  final String subtitle;
  final String cta;
  final String imageUrl;
  final String category;
  final BannerDestination destination;
  final String sourceUrl;
  final bool isDemo;

  static List<_HomeBannerData> fromAdminBanners(List<AppBanner> banners) {
    return [
      for (final banner in banners)
        _HomeBannerData(
          title: banner.title,
          subtitle: banner.body,
          cta: banner.ctaText,
          imageUrl: banner.imageUrl,
          category: banner.targetType,
          destination: resolveBannerDestination(
            targetType: banner.targetType,
            targetValue: banner.targetValue,
          ),
          sourceUrl: '',
          isDemo: false,
        ),
    ];
  }

  static List<_HomeBannerData> demo() {
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
        destination: BannerDestination.internal(
          '/catalog?category=${Uri.encodeComponent('كلاب')}',
        ),
        isDemo: true,
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
        destination: BannerDestination.internal(
          '/catalog?category=${Uri.encodeComponent('قطط')}',
        ),
        isDemo: true,
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
        destination: BannerDestination.internal(
          '/catalog?category=${Uri.encodeComponent('طيور')}',
        ),
        isDemo: true,
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
        destination: BannerDestination.internal(
          '/catalog?category=${Uri.encodeComponent('أسماك')}',
        ),
        isDemo: true,
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
        destination: BannerDestination.internal('/catalog'),
        isDemo: true,
      ),
    ];
  }
}

class _OfferBannerCarousel extends StatefulWidget {
  const _OfferBannerCarousel({required this.banners});

  final List<_HomeBannerData> banners;

  @override
  State<_OfferBannerCarousel> createState() => _OfferBannerCarouselState();
}

class _OfferBannerCarouselState extends State<_OfferBannerCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _activeIndex = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _timer?.cancel();
    _timer = null;
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _OfferBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length) {
      _timer?.cancel();
      _timer = null;
      _activeIndex = 0;
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (_reduceMotion || widget.banners.length < 2 || _timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_controller.hasClients || !mounted) return;
      final next = (_activeIndex + 1) % widget.banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    return Column(children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = width >= 900
              ? 280.0
              : width >= 640
                  ? 250.0
                  : 240.0;
          return SizedBox(
            height: height,
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (index) {
                if (_activeIndex == index) return;
                setState(() => _activeIndex = index);
              },
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
            Semantics(
              label:
                  'العرض ${i + 1} من ${banners.length}${_activeIndex == i ? '، معروض حالياً' : ''}',
              selected: _activeIndex == i,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _activeIndex == i ? 22 : 7,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: _activeIndex == i
                      ? AppTheme.green
                      : AppTheme.green.withValues(alpha: .22),
                ),
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

  Future<void> _openDestination(BuildContext context) async {
    final externalUri = banner.destination.externalUri;
    if (externalUri == null) {
      context.go(banner.destination.path);
      return;
    }
    final opened = await launchUrl(
      externalUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح رابط العرض حالياً')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => _openDestination(context),
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
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
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
                  padding: EdgeInsets.all(
                      MediaQuery.sizeOf(context).width < 420 ? 16 : 22),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (banner.isDemo) ...[
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
                          const SizedBox(height: 8),
                        ],
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
                        const SizedBox(height: 6),
                        Text(
                          banner.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTheme.green),
                          onPressed: () => _openDestination(context),
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
        onTap: () => context.push('/product/${product.id}'),
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
            Center(
                child: ProductImagePlaceholder(
                    category: product.category,
                    productId: product.id,
                    imageUrl: product.imageUrl,
                    size: 92)),
            const SizedBox(height: 8),
            Text(product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            if (product.brand.trim().isNotEmpty)
              Text(product.brand,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Spacer(),
            const Text(
              'سعر الجملة',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            PriceText(price: product.price),
            if (product.retailUnitPrice != null)
              Text(
                'بيع الوحدة: '
                '${product.retailUnitPrice!.toStringAsFixed(2)} د.ل',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            Row(children: [
              Text(product.isOrderable ? 'متوفر' : 'غير متوفر',
                  style: TextStyle(
                      color:
                          product.isOrderable ? AppTheme.green : AppTheme.red,
                      fontSize: 12)),
              const Spacer(),
              IconButton.filled(
                  tooltip: 'إضافة ${product.name} إلى السلة',
                  onPressed: product.isOrderable
                      ? () =>
                          ref.read(cartControllerProvider.notifier).add(product)
                      : null,
                  icon: const Icon(Icons.add)),
            ]),
          ]),
        ),
      );
}
