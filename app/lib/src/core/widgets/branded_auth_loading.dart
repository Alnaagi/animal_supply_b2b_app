import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/shop_branding.dart';
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
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduceMotion == _reduceMotion && _motion.isAnimating == !reduceMotion) {
      return;
    }
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _motion
        ..stop()
        ..value = 1;
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branding = ref.watch(shopBrandingProvider);
    final scheme = Theme.of(context).colorScheme;
    final content = FadeTransition(
      key: const Key('branded-auth-loading-motion'),
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
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.10),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.24),
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: ShopBrandLogo(
                logoUrl: branding.logoUrl,
                size: 58,
                backgroundColor: Colors.transparent,
                fallbackIconColor: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              branding.shopName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            ShopPawSpinner(
              size: 34,
              showBrandMark: false,
              color: scheme.primary,
              light: false,
            ),
          ],
        ),
      ),
    );

    final card = Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: content,
    );

    if (!widget.asOverlay) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: card,
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.42),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: card,
            ),
          ),
        ),
      ),
    );
  }
}
