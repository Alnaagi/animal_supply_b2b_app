import 'package:flutter/material.dart';

/// Circular upload progress with an Arabic percent label (0–100٪).
///
/// When [progress] is null the ring is indeterminate and the label shows `...`.
class CircularUploadProgress extends StatelessWidget {
  const CircularUploadProgress({
    super.key,
    required this.progress,
    this.size = 72,
    this.strokeWidth = 3,
    this.borderRadius = 20,
  });

  /// Upload fraction in `0..1`, or null while the backend reports no byte progress.
  final double? progress;
  final double size;
  final double strokeWidth;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final clamped = progress?.clamp(0.0, 1.0);
    final percent = clamped == null ? null : (clamped * 100).round();
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: size * 0.39,
              height: size * 0.39,
              child: CircularProgressIndicator(
                value: clamped,
                strokeWidth: strokeWidth,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              percent == null ? '...' : '$percent٪',
              style: TextStyle(
                color: Colors.white,
                fontSize: size < 64 ? 10 : 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String uploadProgressLabelAr(double? progress, {String idle = 'رفع صورة'}) {
  if (progress == null) return 'جارٍ الرفع...';
  return 'جارٍ الرفع ${((progress.clamp(0, 1)) * 100).round()}٪';
}
