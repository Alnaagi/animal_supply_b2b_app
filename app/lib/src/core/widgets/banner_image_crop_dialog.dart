import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Banner strip aspect used by demo assets and a good middle ground between
/// phone (~1.5–1.7) and wide desktop (~3+) customer home carousels.
/// Client home still uses [BoxFit.cover], so locking here keeps the intended
/// framing while covering both layouts.
const double kBannerCropAspectRatio = 1600 / 620;

class BannerCropResult {
  const BannerCropResult({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

/// Opens an Instagram-style pan/zoom crop locked to the banner strip aspect.
Future<BannerCropResult?> showBannerImageCropDialog(
  BuildContext context, {
  required Uint8List imageBytes,
  required String sourceFileName,
  double aspectRatio = kBannerCropAspectRatio,
}) {
  return showDialog<BannerCropResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BannerImageCropDialog(
      imageBytes: imageBytes,
      sourceFileName: sourceFileName,
      aspectRatio: aspectRatio,
    ),
  );
}

class BannerImageCropDialog extends StatefulWidget {
  const BannerImageCropDialog({
    super.key,
    required this.imageBytes,
    required this.sourceFileName,
    this.aspectRatio = kBannerCropAspectRatio,
  });

  final Uint8List imageBytes;
  final String sourceFileName;
  final double aspectRatio;

  @override
  State<BannerImageCropDialog> createState() => _BannerImageCropDialogState();
}

enum _CropMode { stretch, crop }

class _BannerImageCropDialogState extends State<BannerImageCropDialog> {
  final TransformationController _transform = TransformationController();
  _CropMode _mode = _CropMode.stretch;
  img.Image? _decoded;
  Size? _viewportSize;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null) {
      _error = 'تعذر قراءة الصورة. اختر ملف JPEG أو PNG أو WebP صالحاً.';
    } else {
      _decoded = decoded;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitCover();
      });
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  bool _isContain = false;

  void _fitCover() {
    _isContain = false;
    final decoded = _decoded;
    final viewport = _viewportSize;
    if (decoded == null || viewport == null || viewport.isEmpty) return;

    final imageWidth = decoded.width.toDouble();
    final imageHeight = decoded.height.toDouble();
    final scale = math.max(
      viewport.width / imageWidth,
      viewport.height / imageHeight,
    );
    final dx = (viewport.width - imageWidth * scale) / 2;
    final dy = (viewport.height - imageHeight * scale) / 2;
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() => _error = null);
  }

  void _fitContain() {
    _isContain = true;
    final decoded = _decoded;
    final viewport = _viewportSize;
    if (decoded == null || viewport == null || viewport.isEmpty) return;

    final imageWidth = decoded.width.toDouble();
    final imageHeight = decoded.height.toDouble();
    final scale = math.min(
      viewport.width / imageWidth,
      viewport.height / imageHeight,
    );
    final dx = (viewport.width - imageWidth * scale) / 2;
    final dy = (viewport.height - imageHeight * scale) / 2;
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() => _error = null);
  }

  void _toggleFit() {
    if (_mode == _CropMode.stretch) {
      setState(() => _mode = _CropMode.crop);
      _fitCover();
      return;
    }
    if (_isContain) {
      _fitCover();
    } else {
      _fitContain();
    }
  }

  Future<void> _export() async {
    final decoded = _decoded;
    final viewport = _viewportSize;
    if (_exporting || decoded == null) {
      return;
    }

    setState(() {
      _exporting = true;
      _error = null;
    });

    try {
      final Uint8List encoded;
      if (_mode == _CropMode.stretch || viewport == null || viewport.isEmpty) {
        encoded = _exportStretchedJpeg(
          source: decoded,
          aspectRatio: widget.aspectRatio,
        );
      } else {
        encoded = _exportCroppedJpeg(
          source: decoded,
          viewport: viewport,
          transform: _transform.value,
          aspectRatio: widget.aspectRatio,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        BannerCropResult(
          bytes: encoded,
          fileName: _bannerJpegName(widget.sourceFileName),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = 'تعذر تجهيز الصورة بعد القص. جرّب صورة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoded = _decoded;
    return AlertDialog(
      key: const ValueKey('banner-image-crop-dialog'),
      title: const Text('قص الصورة'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(
              'يمكنك تمديد الصورة لتناسب إطار البانر بالكامل وعرض كامل الصورة، أو استخدام القص الحر لتحديد جزء معين.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 10),
            SegmentedButton<_CropMode>(
              key: const ValueKey('banner-crop-mode-toggle'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _CropMode.stretch,
                  label: Text('تمديد للإطار (كامل الصورة)'),
                  icon: Icon(Icons.fit_screen_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _CropMode.crop,
                  label: Text('قص حر'),
                  icon: Icon(Icons.crop_outlined, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _exporting
                  ? null
                  : (selection) {
                      setState(() {
                        _mode = selection.single;
                        if (_mode == _CropMode.crop) {
                          _fitCover();
                        }
                      });
                    },
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: Colors.black,
                  child: decoded == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error ?? 'تعذر تحميل الصورة',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final next = constraints.biggest;
                            if (_viewportSize != next) {
                              _viewportSize = next;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && _transform.value.isIdentity()) {
                                  _fitCover();
                                }
                              });
                            }
                            if (_mode == _CropMode.stretch) {
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    widget.imageBytes,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.medium,
                                    gaplessPlayback: true,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                  if (_exporting)
                                    const ColoredBox(
                                      color: Color(0x66000000),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            }
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                InteractiveViewer(
                                  key: const ValueKey('banner-crop-viewer'),
                                  transformationController: _transform,
                                  constrained: false,
                                  boundaryMargin: const EdgeInsets.all(220),
                                  minScale: 0.35,
                                  maxScale: 5,
                                  child: SizedBox(
                                    width: decoded.width.toDouble(),
                                    height: decoded.height.toDouble(),
                                    child: Image.memory(
                                      widget.imageBytes,
                                      fit: BoxFit.fill,
                                      filterQuality: FilterQuality.medium,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ),
                                IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.88,
                                        ),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_exporting)
                                  const ColoredBox(
                                    color: Color(0x66000000),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _mode == _CropMode.stretch
                  ? 'وضع التمديد: تظهر الصورة كاملة متناسبة مع حجم البانر بدون اقتصاص أي جزء.'
                  : 'وضع القص: حرّك وكبّر الصورة لتحديد الجزء المراد عرضه داخل إطار البانر.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
            if (_error != null && decoded != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
      actions: [
        TextButton(
          key: const ValueKey('banner-crop-cancel'),
          onPressed: _exporting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('banner-crop-fit'),
          onPressed: _exporting || decoded == null ? null : _toggleFit,
          icon: const Icon(Icons.fit_screen_outlined, size: 18),
          label: const Text('ملاءمة'),
        ),
        FilledButton.icon(
          key: const ValueKey('banner-crop-save'),
          onPressed: _exporting || decoded == null ? null : _export,
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_exporting ? 'جارٍ القص...' : 'حفظ القص'),
        ),
      ],
    );
  }
}

String _bannerJpegName(String sourceFileName) {
  final trimmed = sourceFileName.trim();
  final dot = trimmed.lastIndexOf('.');
  final base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
  final safe = base.replaceAll(RegExp(r'[^a-zA-Z0-9_\u0600-\u06FF-]+'), '_');
  final name = safe.isEmpty ? 'banner' : safe;
  return '$name.jpg';
}

Uint8List _exportStretchedJpeg({
  required img.Image source,
  required double aspectRatio,
}) {
  final targetWidth = aspectRatio >= 1.5 ? 1600 : 1080;
  final targetHeight = (targetWidth / aspectRatio).round().clamp(1, 4000);
  final resized = img.copyResize(
    source,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.cubic,
  );
  final encoded = img.encodeJpg(resized, quality: 88);
  if (encoded.isEmpty) {
    throw StateError('Unable to encode banner JPEG');
  }
  return Uint8List.fromList(encoded);
}

Uint8List _exportCroppedJpeg({
  required img.Image source,
  required Size viewport,
  required Matrix4 transform,
  required double aspectRatio,
}) {
  final inverted = Matrix4.inverted(transform);
  final topLeft = MatrixUtils.transformPoint(inverted, Offset.zero);
  final bottomRight = MatrixUtils.transformPoint(
    inverted,
    Offset(viewport.width, viewport.height),
  );

  var left = math.min(topLeft.dx, bottomRight.dx);
  var top = math.min(topLeft.dy, bottomRight.dy);
  var right = math.max(topLeft.dx, bottomRight.dx);
  var bottom = math.max(topLeft.dy, bottomRight.dy);

  left = left.clamp(0, source.width.toDouble());
  top = top.clamp(0, source.height.toDouble());
  right = right.clamp(0, source.width.toDouble());
  bottom = bottom.clamp(0, source.height.toDouble());

  var width = (right - left).round();
  var height = (bottom - top).round();
  var x = left.round();
  var y = top.round();

  if (width < 2 || height < 2) {
    // Fallback: cover-centered crop at banner aspect.
    final targetAspect = aspectRatio;
    if (source.width / source.height >= targetAspect) {
      height = source.height;
      width = (height * targetAspect).round().clamp(1, source.width);
      x = ((source.width - width) / 2).round();
      y = 0;
    } else {
      width = source.width;
      height = (width / targetAspect).round().clamp(1, source.height);
      x = 0;
      y = ((source.height - height) / 2).round();
    }
  }

  x = x.clamp(0, math.max(0, source.width - 1));
  y = y.clamp(0, math.max(0, source.height - 1));
  width = width.clamp(1, source.width - x);
  height = height.clamp(1, source.height - y);

  final cropped = img.copyCrop(
    source,
    x: x,
    y: y,
    width: width,
    height: height,
  );
  var frame = cropped;
  if (frame.width > 1600) {
    frame = img.copyResize(
      frame,
      width: 1600,
      interpolation: img.Interpolation.average,
    );
  }
  final encoded = img.encodeJpg(frame, quality: 85);
  if (encoded.isEmpty) {
    throw StateError('Unable to encode banner JPEG');
  }
  return Uint8List.fromList(encoded);
}
