import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One lightweight shimmer animation shared by every placeholder in [child].
class ShopSkeleton extends StatefulWidget {
  const ShopSkeleton({
    required this.child,
    this.semanticLabel = 'جارٍ تحميل المحتوى',
    super.key,
  });

  final Widget child;
  final String semanticLabel;

  @override
  State<ShopSkeleton> createState() => _ShopSkeletonState();
}

class _ShopSkeletonState extends State<ShopSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _animationsDisabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_animationsDisabled == disabled) return;
    _animationsDisabled = disabled;
    if (disabled) {
      _motion
        ..stop()
        ..value = .45;
    } else {
      _motion.repeat();
    }
  }

  @override
  void initState() {
    super.initState();
    _motion.repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('shop-skeleton'),
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      liveRegion: true,
      child: RepaintBoundary(
        child: _ShopSkeletonMotion(
          animation: _motion,
          child: widget.child,
        ),
      ),
    );
  }
}

class ShopSkeletonBox extends StatelessWidget {
  const ShopSkeletonBox({
    this.width,
    required this.height,
    this.borderRadius = 14,
    this.margin,
    super.key,
  });

  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final motion = _ShopSkeletonMotion.maybeOf(context);
    if (motion == null) {
      return _box(context: context, progress: .45);
    }
    return AnimatedBuilder(
      animation: motion,
      builder: (context, _) => _box(context: context, progress: motion.value),
    );
  }

  Widget _box({required BuildContext context, required double progress}) {
    final isRtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final travel = isRtl
        ? 1.7 - (progress * 3.4)
        : -1.7 + (progress * 3.4);
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.72);
    final highlight = Color.alphaBlend(
      scheme.primary.withValues(alpha: .07),
      scheme.surface,
    );
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(travel - .7, 0),
          end: Alignment(travel + .7, 0),
          colors: [base, highlight, base],
          stops: const [0, .5, 1],
        ),
      ),
    );
  }
}

class ShopSkeletonCircle extends StatelessWidget {
  const ShopSkeletonCircle({
    required this.size,
    this.margin,
    super.key,
  });

  final double size;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return ShopSkeletonBox(
      width: size,
      height: size,
      borderRadius: size,
      margin: margin,
    );
  }
}

class ShopSkeletonCard extends StatelessWidget {
  const ShopSkeletonCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.borderRadius = 16,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
  }
}

/// Dashboard skeleton matching the metrics cards + quick actions + recent orders.
class ShopDashboardSkeleton extends StatelessWidget {
  const ShopDashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        // Metrics cards grid
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final columns = constraints.maxWidth >= 1200
                ? 6
                : constraints.maxWidth >= 720
                    ? 3
                    : 2;
            final cardWidth =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(
                columns * 2,
                (index) => SizedBox(
                  width: cardWidth,
                  child: const ShopSkeletonCard(
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ShopSkeletonBox(
                              width: 60,
                              height: 12,
                              borderRadius: 6,
                            ),
                            ShopSkeletonCircle(size: 28),
                          ],
                        ),
                        SizedBox(height: 12),
                        ShopSkeletonBox(
                          width: 80,
                          height: 22,
                          borderRadius: 8,
                        ),
                        SizedBox(height: 8),
                        ShopSkeletonBox(
                          width: 48,
                          height: 10,
                          borderRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        // Action chips
        const Row(
          children: [
            ShopSkeletonBox(width: 90, height: 36, borderRadius: 18),
            SizedBox(width: 8),
            ShopSkeletonBox(width: 110, height: 36, borderRadius: 18),
            SizedBox(width: 8),
            ShopSkeletonBox(width: 100, height: 36, borderRadius: 18),
          ],
        ),
        const SizedBox(height: 20),
        // Section header
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ShopSkeletonBox(width: 140, height: 18, borderRadius: 8),
            ShopSkeletonBox(width: 60, height: 14, borderRadius: 6),
          ],
        ),
        const SizedBox(height: 12),
        // Order cards skeleton
        for (var i = 0; i < 3; i++) ...[
          const ShopSkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShopSkeletonBox(width: 110, height: 16, borderRadius: 6),
                    ShopSkeletonBox(width: 72, height: 22, borderRadius: 11),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    ShopSkeletonCircle(size: 20),
                    SizedBox(width: 8),
                    ShopSkeletonBox(width: 130, height: 14, borderRadius: 6),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShopSkeletonBox(width: 90, height: 14, borderRadius: 6),
                    ShopSkeletonBox(width: 70, height: 18, borderRadius: 6),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Product grid skeleton matching catalog & storefront products grid.
class ShopProductGridSkeleton extends StatelessWidget {
  const ShopProductGridSkeleton({
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= AppBreakpoints.wide
            ? 5
            : width >= AppBreakpoints.expanded
                ? 4
                : width >= AppBreakpoints.compact
                    ? 3
                    : 2;
        const spacing = 12.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 0.68,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) => const ShopSkeletonCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ShopSkeletonBox(
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: 12,
                  ),
                ),
                SizedBox(height: 10),
                ShopSkeletonBox(
                  width: 50,
                  height: 10,
                  borderRadius: 5,
                ),
                SizedBox(height: 6),
                ShopSkeletonBox(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 6,
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShopSkeletonBox(
                      width: 64,
                      height: 16,
                      borderRadius: 6,
                    ),
                    ShopSkeletonCircle(size: 28),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Product list skeleton matching admin products list.
class ShopProductListSkeleton extends StatelessWidget {
  const ShopProductListSkeleton({
    this.itemCount = 5,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) => const ShopSkeletonCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShopSkeletonBox(
              width: 64,
              height: 64,
              borderRadius: 12,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShopSkeletonBox(
                    width: double.infinity,
                    height: 16,
                    borderRadius: 6,
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      ShopSkeletonBox(width: 60, height: 18, borderRadius: 9),
                      SizedBox(width: 6),
                      ShopSkeletonBox(width: 80, height: 18, borderRadius: 9),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ShopSkeletonBox(width: 70, height: 16, borderRadius: 6),
                      ShopSkeletonBox(width: 50, height: 16, borderRadius: 6),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Category strip skeleton matching customer home & catalog category selector.
class ShopCategoryStripSkeleton extends StatelessWidget {
  const ShopCategoryStripSkeleton({
    this.height = 100,
    super.key,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    final compact = height < 85;
    final circleSize = compact ? 38.0 : 56.0;
    final spacing = compact ? 4.0 : 8.0;
    final textHeight = compact ? 10.0 : 12.0;

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShopSkeletonCircle(size: circleSize),
            SizedBox(height: spacing),
            ShopSkeletonBox(
              width: compact ? 42 : 52,
              height: textHeight,
              borderRadius: 5,
            ),
          ],
        ),
      ),
    );
  }
}

/// Order list skeleton matching customer and admin orders.
class ShopOrderListSkeleton extends StatelessWidget {
  const ShopOrderListSkeleton({
    this.itemCount = 4,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) => const ShopSkeletonCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    ShopSkeletonBox(width: 90, height: 16, borderRadius: 6),
                    SizedBox(width: 8),
                    ShopSkeletonBox(width: 60, height: 12, borderRadius: 5),
                  ],
                ),
                ShopSkeletonBox(width: 76, height: 24, borderRadius: 12),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                ShopSkeletonCircle(size: 24),
                SizedBox(width: 8),
                ShopSkeletonBox(width: 140, height: 14, borderRadius: 6),
              ],
            ),
            SizedBox(height: 12),
            ShopSkeletonBox(
              width: double.infinity,
              height: 38,
              borderRadius: 8,
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShopSkeletonBox(width: 100, height: 18, borderRadius: 6),
                ShopSkeletonBox(width: 80, height: 32, borderRadius: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Customer list skeleton matching admin customers screen.
class ShopCustomerListSkeleton extends StatelessWidget {
  const ShopCustomerListSkeleton({
    this.itemCount = 5,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) => const ShopSkeletonCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ShopSkeletonCircle(size: 46),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShopSkeletonBox(width: 160, height: 16, borderRadius: 6),
                      SizedBox(height: 6),
                      ShopSkeletonBox(width: 100, height: 12, borderRadius: 5),
                    ],
                  ),
                ),
                ShopSkeletonBox(width: 64, height: 22, borderRadius: 11),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                ShopSkeletonBox(width: 90, height: 20, borderRadius: 10),
                SizedBox(width: 8),
                ShopSkeletonBox(width: 70, height: 20, borderRadius: 10),
                Spacer(),
                ShopSkeletonBox(width: 70, height: 28, borderRadius: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner hero skeleton.
class ShopBannerSkeleton extends StatelessWidget {
  const ShopBannerSkeleton({
    this.height = 140,
    this.borderRadius = 18,
    super.key,
  });

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShopSkeletonBox(
          width: double.infinity,
          height: height,
          borderRadius: borderRadius,
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShopSkeletonBox(width: 20, height: 6, borderRadius: 3),
            SizedBox(width: 4),
            ShopSkeletonBox(width: 6, height: 6, borderRadius: 3),
            SizedBox(width: 4),
            ShopSkeletonBox(width: 6, height: 6, borderRadius: 3),
          ],
        ),
      ],
    );
  }
}

/// Product details page skeleton.
class ShopProductDetailsSkeleton extends StatelessWidget {
  const ShopProductDetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: const [
        ShopSkeletonBox(
          width: double.infinity,
          height: 260,
          borderRadius: 20,
        ),
        SizedBox(height: 16),
        Row(
          children: [
            ShopSkeletonBox(width: 70, height: 22, borderRadius: 11),
            SizedBox(width: 8),
            ShopSkeletonBox(width: 90, height: 22, borderRadius: 11),
          ],
        ),
        SizedBox(height: 12),
        ShopSkeletonBox(width: double.infinity, height: 22, borderRadius: 8),
        SizedBox(height: 8),
        ShopSkeletonBox(width: 140, height: 14, borderRadius: 6),
        SizedBox(height: 16),
        ShopSkeletonCard(
          margin: EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShopSkeletonBox(width: 60, height: 12, borderRadius: 5),
                  SizedBox(height: 6),
                  ShopSkeletonBox(width: 100, height: 24, borderRadius: 8),
                ],
              ),
              ShopSkeletonBox(width: 110, height: 40, borderRadius: 12),
            ],
          ),
        ),
        SizedBox(height: 14),
        ShopSkeletonCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShopSkeletonBox(width: 110, height: 16, borderRadius: 6),
              SizedBox(height: 10),
              ShopSkeletonBox(width: double.infinity, height: 12, borderRadius: 5),
              SizedBox(height: 6),
              ShopSkeletonBox(width: 220, height: 12, borderRadius: 5),
            ],
          ),
        ),
      ],
    );
  }
}

/// Settings page skeleton.
class ShopSettingsSkeleton extends StatelessWidget {
  const ShopSettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        ShopSkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShopSkeletonBox(width: 120, height: 18, borderRadius: 6),
              const SizedBox(height: 14),
              const Row(
                children: [
                  ShopSkeletonCircle(size: 64),
                  SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShopSkeletonBox(width: 140, height: 18, borderRadius: 6),
                      SizedBox(height: 8),
                      ShopSkeletonBox(width: 90, height: 12, borderRadius: 5),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < 4; i++) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ShopSkeletonBox(width: 80, height: 14, borderRadius: 6),
                      ShopSkeletonBox(width: 110, height: 14, borderRadius: 6),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const ShopSkeletonBox(width: 120, height: 38, borderRadius: 10),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const ShopSkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShopSkeletonBox(width: 130, height: 18, borderRadius: 6),
              SizedBox(height: 10),
              ShopSkeletonBox(width: double.infinity, height: 14, borderRadius: 6),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reports page skeleton.
class ShopReportsSkeleton extends StatelessWidget {
  const ShopReportsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        // Summary metrics
        const Row(
          children: [
            Expanded(
              child: ShopSkeletonCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShopSkeletonBox(width: 60, height: 12, borderRadius: 5),
                    SizedBox(height: 8),
                    ShopSkeletonBox(width: 90, height: 20, borderRadius: 6),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ShopSkeletonCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShopSkeletonBox(width: 60, height: 12, borderRadius: 5),
                    SizedBox(height: 8),
                    ShopSkeletonBox(width: 90, height: 20, borderRadius: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Big report card
        const ShopSkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShopSkeletonBox(width: 140, height: 18, borderRadius: 6),
              SizedBox(height: 14),
              ShopSkeletonBox(
                width: double.infinity,
                height: 120,
                borderRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Breakdown cards
        for (var i = 0; i < 3; i++) ...[
          const ShopSkeletonCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShopSkeletonBox(width: 120, height: 16, borderRadius: 6),
                ShopSkeletonBox(width: 70, height: 16, borderRadius: 6),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Banner manager skeleton.
class ShopBannersSkeleton extends StatelessWidget {
  const ShopBannersSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      itemCount: 3,
      itemBuilder: (context, index) => const ShopSkeletonCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShopSkeletonBox(
              width: double.infinity,
              height: 140,
              borderRadius: 14,
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShopSkeletonBox(width: 140, height: 16, borderRadius: 6),
                ShopSkeletonBox(width: 44, height: 24, borderRadius: 12),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                ShopSkeletonBox(width: 80, height: 18, borderRadius: 9),
                SizedBox(width: 8),
                ShopSkeletonBox(width: 100, height: 18, borderRadius: 9),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Archive screen skeleton.
class ShopArchiveSkeleton extends StatelessWidget {
  const ShopArchiveSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        // Tabs skeleton
        const Row(
          children: [
            Expanded(
              child: ShopSkeletonBox(
                height: 38,
                borderRadius: 10,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: ShopSkeletonBox(
                height: 38,
                borderRadius: 10,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: ShopSkeletonBox(
                height: 38,
                borderRadius: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 4; i++) ...[
          const ShopSkeletonCard(
            child: Row(
              children: [
                ShopSkeletonCircle(size: 38),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShopSkeletonBox(width: 140, height: 16, borderRadius: 6),
                      SizedBox(height: 6),
                      ShopSkeletonBox(width: 100, height: 12, borderRadius: 5),
                    ],
                  ),
                ),
                ShopSkeletonBox(width: 60, height: 28, borderRadius: 8),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Notifications screen skeleton.
class ShopNotificationsSkeleton extends StatelessWidget {
  const ShopNotificationsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: const [
        ShopSkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShopSkeletonBox(width: 160, height: 20, borderRadius: 6),
              SizedBox(height: 8),
              ShopSkeletonBox(width: double.infinity, height: 14, borderRadius: 5),
              SizedBox(height: 16),
              ShopSkeletonBox(width: double.infinity, height: 48, borderRadius: 12),
              SizedBox(height: 12),
              ShopSkeletonBox(width: double.infinity, height: 48, borderRadius: 12),
              SizedBox(height: 12),
              ShopSkeletonBox(width: double.infinity, height: 80, borderRadius: 12),
              SizedBox(height: 16),
              ShopSkeletonBox(width: 140, height: 42, borderRadius: 12),
            ],
          ),
        ),
      ],
    );
  }
}

/// App download page skeleton.
class ShopDownloadSkeleton extends StatelessWidget {
  const ShopDownloadSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: const [
        Center(
          child: SizedBox(
            width: 960,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShopSkeletonCard(
                  child: Column(
                    children: [
                      ShopSkeletonCircle(size: 72),
                      SizedBox(height: 14),
                      ShopSkeletonBox(width: 180, height: 24, borderRadius: 8),
                      SizedBox(height: 8),
                      ShopSkeletonBox(width: 240, height: 14, borderRadius: 5),
                      SizedBox(height: 20),
                      ShopSkeletonBox(width: 160, height: 160, borderRadius: 16),
                      SizedBox(height: 20),
                      ShopSkeletonBox(width: 200, height: 44, borderRadius: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Storefront builder skeleton workspace.
class ShopStorefrontBuilderSkeleton extends StatelessWidget {
  const ShopStorefrontBuilderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        if (!isDesktop) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShopSkeletonBox(
                  width: double.infinity,
                  height: 48,
                  borderRadius: 12,
                ),
                SizedBox(height: 14),
                ShopSkeletonBox(
                  width: double.infinity,
                  height: 380,
                  borderRadius: 20,
                ),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left sidebar skeleton
            Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShopSkeletonBox(
                    width: 140,
                    height: 20,
                    borderRadius: 6,
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < 5; i++) ...[
                    const ShopSkeletonCard(
                      margin: EdgeInsets.only(bottom: 10),
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ShopSkeletonCircle(size: 24),
                          SizedBox(width: 10),
                          ShopSkeletonBox(
                            width: 120,
                            height: 14,
                            borderRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Center preview frame skeleton
            Expanded(
              child: Center(
                child: Container(
                  width: 380,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 3,
                    ),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShopSkeletonBox(
                        width: double.infinity,
                        height: 120,
                        borderRadius: 14,
                      ),
                      SizedBox(height: 12),
                      ShopCategoryStripSkeleton(height: 70),
                      SizedBox(height: 12),
                      ShopProductGridSkeleton(
                        itemCount: 4,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full customer home skeleton (banner + categories + product grid).
class ShopCustomerHomeSkeleton extends StatelessWidget {
  const ShopCustomerHomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        ShopBannerSkeleton(height: 140),
        SizedBox(height: 16),
        ShopCategoryStripSkeleton(height: 80),
        SizedBox(height: 16),
        ShopProductGridSkeleton(itemCount: 4, padding: EdgeInsets.zero),
      ],
    );
  }
}

/// Cart page skeleton (cart item cards + summary).
class ShopCartSkeleton extends StatelessWidget {
  const ShopCartSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 3; i++) ...[
          const ShopSkeletonCard(
            child: Row(
              children: [
                ShopSkeletonBox(width: 72, height: 72, borderRadius: 12),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShopSkeletonBox(width: 140, height: 16, borderRadius: 6),
                      SizedBox(height: 8),
                      ShopSkeletonBox(width: 80, height: 14, borderRadius: 5),
                      SizedBox(height: 8),
                      ShopSkeletonBox(width: 60, height: 16, borderRadius: 6),
                    ],
                  ),
                ),
                ShopSkeletonBox(width: 80, height: 32, borderRadius: 8),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const ShopSkeletonCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShopSkeletonBox(width: 80, height: 14, borderRadius: 5),
                  ShopSkeletonBox(width: 60, height: 14, borderRadius: 5),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShopSkeletonBox(width: 100, height: 18, borderRadius: 6),
                  ShopSkeletonBox(width: 90, height: 18, borderRadius: 6),
                ],
              ),
              SizedBox(height: 16),
              ShopSkeletonBox(
                width: double.infinity,
                height: 48,
                borderRadius: 12,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Admin Shell skeleton with top app bar, optional side navigation rail, and page content skeleton.
class ShopAdminShellSkeleton extends StatelessWidget {
  const ShopAdminShellSkeleton({
    this.contentSkeleton,
    super.key,
  });

  final Widget? contentSkeleton;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final scheme = Theme.of(context).colorScheme;

    return ShopSkeleton(
      semanticLabel: 'جارٍ تجهيز لوحة الإدارة...',
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: wide
              ? null
              : const Center(child: ShopSkeletonCircle(size: 28)),
          title: const ShopSkeletonBox(width: 120, height: 20, borderRadius: 6),
          actions: const [
            Padding(
              padding: EdgeInsetsDirectional.only(end: 16),
              child: ShopSkeletonCircle(size: 32),
            ),
          ],
        ),
        body: Row(
          children: [
            if (wide)
              Container(
                width: 270,
                color: scheme.surface,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        children: [
                          ShopSkeletonCircle(size: 44),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShopSkeletonBox(
                                  width: 90,
                                  height: 14,
                                  borderRadius: 5,
                                ),
                                SizedBox(height: 6),
                                ShopSkeletonBox(
                                  width: 60,
                                  height: 12,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    for (var i = 0; i < 7; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const ShopSkeletonCircle(size: 24),
                            const SizedBox(width: 12),
                            ShopSkeletonBox(
                              width: 80.0 + (i % 3) * 20,
                              height: 14,
                              borderRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: contentSkeleton ?? const ShopDashboardSkeleton(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Customer Shell skeleton with top bar, side rail / bottom navigation, and page content skeleton.
class ShopCustomerShellSkeleton extends StatelessWidget {
  const ShopCustomerShellSkeleton({
    this.contentSkeleton,
    super.key,
  });

  final Widget? contentSkeleton;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = AppBreakpoints.isCompact(constraints.maxWidth);
        final extendedRail = AppBreakpoints.isExpanded(constraints.maxWidth);

        final content = contentSkeleton ?? const ShopCustomerHomeSkeleton();

        return ShopSkeleton(
          semanticLabel: 'جارٍ تجهيز المتجر...',
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Row(
                children: [
                  ShopSkeletonCircle(size: 36),
                  SizedBox(width: 10),
                  ShopSkeletonBox(width: 110, height: 18, borderRadius: 6),
                ],
              ),
              actions: const [
                Padding(
                  padding: EdgeInsetsDirectional.only(end: 16),
                  child: Row(
                    children: [
                      ShopSkeletonBox(
                        width: 100,
                        height: 34,
                        borderRadius: 17,
                      ),
                      SizedBox(width: 8),
                      ShopSkeletonCircle(size: 32),
                    ],
                  ),
                ),
              ],
            ),
            body: compact
                ? content
                : Row(
                    children: [
                      Container(
                        width: extendedRail ? 224 : 72,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 8,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < 5; i++) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Row(
                                  mainAxisAlignment: extendedRail
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
                                  children: [
                                    const ShopSkeletonCircle(size: 26),
                                    if (extendedRail) ...[
                                      const SizedBox(width: 12),
                                      ShopSkeletonBox(
                                        width: 60.0 + (i % 3) * 15,
                                        height: 14,
                                        borderRadius: 5,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1320),
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: content,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
            bottomNavigationBar: compact
                ? Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(
                        5,
                        (index) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ShopSkeletonCircle(size: 22),
                            SizedBox(height: 4),
                            ShopSkeletonBox(
                              width: 32,
                              height: 9,
                              borderRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// Auth screen skeleton placeholder (login card with inputs).
class ShopAuthShellSkeleton extends StatelessWidget {
  const ShopAuthShellSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShopSkeleton(
      semanticLabel: 'جارٍ تجهيز تسجيل الدخول...',
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const ShopSkeletonCard(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShopSkeletonCircle(size: 72),
                    SizedBox(height: 16),
                    ShopSkeletonBox(width: 160, height: 22, borderRadius: 8),
                    SizedBox(height: 8),
                    ShopSkeletonBox(width: 220, height: 14, borderRadius: 5),
                    SizedBox(height: 28),
                    ShopSkeletonBox(
                      width: double.infinity,
                      height: 48,
                      borderRadius: 12,
                    ),
                    SizedBox(height: 16),
                    ShopSkeletonBox(
                      width: double.infinity,
                      height: 48,
                      borderRadius: 12,
                    ),
                    SizedBox(height: 24),
                    ShopSkeletonBox(
                      width: double.infinity,
                      height: 48,
                      borderRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopSkeletonMotion extends InheritedWidget {
  const _ShopSkeletonMotion({
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ShopSkeletonMotion>()
        ?.animation;
  }

  @override
  bool updateShouldNotify(_ShopSkeletonMotion oldWidget) =>
      animation != oldWidget.animation;
}
