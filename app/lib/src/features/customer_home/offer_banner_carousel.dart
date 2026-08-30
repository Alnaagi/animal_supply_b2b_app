import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/routing/banner_destination.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shop_loading.dart';
import '../../data/models/admin_models.dart';

/// Breakpoints for customer-home / storefront banner composition.
abstract final class HomeBannerBreakpoints {
  static const double mobileMax = 600;
  static const double tabletMax = 900;
  static const double desktopMax = 1200;

  static bool isMobile(double width) => width < mobileMax;
  static bool isTablet(double width) => width >= mobileMax && width < tabletMax;
  static bool isDesktop(double width) =>
      width >= tabletMax && width < desktopMax;
  static bool isWide(double width) => width >= desktopMax;

  /// Responsive banner height. Legacy/default config heights (≤120) mean "auto".
  ///
  /// Uses the banner [BannerAspectMode] so the banner image fills the frame
  /// and shows the complete banner cleanly. Wide keeps the 1600:620 ratio strip; square is 1:1.
  static double resolveHeight(
    double width, {
    double? configuredHeight,
    BannerAspectMode aspectMode = BannerAspectMode.wide,
  }) {
    final fromAspect = width / aspectMode.ratio;
    final double auto;
    switch (aspectMode) {
      case BannerAspectMode.square:
        // Cap square height on large screens so home layout stays usable.
        auto = fromAspect.clamp(160.0, isMobile(width) ? width : 420.0);
      case BannerAspectMode.wide:
        auto = isMobile(width)
            ? fromAspect.clamp(152.0, 196.0)
            : isTablet(width)
                ? 228.0
                : isDesktop(width)
                    ? 280.0
                    : 320.0;
    }
    if (configuredHeight == null || configuredHeight <= 120) return auto;
    // Soft-follow admin preference without collapsing or over-stretching.
    return configuredHeight.clamp(auto * 0.82, auto * 1.18);
  }
}

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
    this.aspectMode = BannerAspectMode.wide,
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
  final BannerAspectMode aspectMode;

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
          aspectMode: banner.aspectMode,
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
    this.height,
    this.autoPlay = true,
    this.intervalSeconds = 4,
    this.showIndicators = true,
    this.borderRadius = 24,
    this.interactionEnabled = true,
  });

  final List<HomeBannerSlide> banners;
  final bool preview;

  /// When set, forces the phone or wide-web banner proportions used on
  /// customer home. Otherwise the layout follows the available width.
  final bool? compact;
  final double? height;
  final bool autoPlay;
  final int intervalSeconds;
  final bool showIndicators;
  final double borderRadius;
  final bool interactionEnabled;

  @override
  State<OfferBannerCarousel> createState() => _OfferBannerCarouselState();
}

class _OfferBannerCarouselState extends State<OfferBannerCarousel> {
  static const _virtualStartPage = 10000;
  static const _peekViewportFraction = .90;

  late PageController _controller;
  Timer? _timer;
  int _activeIndex = 0;
  int _currentPage = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _currentPage = _initialPage(widget.banners.length);
    _controller = PageController(
      initialPage: _currentPage,
      viewportFraction: _peekViewportFraction,
    );
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
    _currentPage = _initialPage(widget.banners.length);
    if (_controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpToPage(_currentPage);
      });
    } else {
      _controller.dispose();
      _controller = PageController(
        initialPage: _currentPage,
        viewportFraction: _peekViewportFraction,
      );
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

  int _initialPage(int slideCount) {
    if (slideCount < 2) return 0;
    return _virtualStartPage - (_virtualStartPage % slideCount);
  }

  void _startTimer() {
    if (_reduceMotion ||
        !widget.autoPlay ||
        widget.banners.length < 2 ||
        _timer != null) {
      return;
    }
    final seconds = widget.intervalSeconds.clamp(2, 30);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!_controller.hasClients || !mounted) return;
      final next = _currentPage + 1;
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
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final hasPeek = banners.length > 1;
          final renderedPageWidth =
              width * (hasPeek ? _peekViewportFraction : 1);
          final mobileLayout =
              widget.compact ?? HomeBannerBreakpoints.isMobile(width);
          final frameAspect = _stableFrameAspect(banners);
          final resolvedHeight = HomeBannerBreakpoints.resolveHeight(
            renderedPageWidth,
            configuredHeight: widget.height,
            aspectMode: frameAspect,
          );
          final frame = SizedBox(
            key: const Key('offer-banner-carousel-frame'),
            height: resolvedHeight,
            width: double.infinity,
            child: banners.length == 1
                ? _OfferBannerCard(
                    banner: banners.first,
                    preview: widget.preview || !widget.interactionEnabled,
                    compact:
                        mobileLayout || HomeBannerBreakpoints.isTablet(width),
                    borderRadius: widget.borderRadius,
                  )
                : PageView.builder(
                    key: const Key('offer-banner-peek-page-view'),
                    controller: _controller,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (page) {
                      final index = page % banners.length;
                      _currentPage = page;
                      if (_activeIndex == index) return;
                      setState(() => _activeIndex = index);
                    },
                    itemBuilder: (context, page) {
                      final index = page % banners.length;
                      return AnimatedBuilder(
                        key: ValueKey('offer-banner-page-$page'),
                        animation: _controller,
                        child: _OfferBannerCard(
                          banner: banners[index],
                          preview: widget.preview || !widget.interactionEnabled,
                          compact: mobileLayout ||
                              HomeBannerBreakpoints.isTablet(width),
                          borderRadius: widget.borderRadius,
                        ),
                        builder: (context, child) {
                          if (_reduceMotion) return child!;
                          final current = _controller.hasClients &&
                                  _controller.position.haveDimensions
                              ? _controller.page ?? _currentPage.toDouble()
                              : _currentPage.toDouble();
                          final distance =
                              (current - page).abs().clamp(0.0, 1.0);
                          final scale = 1 - (distance * .055);
                          return Transform.scale(
                            scale: scale,
                            alignment: Alignment.center,
                            child: child,
                          );
                        },
                      );
                    },
                  ),
          );
          if (_reduceMotion) return frame;
          return AnimatedSize(
            key: ValueKey<double>(resolvedHeight),
            duration: AppMotion.standard,
            curve: AppMotion.standardCurve,
            alignment: Alignment.topCenter,
            child: frame,
          );
        },
      ),
      if (widget.showIndicators) ...[
        const SizedBox(height: 10),
        Builder(
          builder: (context) {
            final primary = Theme.of(context).colorScheme.primary;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < banners.length; i++)
                  Semantics(
                    label:
                        'العرض ${i + 1} من ${banners.length}${_activeIndex == i ? '، معروض حالياً' : ''}',
                    selected: _activeIndex == i,
                    child: AnimatedContainer(
                      key: ValueKey('offer-banner-indicator-$i'),
                      duration:
                          _reduceMotion ? Duration.zero : AppMotion.standard,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _activeIndex == i ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: _activeIndex == i
                            ? primary
                            : primary.withValues(alpha: .22),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ]);
  }
}

BannerAspectMode _stableFrameAspect(List<HomeBannerSlide> banners) {
  final first = banners.first.aspectMode;
  for (final banner in banners.skip(1)) {
    if (banner.aspectMode != first) return BannerAspectMode.wide;
  }
  return first;
}

class _OfferBannerCard extends StatelessWidget {
  const _OfferBannerCard({
    required this.banner,
    required this.preview,
    required this.compact,
    this.borderRadius = 24,
  });

  final HomeBannerSlide banner;
  final bool preview;
  final bool compact;
  final double borderRadius;

  Future<void> _openDestination(BuildContext context) async {
    if (preview) return;
    final externalUri = banner.destination.externalUri;
    if (externalUri == null) {
      if (banner.destination.path.isNotEmpty) {
        context.go(banner.destination.path);
      }
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
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDestination(context),
          child: _OverlayBanner(
            banner: banner,
            compact: compact,
          ),
        ),
      ),
    );
  }
}

class _BannerImage extends StatelessWidget {
  const _BannerImage({required this.imageUrl, this.alignment});

  final String imageUrl;
  final Alignment? alignment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final fallbackDecoration = BoxDecoration(
      gradient: LinearGradient(
        colors: [colors.primary, colors.secondary],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
    );
    return Image.network(
      imageUrl,
      fit: BoxFit.fill,
      alignment: alignment ?? Alignment.center,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      width: double.infinity,
      height: double.infinity,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return DecoratedBox(
          key: const Key('offer-banner-image-loading'),
          decoration: fallbackDecoration,
          child: Center(
            child: reduceMotion
                ? Icon(
                    Icons.image_outlined,
                    color: colors.onPrimary,
                    size: 28,
                  )
                : ShopLoading.compact(
                    size: 22,
                    color: colors.onPrimary,
                    light: true,
                  ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return DecoratedBox(
          key: const Key('offer-banner-image-error'),
          decoration: fallbackDecoration,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 24),
              child: Icon(
                Icons.pets,
                color: colors.onPrimary.withValues(alpha: .30),
                size: 112,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Full-bleed clean banner image.
class _OverlayBanner extends StatelessWidget {
  const _OverlayBanner({
    required this.banner,
    required this.compact,
  });

  final HomeBannerSlide banner;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('offer-banner-overlay'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary, colors.secondary],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: _BannerImage(
        imageUrl: banner.imageUrl,
        alignment: compact
            ? const Alignment(0, -0.08)
            : const Alignment(0.15, 0),
      ),
    );
  }
}
