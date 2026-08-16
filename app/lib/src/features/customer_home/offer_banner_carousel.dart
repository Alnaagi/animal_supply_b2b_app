import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/routing/banner_destination.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/admin_models.dart';

class HomeBannerSlide {
  const HomeBannerSlide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.imageUrl,
    required this.category,
    required this.destination,
    required this.sourceUrl,
    required this.isDemo,
  });

  final String id;
  final String title;
  final String subtitle;
  final String cta;
  final String imageUrl;
  final String category;
  final BannerDestination destination;
  final String sourceUrl;
  final bool isDemo;

  static List<HomeBannerSlide> fromAdminBanners(List<AppBanner> banners) {
    return [
      for (final banner in banners)
        HomeBannerSlide(
          id: banner.id,
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

  static List<HomeBannerSlide> demo() {
    // External demo photo URLs only. Do not copy these images into the repo.
    // Replace with client-approved Supabase Storage banners before production.
    return [
      HomeBannerSlide(
        id: 'demo-1',
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
      HomeBannerSlide(
        id: 'demo-2',
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
      HomeBannerSlide(
        id: 'demo-3',
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
      HomeBannerSlide(
        id: 'demo-4',
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
      const HomeBannerSlide(
        id: 'demo-5',
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

class OfferBannerCarousel extends StatefulWidget {
  const OfferBannerCarousel({
    super.key,
    required this.banners,
    this.preview = false,
    this.compact,
  });

  final List<HomeBannerSlide> banners;
  final bool preview;

  /// When set, forces the phone or wide-web banner proportions used on
  /// customer home. Otherwise the layout follows the available width.
  final bool? compact;

  @override
  State<OfferBannerCarousel> createState() => _OfferBannerCarouselState();
}

class _OfferBannerCarouselState extends State<OfferBannerCarousel> {
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
  void didUpdateWidget(covariant OfferBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_slidesChanged(oldWidget.banners, widget.banners)) return;
    _timer?.cancel();
    _timer = null;
    _activeIndex = 0;
    if (_controller.hasClients) {
      _controller.jumpToPage(0);
    }
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool _slidesChanged(
    List<HomeBannerSlide> previous,
    List<HomeBannerSlide> next,
  ) {
    if (previous.length != next.length) return true;
    for (var i = 0; i < next.length; i++) {
      if (previous[i].id != next[i].id) return true;
    }
    return false;
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
          final compact = widget.compact ?? width < 640;
          final height = compact
              ? 240.0
              : width >= 900
                  ? 280.0
                  : 250.0;
          return SizedBox(
            height: height,
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (index) {
                if (_activeIndex == index) return;
                setState(() => _activeIndex = index);
              },
              itemCount: banners.length,
              itemBuilder: (context, index) => _OfferBannerCard(
                banner: banners[index],
                preview: widget.preview,
                compact: compact,
              ),
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
  const _OfferBannerCard({
    required this.banner,
    required this.preview,
    required this.compact,
  });

  final HomeBannerSlide banner;
  final bool preview;
  final bool compact;

  Future<void> _openDestination(BuildContext context) async {
    if (preview) return;
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
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDestination(context),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
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
                      child: ShopLoading.compact(
                        size: 22,
                        color: Colors.white,
                        light: true,
                      ),
                    ),
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
                  constraints: BoxConstraints(maxWidth: compact ? 280 : 520),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 16 : 22),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
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
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
