import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/shop_branding.dart';
import '../theme/app_theme.dart';
import 'shop_brand_logo.dart';
import 'shop_loading.dart';

class BrandedAuthLoading extends ConsumerStatefulWidget {
  const BrandedAuthLoading({
    required this.message,
    this.asOverlay = false,
    super.key,
  });

  final String message;
  final bool asOverlay;

  @override
  ConsumerState<BrandedAuthLoading> createState() => _BrandedAuthLoadingState();
}

class _BrandedAuthLoadingState extends ConsumerState<BrandedAuthLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(shopBrandingProvider);
    final content = FadeTransition(
      opacity: Tween<double>(begin: 0.82, end: 1).animate(
        CurvedAnimation(parent: _motion, curve: Curves.easeInOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(
          CurvedAnimation(parent: _motion, curve: Curves.easeInOut),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const Key('branded-auth-loading'),
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: const Color(0xff7dccab),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: ShopBrandLogo(
                logoUrl: branding.logoUrl,
                size: 72,
                backgroundColor: Colors.transparent,
                fallbackIconColor: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              branding.shopName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xffd7efe4),
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            const ShopPawSpinner(
              size: 34,
              color: Color(0xff7dccab),
              showBrandMark: false,
              light: true,
            ),
          ],
        ),
      ),
    );

    if (!widget.asOverlay) {
      return ColoredBox(
        color: AppTheme.darkGreen,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: content,
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: AppTheme.darkGreen.withValues(alpha: 0.88),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
