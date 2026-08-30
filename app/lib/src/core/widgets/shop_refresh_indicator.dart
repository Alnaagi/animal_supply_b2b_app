import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../localization/arabic_copy.dart';
import '../theme/app_theme.dart';

/// Pull-to-refresh with a frosted-glass HUD and a lightweight spinner.
class ShopRefreshIndicator extends StatefulWidget {
  const ShopRefreshIndicator({
    required this.onRefresh,
    required this.child,
    super.key,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  static const double dragThreshold = 72;
  static const double maxPull = 1.28;

  static String messageFor(RefreshIndicatorStatus? status) {
    return switch (status) {
      RefreshIndicatorStatus.drag => ArabicCopy.pullToRefresh,
      RefreshIndicatorStatus.armed => ArabicCopy.releaseToRefresh,
      RefreshIndicatorStatus.snap ||
      RefreshIndicatorStatus.refresh =>
        ArabicCopy.refreshing,
      _ => ArabicCopy.refreshing,
    };
  }

  /// Maps raw overscroll to visual pull with rubber-band resistance.
  static double visualPullForOffset(double offset) {
    final linear = math.max(0.0, offset) / dragThreshold;
    if (linear <= 1) {
      return Curves.easeOutQuad.transform(linear.clamp(0.0, 1.0));
    }
    final extra = ((linear - 1) / 0.7).clamp(0.0, 1.0);
    return 1.0 + (maxPull - 1.0) * Curves.easeOutCubic.transform(extra);
  }

  @override
  State<ShopRefreshIndicator> createState() => _ShopRefreshIndicatorState();
}

class _ShopRefreshIndicatorState extends State<ShopRefreshIndicator>
    with TickerProviderStateMixin {
  RefreshIndicatorStatus? _status;
  double? _dragOffset;
  late final AnimationController _pull;
  late final AnimationController _spin;
  bool _overlayVisible = false;

  bool get _spinning =>
      _status == RefreshIndicatorStatus.snap ||
      _status == RefreshIndicatorStatus.refresh;

  bool get _reduceMotion {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  bool get _shouldShowOverlay {
    final status = _status;
    if (status == RefreshIndicatorStatus.drag ||
        status == RefreshIndicatorStatus.armed ||
        status == RefreshIndicatorStatus.snap ||
        status == RefreshIndicatorStatus.refresh) {
      return true;
    }
    return _pull.value > 0.02;
  }

  @override
  void initState() {
    super.initState();
    _pull = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0,
      upperBound: ShopRefreshIndicator.maxPull,
    );
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pull.addListener(_syncOverlayVisibility);
  }

  @override
  void dispose() {
    _pull.removeListener(_syncOverlayVisibility);
    _pull.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _syncOverlayVisibility() {
    final show = _shouldShowOverlay;
    if (show == _overlayVisible) return;
    setState(() => _overlayVisible = show);
  }

  Future<void> _animatePullTo(
    double next, {
    required Duration duration,
  }) {
    if (_reduceMotion) {
      _pull.value = next.clamp(0.0, ShopRefreshIndicator.maxPull);
      return Future<void>.value();
    }
    if ((next - _pull.value).abs() < 0.003 && !_pull.isAnimating) {
      return Future<void>.value();
    }
    return _pull.animateTo(
      next.clamp(0.0, ShopRefreshIndicator.maxPull),
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  void _onStatus(RefreshIndicatorStatus? status) {
    if (status == _status) return;
    setState(() => _status = status);
    switch (status) {
      case RefreshIndicatorStatus.drag:
        _spin.stop();
        _spin.reset();
      case RefreshIndicatorStatus.armed:
        _spin.stop();
        if (_pull.value < 1) {
          _animatePullTo(
            1,
            duration: const Duration(milliseconds: 200),
          );
        }
      case RefreshIndicatorStatus.snap:
      case RefreshIndicatorStatus.refresh:
        _animatePullTo(
          1,
          duration: const Duration(milliseconds: 280),
        );
        if (_reduceMotion) {
          _spin
            ..stop()
            ..value = 0;
        } else {
          _spin.repeat();
        }
      case RefreshIndicatorStatus.canceled:
      case RefreshIndicatorStatus.done:
      case null:
        _spin.stop();
        _spin.reset();
        _dragOffset = null;
        _animatePullTo(
          0,
          duration: const Duration(milliseconds: 220),
        );
    }
    _syncOverlayVisibility();
  }

  bool _atLeadingEdge(ScrollMetrics metrics) {
    return (metrics.axisDirection == AxisDirection.down &&
            metrics.extentBefore <= 0.5) ||
        (metrics.axisDirection == AxisDirection.up &&
            metrics.extentAfter <= 0.5);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        _atLeadingEdge(notification.metrics) &&
        _status == null) {
      _dragOffset = 0;
    }

    if (_dragOffset == null) return false;

    if (notification is ScrollUpdateNotification &&
        notification.scrollDelta != null) {
      if (notification.metrics.axisDirection == AxisDirection.down) {
        _dragOffset = _dragOffset! - notification.scrollDelta!;
      } else if (notification.metrics.axisDirection == AxisDirection.up) {
        _dragOffset = _dragOffset! + notification.scrollDelta!;
      }
      _syncPull();
    } else if (notification is OverscrollNotification) {
      if (notification.metrics.axisDirection == AxisDirection.down) {
        _dragOffset = _dragOffset! - notification.overscroll;
      } else if (notification.metrics.axisDirection == AxisDirection.up) {
        _dragOffset = _dragOffset! + notification.overscroll;
      }
      _syncPull();
    }
    return false;
  }

  void _syncPull() {
    if (_spinning) return;
    final next = ShopRefreshIndicator.visualPullForOffset(
      math.max(0.0, _dragOffset ?? 0),
    );
    final delta = (next - _pull.value).abs();
    if (delta < 0.002) return;

    if (_pull.isAnimating) {
      _pull.stop();
    }
    const follow = kIsWeb ? 0.48 : 0.70;
    _pull.value = lerpDouble(_pull.value, next, follow)!
        .clamp(0.0, ShopRefreshIndicator.maxPull);
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = _reduceMotion;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: RefreshIndicator.noSpinner(
              onStatusChange: _onStatus,
              onRefresh: widget.onRefresh,
              child: widget.child,
            ),
          ),
        ),
        if (_overlayVisible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([_pull, _spin]),
                builder: (context, _) {
                  return _ShopPullRefreshHud(
                    pull: _pull.value,
                    spin: _spin.value,
                    spinning: _spinning,
                    rtl: rtl,
                    reduceMotion: reduceMotion,
                    message: ShopRefreshIndicator.messageFor(_status),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _ShopPullRefreshHud extends StatelessWidget {
  const _ShopPullRefreshHud({
    required this.pull,
    required this.spin,
    required this.spinning,
    required this.rtl,
    required this.reduceMotion,
    required this.message,
  });

  final double pull;
  final double spin;
  final bool spinning;
  final bool rtl;
  final bool reduceMotion;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appear = pull.clamp(0.0, 1.0);
    final drop = 10.0 + (appear * 16.0);
    final scale = 0.88 + (appear * 0.12);

    return Padding(
      padding: EdgeInsets.only(top: drop),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: (0.35 + appear * 0.65).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: _FrostedRefreshHud(
                pull: appear,
                spin: spin,
                spinning: spinning,
                rtl: rtl,
                reduceMotion: reduceMotion,
                message: message,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedRefreshHud extends StatelessWidget {
  const _FrostedRefreshHud({
    required this.pull,
    required this.spin,
    required this.spinning,
    required this.rtl,
    required this.reduceMotion,
    required this.message,
    required this.color,
  });

  final double pull;
  final double spin;
  final bool spinning;
  final bool rtl;
  final bool reduceMotion;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: color.withValues(alpha: 0.22),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 28,
                  key: const Key('shop-refresh-indicator'),
                  child: CustomPaint(
                    painter: _RefreshRingPainter(
                      pull: pull,
                      spin: spin,
                      spinning: spinning,
                      rtl: rtl,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : AppMotion.quick,
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Text(
                    message,
                    key: ValueKey(message),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.94),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshRingPainter extends CustomPainter {
  _RefreshRingPainter({
    required this.pull,
    required this.spin,
    required this.spinning,
    required this.rtl,
    required this.color,
  });

  final double pull;
  final double spin;
  final bool spinning;
  final bool rtl;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.34;
    final sweep =
        spinning ? 1.55 * math.pi : lerpDouble(0.85, 1.35, pull)! * math.pi;
    final start =
        -math.pi / 2 + (spinning ? spin * math.pi * 2 * (rtl ? -1 : 1) : 0);
    final signedSweep = rtl ? -sweep : sweep;

    final track = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..color = color.withValues(alpha: spinning ? 0.95 : 0.72 + pull * 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      signedSweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RefreshRingPainter oldDelegate) {
    return oldDelegate.pull != pull ||
        oldDelegate.spin != spin ||
        oldDelegate.rtl != rtl ||
        oldDelegate.spinning != spinning ||
        oldDelegate.color != color;
  }
}
