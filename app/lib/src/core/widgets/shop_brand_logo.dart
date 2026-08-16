import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ShopBrandLogo extends StatelessWidget {
  const ShopBrandLogo({
    this.logoUrl,
    this.logoBytes,
    this.size = 40,
    this.backgroundColor = AppTheme.green,
    this.fallbackIconColor = Colors.white,
    this.semanticLabel = 'شعار المتجر',
    super.key,
  });

  final String? logoUrl;
  final Uint8List? logoBytes;
  final double size;
  final Color backgroundColor;
  final Color fallbackIconColor;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim() ?? '';
    final inset = (size * 0.12).clamp(4.0, 10.0);
    final fallback = Icon(
      Icons.pets,
      color: fallbackIconColor,
      size: size * 0.56,
    );
    final bytes = logoBytes;
    final Widget mark;
    if (bytes != null && bytes.isNotEmpty) {
      mark = _fittedImage(
        Image.memory(
          bytes,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      );
    } else if (url.isEmpty) {
      mark = fallback;
    } else {
      mark = _fittedImage(
        Image.network(
          url,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          // Canvas paint keeps width/height; HTML <img> can collapse to the
          // file's intrinsic size (a 16px scribble inside a grey chip).
          webHtmlElementStrategy: WebHtmlElementStrategy.never,
          loadingBuilder: (context, child, loadingProgress) =>
              loadingProgress == null ? child : fallback,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      );
    }
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
            ),
            child: ClipOval(
              child: Padding(
                padding: EdgeInsets.all(inset),
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: mark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fittedImage(Image image) {
    return SizedBox(
      width: size,
      height: size,
      child: image,
    );
  }
}
