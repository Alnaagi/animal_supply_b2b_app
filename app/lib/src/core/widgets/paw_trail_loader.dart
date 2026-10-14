import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/shop_branding.dart';
import '../localization/arabic_copy.dart';

/// Vertical trail of paw prints walking bottom to top.
/// Matches the HTML loader in `web/index.html`; keep both in sync.
class PawTrail extends StatelessWidget {
  const PawTrail({
    required this.progress,
    this.width = 96,
    this.color,
    super.key,
  });

  /// 0 = no prints, 1 = all prints placed.
  final double progress;
  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * 5 / 3),
      painter: _PawTrailPainter(
        progress: progress,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _PawTrailPainter extends CustomPainter {
  _PawTrailPainter({required this.progress, required this.color});

  static const _count = 4;
  static const _stagger = 0.2;
  static const _stepLength = 0.2;

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paw = size.width * 0.36;
    for (var i = 0; i < _count; i++) {
      final local =
          ((progress - i * _stagger) / _stepLength).clamp(0.0, 1.0).toDouble();
      if (local == 0) continue;
      // First print starts on the right (RTL lead foot), then alternates.
      final rightFoot = i.isEven;
      final center = Offset(
        size.width * (rightFoot ? 0.68 : 0.32),
        size.height * (0.86 - i * 0.24),
      );
      final scale = local < 0.6
          ? Curves.easeOut.transform(local / 0.6) * 1.12
          : 1.12 - 0.12 * ((local - 0.6) / 0.4);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rightFoot ? 0.2 : -0.2);
      canvas.scale(scale);
      _drawPaw(canvas, paw, color.withValues(alpha: local.clamp(0.0, 1.0)));
      canvas.restore();
    }
  }

  void _drawPaw(Canvas canvas, double s, Color color) {
    final paint = Paint()..color = color;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, s * 0.18),
        width: s * 0.56,
        height: s * 0.48,
      ),
      paint,
    );
    const toes = [
      Offset(-0.30, -0.16),
      Offset(-0.12, -0.36),
      Offset(0.12, -0.36),
      Offset(0.30, -0.16),
    ];
    for (final toe in toes) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(s * toe.dx, s * toe.dy),
          width: s * 0.22,
          height: s * 0.28,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PawTrailPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

/// One-shot paw trail shown over the app on cold start.
/// The app keeps booting underneath, so this never delays real loading.
/// Web is disabled by default because `web/index.html` shows the HTML loader.
class AppLoadingIntro extends ConsumerStatefulWidget {
  const AppLoadingIntro({
    required this.child,
    this.enabled = !kIsWeb,
    this.duration = const Duration(milliseconds: 1600),
    super.key,
  });

  final Widget child;
  final bool enabled;
  final Duration duration;

  @override
  ConsumerState<AppLoadingIntro> createState() => _AppLoadingIntroState();
}

class _AppLoadingIntroState extends ConsumerState<AppLoadingIntro>
    with SingleTickerProviderStateMixin {
  static const _fadeDuration = Duration(milliseconds: 280);

  AnimationController? _motion;
  late bool _visible = widget.enabled;
  bool _fading = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !_visible) return;
    _started = true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (reduceMotion) {
      _visible = false;
      return;
    }
    final motion = AnimationController(vsync: this, duration: widget.duration);
    _motion = motion;
    motion.forward().whenComplete(() {
      if (mounted) setState(() => _fading = true);
    });
  }

  @override
  void dispose() {
    _motion?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motion;
    if (!_visible || motion == null) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    final shopName = ref.watch(shopBrandingProvider).shopName;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _fading ? 0 : 1,
            duration: _fadeDuration,
            onEnd: () {
              if (mounted && _fading) setState(() => _visible = false);
            },
            child: AbsorbPointer(
              child: ColoredBox(
                key: const Key('app-loading-intro'),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: Semantics(
                    label: ArabicCopy.screenLoading,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: AnimatedBuilder(
                            animation: motion,
                            builder: (context, _) => PawTrail(
                              // Finish placing prints a bit before the end so
                              // the full trail is visible before fading.
                              progress: math.min(1, motion.value / 0.85),
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          shopName,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
