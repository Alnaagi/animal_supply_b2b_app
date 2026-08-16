import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/shop_branding.dart';
import '../localization/arabic_copy.dart';
import '../theme/app_theme.dart';
import 'shop_brand_logo.dart';

enum ShopLoadingLayout { page, section, compact, banner }

/// Lightweight store-branded loader: paw orbit + optional shop logo/name.
/// One ticker, CustomPaint only — cheap enough for Flutter web.
class ShopLoading extends StatelessWidget {
  const ShopLoading._({
    required this.layout,
    this.message,
    this.height,
    this.size,
    this.color,
    this.light = false,
    super.key,
  });

  const ShopLoading.page({
    String? message,
    Key? key,
  }) : this._(
          layout: ShopLoadingLayout.page,
          message: message,
          key: key,
        );

  const ShopLoading.section({
    String? message,
    double? height,
    Key? key,
  }) : this._(
          layout: ShopLoadingLayout.section,
          message: message,
          height: height,
          key: key,
        );

  const ShopLoading.compact({
    double size = 18,
    Color? color,
    bool light = false,
    Key? key,
  }) : this._(
          layout: ShopLoadingLayout.compact,
          size: size,
          color: color,
          light: light,
          key: key,
        );

  const ShopLoading.banner({
    String? message,
    Key? key,
  }) : this._(
          layout: ShopLoadingLayout.banner,
          message: message,
          key: key,
        );

  final ShopLoadingLayout layout;
  final String? message;
  final double? height;
  final double? size;
  final Color? color;
  final bool light;

  @override
  Widget build(BuildContext context) {
    if (layout == ShopLoadingLayout.compact) {
      return KeyedSubtree(
        key: const Key('shop-loading-compact'),
        child: ShopPawSpinner(
          size: size ?? 18,
          color: color ?? (light ? Colors.white : AppTheme.green),
          showBrandMark: false,
          light: light,
        ),
      );
    }
    return _ShopLoadingBranded(
      layout: layout,
      message: message,
      height: height,
      size: size,
      color: color,
      light: light,
    );
  }
}

class _ShopLoadingBranded extends ConsumerWidget {
  const _ShopLoadingBranded({
    required this.layout,
    this.message,
    this.height,
    this.size,
    this.color,
    this.light = false,
  });

  final ShopLoadingLayout layout;
  final String? message;
  final double? height;
  final double? size;
  final Color? color;
  final bool light;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(shopBrandingProvider);
    final tone = color ?? (light ? Colors.white : AppTheme.green);
    final spinner = ShopPawSpinner(
      size: size ??
          switch (layout) {
            ShopLoadingLayout.page => 92,
            ShopLoadingLayout.section => 64,
            ShopLoadingLayout.banner => 28,
            ShopLoadingLayout.compact => 18,
          },
      color: tone,
      logoUrl: branding.logoUrl,
      showBrandMark: layout != ShopLoadingLayout.compact,
      light: light,
    );

    final copy = message ??
        switch (layout) {
          ShopLoadingLayout.page => ArabicCopy.screenLoading,
          ShopLoadingLayout.banner => ArabicCopy.refreshing,
          ShopLoadingLayout.section ||
          ShopLoadingLayout.compact =>
            ArabicCopy.sectionLoading,
        };
    final nameColor = light ? Colors.white : AppTheme.darkGreen;
    final copyColor = light ? const Color(0xffd7efe4) : AppTheme.darkGreen;

    if (layout == ShopLoadingLayout.banner) {
      return Material(
        key: const Key('shop-loading-banner'),
        color: AppTheme.green.withValues(alpha: 0.10),
        elevation: 0,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              spinner,
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  copy,
                  style: TextStyle(
                    color: copyColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final body = Column(
      key: Key(
        layout == ShopLoadingLayout.page
            ? 'shop-loading-page'
            : 'shop-loading-section',
      ),
      mainAxisSize: MainAxisSize.min,
      children: [
        spinner,
        if (layout == ShopLoadingLayout.page) ...[
          const SizedBox(height: 16),
          Text(
            branding.shopName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: nameColor,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          copy,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: copyColor,
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
      ],
    );

    final centered = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: body,
      ),
    );
    if (height == null) return centered;
    return SizedBox(height: height, child: centered);
  }
}

class ShopPawSpinner extends StatefulWidget {
  const ShopPawSpinner({
    this.size = 56,
    this.color = AppTheme.green,
    this.logoUrl,
    this.showBrandMark = true,
    this.light = false,
    super.key,
  });

  final double size;
  final Color color;
  final String? logoUrl;
  final bool showBrandMark;
  final bool light;

  @override
  State<ShopPawSpinner> createState() => _ShopPawSpinnerState();
}

class _ShopPawSpinnerState extends State<ShopPawSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final markSize = size >= 56 ? size * 0.58 : size * 0.72;
    return Semantics(
      label: ArabicCopy.screenLoading,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, child) {
              final t = _motion.value;
              final breathe = 0.94 + (math.sin(t * math.pi * 2) * 0.06);
              final tilt = math.sin(t * math.pi * 2) * 0.14;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: breathe,
                    child: CustomPaint(
                      size: Size.square(size),
                      painter: _PawOrbitPainter(
                        progress: t,
                        color: widget.color,
                      ),
                    ),
                  ),
                  Transform.rotate(
                    angle: tilt,
                    child: child,
                  ),
                ],
              );
            },
            child: widget.showBrandMark && size >= 40
                ? ShopBrandLogo(
                    logoUrl: widget.logoUrl,
                    size: markSize,
                    backgroundColor: widget.light
                        ? Colors.white.withValues(alpha: 0.12)
                        : const Color(0xffe3f3eb),
                    fallbackIconColor:
                        widget.light ? Colors.white : widget.color,
                  )
                : CustomPaint(
                    size: Size.square(markSize),
                    painter: _PawPrintPainter(color: widget.color),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PawOrbitPainter extends CustomPainter {
  _PawOrbitPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;
    final arc = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.width * 0.045)
      ..strokeCap = StrokeCap.round;
    // RTL: sweep from the right, counterclockwise.
    final start = -progress * math.pi * 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      math.pi * 0.95,
      false,
      arc,
    );

    final padPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 3; i++) {
      final angle = start + (i * (math.pi * 2 / 3));
      final pad = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final fade =
          0.35 + (0.65 * ((math.sin(progress * math.pi * 2 + i) + 1) / 2));
      padPaint.color = color.withValues(alpha: fade);
      canvas.drawCircle(pad, size.width * 0.055, padPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PawOrbitPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _PawPrintPainter extends CustomPainter {
  _PawPrintPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.70),
        width: w * 0.50,
        height: h * 0.40,
      ),
      paint,
    );
    const toes = [
      Offset(0.22, 0.34),
      Offset(0.40, 0.18),
      Offset(0.60, 0.18),
      Offset(0.78, 0.34),
    ];
    for (final toe in toes) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * toe.dx, h * toe.dy),
          width: w * 0.20,
          height: h * 0.24,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PawPrintPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
