import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../localization/arabic_copy.dart';
import '../theme/app_theme.dart';

/// Pull-to-refresh with a stretching green arrow that morphs into a loading circle.
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
  late final AnimationController _morph;
  late final AnimationController _spin;
  bool _overlayVisible = false;

  bool get _spinning =>
      _status == RefreshIndicatorStatus.snap ||
      _status == RefreshIndicatorStatus.refresh;

  bool get _shouldShowOverlay {
    final status = _status;
    if (status == RefreshIndicatorStatus.drag ||
        status == RefreshIndicatorStatus.armed ||
        status == RefreshIndicatorStatus.snap ||
        status == RefreshIndicatorStatus.refresh) {
      return true;
    }
    return _pull.value > 0.02 || _morph.value > 0.02;
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
    _morph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pull.addListener(_syncOverlayVisibility);
    _morph.addListener(_syncOverlayVisibility);
  }

  @override
  void dispose() {
    _pull.removeListener(_syncOverlayVisibility);
    _morph.removeListener(_syncOverlayVisibility);
    _pull.dispose();
    _morph.dispose();
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
        _morph.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      case RefreshIndicatorStatus.armed:
        _spin.stop();
        _morph.animateTo(
          0.38,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOutCubic,
        );
        if (_pull.value < 1) {
          _animatePullTo(
            1,
            duration: const Duration(milliseconds: 200),
          );
        }
      case RefreshIndicatorStatus.snap:
      case RefreshIndicatorStatus.refresh:
        _morph.animateTo(
          1,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
        _animatePullTo(
          1,
          duration: const Duration(milliseconds: 280),
        );
        _spin.repeat();
      case RefreshIndicatorStatus.canceled:
      case RefreshIndicatorStatus.done:
      case null:
        _spin.stop();
        _spin.reset();
        _morph.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
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

    // Follow the finger with light smoothing. Restarting animateTo on every
    // overscroll chunk fights the gesture and feels jumpy on Flutter web.
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
                animation: Listenable.merge([_pull, _morph, _spin]),
                builder: (context, _) {
                  return _ShopPullRefreshHud(
                    pull: _pull.value,
                    morph: _morph.value,
                    spin: _spin.value,
                    spinning: _spinning,
                    rtl: rtl,
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
    required this.morph,
    required this.spin,
    required this.spinning,
    required this.rtl,
    required this.message,
  });

  final double pull;
  final double morph;
  final double spin;
  final bool spinning;
  final bool rtl;
  final String message;

  @override
  Widget build(BuildContext context) {
    final clamped = pull.clamp(0.0, ShopRefreshIndicator.maxPull);
    final appear = clamped.clamp(0.0, 1.0);
    final stretchT = Curves.easeOutCubic.transform(appear);
    final stretch = 1.0 + ((1.0 - morph) * stretchT * 0.26);
    final drop = 8.0 + (appear * 18.0) + (morph * 8.0);
    final scale = 0.78 + (appear * 0.22);

    return Padding(
      padding: EdgeInsets.only(top: drop),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: (0.28 + appear * 0.72).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: _RefreshMark(
                pull: appear,
                morph: morph,
                stretch: stretch,
                spin: spin,
                spinning: spinning,
                rtl: rtl,
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Text(
              message,
              key: ValueKey(message),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.darkGreen.withValues(alpha: 0.92),
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.2,
                shadows: const [
                  Shadow(
                    color: Color(0x66ffffff),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshMark extends StatelessWidget {
  const _RefreshMark({
    required this.pull,
    required this.morph,
    required this.stretch,
    required this.spin,
    required this.spinning,
    required this.rtl,
  });

  final double pull;
  final double morph;
  final double stretch;
  final double spin;
  final bool spinning;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('shop-refresh-indicator'),
      elevation: 3,
      shadowColor: AppTheme.green.withValues(alpha: 0.28),
      color: Colors.white,
      shape: const CircleBorder(),
      child: SizedBox.square(
        dimension: 52,
        child: CustomPaint(
          size: const Size.square(52),
          painter: _StretchingRefreshPainter(
            pull: pull,
            morph: morph,
            stretch: stretch,
            spin: spin,
            rtl: rtl,
            spinning: spinning,
          ),
        ),
      ),
    );
  }
}

class _StretchingRefreshPainter extends CustomPainter {
  _StretchingRefreshPainter({
    required this.pull,
    required this.morph,
    required this.stretch,
    required this.spin,
    required this.rtl,
    required this.spinning,
  });

  final double pull;
  final double morph;
  final double stretch;
  final double spin;
  final bool rtl;
  final bool spinning;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const color = AppTheme.green;
    final arrowOpacity = (1.0 - morph).clamp(0.0, 1.0);
    final ringOpacity = morph.clamp(0.0, 1.0);

    if (arrowOpacity > 0.02) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(1, stretch);
      canvas.translate(-center.dx, -center.dy);
      _paintArrow(canvas, size, center, color.withValues(alpha: arrowOpacity));
      canvas.restore();
    }
    if (ringOpacity > 0.02) {
      _paintRing(
        canvas,
        center,
        size.width * 0.30,
        color,
        ringOpacity,
      );
    }
  }

  void _paintArrow(Canvas canvas, Size size, Offset center, Color color) {
    final w = size.width;
    final h = size.height;
    final length = lerpDouble(h * 0.28, h * 0.42, pull)!;
    final top = center.dy - length * 0.42;
    final bottom = center.dy + length * 0.46;
    final stroke = lerpDouble(2.6, 3.4, pull)!;

    final shaft = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(center.dx, top), Offset(center.dx, bottom), shaft);

    final head = Path()
      ..moveTo(center.dx - w * 0.16, bottom - h * 0.12)
      ..lineTo(center.dx, bottom + h * 0.02)
      ..lineTo(center.dx + w * 0.16, bottom - h * 0.12);
    canvas.drawPath(head, shaft);
  }

  void _paintRing(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double opacity,
  ) {
    final sweep = spinning
        ? lerpDouble(1.35, 1.65, pull)! * math.pi
        : lerpDouble(1.15, 1.85, pull)! * math.pi;
    final start =
        -math.pi / 2 + (spinning ? spin * math.pi * 2 * (rtl ? -1 : 1) : 0);
    final signedSweep = rtl ? -sweep : sweep;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      signedSweep,
      false,
      paint,
    );

    if (spinning) return;

    final end = start + signedSweep;
    final headScale = (1.0 - (opacity * 0.35)).clamp(0.35, 1.0);
    final ux = math.cos(end);
    final uy = math.sin(end);
    final tip = Offset(
      center.dx + ux * radius - uy * 9 * headScale * (rtl ? -1 : 1),
      center.dy + uy * radius + ux * 9 * headScale * (rtl ? -1 : 1),
    );
    final inner = Offset(
      center.dx + ux * (radius - 5.5 * headScale),
      center.dy + uy * (radius - 5.5 * headScale),
    );
    final outer = Offset(
      center.dx + ux * (radius + 5.5 * headScale),
      center.dy + uy * (radius + 5.5 * headScale),
    );
    final head = Path()
      ..moveTo(inner.dx, inner.dy)
      ..lineTo(outer.dx, outer.dy)
      ..lineTo(tip.dx, tip.dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()..color = color.withValues(alpha: opacity * 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _StretchingRefreshPainter oldDelegate) {
    return oldDelegate.pull != pull ||
        oldDelegate.morph != morph ||
        oldDelegate.stretch != stretch ||
        oldDelegate.spin != spin ||
        oldDelegate.rtl != rtl ||
        oldDelegate.spinning != spinning;
  }
}
