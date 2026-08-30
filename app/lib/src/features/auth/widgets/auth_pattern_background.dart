import 'package:flutter/material.dart';

/// An elegant, atmospheric background for authentication and splash screens
/// with subtle ambient gradients, glowing soft orbs, and a vector animal & pet
/// supply motif wallpaper (paws, food bowls, bones, fish, birds/falcons, sparkles).
class AuthPatternBackground extends StatelessWidget {
  const AuthPatternBackground({
    super.key,
    required this.child,
    this.primaryColor,
    this.secondaryColor,
    this.neutralColor,
  });

  final Widget child;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Color? neutralColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primary = primaryColor ?? scheme.primary;
    final secondary = secondaryColor ?? scheme.secondary;
    final neutral = neutralColor ?? scheme.onSurfaceVariant;
    final canvasBase = Color.alphaBlend(
      primary.withValues(alpha: 0.055),
      scheme.surface,
    );
    final canvasMid = Color.alphaBlend(
      secondary.withValues(alpha: 0.075),
      canvasBase,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. A tinted canvas keeps the login experience warm and branded even
        // when the active theme uses a white surface.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color.alphaBlend(
                  primary.withValues(alpha: 0.22),
                  canvasBase,
                ),
                Color.alphaBlend(
                  primary.withValues(alpha: 0.035),
                  canvasMid,
                ),
                Color.alphaBlend(
                  secondary.withValues(alpha: 0.18),
                  canvasMid,
                ),
              ],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
        ),

        // 2. Soft atmospheric glows harmonized with the active theme.
        Positioned(
          top: -120,
          right: -80,
          child: _GlowOrb(
            size: 420,
            color: primary.withValues(alpha: 0.20),
          ),
        ),
        Positioned(
          bottom: -140,
          left: -90,
          child: _GlowOrb(
            size: 440,
            color: secondary.withValues(alpha: 0.18),
          ),
        ),
        Positioned(
          top: 180,
          left: -100,
          child: _GlowOrb(
            size: 300,
            color: primary.withValues(alpha: 0.11),
          ),
        ),

        // 3. Large flowing shapes keep the backdrop from feeling like a
        // flat wallpaper while remaining behind the login card.
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AuthBackdropPainter(
                primaryColor: primary,
                secondaryColor: secondary,
              ),
            ),
          ),
        ),

        // 4. Crisp vector animal & pet pattern overlay.
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AnimalSupplyPatternPainter(
                primaryColor: primary,
                secondaryColor: secondary,
                neutralColor: neutral,
              ),
            ),
          ),
        ),

        // 5. Foreground content (e.g. login card).
        child,
      ],
    );
  }
}

/// Draws broad, low-contrast arcs and bubbles behind the repeating motifs.
/// These shapes add depth without competing with the authentication form.
class _AuthBackdropPainter extends CustomPainter {
  const _AuthBackdropPainter({
    required this.primaryColor,
    required this.secondaryColor,
  });

  final Color primaryColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final primary = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = primaryColor.withValues(alpha: .10);
    final secondary = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = secondaryColor.withValues(alpha: .10);
    final primaryWash = Paint()
      ..style = PaintingStyle.fill
      ..color = primaryColor.withValues(alpha: .045);
    final secondaryWash = Paint()
      ..style = PaintingStyle.fill
      ..color = secondaryColor.withValues(alpha: .04);

    final width = size.width;
    final height = size.height;
    canvas.drawOval(
      Rect.fromCircle(
        center: Offset(width * .05, height * .16),
        radius: width * .42,
      ),
      primaryWash,
    );
    canvas.drawOval(
      Rect.fromCircle(
        center: Offset(width * .98, height * .82),
        radius: width * .46,
      ),
      secondaryWash,
    );

    for (var index = -1; index < 4; index++) {
      final offset = index * 90.0;
      canvas.drawArc(
        Rect.fromLTWH(
          -width * .22 + offset,
          height * .12,
          width * .86,
          height * .48,
        ),
        0.22,
        1.12,
        false,
        index.isEven ? primary : secondary,
      );
    }
    for (var index = 0; index < 3; index++) {
      canvas.drawArc(
        Rect.fromLTWH(
          width * .42,
          height * .42 + (index * 74),
          width * .86,
          height * .44,
        ),
        3.35,
        1.0,
        false,
        index.isEven ? secondary : primary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuthBackdropPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}

/// A soft, blurred ambient glow orb that adds depth behind the pattern.
class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Types of decorative motifs drawn across the pattern grid.
enum _MotifType {
  paw,
  bone,
  bowl,
  fish,
  bird,
  sparkle,
  dot,
}

/// A custom painter that draws a balanced, beautiful grid of animal motifs:
/// - Animal paws (🐾)
/// - Pet food bowls (🥣)
/// - Dog bones (🦴)
/// - Fish (🐟)
/// - Soaring birds / falcons (🕊️)
/// - Sparkles & soft micro-dots
class _AnimalSupplyPatternPainter extends CustomPainter {
  const _AnimalSupplyPatternPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.neutralColor,
  });

  final Color primaryColor;
  final Color secondaryColor;
  final Color neutralColor;

  static const double cellWidth = 92.0;
  static const double cellHeight = 92.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / cellWidth).ceil() + 1;
    final rows = (size.height / cellHeight).ceil() + 1;

    // Palette of subtle yet crisp, noticeable, elegant tones derived purely from active theme
    final primarySoft = primaryColor.withValues(alpha: 0.24);
    final secondarySoft = secondaryColor.withValues(alpha: 0.21);
    final neutralSoft = neutralColor.withValues(alpha: 0.16);

    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        // Stagger every odd row for a balanced diagonal wallpaper layout
        final xOffset = (r % 2 == 1) ? cellWidth * 0.5 : 0.0;
        final centerX =
            (c * cellWidth) + (cellWidth / 2) + xOffset - (cellWidth * 0.25);
        final centerY = (r * cellHeight) + (cellHeight / 2);

        final index = (c * 7 + r * 13 + (c % 3) * 5) % 19;
        final motif = _selectMotif(index);
        final rotation = _rotationForIndex(index);
        final scale = _scaleForIndex(index);
        final color =
            _colorForIndex(index, primarySoft, secondarySoft, neutralSoft);

        fillPaint.color = color;

        canvas.save();
        canvas.translate(centerX, centerY);
        canvas.rotate(rotation);
        canvas.scale(scale);

        _drawMotif(canvas, Offset.zero, 34.0, motif, fillPaint);

        canvas.restore();
      }
    }
  }

  _MotifType _selectMotif(int index) {
    switch (index % 7) {
      case 0:
        return _MotifType.paw;
      case 1:
        return _MotifType.bone;
      case 2:
        return _MotifType.bowl;
      case 3:
        return _MotifType.fish;
      case 4:
        return _MotifType.bird;
      case 5:
        return _MotifType.sparkle;
      default:
        return _MotifType.dot;
    }
  }

  double _rotationForIndex(int index) {
    final angles = [
      0.15,
      -0.22,
      0.08,
      -0.14,
      0.28,
      -0.05,
      0.18,
      -0.26,
      0.12,
      -0.16,
      0.22,
      -0.08,
      0.30,
      -0.18,
      0.10,
      -0.20,
      0.05,
      -0.12,
      0.25,
    ];
    return angles[index % angles.length];
  }

  double _scaleForIndex(int index) {
    final scales = [
      0.95,
      0.85,
      1.05,
      0.88,
      1.0,
      0.92,
      1.1,
      0.82,
      0.98,
      0.86,
      1.02,
      0.90,
      0.84,
      1.08,
      0.92,
      0.88,
      1.0,
      0.85,
      0.96,
    ];
    return scales[index % scales.length];
  }

  Color _colorForIndex(int index, Color p, Color s, Color n) {
    switch (index % 3) {
      case 0:
        return p;
      case 1:
        return s;
      default:
        return n;
    }
  }

  void _drawMotif(
    Canvas canvas,
    Offset center,
    double size,
    _MotifType motif,
    Paint paint,
  ) {
    switch (motif) {
      case _MotifType.paw:
        _drawPaw(canvas, center, size, paint);
      case _MotifType.bone:
        _drawBone(canvas, center, size, paint);
      case _MotifType.bowl:
        _drawBowl(canvas, center, size, paint);
      case _MotifType.fish:
        _drawFish(canvas, center, size, paint);
      case _MotifType.bird:
        _drawBird(canvas, center, size, paint);
      case _MotifType.sparkle:
        _drawSparkle(canvas, center, size * 0.75, paint);
      case _MotifType.dot:
        _drawDot(canvas, center, size * 0.28, paint);
    }
  }

  /// Draws a classic paw print (central metacarpal pad + 4 toe pads).
  void _drawPaw(Canvas canvas, Offset center, double size, Paint paint) {
    // 1. Main pad (smooth rounded trapezoid / bean shape)
    final padPath = Path();
    final padW = size * 0.58;
    final padH = size * 0.44;
    final padTop = center.dy + size * 0.02;
    final padBottom = padTop + padH;

    padPath.moveTo(center.dx - padW * 0.42, padTop + padH * 0.28);
    // Top slight dip
    padPath.cubicTo(
      center.dx - padW * 0.2,
      padTop - padH * 0.08,
      center.dx + padW * 0.2,
      padTop - padH * 0.08,
      center.dx + padW * 0.42,
      padTop + padH * 0.28,
    );
    // Right side
    padPath.cubicTo(
      center.dx + padW * 0.55,
      padTop + padH * 0.7,
      center.dx + padW * 0.35,
      padBottom,
      center.dx,
      padBottom,
    );
    // Left side
    padPath.cubicTo(
      center.dx - padW * 0.35,
      padBottom,
      center.dx - padW * 0.55,
      padTop + padH * 0.7,
      center.dx - padW * 0.42,
      padTop + padH * 0.28,
    );
    padPath.close();
    canvas.drawPath(padPath, paint);

    // 2. Four curved toe pads
    final toeRadiusX = size * 0.085;
    final toeRadiusY = size * 0.115;

    final toeAngles = [-0.35, -0.12, 0.12, 0.35];
    final toeOffsets = [
      Offset(center.dx - size * 0.28, center.dy - size * 0.12),
      Offset(center.dx - size * 0.10, center.dy - size * 0.28),
      Offset(center.dx + size * 0.10, center.dy - size * 0.28),
      Offset(center.dx + size * 0.28, center.dy - size * 0.12),
    ];

    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(toeOffsets[i].dx, toeOffsets[i].dy);
      canvas.rotate(toeAngles[i]);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: toeRadiusX * 2,
          height: toeRadiusY * 2,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  /// Draws a dog bone shape (center bar + 4 circular end lobes).
  void _drawBone(Canvas canvas, Offset center, double size, Paint paint) {
    final barW = size * 0.58;
    final barH = size * 0.16;
    final lobeR = size * 0.11;

    // Center bar
    final barRect = Rect.fromCenter(
      center: center,
      width: barW,
      height: barH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, Radius.circular(barH / 2)),
      paint,
    );

    // Lobes on left and right ends
    final endX = barW * 0.44;
    final lobeY = barH * 0.52;

    canvas.drawCircle(
        Offset(center.dx - endX, center.dy - lobeY), lobeR, paint);
    canvas.drawCircle(
        Offset(center.dx - endX, center.dy + lobeY), lobeR, paint);
    canvas.drawCircle(
        Offset(center.dx + endX, center.dy - lobeY), lobeR, paint);
    canvas.drawCircle(
        Offset(center.dx + endX, center.dy + lobeY), lobeR, paint);
  }

  /// Draws a modern pet food bowl with a rim and curved bowl base.
  void _drawBowl(Canvas canvas, Offset center, double size, Paint paint) {
    final bowlPath = Path();
    final topY = center.dy - size * 0.12;
    final botY = center.dy + size * 0.24;
    final topHalfW = size * 0.40;
    final botHalfW = size * 0.26;

    // Top rim oval
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, topY),
        width: topHalfW * 2,
        height: size * 0.14,
      ),
      paint,
    );

    // Bowl body
    bowlPath.moveTo(center.dx - topHalfW, topY);
    bowlPath.quadraticBezierTo(
      center.dx - topHalfW * 0.9,
      botY,
      center.dx - botHalfW,
      botY,
    );
    bowlPath.lineTo(center.dx + botHalfW, botY);
    bowlPath.quadraticBezierTo(
      center.dx + topHalfW * 0.9,
      botY,
      center.dx + topHalfW,
      topY,
    );
    bowlPath.close();
    canvas.drawPath(bowlPath, paint);
  }

  /// Draws an elegant fish silhouette with fins and tail.
  void _drawFish(Canvas canvas, Offset center, double size, Paint paint) {
    final fishPath = Path();
    final length = size * 0.72;
    final height = size * 0.32;
    final headX = center.dx + length * 0.44;
    final tailX = center.dx - length * 0.44;
    final bodyLeft = center.dx - length * 0.22;

    // Curved body
    fishPath.moveTo(headX, center.dy);
    fishPath.quadraticBezierTo(
      center.dx,
      center.dy - height * 0.85,
      bodyLeft,
      center.dy,
    );
    fishPath.quadraticBezierTo(
      center.dx,
      center.dy + height * 0.85,
      headX,
      center.dy,
    );

    // Tail fin
    fishPath.moveTo(bodyLeft, center.dy);
    fishPath.lineTo(tailX, center.dy - height * 0.65);
    fishPath.lineTo(tailX + length * 0.08, center.dy);
    fishPath.lineTo(tailX, center.dy + height * 0.65);
    fishPath.close();

    canvas.drawPath(fishPath, paint);
  }

  /// Draws a soaring bird / falcon motif (reflecting Al-Bashek identity).
  void _drawBird(Canvas canvas, Offset center, double size, Paint paint) {
    final birdPath = Path();
    final span = size * 0.75;
    final h = size * 0.32;

    // Wing arc and soaring silhouette
    birdPath.moveTo(center.dx - span / 2, center.dy - h * 0.2);
    birdPath.cubicTo(
      center.dx - span * 0.25,
      center.dy - h * 0.8,
      center.dx - span * 0.08,
      center.dy + h * 0.15,
      center.dx,
      center.dy + h * 0.35,
    );
    birdPath.cubicTo(
      center.dx + span * 0.08,
      center.dy + h * 0.15,
      center.dx + span * 0.25,
      center.dy - h * 0.8,
      center.dx + span / 2,
      center.dy - h * 0.2,
    );
    birdPath.quadraticBezierTo(
      center.dx + span * 0.18,
      center.dy,
      center.dx,
      center.dy + h * 0.75,
    );
    birdPath.quadraticBezierTo(
      center.dx - span * 0.18,
      center.dy,
      center.dx - span / 2,
      center.dy - h * 0.2,
    );
    birdPath.close();

    canvas.drawPath(birdPath, paint);
  }

  /// Draws a delicate 4-point sparkle star (✦).
  void _drawSparkle(Canvas canvas, Offset center, double size, Paint paint) {
    final sparklePath = Path();
    final r = size * 0.44;

    sparklePath.moveTo(center.dx, center.dy - r);
    sparklePath.quadraticBezierTo(
      center.dx,
      center.dy,
      center.dx + r,
      center.dy,
    );
    sparklePath.quadraticBezierTo(
      center.dx,
      center.dy,
      center.dx,
      center.dy + r,
    );
    sparklePath.quadraticBezierTo(
      center.dx,
      center.dy,
      center.dx - r,
      center.dy,
    );
    sparklePath.quadraticBezierTo(
      center.dx,
      center.dy,
      center.dx,
      center.dy - r,
    );
    sparklePath.close();

    canvas.drawPath(sparklePath, paint);
  }

  /// Draws a soft micro-dot for rhythm in the pattern.
  void _drawDot(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _AnimalSupplyPatternPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.neutralColor != neutralColor;
  }
}
