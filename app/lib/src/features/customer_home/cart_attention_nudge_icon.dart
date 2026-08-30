import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated shopping cart navigation icon that performs an eye-catching wiggle,
/// bounce, and glowing badge pulse to remind users of pending items in their cart
/// after prolonged scrolling or browsing across the customer experience.
class CartAttentionNudgeIcon extends StatefulWidget {
  const CartAttentionNudgeIcon({
    required this.count,
    required this.icon,
    this.isNudging = false,
    this.reduceMotion = false,
    super.key,
  });

  final int count;
  final IconData icon;
  final bool isNudging;
  final bool reduceMotion;

  @override
  State<CartAttentionNudgeIcon> createState() => _CartAttentionNudgeIconState();
}

class _CartAttentionNudgeIconState extends State<CartAttentionNudgeIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.isNudging && !widget.reduceMotion && widget.count > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant CartAttentionNudgeIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion || widget.count <= 0) {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.value = 0;
      }
      return;
    }

    if (widget.isNudging &&
        (!oldWidget.isNudging ||
            widget.count > oldWidget.count ||
            !_controller.isAnimating)) {
      _controller.forward(from: 0);
    } else if (!widget.isNudging && oldWidget.isNudging && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion || widget.count <= 0) {
      return Badge(
        key: const Key('customer-cart-nav-badge'),
        isLabelVisible: widget.count > 0,
        label: Text('${widget.count}'),
        child: Icon(widget.icon, key: const Key('customer-cart-nav-icon')),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final highlightColor =
        isDark ? const Color(0xffffb74d) : const Color(0xffe65100);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // The attention-grabbing wiggle and bounce occurs during the first 72%
        // of the animation timeline, then smoothly settles back to rest.
        final wigglePhase = (t / 0.72).clamp(0.0, 1.0);
        final isWiggling = t <= 0.72 && widget.isNudging;
        final decay = 1.0 - wigglePhase;

        // Decaying physics-inspired angular oscillation (~12 degrees peak)
        final angle = isWiggling
            ? math.sin(wigglePhase * 7.0 * math.pi) * decay * 0.20
            : 0.0;

        // Vertical hopping bounce (-3.5px peak)
        final bounce = isWiggling
            ? -math.sin(wigglePhase * 3.5 * math.pi).abs() * decay * 3.5
            : 0.0;

        // Subtle cart scale pop
        final cartScale = isWiggling
            ? 1.0 + (math.sin(wigglePhase * 3.5 * math.pi).abs() * decay * 0.14)
            : 1.0;

        // Badge scale pulse & radiant glow
        final badgeScale = isWiggling
            ? 1.0 + (math.sin(wigglePhase * 3.5 * math.pi).abs() * decay * 0.26)
            : 1.0;
        final glowAlpha = isWiggling ? (decay * 0.60).clamp(0.0, 0.60) : 0.0;

        return Transform.translate(
          key: const Key('customer-cart-nudge-transform'),
          offset: Offset(0.0, bounce),
          child: Transform.rotate(
            angle: angle,
            alignment: Alignment.bottomCenter,
            child: Transform.scale(
              scale: cartScale,
              alignment: Alignment.bottomCenter,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Badge(
                    key: const Key('customer-cart-nav-badge'),
                    isLabelVisible: widget.count > 0,
                    backgroundColor: isWiggling
                        ? Color.lerp(
                            theme.colorScheme.error,
                            highlightColor,
                            decay * 0.5,
                          )
                        : null,
                    label: Transform.scale(
                      scale: badgeScale,
                      child: Text(
                        '${widget.count}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      key: const Key('customer-cart-nav-icon'),
                    ),
                  ),
                  if (glowAlpha > 0.05 && widget.count > 0)
                    PositionedDirectional(
                      top: -2,
                      end: -4,
                      child: IgnorePointer(
                        child: Container(
                          width: 18 * badgeScale,
                          height: 18 * badgeScale,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    highlightColor.withValues(alpha: glowAlpha),
                                blurRadius: 8 * badgeScale,
                                spreadRadius: 2 * badgeScale,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
